---
name: jvm-performance
description: "JVM performance discipline for Spring/Kotlin services — async-profiler for CPU/alloc flame graphs, JDK Flight Recorder (JFR) for production profiling, GC choice and tuning (G1, ZGC, Generational ZGC), heap and thread dumps with MAT/Eclipse-MAT/jcmd, Native Memory Tracking, JMH benchmarking, JIT compiler tuning, container memory sizing, GraalVM Native Image trade-offs. Use when production latency or throughput regression, OOM, GC pauses, thread starvation, or capacity planning."
risk: safe
source: "custom — JVM 21+ performance discipline for Spring services"
date_added: "2026-05-12"
---

# JVM Performance (Spring / Kotlin)

When production latency regresses, throughput drops, or memory grows unbounded, JVM performance work begins. This skill is the methodology: **measure first, hypothesise second, change last**. It covers profiling tooling, GC choice, memory analysis, and tuning.

> Premature optimisation is the root of all evil. Late optimisation under prod fire is the root of bad decisions. Tools are the difference.

## Use this skill when

- Investigating latency regression in production (p95/p99 spike)
- Diagnosing throughput drop after deploy
- OutOfMemoryError or steadily growing heap
- GC pauses noticeable in latency tails
- Thread starvation / context-switch storms
- Capacity planning before scaling up/out
- Picking GC for a workload (G1 vs ZGC vs Generational ZGC)
- Sizing container memory limits (and not getting OOM-killed)
- Deciding whether GraalVM Native Image is worth the trade-offs

## Do not use this skill when

- The slow query is in PostgreSQL — that's `database-design/resources/optimization.md`
- The bottleneck is **business logic algorithm** — that's `algorithms-applied-backend`
- The issue is **architectural** (synchronous calls, no caching) — fix architecture, not the JVM
- You haven't proven there IS a JVM problem — measure first; symptoms often point elsewhere

## Selective Reading Rule

| File | Description | When to read |
|---|---|---|
| `resources/profiling-tools.md` | async-profiler (CPU, alloc, wall, lock flame graphs), JFR / JMC, jcmd, JConsole / VisualVM; how to invoke each and read output | CPU/alloc bottleneck investigation; capturing production profile |
| `resources/gc-and-memory.md` | GC choice (G1, ZGC, Generational ZGC, Parallel); generational vs non-generational; tuning flags; heap dump analysis (Eclipse MAT, jhat); Native Memory Tracking; container memory sizing | GC pause investigation, OOM analysis, memory leaks, container sizing |
| `resources/jit-and-warmup.md` | C1 vs C2 compiler, inlining, deoptimisation, tiered compilation, AOT / GraalVM Native Image trade-offs; JMH benchmarking discipline | Microbenchmarks, startup-time optimisation, native-image decision |

## Core principles

1. **Measure, don't guess.** Every "I think GC is the problem" is wrong about 70% of the time. Profile first.
2. **Production data > synthetic benchmarks.** JFR runs continuously in prod with ~1% overhead. Use it. Lab benchmarks miss real-world workload shape.
3. **CPU profile reveals hot code. Allocation profile reveals memory pressure. Wall profile reveals where time is spent waiting.** Three different views — use the right one.
4. **The fastest path is the one not taken.** Cache, batch, defer, eliminate. Often the right "performance fix" is removing work, not optimising it.
5. **GC tuning is a last resort.** Modern collectors (G1, ZGC) auto-tune well. Flag-tuning before profiling = cargo cult.
6. **Container memory: heap is not all the JVM uses.** Heap + Metaspace + Code Cache + Direct + Native + Thread stacks. Size container at heap × 1.5-2.
7. **Don't optimise unprofiled code.** Top-down: find the hottest function, fix it, re-profile. Repeat until you stop seeing wins.

## Tooling stack — what to use when

| Symptom | Tool |
|---|---|
| CPU pegged, high latency | **async-profiler CPU** flame graph |
| Allocation pressure / frequent GC | **async-profiler alloc** flame graph |
| Threads waiting / lock contention | **async-profiler lock** + **wall** profiles, **jcmd Thread.print** |
| Long GC pauses | **JFR + JMC** GC view, GC logs (`-Xlog:gc*`) |
| OOM | **heap dump on OOM** (`-XX:+HeapDumpOnOutOfMemoryError`) + **Eclipse MAT** |
| Steadily growing heap (slow leak) | Periodic heap dumps + MAT comparison |
| Thread starvation / deadlock | **jcmd `Thread.print`** or **jstack** |
| Slow startup | **JFR startup profile**, GraalVM AOT analysis |
| Production continuous profile | **JFR continuous recording** (~1% overhead) |
| Microbenchmark / regression test | **JMH** (`@Benchmark`, `@BenchmarkMode`, etc.) |

## Quick win triage

When called to investigate latency:

```
1. Check the obvious: load avg, CPU, memory, disk IO, network — `top`, `iostat`, `vmstat`
2. Look at GC: `jcmd <pid> GC.heap_info`, `jstat -gc <pid> 1s`
3. Thread dump: `jcmd <pid> Thread.print > threads.txt` — anyone BLOCKED, WAITING long?
4. Quick CPU profile: `async-profiler -d 30 -f cpu.html <pid>`
5. If GC suspected: JFR 60s recording, open in JMC
6. If OOM imminent: heap dump (`jcmd <pid> GC.heap_dump /tmp/heap.hprof`) → MAT
```

