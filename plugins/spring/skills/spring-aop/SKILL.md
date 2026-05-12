---
name: spring-aop
description: "Aspect-Oriented Programming for Kotlin / Spring Boot 3+ services — `@Aspect` / `@Component` declaration, `@EnableAspectJAutoProxy` (auto-enabled by Boot), advice types (`@Before` / `@After` / `@AfterReturning` / `@AfterThrowing` / `@Around`), pointcut expressions (`execution(...)`, `within(...)`, `bean(...)`, `@annotation(...)`, `@within(...)`, `@target(...)`, `args(...)`, `this(...)`, `target(...)`) with reusable `@Pointcut` names, advice ordering with `@Order`, the **proxy mechanics** (JDK dynamic proxy for interfaces vs CGLIB subclass for classes, Boot defaults to CGLIB), and the canonical home for **the proxy gotchas** that bite every AOP-driven annotation (`@Transactional` / `@Async` / `@Cacheable` / `@Scheduled` / `@PreAuthorize`): self-invocation (`this.method()` skips the proxy), `private` methods (not interceptable), `final` methods / classes (CGLIB can't subclass, Kotlin classes need `kotlin-spring` `all-open` or explicit `open`), construction via `new SomeService(...)` (no Spring, no proxy), aspects on methods called from constructors (proxy not installed yet). Spring AOP vs AspectJ (proxy-based runtime vs compile-time / load-time weaving) as the escape hatch when the proxy model isn't enough. When custom aspects are justified (structured logging across a class of methods, audit trail, request-time metric, idempotency-key check) versus a smell (domain logic in aspects, re-implementing what Spring already provides, swallowing exceptions in `@AfterThrowing`, pointcuts so broad they match unintended beans, `@Around` aspects that `proceed()` conditionally without a documented contract). Testing aspects via integration slices, never in isolation. Use whenever the user writes or reviews a custom aspect, asks 'why isn't my `@Transactional` / `@Async` / `@Cacheable` firing?', considers self-injection or `AopContext.currentProxy()`, hits 'Cannot subclass final class', debates AspectJ vs Spring AOP, or wants to add cross-cutting behaviour without sprinkling it across every method body. `@Transactional` deep mechanics live in `spring-transactions`; `@Async` in `spring-async`; `@Cacheable` in `spring-cache`; security expressions in `spring-security`; Resilience4j in `microservices-patterns-deep` — this skill owns the AOP substrate they all sit on."
risk: safe
source: "custom — Spring AOP for Kotlin/Spring Boot 3+"
date_added: "2026-05-12"
---

# Spring AOP (Kotlin / Spring Boot 3+)

> AOP is the answer to "this concern wants to be in 80 methods but doesn't belong to any of them". Spring AOP is the 90%-good-enough proxy-based implementation that all of Spring's own annotations (`@Transactional`, `@Async`, `@Cacheable`, `@Scheduled`, `@PreAuthorize`) sit on. Knowing the proxy model — what it can and can't intercept — is the difference between "magic works" and three days of debugging a silent no-op.

## Use this skill when

- Writing or reviewing a custom `@Aspect` — picking the advice type, the pointcut, the ordering
- Debugging "why isn't my `@Transactional` / `@Async` / `@Cacheable` / `@Scheduled` / `@PreAuthorize` firing?" — almost always a proxy gotcha (self-invocation, `final`, `private`, `new`-ed instance, missing `kotlin-spring` plugin)
- Hitting `Cannot subclass final class` at startup on a Kotlin Spring class
- Considering `AopContext.currentProxy()`, `@Lazy` self-injection, or splitting a class into two beans to escape self-invocation
- Deciding between Spring AOP (proxy-based runtime) and full AspectJ (compile-time / load-time weaving) — the escape hatch
- Adding structured logging / audit / metrics / idempotency-key checks across a class of methods and wondering whether AOP is the right shape
- Ordering multiple aspects that intercept the same join point with `@Order`
- Reviewing a custom aspect that re-implements what `@Transactional` / `@Cacheable` / `@Validated` already provide — usually deletable

## Do not use this skill when

