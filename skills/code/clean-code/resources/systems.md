# Systems — composition root, DI, POJOs at the core, aspects at the edge

System-level discipline: where wiring lives, what cross-cutting concerns belong where, and the rule that the domain compiles without Spring.

## Output template — when reviewing system wiring

1. **Where's the composition root?** All `new` / `@Bean` happens there; business code receives collaborators.
2. **Smells found.** Field injection, service-locator usage, framework imports in domain, inline cross-cutting.
3. **Cross-cutting concerns** — should this be an aspect/annotation?
4. **Action plan.** Inject what's looked up, lift cross-cutting to a declarative seam, isolate framework from domain.

## The composition root rule

A composition root is the **single place** where the application's object graph is built. In Spring Boot: `@SpringBootApplication` + `@Configuration` classes + component scanning. All dependency wiring happens here. Business code does **not** call `new` on a collaborator or fetch one from a static.

```kotlin
// ✓ Business code receives collaborators
@Service
class OrderApplicationService(
    private val orders: OrderRepository,
    private val publisher: ApplicationEventPublisher,
    private val clock: Clock,
) { ... }

// ✗ Lazy-init in business code — construction leaked into use
class OrderApplicationService {
    private var orders: OrderRepository? = null
    fun submit(...) {
        if (orders == null) orders = OrderRepository(...)
    }
}

// ✗ Service locator — class actively resolves its own deps
class OrderApplicationService(private val ctx: ApplicationContext) {
    fun submit(...) {
        val orders = ctx.getBean(OrderRepository::class.java)
    }
}
```

## Constructor injection by default

| Form | When |
|---|---|
| **Constructor** | Default. Required collaborators as `val` primary-constructor parameters. Cycles surface at compile/startup, not in production. |
| **Setter** | Genuinely optional collaborator with a default. In Kotlin usually replaced by a default constructor argument: `clock: Clock = Clock.systemUTC()`. |
| **Field (`@Autowired var`)** | **Never in Kotlin.** Defeats `val`, hides cycles, requires Spring to test. |

## POJOs at the core

Domain classes import **no framework types**. No `@Component`, no `@Entity`, no `@Autowired`, no `org.springframework.*` in the domain layer. The domain compiles without Spring on the classpath. Persistence, transactions, security, caching attach at the **edge** — application layer, adapters, configuration.

## Cross-cutting concerns are declarative, not inline

| Concern | Spring affordance | Anti-pattern |
|---|---|---|
| Transactions | `@Transactional` on the application-service method | `transactionManager.begin()` / commit / rollback in service code |
| Security | `@PreAuthorize` / `@Secured` / filter chain | `if (!user.hasRole(...))` at the top of every method |
| Caching | `@Cacheable` / `@CacheEvict` | `cache.get(key) ?: compute().also { cache.put(key, it) }` |
| Retry | Resilience4j `@Retry` / Spring Retry | manual `for (attempt in 1..3) try ... catch ...` |
| Circuit breaker | Resilience4j `@CircuitBreaker` | manual failure-counter + state machine |
| Metrics | Micrometer `@Timed` / `Counter` on a method | `meter.start(); try { ... } finally { meter.record(...) }` |
| Audit logging | `@Aspect` `@Around("execution(...)")` advice | `logger.info("user X did Y")` at every call site |
| Distributed tracing | OpenTelemetry agent / auto-instrumentation | manual `tracer.start(...)` spans |

**The 3-places rule:** a concern qualifies as cross-cutting if it's needed in **≥ 3 places** and is **policy** (uniform), not **logic** (variable per call). Don't pre-aspect a one-off.

## Lazy-init — tolerated at seams, banned in business code

`lazy { }` is fine when computing an expensive **derived value** that may never be needed, the value is **immutable**, and the boundary is a clear seam (a `@Bean` method, an extension property, a top-level `val`).

Not fine when it's a **dependency** — that's what DI is for. Not fine when it mutates (`var` with null check — race condition). Not fine when scattered.

## Modulith-first, microservices-later

Don't split a 3-team monolith into 12 microservices "for scale" before any service has a different deploy cadence, load profile, or team owner. **Spring Modulith** gives you in-process module boundaries with `@ApplicationModule`, event-driven communication, and architecture tests — for much lower cost. Split into a separate service when:

- The module has a different deploy cadence.
- It has a different scaling profile.
- A different team owns it.
- Its data store and consistency model are incompatible.

## Smell → fix lookup

| Smell | Fix |
|---|---|
| `new MyService()` in business code | Constructor injection. |
| `ApplicationContext.getBean(...)` in domain | Inject the bean. |
| `if (svc == null) svc = ...` manual lazy-init | Inject. If genuinely lazy, `lazy { }` at a seam. |
| `@Autowired var` field | `val` constructor parameter. |
| `try { ... transactionManager.commit() } catch { rollback() }` | `@Transactional`. |
| Audit / metrics / retry code at top of business method | Aspect or annotation. |
| 800-line `@Configuration` class | Split per module (`OrderModuleConfig`, etc.). |
| `if (env == "prod") ...` in business code | `@Profile` or `@ConditionalOnProperty` on alternative beans. |
| Environment variable read in service constructor | `@ConfigurationProperties` data class injected as bean. |
| Three services duplicate "open Stripe client" code | Wrap in a `StripeClient` `@Component`; inject. |
| Test for service needs `@SpringBootTest` + Testcontainers + WireMock just to construct | Use case too coupled — narrow it, inject ports, build it as a plain Kotlin class in the test. |

## Anti-patterns in system-level work itself

- **Big Design Up Front (BDUF).** Designing the read model, event bus, saga engine, and 4 microservices for a 2-week MVP. Solve today's story.
- **God `Application.kt` / `main`.** Bootstrap that grew to read 12 env vars, branch on 5 profiles, conditionally register 30 beans. Split into `@Configuration` modules.
- **Premature microservices.** Modulith first; split when a real boundary appears.
- **Cargo-cult standards.** Adopting GraphQL / event sourcing / hexagonal because the conference talk said so. Adopt when *this* project's pain matches the standard's solution.
- **AOP for non-cross-cutting code.** An `@Aspect` for one method in one place is just a function call.
- **Decision deferral as decision avoidance.** Defer until the **last responsible** moment — when not deciding costs more than deciding wrong.
- **Test-only seams.** Composition root so framework-bound that the only way to test the core is `@SpringBootTest`. The core should be runnable from a 10-line POJO main.
