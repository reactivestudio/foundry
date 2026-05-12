# JIT, Warm-up, AOT, and Benchmarking

How the JIT compiler works and what to do about it. Warm-up patterns. GraalVM Native Image trade-offs. JMH benchmarking discipline.

---

## 1. JIT compiler stack (HotSpot)

```
Interpreter (slowest) → C1 compiler (Client; fast compile, less optimised)
                      → C2 compiler (Server; slow compile, deeply optimised)
                      → (sometimes) deoptimisation back to interpreter on assumption break
```

Tiered compilation (default since JDK 8) uses both: code runs in interpreter, then C1, then C2 if hot enough. Each tier has a compile threshold (invocation count + backedge count).

### Implications

- **Method invoked < 1500 times** → likely still in interpreter or C1. Slow.
- **Method invoked > 10000 times with no deopts** → fully C2-compiled, maximally optimised.
- **Method compiled but pattern changes (e.g., new branch taken)** → deoptimised, recompiled.

### See JIT activity

```
-XX:+PrintCompilation                 # log every compilation event
-XX:+UnlockDiagnosticVMOptions -XX:+PrintInlining   # log inlining decisions
-XX:CompileThreshold=10000            # invocations before C2 kicks in (default ~10K)
```

Output sample:
```
123  45 % b 4  com.example.Service::hotMethod @ 17 (87 bytes)
```
- `45` = compile ID
- `%` = OSR (on-stack-replacement) — replaced mid-execution
- `b` = blocking
- `4` = C2 tier

---

## 2. Inlining — the most important optimisation

C2 inlines method bodies into call sites if size and frequency permit. Inlined methods can be further optimised together. **Most JIT performance comes from inlining + escape analysis.**

### Helping the JIT inline

- **Keep hot methods small.** Methods > 325 bytecode bytes are not inlined by default.
- **Avoid mega-morphic dispatch.** If a virtual call has > 2 receiver types observed at runtime, JIT can't inline it efficiently. Use sealed hierarchies, `final` Kotlin classes (default!), or `inline` keyword.
- **Don't reflect / Method.invoke in hot paths.** Reflection blocks inlining. Use `MethodHandle` + cache, or generate bytecode (ASM/ByteBuddy).
- **Avoid lambdas with captured mutable state in hot paths** — they may inline, but escape analysis suffers.

### Kotlin-specific

- **Kotlin classes are `final` by default.** This helps JIT inline calls.
- **`inline fun`** — Kotlin source-level inlining, separate from JIT inlining. Useful for higher-order functions to avoid lambda allocation.
- **`inline class` / `@JvmInline value class`** — no boxing for wrapper types. Hot-path-friendly.
- **`internal` modifier** — `final` for JIT purposes, accessible within module.
- **`open` modifier** — opts into virtuality; only use when the class is genuinely meant to be subclassed.

---

## 3. Escape analysis

C2 analyses object lifetimes. If an object never "escapes" the method (not stored in a field, returned, passed to another method that escapes it), the JIT can:

- **Stack-allocate** the object (no heap pressure)
- **Scalar-replace** — break the object into its fields, no allocation at all

```kotlin
fun computeArea(width: Int, height: Int): Int {
    val dim = Dimension(width, height)   // may be scalar-replaced
    return dim.width * dim.height
}
```

If `Dimension` doesn't escape, allocation disappears.

### See it work

```
-XX:+UnlockDiagnosticVMOptions -XX:+PrintEscapeAnalysis
```

Or in JFR: "Allocation in new TLAB" should decrease for short-lived objects in hot methods.

### Common escape-analysis killers

- Storing into a field (escapes the method)
- Throwing the object (escapes via stack)
- Locking on the object (synchronisation blocks escape analysis)
- Method too big to inline → escape can't be proved

---

## 4. Warm-up

JIT-compiled code is faster than interpreted by 10-100×. Until your hot methods are compiled, you're slow.

### Typical Spring Boot warm-up profile

| Phase | Time | What |
|---|---|---|
| JVM start | 0-1s | Bootstrap classes |
| Spring boot init | 1-5s | Component scan, bean creation, JPA metadata |
| First requests | 0-30s | JIT C1 compilation |
| Steady-state | 30s+ | JIT C2 compilation, full speed |