- The question is **`@Transactional` propagation / isolation / `rollbackFor` / `readOnly`** — that's `spring-transactions`. The proxy-gotcha diagnosis lives **here** (`spring-aop` is the canonical home), but the transactional semantics live there.
- The question is **`@Async` executor configuration, virtual threads, `AsyncConfigurer`, exception handling** — that's `spring-async`.
- The question is **`@Cacheable` / `@CacheEvict` / `@CachePut`, cache providers, invalidation, stampede mitigation** — that's `spring-cache`.
- The question is **`@PreAuthorize` / `@PostAuthorize` expressions, custom permission evaluators** — that's `spring-security`.
- The question is **`@Scheduled` cron / `fixedDelay` / `fixedRate`, ShedLock for clustered scheduling** — that's `spring-scheduler`.
- The question is **Resilience4j `@Retry` / `@CircuitBreaker`** — that's `microservices-patterns-deep`.
- The question is **`@EventListener` / `@TransactionalEventListener`** — that's `spring-events`.
- The question is **bean wiring, `@Component` vs `@Bean`, scopes, lifecycle** — that's `spring-bean`.
- You're picking the **architectural layout** — that's `architecture-patterns`.

## Core principles

1. **Cross-cutting concerns belong in aspects; domain logic does not.** Logging, auditing, metrics, retry, transactions, caching, security — all cross-cutting. "Calculate the order total" is not. Aspects that drive behaviour the caller can't see are a maintenance trap.
2. **Spring AOP is proxy-based, and the proxy is the actor.** Every AOP-driven annotation (`@Transactional`, `@Async`, `@Cacheable`, `@Scheduled`, `@PreAuthorize`, your custom aspects) only fires when the call goes **through the proxy**. Skip the proxy — self-invocation, `private`, `final`, `new`-ed instance, non-bean — and the annotation is dead text. Most "why isn't my aspect firing?" bugs are this.
3. **Prefer Spring's built-in AOP-driven annotations over custom aspects.** `@Transactional`, `@Cacheable`, `@Validated`, `@PreAuthorize`, `@Retry`, `@Observed` cover 90% of cross-cutting needs. Write a custom aspect only when none of these fit.
4. **`@Around` is the most powerful and the most footgun-prone.** It can swallow exceptions, change arguments, skip `proceed()`, mutate the return value. If `@Before` / `@After` / `@AfterReturning` / `@AfterThrowing` can express the intent, use them instead.
5. **Pointcuts should be precise.** A pointcut so broad it matches `execution(* *(..))` will silently apply to half the application's beans. Scope by package, by stereotype, by annotation — almost never by signature alone.
6. **Test aspects through the proxied boundary, never the aspect class in isolation.** Instantiating an `@Aspect` class with `new` doesn't engage the proxy machinery — the test is meaningless. Slice-boot the relevant Spring beans and verify behaviour through a bean method call.
7. **Aspects on Kotlin code need `open`.** Kotlin classes are `final` by default; CGLIB can't subclass `final`. The `kotlin-spring` (`all-open`) plugin opens stereotyped classes automatically. Plain classes that aspects target need `open class` explicitly.

## Spring AOP vs AspectJ

Spring AOP and AspectJ both implement AOP, but at different times and with different tradeoffs.

| | **Spring AOP** | **AspectJ (full)** |
|---|---|---|
| **Weaving** | Runtime — proxy created when the Spring container instantiates the bean | Compile-time (`ajc` compiler) or load-time (LTW, JVM agent) |
| **Scope** | Public methods on Spring-managed beans, called from outside the class | Any method — `private`, `final`, static, intra-class, constructors, field access |
| **Dependency** | `spring-aop` + `aspectjweaver` (for pointcut expression parsing only) | Full AspectJ runtime + compiler / agent |
| **Performance** | One proxy hop per call (~ns) | Zero hops — woven into bytecode |
| **Self-invocation** | Skipped (`this.method()` doesn't hit the proxy) | Works (it's just bytecode) |
| **`private` / `final`** | Not interceptable | Interceptable |
| **Setup complexity** | Zero (auto-enabled by Boot) | Compiler plugin or JVM agent + careful build wiring |
| **When to choose** | 99% of application code. All of Spring's own annotations use this. | Escape hatch: you need to intercept what Spring AOP can't (intra-class, constructors, fields, `final`/`private`), or you can't tolerate the proxy overhead in a hot path. |