If a customer is bleeding, do (1) and (4) first. Don't fix without root cause; see `debugging-systematic`.

## Anti-patterns

- **Tuning GC flags first.** Almost never the right move. Profile first.
- **Increasing heap to "fix" GC pauses.** Bigger heap → longer pauses (with G1/Parallel). With ZGC it's safer, but address the allocation pressure, not the symptom.
- **`System.gc()` in code.** Hints to the GC are mostly ignored or harmful.
- **Synchronous JNI calls in hot paths.** No JIT, no inlining, often safepoint poll bottleneck.
- **Reflection in hot paths without method handle caching.** Slow. Use `MethodHandle` + cache.
- **Heap dumps in production without coordination.** Multi-GB dumps freeze the JVM during dump. Coordinate with ops.
- **Java-style autoboxing of primitives in loops.** `for (i in 0..n) sum += map[i]` boxes `i` → autoboxing pressure. Kotlin `IntArray` vs `Array<Int>` matters.
- **`String.format` in hot logging path.** Kotlin string templates are fine; format spec parsing is slow.
- **Profiling on the developer laptop.** Different CPU, different JIT decisions, different concurrency model. Use prod-like environments.
- **Optimising before you understand.** Latency regression "fixed" by changing the wrong knob comes back two weeks later.
- **Allocating large arrays in hot paths.** Each allocation pressures TLAB; consider pooling (with care — pools can leak, become contended).

## JVM 21+ specifics for Kotlin/Spring

| Feature | What | When useful |
|---|---|---|
| **Virtual threads (Project Loom)** | Lightweight threads, kernel-thread-free | I/O-bound workloads (blocking JDBC, HTTP clients); replaces reactive for many cases |
| **Generational ZGC** | Sub-millisecond pauses + generational efficiency | Latency-critical services with mixed allocation profiles |
| **Records / sealed classes** | Compile-time guarantees, less GC pressure than ad-hoc class hierarchies | Kotlin already has `data class` / `sealed class`; this is for Java interop |
| **Pattern matching** | Cleaner switches | Compiler emits same bytecode |
| **Foreign Function & Memory API** | Off-heap memory without `Unsafe` | High-perf interop, off-heap caches |
| **Vector API** (preview) | SIMD operations | Numerical inner loops |

For Kotlin: prefer Kotlin's own features (`data class`, `sealed`, coroutines) over Java equivalents where they overlap; virtual threads are the exception — Kotlin coroutines and virtual threads complement each other for different patterns.

## Production deployment defaults (Kotlin/Spring Boot 3+ on JVM 21)

```yaml
# JVM flags for typical OLTP service
JAVA_OPTS: >-
  -XX:+UseG1GC
  -XX:MaxGCPauseMillis=200
  -XX:+ParallelRefProcEnabled
  -XX:+UseStringDeduplication
  -Xmx2g
  -Xms2g
  -XX:MaxMetaspaceSize=256m
  -XX:ReservedCodeCacheSize=256m
  -XX:+HeapDumpOnOutOfMemoryError
  -XX:HeapDumpPath=/var/log/heap-dumps
  -XX:+ExitOnOutOfMemoryError
  -Xlog:gc*:file=/var/log/gc.log:time,uptime,level,tags:filecount=10,filesize=10M
  -XX:StartFlightRecording=settings=profile,duration=0s,filename=/var/log/jfr/continuous.jfr,disk=true,maxsize=200m,maxage=24h,name=continuous
```

For latency-critical: swap to ZGC:
```
-XX:+UseZGC -XX:+ZGenerational  # JVM 21+ generational ZGC
```

(See `gc-and-memory.md` for flag-by-flag explanation.)

## Container memory sizing (Kubernetes)

```
container memory request/limit = max(Heap, Initial) + 
                                 NonHeap (Metaspace + Code Cache + Compressed Class Space) +
                                 Direct Buffers +
                                 Thread stacks (~ #threads × 1MB) +
                                 OS/process overhead

Typical formula: container memory = heap × 1.5 to 2
```

Set `-Xmx` and `-Xms` to the same value to avoid heap resize churn. Use `MaxRAMPercentage=75` if you want JVM to size automatically from cgroup limit.

## Related skills

- `debugging-systematic` — root cause first; same discipline applied to perf
- `methodology-verification` — before claiming "fixed", show before/after metrics
- `database-design/resources/optimization.md` — most "JVM" perf issues are DB issues
- `caching-strategies-spring` — when the fix is "don't compute it again"
- `algorithms-applied-backend` — when the fix is "less work, not faster work"
- `architecture` — when the fix is structural
- `spring-boot-mastery` — Actuator metrics, async tuning

## Limitations

- Patterns assume JVM 21+ (LTS). JVM 17 still works for most; JVM 11 is missing ZGC features (no generational, no concurrent class unloading).
- No coverage of OS-level tuning (kernel scheduling, TCP, NUMA pinning). That's ops territory.
- Stop and ask if the **performance target** is unclear (p99 ms, throughput rps, cost per request) — without a target, "fast enough" is undefined.
