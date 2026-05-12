# Bean Lifecycle and AOP

How Spring brings up beans, runs init logic, shuts down gracefully. AOP for cross-cutting concerns without `if` lattices.

---

## 1. Bean lifecycle, end-to-end

```
1. Bean defined  (via @Component, @Bean, @Configuration scan)
2. Bean instantiated  (constructor called)
3. Dependencies injected  (via constructor — only option for `val` fields)
4. @PostConstruct methods called
5. (Optional) Smart init: ApplicationRunner / CommandLineRunner / ApplicationListener
6. Ready
   ...
   Shutdown signal
   ...
7. @PreDestroy methods called
8. Bean disposed
```

### Constructor injection only

```kotlin
@Service
class OrderService(
    private val orders: OrderRepository,
    private val events: ApplicationEventPublisher,
    private val clock: Clock,
)
```

- `val` (immutable) — Kotlin idiomatic
- Single constructor, Spring auto-detects (no `@Autowired` needed)
- Tests instantiate directly: `OrderService(mockk(), mockk(), Clock.fixed(...))`

Field injection (`@Autowired var orders: OrderRepository`) is forbidden. Reasons in `clean-code-systems` (constructor-injection-by-default).

---

## 2. `@PostConstruct` and `@PreDestroy`

```kotlin
@Service
class CacheWarmer(
    private val cache: Cache,
    private val source: SomethingExpensive,
) {
    @PostConstruct
    fun warmCache() {
        cache.putAll(source.loadAll())   // runs once, after DI complete
    }

    @PreDestroy
    fun shutdown() {
        cache.clear()
    }
}
```

**Rules:**
- `@PostConstruct` runs **after** all dependencies are injected. Safe to call them.
- `@PostConstruct` is **synchronous** during startup — slow ones delay readiness. Don't call external APIs.
- Throwing from `@PostConstruct` aborts startup. Use carefully.
- `@PreDestroy` runs during graceful shutdown. May be skipped on `kill -9`.

---

## 3. `ApplicationRunner` / `CommandLineRunner`

Run logic **after** the entire context is up, *before* serving traffic.

```kotlin
@Component
class StartupChecks(
    private val migrations: MigrationVerifier,
    private val externalApis: ExternalApiHealth,
) : ApplicationRunner {
    override fun run(args: ApplicationArguments) {
        migrations.verifyAllMigrationsApplied()
        externalApis.pingAll()
    }
}
```

Difference vs `@PostConstruct`:
- `@PostConstruct` per-bean; runs after its own deps.
- `ApplicationRunner` runs **after the entire ApplicationContext is ready** — so all beans, all auto-configs, all `@PostConstruct`s done.
- Use `ApplicationRunner` for cross-bean coordination ("verify migrations + verify externals + warm caches in order").

### Ordering multiple runners

```kotlin
@Component
@Order(1) class FirstRunner : ApplicationRunner { … }

@Component
@Order(2) class SecondRunner : ApplicationRunner { … }
```

Lower `@Order` = earlier.

---

## 4. `ApplicationListener` — event-driven init

```kotlin
@Component
class WarmsCacheOnReady(private val cache: Cache) {
    @EventListener
    fun on(event: ApplicationReadyEvent) {
        cache.warm()
    }
}
```

Spring publishes lifecycle events:

| Event | When |
|---|---|
| `ApplicationStartingEvent` | Very early |
| `ApplicationEnvironmentPreparedEvent` | Env loaded, before context creation |
| `ApplicationContextInitializedEvent` | Context created, beans not loaded |
| `ApplicationPreparedEvent` | Beans loaded, not refreshed |
| `ContextRefreshedEvent` | Refresh complete (you can use beans now) |
| `ApplicationStartedEvent` | Boot complete, runners not yet run |
| `ApplicationReadyEvent` | All runners done, ready to serve traffic ✅ |
| `ApplicationFailedEvent` | Bootstrap failed |
| `ContextClosedEvent` | Shutdown initiated |

For "do X when app is ready to serve" → `ApplicationReadyEvent`. For "do X when bean Y becomes available" → custom events or `@PostConstruct` on bean Y.

---

## 5. Lazy beans

By default, all `@Component` / `@Bean` are eagerly instantiated at startup. `@Lazy` defers:

```kotlin
@Component
@Lazy
class SeldomUsedExpensiveBean(...)
```

Created on first use. Costs ~negligible per call (one volatile read) but defers heavy startup.