For Spring Boot Kotlin services in 2026, **Spring AOP is the default and almost always sufficient**. Reach for full AspectJ only when the proxy model genuinely cannot express what you need — and even then, audit the design first: if you need to intercept `private` methods, those `private` methods are usually doing too much.

## The proxy mechanism — JDK dynamic vs CGLIB

Spring AOP wraps the bean in a proxy that intercepts method calls, runs the configured advice, and forwards to the real method. Two implementations:

| | **JDK dynamic proxy** | **CGLIB proxy** |
|---|---|---|
| **Mechanism** | `java.lang.reflect.Proxy` — generates a class implementing the bean's interfaces, delegates calls | Subclasses the bean's class via bytecode generation, overrides methods |
| **Requires** | Target implements at least one interface | Target class is non-`final` (Spring's `objenesis` handles construction) |
| **Can proxy** | Only methods declared on interfaces | All non-`final` public methods of the class |
| **Boot 3 default** | Opt-in via `spring.aop.proxy-target-class=false` | Default (`proxyTargetClass = true`) for `@Component` stereotypes |

Boot 3 defaults to **CGLIB for every `@Component` stereotype**. The historical "JDK proxy if interface, CGLIB otherwise" rule no longer applies as the default; forcing JDK proxies is opt-in and rare.

You almost never think about which proxy you got — both work transparently. The cases where it matters: a class without an interface declared `final` (CGLIB fails with `Cannot subclass final class`), `final` methods on an otherwise-proxiable class (CGLIB silently skips; JDK proxy doesn't see them anyway). `@EnableAspectJAutoProxy` is auto-enabled in Spring Boot — you don't write it.

## Advice types — when each

| Advice | Fires | Can mutate args / return / throw | Use when |
|---|---|---|---|
| **`@Before`** | Before the join point method runs | No — args are read-only at this stage | Pre-condition checks, request-time logging, MDC enrichment, security-context setup |
| **`@After`** | After the method returns OR throws (finally semantics) | No | Cleanup, MDC teardown, releasing a resource — runs whether the method succeeded or failed |
| **`@AfterReturning`** | After the method returns normally | Can read (not mutate) the returned value via `returning = "name"` | Success-path logging, metric increment on success, post-condition checks |
| **`@AfterThrowing`** | After the method throws | Can read the exception via `throwing = "name"` | Failure-path logging / metric, **never** swallow the exception (just observing — exception still propagates) |
| **`@Around`** | Wraps the method — most powerful | Can read/mutate args, conditionally call `proceed()`, replace the return value, replace or swallow the exception | When you need both before and after with shared state (`Instant start = ...`), or genuine wrap-the-call semantics (retry, circuit-breaker, cache-aside, timing) |

**Decision rule**: pick the least powerful advice that expresses the intent. `@Around` is footgun-prone because the body controls whether the method runs at all and what comes out — bugs in `@Around` are silent and cross-cutting.

## Pointcut expressions — reference

A pointcut picks which join points (method calls) the advice applies to. Compose with `&&`, `||`, `!`.

| Designator | Matches | Example |
|---|---|---|
| `execution(...)` | Method execution by signature (visibility, return type, package, class, method, parameters) | `execution(public * com.example.orders..*Service.*(..))` |
| `within(...)` | Any join point within a type / package | `within(com.example.orders..*)` |
| `bean(...)` | Bean by name (or name pattern) | `bean(*Repository)` |
| `@annotation(X)` | Methods annotated with `X` | `@annotation(org.springframework.transaction.annotation.Transactional)` |
| `@within(X)` | Methods declared in a type annotated with `X` | `@within(org.springframework.stereotype.Service)` |
| `@target(X)` | Methods on a bean whose runtime type is annotated with `X` | `@target(com.example.Audited)` |
| `args(...)` | Methods whose arguments match the pattern; binds args into advice | `args(orderId, ..)` |
| `this(...)` | The proxy implements the given type | `this(com.example.OrderApi)` |
| `target(...)` | The proxied target class implements / is the given type | `target(com.example.OrderApi)` |

### `execution()` syntax

`execution(<modifier>? <return-type> <declaring-type>?.<method-name>(<params>) <throws>?)` — `*` is a single-token wildcard; `..` is "zero or more tokens" (in packages or args).

```kotlin
execution(public * com.example.orders..*Service.*(..))   // all public methods of any *Service in com.example.orders.*
execution(com.example.Order *.*(..))                     // any method returning Order
execution(* *..findById(*))                              // any single-arg findById
```

### Reusable `@Pointcut` definitions

```kotlin
@Aspect
@Component
class LoggingAspect {

    @Pointcut("@within(org.springframework.stereotype.Service)")
    fun anyService() {}

    @Pointcut("@annotation(com.example.Audited)")
    fun audited() {}

    @Pointcut("anyService() && audited()")
    fun auditedServiceMethod() {}

    @Around("auditedServiceMethod()")
    fun logAround(joinPoint: ProceedingJoinPoint): Any? { ... }
}
```

Named pointcuts read like documentation and let you compose. Inline `@Around("@within(...) && @annotation(...)")` strings get unreadable fast.

## The proxy gotchas (the canonical home)

Every AOP-driven annotation in Spring — `@Transactional`, `@Async`, `@Cacheable`, `@Scheduled`, `@PreAuthorize`, your custom aspects — sits on the same proxy machinery and inherits the same five footguns. This is the single most common source of "the annotation isn't working" tickets. **`spring-transactions` and the others point here for the diagnosis.**

### 1. Self-invocation — `this.method()` skips the proxy

```kotlin
@Service
open class OrderService(
    private val repo: OrderRepository,
) {
    fun place(req: PlaceOrderRequest) {
        // calling `this.audit(...)` inside this class — goes direct to the method
        // body, bypasses the proxy, so @Around / @Transactional / @Async on audit()
        // never fires.
        audit(req)                                                  // ← bug
    }

    @Audited("place-order")
    @Transactional
    fun audit(req: PlaceOrderRequest) { ... }
}
```

When a method on `this` calls another method on `this`, the second call goes direct to the bytecode of `this.audit(...)` — it does not go through `proxy.audit(...)`. The proxy never sees the call, so the aspect/annotation never fires. Same problem for `@Transactional`, `@Async`, `@Cacheable`, `@Scheduled`, `@PreAuthorize`.

**Fixes, in order of preference:**

**(A) Split into two beans.** The clean fix — and usually the design was telling you something:

```kotlin
@Service
class OrderService(
    private val repo: OrderRepository,
    private val audit: AuditService,                                // ← injected, separate bean
) {
    fun place(req: PlaceOrderRequest) {
        audit.record(req)                                           // ← goes through audit's proxy
    }
}

@Service
class AuditService(...) {
    @Audited("place-order")
    @Transactional
    fun record(req: PlaceOrderRequest) { ... }
}
```

Now `audit.record(...)` is a call to a different bean, which is a proxy, so the aspect fires. The reason this is usually the right design: if `audit(...)` has its own cross-cutting behaviour (transaction, audit, async), it's a different responsibility from `place(...)`. Two responsibilities → two beans.

**(B) Self-injection via `@Lazy`.** A smell, but sometimes pragmatic: inject `@Lazy private val self: OrderService` and call `self.audit(req)`. `@Lazy` is required because Spring would refuse the circular self-dependency at startup. Works, but signals the design hasn't fully split responsibilities — prefer (A).

**(C) `AopContext.currentProxy()`.** A worse smell: requires `@EnableAspectJAutoProxy(exposeProxy = true)` and `(AopContext.currentProxy() as OrderService).audit(req)`. Couples your code to Spring internals, fails in plain-Kotlin tests. Avoid unless you have no other option.

### 2. `private` methods are not interceptable

```kotlin
@Service
open class OrderService(...) {
    @Transactional
    private fun doWork() { ... }                                    // ← Spring AOP can't see this
}
```

Both JDK dynamic proxies and CGLIB intercept by **overriding** methods. `private` methods aren't on the interface (JDK can't see them) and aren't overridable (CGLIB can't subclass them). The annotation is silently dead. AspectJ can intercept `private` methods; Spring AOP cannot.