So: **first 30s of requests are slow.** This matters for:
- Canary deployments (don't shift traffic immediately)
- Health probes (readiness should pass AFTER warm-up, not just after Spring init)
- Auto-scaling (a new instance is slow for 30s)

### Warm-up strategies

**A. Replay synthetic traffic on startup:**

```kotlin
@Component
class WarmUpRunner(private val webTestClient: WebTestClient) {
    @EventListener(ApplicationReadyEvent::class)
    fun warmUp() {
        repeat(1000) {
            webTestClient.get().uri("/api/v1/health/deep").exchange()
            webTestClient.get().uri("/api/v1/orders/$sampleId").exchange()
        }
    }
}
```

Run synthetic traffic for ~30s, then health probe becomes UP. Cost: cold start adds 30s.

**B. Class Data Sharing (CDS) + Application CDS:**

```
# Generate AppCDS archive (once)
java -XX:DumpLoadedClassList=classes.txt -jar app.jar &
sleep 30; kill $!
java -Xshare:dump -XX:SharedClassListFile=classes.txt 
     -XX:SharedArchiveFile=app.jsa -jar app.jar

# Use in production
java -XX:SharedArchiveFile=app.jsa -jar app.jar
```

Reduces class loading time (~30-50% startup speedup). Doesn't help with JIT warm-up.

**C. Train and replay AppCDS:**

Spring Boot 3+ has `paketo` buildpacks integration that generates AppCDS automatically.

**D. GraalVM Native Image** — eliminates JIT entirely. See section 5.

---

## 5. GraalVM Native Image

Compile Java/Kotlin → native binary AOT (Ahead-of-Time). No JVM, no JIT, instant startup.

### Pros

- **Startup time** drops from seconds to milliseconds (50-100ms typical)
- **Memory footprint** drops by 50-70% (no JIT, smaller runtime)
- **Container image** smaller (~80MB vs 250MB+)
- **Cold-start friendly** — perfect for serverless

### Cons

- **Build time** 5-20 minutes for a typical Spring app
- **Reflection requires hints.** Spring Boot 3+ has integration, but every library that uses reflection at runtime needs registration.
- **No JIT** → peak throughput is **lower** than warm JVM (typically 20-40% lower)
- **No dynamic class loading.** No bytecode generation (Hibernate proxies, CGLIB, ByteBuddy at runtime) — must be replaced with build-time alternatives.
- **Debugging is hard.** No agent attach.
- **Build complexity.** Reachability metadata, profile-guided optimization.

### When Native Image makes sense

- **Serverless / function-style deployment** — startup matters more than peak throughput
- **Sidecar / utility services** — short-lived, fast-start desired
- **Containers with very tight memory limits** — saves 100MB+
- **Cost-optimised microservices that scale-to-zero**

### When NOT to use Native Image

- **Long-running services where peak throughput matters** — JIT wins
- **You're using a library not on the Native Image compatibility list** — debugging fragile
- **Build time / CI/CD speed matters** — 20min native build vs 2min JVM build
- **Code uses runtime bytecode generation extensively** — won't work

### Spring Boot 3 native quick start

```kotlin
// build.gradle.kts
plugins {
    id("org.springframework.boot") version "3.x"
    id("org.graalvm.buildtools.native") version "0.10.x"
}
```

```bash
./gradlew nativeCompile
./build/native/nativeCompile/app
```

Test heavily — many libraries break in subtle ways under Native Image.

---

## 6. JMH — microbenchmarks done right

JMH (Java Microbenchmark Harness) is the only way to reliably measure microbenchmarks on the JVM. Hand-rolled `System.currentTimeMillis()` benchmarks lie because of JIT, dead-code elimination, escape analysis, and CPU caches.

### Setup

```kotlin
plugins {
    id("me.champeau.jmh") version "0.7.2"
}

dependencies {
    jmh("org.openjdk.jmh:jmh-core:1.37")
    jmh("org.openjdk.jmh:jmh-generator-annprocess:1.37")
}
```

### Example benchmark

```kotlin
@BenchmarkMode(Mode.AverageTime)
@OutputTimeUnit(TimeUnit.NANOSECONDS)
@State(Scope.Benchmark)
@Fork(value = 2, jvmArgs = ["-Xmx2g"])
@Warmup(iterations = 5, time = 1)
@Measurement(iterations = 10, time = 1)
open class MoneyBenchmark {

    private lateinit var a: Money
    private lateinit var b: Money

    @Setup
    fun setup() {
        a = Money(12345, "EUR")
        b = Money(67890, "EUR")
    }

    @Benchmark
    fun addMoney(): Money = a + b

    @Benchmark
    fun addMoneyBoxed(): java.math.BigDecimal =
        java.math.BigDecimal("123.45").add(java.math.BigDecimal("678.90"))
}
```

Run:
```bash
./gradlew jmh
```

Read output:
```
Benchmark                       Mode  Cnt    Score    Error  Units
MoneyBenchmark.addMoney         avgt   20    2.345 ±  0.123  ns/op
MoneyBenchmark.addMoneyBoxed    avgt   20  145.678 ±  4.567  ns/op
```

### JMH common annotations

| Annotation | Meaning |
|---|---|
| `@BenchmarkMode(AverageTime)` | Measure ns/op average |
| `@BenchmarkMode(Throughput)` | Measure ops/s |
| `@BenchmarkMode(SingleShotTime)` | One iteration — useful for cold cases |
| `@OutputTimeUnit(NANOSECONDS)` | Output unit |
| `@State(Scope.Benchmark)` | Shared state across threads |
| `@Fork(2)` | Run 2 JVM forks (gets independent estimates) |
| `@Warmup(iterations = 5)` | 5 warm-up iterations |
| `@Measurement(iterations = 10)` | 10 measurement iterations |
| `@Param("8", "64", "256")` | Parameterised |

### Avoiding dead-code elimination

```kotlin
@Benchmark
fun naive(): Unit {
    val x = compute()    // result is unused → JIT eliminates the call
}

// vs:

@Benchmark
fun correct(blackhole: Blackhole) {
    blackhole.consume(compute())   // Blackhole forces JIT to keep the value
}

// Or return the value:
@Benchmark
fun correctReturn(): Int = compute()
```

### Common JMH pitfalls

- **Forgetting `@State`.** Without it, JMH might inline computations away.
- **Setup in `@Benchmark` method.** Use `@Setup`. Setup work distorts measurement.
- **`Random()` in benchmark.** Use `ThreadLocalRandom` or seed deterministically.
- **Loop within `@Benchmark` method.** JMH does the looping. Your inner loop becomes unrealistic.
- **Comparing across JVM versions / machines.** JMH only compares within identical environment.

### CI integration

Run JMH on PR. Compare results. Alert on regression > N%.

```yaml
# .github/workflows/perf.yml
- run: ./gradlew jmh
- name: Compare to baseline
  run: |
    python compare_jmh.py baseline.json build/results/jmh/results.json --threshold 5
```

Caveat: CI runners have variable performance. Use dedicated benchmark hardware or accept high noise floor.

---

## 7. Common performance pitfalls (Kotlin-specific)

- **Boxing primitives.** `Map<Int, Int>` boxes. Use `IntArray`, `LongArray`, or specialised libraries (Koloboke, fastutil).
- **`List<Int>` vs `IntArray`** for tight loops. `IntArray` avoids autoboxing.
- **`forEach { }` vs `for` loop** in hottest loops. `forEach` allocates a `Function1` instance (often inlined away, but verify). For absolutely hot paths, `for` is safer.
- **Lambda captures.** `users.filter { it.active && cutoff < it.createdAt }` — `cutoff` captured into lambda; may force allocation. JIT can usually fix this, but not always.
- **`String.format`** in hot paths. Parse spec on each call. Use string templates or pre-compiled formatters.
- **`String.replace("a", "b")`** in a loop. `String.replaceAll` is faster but compiles regex. Use `StringBuilder.replace()` or pre-compiled `Pattern`.
- **`if (logger.isDebugEnabled())` checks.** Not needed for Kotlin string templates — Kotlin compiles them lazily. But if you have heavy `toString()` on objects in the template, the wrap is worth it.
- **Spring AOP overhead.** Every `@Transactional` method has proxy overhead. Per-call: ~tens of ns. For hot inner-loop methods, consider extracting the inner loop out of the transactional method.

---

## 8. JIT-friendly code patterns

```kotlin
// Final = good (Kotlin default)
class OrderPriceCalculator { ... }

// final by default → JIT can inline calls to its methods

// Sealed = good (closed set of types)
sealed interface PaymentResult
data class Succeeded(...) : PaymentResult
data class Failed(...) : PaymentResult

// JIT sees 2 receivers max → can inline

// Avoid:
open class GenericService { open fun process() = ... }
class ServiceA : GenericService()
class ServiceB : GenericService()
class ServiceC : GenericService()
// ... + 10 more
// Megamorphic dispatch on process() → no inlining

// Better: visitor pattern + sealed, OR strategy pattern with inlined dispatch
```

```kotlin
// Inline higher-order functions: zero allocation
inline fun <T, R> withTimer(timer: Timer, block: () -> R): R = 
    timer.recordCallable(block)!!

// Without `inline`, every call allocates a Function0<R>.
```

---

## 9. Pitfalls

- **Microbenchmarking without JMH.** Numbers will be wrong.
- **Profiling the dev laptop.** Different JIT decisions, different concurrency. Profile in prod-like env.
- **Comparing cold to warm.** Always measure after warm-up.
- **Trusting JIT to "figure it out".** Mostly true; but megamorphic dispatch, mega-methods, and reflection do hurt. Help where possible.
- **Premature `inline fun` everywhere.** Inlining grows code; can hurt instruction cache and JIT C2 compile budget. Use for genuinely hot higher-order functions.
- **Native Image as default.** Most services don't need it. Pay the build-time and runtime-throughput cost only when startup time matters.
- **No JIT tuning.** JIT defaults are usually optimal. Don't twiddle `CompileThreshold` etc. without strong evidence.