### Global lazy init

```yaml
spring:
  main:
    lazy-initialization: true
```

All beans lazy by default. Faster startup, but startup errors surface as first-request errors. Trade-off.

**Use lazy global init for:** dev / CLI tools where startup speed matters more than early error detection.

**Don't use for:** production services where you want errors visible at startup.

---

## 6. Bean scope

```kotlin
@Component @Scope("singleton")   // default
@Component @Scope("prototype")   // new instance per injection
@Component @Scope("request")     // per HTTP request (Web scope)
@Component @Scope("session")     // per HTTP session
```

99% of Spring beans are singletons. Don't change unless you have a real reason.

`prototype` is the "I want a fresh instance each time" use case — but injecting prototype into singleton is tricky (singleton holds reference to one prototype). Use `ObjectFactory<T>` or method injection.

---

## 7. `@DependsOn`

Force ordering when one bean must initialise before another:

```kotlin
@Component
@DependsOn("databaseMigrator")
class CachingLayer(...)
```

Almost always a smell. Better:
- Use `ApplicationRunner` for ordered runtime init
- Constructor-inject the dep (then DI handles order)

Reach for `@DependsOn` only when constructor injection isn't possible (e.g., reactive registration of external triggers).

---

## 8. Graceful shutdown

```yaml
server:
  shutdown: graceful

spring:
  lifecycle:
    timeout-per-shutdown-phase: 30s
```

When the app receives SIGTERM:
1. Server stops accepting new requests (rejects with 503 or refuses connection)
2. In-flight requests complete (up to timeout)
3. `@PreDestroy` / `DisposableBean.destroy()` runs
4. JVM exits

Without this, requests get killed mid-execution. Always enable in production.

### K8s readiness/liveness probes

```yaml
management:
  endpoint:
    health:
      probes:
        enabled: true
      show-details: when-authorized

# K8s manifest:
# livenessProbe.path: /actuator/health/liveness
# readinessProbe.path: /actuator/health/readiness
```

Spring Boot Actuator provides `liveness` and `readiness` separately:
- **Liveness** — am I alive? (false → K8s restarts pod)
- **Readiness** — am I ready to serve? (false → K8s stops sending traffic, but keeps pod)

During shutdown, readiness becomes DOWN immediately, then graceful shutdown proceeds.

---

## 9. AOP — cross-cutting concerns

When you need to add behaviour around many methods (logging, retry, metrics, security), Spring AOP avoids `if` and inheritance chains.

### Built-in AOP-powered annotations

| Annotation | What it does |
|---|---|
| `@Transactional` | Wrap method in DB transaction |
| `@Cacheable` / `@CachePut` / `@CacheEvict` | Spring Cache around method |
| `@Async` | Run method in another thread |
| `@Scheduled` | Cron-like recurring execution |
| `@Retryable` (Spring Retry) | Retry on exception |
| `@PreAuthorize` / `@PostAuthorize` | Security check |
| `@Observed` | Metrics + tracing (Micrometer Observability) |

These are AOP under the hood. Most apps need only these — no custom aspects.

### Custom aspect — when you must

```kotlin
@Aspect
@Component
class AuditLoggingAspect(private val auditLog: AuditLog) {

    @Around("@annotation(audited)")
    fun logAudit(joinPoint: ProceedingJoinPoint, audited: Audited): Any? {
        val start = Instant.now()
        val args = joinPoint.args
        try {
            val result = joinPoint.proceed()
            auditLog.record(audited.action, args, result, success = true, duration = Duration.between(start, Instant.now()))
            return result
        } catch (e: Exception) {
            auditLog.record(audited.action, args, error = e.message, success = false, duration = Duration.between(start, Instant.now()))
            throw e
        }
    }
}

@Target(AnnotationTarget.FUNCTION)
@Retention(AnnotationRetention.RUNTIME)
annotation class Audited(val action: String)

// Usage
@Service
class OrderService(...) {
    @Audited("place-order")
    fun place(req: PlaceOrderRequest): Order { … }
}
```

Any `@Audited` method now has logging automatically. Adding a new audited method = add annotation.

### AOP caveats

- Spring AOP uses **JDK dynamic proxies** (for interfaces) or **CGLIB** (for classes). Only intercepts **external** calls (`a.someMethod()` from outside). **Self-invocation** is not intercepted:

  ```kotlin
  @Service
  class X {
      @Transactional fun outer() { inner() }     // outer is transactional
      @Transactional fun inner() { ... }          // NOT transactional when called from outer
  }
  ```
  
  Fix: inject `self: X` and call `self.inner()`, or restructure.