**Fix**: make the method `public` (or `internal` — see Kotlin specifics) on a bean. If "but the caller is just this class!" — then the annotation belongs on the public entry point, not the helper.

### 3. `final` methods / `final` classes

```kotlin
@Service
class OrderService(...) {                                            // ← Kotlin: `final` by default!
    @Transactional
    fun place(req: PlaceOrderRequest) { ... }
}
```

- **CGLIB** generates a subclass that overrides methods. It can't subclass a `final` class — startup fails with `Cannot subclass final class`. It can't override a `final` method — the method is silently skipped, the aspect doesn't fire.
- **JDK dynamic proxy** generates a new class implementing the bean's interfaces. `final` on the class doesn't matter, but `final` methods on the interface aren't a thing in Java (interface methods can't be `final` before `default` methods anyway).

**Kotlin classes are `final` by default.** Two options:

- **`kotlin-spring` (`all-open`) plugin** (the right answer for app code) automatically opens classes annotated with `@Component` / `@Service` / `@Repository` / `@Controller` / `@RestController` / `@Configuration` / `@Async` / `@Transactional` / `@Cacheable`. Most teams' `build.gradle.kts` already has it:

  ```kotlin
  plugins {
      kotlin("plugin.spring") version "..."
  }
  ```

- **`open class` explicitly** for classes that aspects target but aren't stereotyped (rare in app code; common in libraries):

  ```kotlin
  open class CustomBean(...) {
      open fun handle() { ... }
  }
  ```

`kotlin-jpa` (`no-arg`) is a separate, orthogonal plugin that adds a synthetic no-arg constructor to `@Entity` / `@MappedSuperclass` / `@Embeddable`. See `hibernate` for that side.

### 4. `new SomeService(...)` — no Spring, no proxy

```kotlin
@RestController
class OrderController {
    fun place(req: PlaceOrderRequest) {
        val service = OrderService(...)                              // ← non-Spring instance
        service.place(req)                                           // ← @Transactional silently no-op
    }
}
```

A non-Spring-managed instance has no proxy wrapped around it — the AOP machinery only kicks in when Spring's `BeanPostProcessor` wraps the bean during context refresh. The annotation is dead. Always inject the bean; never `new` a `@Service`.

### 5. Aspects on methods called from constructors

```kotlin
@Service
open class OrderService(
    private val repo: OrderRepository,
) {
    init {
        warmCache()                                                  // ← proxy not installed yet
    }

    @Cacheable("orders")
    open fun warmCache() { ... }
}
```

The proxy is wrapped by `BeanPostProcessor#postProcessAfterInitialization` — **after** the constructor and `@PostConstruct` complete. Inside the constructor (and inside `init { }`), `this` is the raw bean, not the proxy. Aspect doesn't fire.

**Fix**: move the call to `@PostConstruct` on a separate bean, or to `ApplicationRunner`, or to an `@EventListener(ApplicationReadyEvent::class)`. See `spring-bean` for the lifecycle hooks.

## Built-in AOP-driven Spring annotations

Each is a custom aspect Spring (or its ecosystem) wrote for you. Same proxy machinery, same gotchas.

| Annotation | What it wraps the method in | Canonical skill |
|---|---|---|
| `@Transactional` | DB transaction (begin / commit / rollback) | **`spring-transactions`** |
| `@Async` | Submit to a `TaskExecutor`; return `CompletableFuture<T>` or `Unit` | **`spring-async`** |
| `@Scheduled` | Register on a `TaskScheduler`; cron / fixedRate / fixedDelay | **`spring-scheduler`** |
| `@Cacheable` | Cache-aside check → call → store | **`spring-cache`** |
| `@CacheEvict` / `@CachePut` | Cache mutation | **`spring-cache`** |
| `@PreAuthorize` / `@PostAuthorize` | SpEL authorisation check | **`spring-security`** |
| `@EventListener` | Subscribe to `ApplicationEvent`s | **`spring-events`** |
| `@TransactionalEventListener` | Subscribe with TX-phase filter (`AFTER_COMMIT`) | **`spring-events`** |
| `@Validated` (on a bean method) | Method-level bean validation | **`spring-validation`** |
| `@Retry` / `@CircuitBreaker` / `@Bulkhead` / `@RateLimiter` (Resilience4j) | Resilience patterns | **`microservices-patterns-deep`** |
| `@Observed` (Micrometer) | Metrics + tracing span around the method | `spring-actuator` |