- **Final classes** can't be CGLIB-proxied. Kotlin classes are `final` by default — add `kotlin-spring` plugin (`build.gradle.kts`) which opens `@Component`, `@Service`, etc. classes automatically.

- **Performance** — each proxy adds a tiny overhead (~ns per call). Not a concern except for hot paths called millions of times/s.

### When NOT to use AOP

- If you can solve it with a function or class, do that. AOP is for cross-cutting concerns that affect **many** methods.
- Don't write 20 custom aspects. Each is a hidden side-effect. Stick to the 5-7 built-in annotations + at most 1-2 custom aspects.

---

## 10. `@Async` — what it really does

```kotlin
@Service
class NotificationService(...) {
    @Async
    fun sendNotificationAsync(userId: UUID, message: String) {
        // runs in a separate thread
        emailClient.send(...)
    }
}
```

Caller returns immediately; method runs in the background.

### Gotchas

- **Return value is `Future<T>`** if you need it back; `void` if fire-and-forget
- **Self-invocation doesn't work** (see AOP caveats)
- **Thread pool config**: by default Spring uses `SimpleAsyncTaskExecutor` — **creates new thread per call**, no pooling! Always configure:

```kotlin
@Configuration
@EnableAsync
class AsyncConfig {
    @Bean(name = ["taskExecutor"])
    fun taskExecutor(): Executor = ThreadPoolTaskExecutor().apply {
        corePoolSize = 4
        maxPoolSize = 16
        queueCapacity = 100
        setThreadNamePrefix("async-")
        initialize()
    }
}
```

- **Exceptions are swallowed** unless return is `CompletableFuture`. Configure global handler:

```kotlin
@Configuration
@EnableAsync
class AsyncConfig : AsyncConfigurer {
    override fun getAsyncExecutor(): Executor { … }

    override fun getAsyncUncaughtExceptionHandler(): AsyncUncaughtExceptionHandler =
        AsyncUncaughtExceptionHandler { ex, method, args ->
            logger.error("async {} failed", method, ex)
        }
}
```

In 2025 (Spring Boot 3.2+), virtual threads from Project Loom are a better choice for many `@Async` use cases — see `boot-3-and-4-changes.md`.

---

## 11. `@Scheduled`

```kotlin
@Component
class CleanupJob(...) {
    @Scheduled(cron = "0 0 3 * * *", zone = "UTC")  // every day 3 AM UTC
    fun cleanupOldRecords() { … }

    @Scheduled(fixedDelay = 60_000)  // 60s after previous completion
    fun pollExternalQueue() { … }

    @Scheduled(fixedRate = 60_000)   // every 60s regardless of duration (concurrent invocations possible)
    fun heartbeat() { … }
}
```

Enable: `@EnableScheduling` on `@Configuration`.

### Gotchas

- **Multi-instance** — every instance runs the schedule independently. For job-once semantics, use ShedLock or DB-based leader election.
- **Default single-threaded scheduler** — long-running jobs block subsequent runs. Configure thread pool:

```kotlin
@Bean
fun taskScheduler(): TaskScheduler = ThreadPoolTaskScheduler().apply {
    poolSize = 5
    setThreadNamePrefix("scheduler-")
    initialize()
}
```

- **Exceptions** rolled into logs, schedule continues. Wrap in try/catch if you want different behaviour.

For complex scheduling, use Spring Batch or Quartz instead.

---

## 12. Cross-cutting concerns checklist

These belong to AOP / annotations, not duplicated in every service:

- [ ] Audit logging — `@Audited` aspect or via `@Observed`
- [ ] Metrics — `@Timed`, `@Counted` (Micrometer) or `@Observed`
- [ ] Tracing — automatic with Micrometer Tracing
- [ ] Retry — `@Retryable` (Spring Retry library)
- [ ] Caching — `@Cacheable` / Spring Cache
- [ ] Security — `@PreAuthorize` / `@PostAuthorize`
- [ ] Transactions — `@Transactional`
- [ ] Async — `@Async`
- [ ] Schedule — `@Scheduled`

If you find yourself adding `try { ... } catch (...) { logger.error(...); metrics.increment(...) }` to every service method — that's the AOP signal.