90% of cross-cutting needs are covered by the above. **Reach for a custom aspect only when none of these fit.**

## When custom aspects are justified — and when they're a smell

**Justified:**

- **Structured logging across a class of methods.** Every `@Service` method gets entry/exit lines with timing, filtered args, correlation ID.
- **Audit trail.** `@Audited("place-order")` aspect writes to an audit log (consider `REQUIRES_NEW` if it must commit independently — see `spring-transactions`).
- **Request-time metric** for endpoints not well-covered by `@Observed`.
- **Idempotency-key check** on inbound HTTP handlers — pull header, look up in cache, short-circuit if already processed.
- **Tenant-context propagation** — read tenant from request, push into `ThreadLocal` / `MDC`, pop after.
- **Method-level feature flag** — `@FeatureFlag("new-checkout")` routes to old vs new based on flag state.

What these share: the concern is genuinely cross-cutting, the behaviour is observable from outside (the aspect doesn't silently change domain results), the contract is small.

**Smells** (covered in Anti-patterns below): domain logic in aspects, re-implementing what Spring already provides, swallowing exceptions, pointcuts so broad they catch unintended beans, conditionally proceeding without a documented contract, ordering by guesswork, aspects on methods called from constructors.

## Advice ordering with `@Order`

When two or more aspects intercept the same join point, the order matters. By default Spring's ordering is undefined (effectively "whatever order the beans were discovered"), which is a recipe for environment-dependent bugs.

```kotlin
import org.springframework.core.Ordered.HIGHEST_PRECEDENCE
import org.springframework.core.Ordered.LOWEST_PRECEDENCE

@Aspect
@Component
@Order(HIGHEST_PRECEDENCE)                                          // outermost — runs first on the way in, last on the way out
class TracingAspect {
    @Around("@within(org.springframework.stereotype.Service)")
    fun trace(jp: ProceedingJoinPoint): Any? {
        val span = tracer.startSpan(jp.signature.name)
        return try { jp.proceed() } finally { span.end() }
    }
}

@Aspect
@Component
@Order(0)                                                            // middle
class MetricsAspect {
    @Around("@within(org.springframework.stereotype.Service)")
    fun timed(jp: ProceedingJoinPoint): Any? {
        val start = Instant.now()
        return try {
            jp.proceed()
        } finally {
            metrics.record(jp.signature.name, Duration.between(start, Instant.now()))
        }
    }
}

@Aspect
@Component
@Order(LOWEST_PRECEDENCE)                                            // innermost — runs last on the way in, first on the way out
class AuditAspect {
    @Around("@annotation(com.example.Audited)")
    fun audit(jp: ProceedingJoinPoint): Any? { ... }
}
```

Reading rule: **lower `@Order` value = higher precedence = wraps further out**. The outermost advice sees the call first and the result last; the innermost is closest to the method body.

Common ordering: tracing (outermost) → metrics → security → transaction → cache (innermost, closest to the database). The defaults Spring uses for its own annotations follow roughly this — see the Javadoc on `org.springframework.transaction.annotation.Transactional` for the relative ordering of `@Transactional` vs other annotations.

## A complete custom aspect — example

A simple `@Around` aspect that logs entry, exit (with duration), and error for any `@Audited`-annotated method, with a reusable `@Pointcut`:

```kotlin
@Target(AnnotationTarget.FUNCTION)
@Retention(AnnotationRetention.RUNTIME)
annotation class Audited(val action: String)

@Aspect
@Component
@Order(50)
class AuditLoggingAspect(
    private val auditLog: AuditLog,
    private val clock: Clock,
) {

    @Pointcut("@annotation(com.example.Audited)")
    fun anyAudited() {}

    @Around("anyAudited() && @annotation(audited)")
    fun logAround(joinPoint: ProceedingJoinPoint, audited: Audited): Any? {
        val start = clock.instant()
        return try {
            val result = joinPoint.proceed()
            auditLog.record(
                action = audited.action,
                args = joinPoint.args.toList(),
                success = true,
                duration = Duration.between(start, clock.instant()),
            )
            result
        } catch (e: Throwable) {
            auditLog.record(
                action = audited.action,
                args = joinPoint.args.toList(),
                success = false,
                error = e::class.simpleName,
                duration = Duration.between(start, clock.instant()),
            )
            throw e                                                  // ← never swallow
        }
    }
}

@Service
class OrderService(...) {
    @Audited("place-order")
    fun place(req: PlaceOrderRequest): Order { ... }
}
```

Notes:
- Named `@Pointcut` (`anyAudited`) makes the intent readable; the `@Around` binds the annotation instance via `@annotation(audited)` so the advice can read `audited.action`.
- `joinPoint.proceed()` is called exactly once on the success path. The error path observes-and-rethrows; never swallows.
- `@Order(50)` documents this aspect's position relative to others. Without it, ordering relative to `@Transactional` etc. is undefined.

## Testing aspects

The single most common mistake: testing the `@Aspect` class in isolation. The aspect machinery runs when Spring wraps the bean in a proxy. A plain `new OrderService(...)` has no proxy — the advice never fires, the test is meaningless.

Three viable approaches:

- **Slice-boot the Spring context** — `@SpringBootTest(classes = [AopConfig::class, AuditLoggingAspect::class, OrderService::class])` (or a narrower configuration) wires the aspect plus the target bean and exercises the call through Spring DI. The proxy is installed, the advice runs.
- **Integration test through the real boundary** — `@WebMvcTest` for aspects on controllers, `@DataJpaTest` for aspects on repositories, full `@SpringBootTest` for cross-cutting aspects.
- **Aspect-as-collaborator unit test** — split the aspect's logic into a pure helper class with no Spring dependency, unit-test that. The aspect becomes a thin wrapper. Works for complex `@Around` logic.

What never works: instantiating the aspect with `new` and calling `aspect.logAround(...)` directly — you exercise the body of the advice but not whether the aspect intercepts the right join points.

## Kotlin specifics

- **`kotlin-spring` (`all-open`) compiler plugin is non-negotiable.** It opens classes annotated with `@Component` / `@Service` / `@Repository` / `@Controller` / `@RestController` / `@Configuration` / `@Async` / `@Transactional` / `@Cacheable`. Without it, every annotated Kotlin class fails CGLIB at startup with `Cannot subclass final class`. Check `build.gradle.kts` if AOP is mysteriously broken.
- **`kotlin-jpa` (`no-arg`) is separate and orthogonal.** Adds a synthetic no-arg constructor to `@Entity` / `@MappedSuperclass` / `@Embeddable`. Doesn't touch AOP — see `hibernate`.
- **Plain Kotlin classes that aspects target need `open class`.** Stereotyped classes get this from `all-open`; everything else is `final` by default. A custom aspect intercepting a non-stereotype class (domain helper, `@Bean`-defined utility) needs `open class CustomBean { open fun ... }`.
- **Coroutines + AOP is awkward.** Pointcuts on `suspend fun` work in Spring 6+ (the `Continuation` arg shows up but Spring handles the matcher). However, `@Around` on a `suspend` method is footgun-prone: the AOP-visible return type is `Any?`, and wrapping `joinPoint.proceed()` in `runBlocking { }` blocks a coroutine-dispatcher thread. Practical: avoid `@Around` on `suspend` for now — keep the cross-cutting concern in a non-suspend bridge method, or use coroutine-aware mechanisms (`CoroutineContext` elements, Reactor `ContextView` on WebFlux).
- **`internal` Kotlin visibility + AOP**: `internal` mangles the JVM method name (`place` → `place$myModule_main`). Pointcuts matching by method name either use the mangled name (fragile) or match by annotation / signature / type. Prefer annotation-based pointcuts for `internal` methods.
- **`object` and AOP**: a Kotlin `object` is a JVM singleton constructed by the JVM, not Spring. No proxy, no AOP. Use `@Component class` for anything that needs aspect interception.

## Anti-patterns

- **Domain logic in an aspect.** Aspects are observers / wrappers, not domain code. Discount calculation, order-total formula, eligibility check — they don't live in `@Around`.
- **Swallowing exceptions in `@AfterThrowing` or `@Around`.** `@AfterThrowing` observes; the exception propagates regardless. `@Around` *can* catch-and-return and swallow — almost always a bug.
- **Pointcuts so broad they match unintended beans.** `execution(* *(..))` hits `Object.toString()` on every bean. Always scope: `within(com.example.app..*)`, `@within(SomeAnnotation)`, `bean(*Service)`.
- **`@Around` aspects that `proceed()` conditionally without a documented contract.** Silently changes call semantics; the caller has no idea why their method returned `null`.
- **Advice ordering by guesswork.** No `@Order` on multiple aspects on the same join point. Behaviour depends on bean discovery order — changes with classpath.
- **Ignoring the proxy nature.** "Why isn't my aspect firing?" — almost always self-invocation, `final`, `private`, `new`-ed instance, or missing `kotlin-spring` plugin. Diagnose before exotic theories.
- **Testing the `@Aspect` class with `new`.** Proxy isn't engaged; the test is meaningless. Slice-boot the context.
- **Custom aspect that re-implements `@Transactional` / `@Cacheable` / `@Validated`.** Delete it; use Spring's.
- **Reaching for full AspectJ to escape self-invocation.** Sometimes legitimate; 90% of the time the design is the problem — split the responsibility into a second bean.

## Related skills

- `spring` — family router and cross-cutting Spring principles
- `spring-bean` — lifecycle ordering, why the proxy is installed in `postProcessAfterInitialization`
- `spring-boot` — `@EnableAspectJAutoProxy` auto-enabled by Boot
- `spring-transactions` — `@Transactional` semantics; **proxy-gotcha diagnosis points here**
- `spring-async` — `@Async` and the same proxy gotchas
- `spring-scheduler` — `@Scheduled` and the same proxy gotchas
- `spring-cache` — `@Cacheable` / `@CacheEvict` / `@CachePut`; same proxy gotchas
- `spring-security` — `@PreAuthorize` / `@PostAuthorize` expressions; same proxy gotchas
- `spring-events` — `@EventListener` / `@TransactionalEventListener` (AFTER_COMMIT)
- `spring-validation` — `@Validated` on bean methods (method-level Bean Validation as an aspect)
- `spring-actuator` — `@Observed` (Micrometer Observation) as an AOP-driven annotation
- `spring-modulith` — `@ApplicationModuleListener` builds on `@TransactionalEventListener`
- `spring-web-mvc` — controller advice and interceptors as alternatives on the web layer
- `spring-rest-clients` — `HttpExchange` declarative clients use proxies
- `spring-data-jpa` — repository proxies and exception translation
- `hibernate` — `kotlin-jpa` (`no-arg`) plugin; lazy-loading proxies
- `spring-amqp` — `@RabbitListener` proxying for message consumers
- `microservices-patterns-deep` — Resilience4j `@Retry` / `@CircuitBreaker` as AOP-driven annotations
- `cqrs-implementation` — command-handler dispatch via aspects in some implementations
- `database-design` — orthogonal; routed here when a "TX boundary" question is really an AOP-fire question
- `api-design-principles` — idempotency-key middleware as an aspect candidate
- `testing-strategy-kotlin-spring` — slice-booting a context that engages a specific aspect
- `methodology` — the always-on coding cadence wrapping any change to an aspect
- `clean-code-systems` — cross-cutting concerns wired declaratively, not inline
- `karpathy-guidelines` — always-on coding discipline

## Limitations

- Targets Spring AOP on Spring Boot **3+** with Kotlin 2.x / JVM 21+. Boot 2.x defaults (`proxyTargetClass`) differ.
- Doesn't cover **full AspectJ depth** — compile-time weaving, `ajc` compiler, LTW JVM agents, intertype declarations, field-access / constructor pointcuts. See the AspectJ docs and Spring reference's AspectJ section.
- Doesn't cover **AOP overhead benchmarking** — every proxy hop adds nanoseconds; irrelevant for most services. Hot-path code should profile (see `jvm-performance`) and consider AspectJ weaving.
- Doesn't cover **GraalVM Native Image + AOP** — works but reflection / proxy hints may need `@RegisterReflectionForBinding` for custom aspects.
- Doesn't cover **WebFlux + AOP on `Mono` / `Flux` return types** in depth — `@Around` wraps the imperative call, not the reactive pipeline; cross-cutting concerns compose via `.doOnSuccess { ... }` / `.doOnError { ... }`. See Reactor docs.
