---
name: clean-code-systems
description: "System-level construction and modularity discipline for Kotlin/Spring Boot code — opinionated rules for separating construction from use (composition root, no lazy-init scattered through business code), Dependency Injection / Inversion of Control (constructor injection over field/setter, no service-locator lookups in domain), POJOs at the core (Kotlin classes with zero framework imports in the domain), cross-cutting concerns wired declaratively (transactions, security, caching, retry, observability via aspects — not coded inline), test-drivable architecture (evolve incrementally, no Big Design Up Front), decision-deferral to the last responsible moment, judicious use of standards (only when they add demonstrable value), and Domain-Specific Languages at the domain boundary. Adapted from R. Martin's Clean Code Ch. 11 'Systems', filtered for what Kotlin/Spring already solves (constructor-injection-by-default, `@ConfigurationProperties`, `@Profile` / `@Conditional`, `@Transactional` as aspect, Spring Modulith for in-process modularity, Kotlin's `object` singletons, `lazy { }` delegation, type-safe builder DSLs, the `beans { }` Spring DSL, Gradle Kotlin DSL) and extended with Spring Boot conventions (auto-configuration, starter modules, profile-driven wiring, test slices, functional bean definitions). Use when designing the bootstrap / composition root of a new service, picking between constructor / setter / field injection, deciding where lazy-init belongs, wrapping a cross-cutting concern (auth, audit, retry, metrics, transactions) as an aspect vs. inline code, choosing between Spring Modulith and separate microservices, designing a domain-specific configuration / business-rules DSL, refactoring a service whose construction code is tangled with runtime logic, planning incremental architectural evolution without a rewrite, or auditing a service for system-level coupling and modularity smells."
risk: safe
source: "Adapted from R. Martin & K. D. Wampler, Clean Code (2008), ch. 11 'Systems', filtered for Kotlin/Spring + house rules"
date_added: "2026-05-12"
---

# Clean Code: Systems

> "Complexity kills. It sucks the life out of developers, it makes products difficult to plan, build, and test." — Ray Ozzie (quoted by Wampler)
>
> "An optimal system architecture consists of modularised domains of concern, each implemented with Plain Old [Kotlin] Objects. The different domains are integrated together with minimally invasive Aspects or Aspect-like tools." — Wampler, paraphrased
>
> "Use the simplest thing that can possibly work." — closing line of Ch. 11

Systems break in three places: at **bootstrap** (construction code mixed with use), at **boundaries** (cross-cutting concerns hard-coded everywhere), and at **decisions** (committed too early, expensive to walk back). Clean code at the *function* and *class* level is not enough — a codebase built from clean classes can still ship a tangled system if the wiring is mixed with the work, and if change-resilience was never designed in.

This skill is the opinionated catalog of system-level discipline: classical rules from Martin/Wampler's Ch. 11, filtered through what Spring and Kotlin have made trivial (constructor injection, aspects via annotations, type-safe DSLs, Modulith) and extended with house rules where they bend the abstract advice into concrete project conventions.

## Use this skill when
- Starting the bootstrap / composition root of a new Spring Boot service.
- Deciding **how** to inject dependencies (constructor, setter, field, factory, service locator) — and where the boundary between framework and domain code sits.
- Spotting a `lazy { ... }` or `if (x == null) x = ...` idiom in business code and asking whether construction has leaked.
- Adding a cross-cutting concern (audit, retry, metrics, security, transaction) and choosing between writing it inline, wrapping it in a decorator, or declaring it as an aspect.
- Deciding between **Spring Modulith** (in-process modules with events) and **microservices** for a new bounded context.
- Designing a small **DSL** for configuration, business rules, or routing — and asking whether a DSL even earns its place.
- Refactoring a `main` / `Application.kt` that has accumulated wiring logic, profile switches, and bean conditionals.
- Auditing a service for system-level smells: tight coupling, hidden lazy-init, premature framework adoption, BDUF, untested wiring.
- Planning incremental architectural change — strangler, parallel-write, feature-flagged migration — without a rewrite.

## Do not use this skill when
- Designing **inside one function or class** — use `clean-code-functions` / `clean-code-objects-and-data` / `solid-principles` / `grasp-patterns`.
- Picking a **layout pattern** for a single module (Layered vs. Onion vs. Clean) — use `architecture-patterns`.
- Drawing **bounded contexts** — use `ddd-strategic-design` first; this skill covers how to *wire* them, not how to find them.
- Choosing the **distributed-systems** patterns (gateway, mesh, service discovery, circuit-breaker tuning) — use `microservices-patterns-deep`.
- The "system" is a hosted-anywhere library or a script — there is no composition root to design.

## Core principles (the ten)

1. **Separate construction from use.** The bootstrap (object construction + dependency wiring) is a different concern from the runtime work. Construction code lives in `main` / `@SpringBootApplication` / `@Configuration` classes; the rest of the system assumes wiring is already done. The application has **zero knowledge** of how it was wired.
2. **Dependency Injection, not service location.** A class declares what it needs (constructor parameters) and is *given* those collaborators. It does not look them up (`ApplicationContext.getBean(...)`), instantiate them (`new MyServiceImpl()`), or call frameworks to fetch them (JNDI, static factories). IoC moves the wiring responsibility out of the class — preserving SRP, simplifying tests.
3. **Constructor injection by default.** Setter injection only for genuinely optional collaborators with sensible defaults; field injection (`@Autowired var ...`) is forbidden in Kotlin (it defeats `val`, hides cycles, breaks testability without Spring). Required dependencies become `val` constructor parameters.
4. **POJOs at the core.** Domain classes import no framework types — no `@Component`, no `@Entity`, no `@Autowired`, no `org.springframework.*`. Persistence, transactions, security, caching attach at the **edge** (application layer, adapters, configuration). The core compiles without Spring on the classpath.
5. **Cross-cutting concerns are declarative, not coded inline.** Transactions, security checks, retries, audit logs, metrics, caching are aspects (annotations or wrappers) attached at the seam — not `try/catch` / `if (auth)` / `meter.record(...)` scattered through business methods. One place changes one cross-cutting policy.
6. **Test-drive the architecture; no BDUF.** Start with the simplest decoupled design that delivers today's stories. Add infrastructure (cache, event bus, projection store, separate read model) only when a story needs it. Keep seams clean so the addition stays additive, not invasive.
7. **Defer decisions to the last responsible moment.** A premature decision is made with the least information — about the domain, the load, the integrations, the team. Decoupled architecture is what gives you the option to defer; tight coupling locks the decision in.
8. **Standards earn their place by adding demonstrable value.** Adopt JPA, gRPC, OAuth2, GraphQL, EJB-style boundaries — when they solve a problem you have, not because the industry signals it. Resist obsession with standards that lose touch with project needs.
9. **A DSL minimises the gap between the domain and the code.** When the domain has its own vocabulary that experts speak (routing rules, pricing tiers, eligibility, build pipeline), a small DSL lets the code read like that prose. The DSL is a feature when domain experts can read it; otherwise it's overhead.
10. **Modularity at every scope.** The same separation-of-concerns argument that cleans up a function cleans up a service, a service group, and a bounded context. Apply it consistently — at the function level (Ch. 3), the class level (Ch. 6, 10), and the system level (Ch. 11).

## The composition root — where wiring lives

A **composition root** is the single place where the application's object graph is built. In Spring Boot, it's the `@SpringBootApplication` class + `@Configuration` classes + `@Component` scanning. The rule is: **all dependency wiring happens here**; no business code calls `new` on a collaborator or fetches one from a static.

```kotlin
// ✓ Composition root — main + @Configuration
@SpringBootApplication
class OrderServiceApplication

fun main(args: Array<String>) {
    runApplication<OrderServiceApplication>(*args)
}

@Configuration
class OrderModuleConfig {
    @Bean
    fun orderApplicationService(
        orders: OrderRepository,
        publisher: ApplicationEventPublisher,
        clock: Clock,
    ): OrderApplicationService = OrderApplicationService(orders, publisher, clock)
}
```

```kotlin
// ✓ Service receives collaborators — no lookup, no new, no lazy-init
@Service
class OrderApplicationService(
    private val orders: OrderRepository,
    private val publisher: ApplicationEventPublisher,
    private val clock: Clock,
) { ... }
```

**Anti-patterns**:
```kotlin
// ✗ Lazy-init in business code — construction leaked into use
class OrderApplicationService {
    private var orders: OrderRepository? = null
    fun submit(...) {
        if (orders == null) orders = OrderRepository(...)   // ← bootstrap in runtime
        ...
    }
}

// ✗ Service locator — class actively resolves its own deps
class OrderApplicationService(private val ctx: ApplicationContext) {
    fun submit(...) {
        val orders = ctx.getBean(OrderRepository::class.java)   // ← runtime lookup
    }
}
```

## Lazy-init: tolerated at the seam, banned in business code

`lazy { ... }` is fine when:
- Computing an expensive **derived value** that may never be needed (a parsed config, a memoised lookup).
- The lazy value is **immutable** (`val cached: List<X> by lazy { computeOnce() }`).
- The lazy boundary is at a clear seam (a `@Bean` method, an extension property, a top-level `val`).

It is not fine when:
- It's a **dependency** — that's what DI is for.
- It mutates (`var` with null check) — race condition, no thread safety.
- It's scattered — many sites lazily initialising the same thing, no global strategy.

```kotlin
// ✓ lazy at a seam — derived, immutable, expensive
class GeoCatalog(private val raw: GeoFeed) {
    val tree: SpatialIndex by lazy { SpatialIndex.from(raw.entries) }
}

// ✗ lazy as a dependency-injection workaround
class OrderService {
    private val payments: PaymentClient by lazy { PaymentClient.fromEnv() }   // ← inject it
}
```

## Constructor vs setter vs field injection — quick rules

| Form | When | Notes |
|---|---|---|
| **Constructor** | Default. Required collaborators. | Kotlin's `val` primary constructor is built for this. Cycles surface at compile/startup, not in production. |
| **Setter** | Genuinely optional collaborator with a sensible default. | Rare in Kotlin — usually replaced by a default constructor argument: `clock: Clock = Clock.systemUTC()`. |
| **Field** (`@Autowired var`) | Never in Kotlin. | Hides cycles, defeats `val`, requires Spring to test, can't enforce non-null at compile time. |
| **Static / global / `companion object` factory** | For things that *are* singletons by nature (a `Clock`, a `Random`) — used as default arguments, not injected. | Anything stateful → DI. |

## Cross-cutting concerns — the aspect catalogue

| Concern | Spring affordance | Anti-pattern |
|---|---|---|
| Transactions | `@Transactional` at the application-service method | `transactionManager.begin()` / commit / rollback in service code |
| Security | `@PreAuthorize` / `@Secured` / filter chain | `if (!user.hasRole(...))` checks at the top of every method |
| Caching | `@Cacheable` / `@CacheEvict` | `cache.get(key) ?: compute().also { cache.put(key, it) }` boilerplate |
| Retry | Resilience4j `@Retry` / Spring Retry | manual `for (attempt in 1..3) try ... catch ...` |
| Circuit breaker | Resilience4j `@CircuitBreaker` | manual failure-counter + state machine |
| Metrics | Micrometer `@Timed` / `Counter` on a method | `meter.start(); try { ... } finally { meter.record(...) }` |
| Audit logging | `@Aspect` `@Around("execution(...)")` advice | `logger.info("user X did Y")` at every call site |
| Distributed tracing | Auto-instrumented by Spring Boot Actuator / OpenTelemetry agent | manual `tracer.start(...)` spans |
| Idempotency | a `@RequestIdempotent` aspect or Spring Modulith outbox | manual idempotency-token tables checked in business code |

**House rule**: a concern qualifies as cross-cutting if it's needed in **≥ 3 places** and is **policy** (uniform across calls), not **logic** (variable per call). Wrap the third occurrence; don't pre-aspect a one-off.

## Test-driving architecture — the incremental ladder

Don't start with the full set of integrations. Start with the smallest end-to-end happy path that delivers today's story. Add what the next story needs.

| Layer | Adds when |
|---|---|
| **POJO + in-memory repo + plain controller** | Day 1 — get a vertical slice running. |
| **`@DataJpaTest` + Testcontainers Postgres** | A query becomes complex enough that an in-memory mock would lie. |
| **`@WebMvcTest` for the API contract** | The contract has shape (validation rules, error responses) worth pinning. |
| **`@SpringBootTest` integration** | Wiring or cross-cutting (security, transactions) matters more than the units. |
| **Async messaging** | Two services need to coordinate without synchronous coupling. |
| **Projection / read model (CQRS)** | Read-side query shapes diverge enough from the write model that a denormalised view earns its keep. |
| **Saga / process manager** | A workflow spans multiple aggregates and needs compensation. |
| **Separate microservice** | The bounded context has a different deploy cadence, scaling profile, or team. |

Each step is **additive on the previous architecture**, *if* the previous step kept seams clean.

## Quick smell → fix table

| Smell | Fix |
|---|---|
| `new MyService()` in business code | Constructor injection; declare as `@Bean` or `@Component`. |
| `ApplicationContext.getBean(...)` in domain | Inject the bean. Service locator is anti-DI. |
| `if (svc == null) svc = ...` (manual lazy-init) | Inject. If genuinely lazy, `lazy { }` at a seam. |
| `@Autowired var` field | `val` constructor parameter. |
| `try { ... transactionManager.commit() } catch { rollback() }` | `@Transactional` annotation; remove TX plumbing. |
| Audit / metrics / retry code at top of business method | Aspect or annotation; move policy to one place. |
| 800-line `@Configuration` class | Split per module (`OrderModuleConfig`, `PaymentModuleConfig`). |
| Profile-coupled if/else in business code (`if (env == "prod") ...`) | `@Profile` or `@ConditionalOnProperty` on alternative beans. |
| Environment variable read in service constructor | `@ConfigurationProperties` data class injected as bean. |
| Hand-rolled bean wiring in `main()` for a Spring Boot app | Use component scan + `@Configuration`. Manual wiring is for non-Spring projects (Koin, simple `main` apps). |
| Three services duplicate "open Stripe client" code | Wrap in a `StripeClient` `@Component`; inject. |
| DSL invented before two callers need it | Plain code with two callers is fine; DSL pays off at 5+ distinct uses or a domain expert who'll read it. |

## Selective Reading Rule

| File | When to read |
|---|---|
| `resources/general-system-rules.md` | Martin/Wampler Ch. 11 rules as a foundation — separating construction from use, factories, DI/IoC, cross-cutting concerns + AOP, Java proxies (history), POJOs vs framework coupling, test-driving the architecture, decision deferral, judicious standards, DSLs. Bad/Good with explanations. Read first. |
| `resources/kotlin-specific-systems.md` | What Kotlin solves: `object` declarations as compile-time singletons, `companion object` factories, `lazy { }` delegation as a controlled lazy-init, default arguments replacing setter-injection patterns, type-safe builder DSLs, Gradle Kotlin DSL, the Koin alternative for non-Spring Kotlin apps, `inline` higher-order functions as lightweight AOP, extension functions as cross-cutting helpers, coroutine `CoroutineScope` boundaries as system seams. |
| `resources/spring-boot-systems.md` | Spring Boot conventions: `@SpringBootApplication` and auto-configuration, constructor injection idioms in Kotlin, `@Configuration` module split, `@ConfigurationProperties` typed config, `@Profile` / `@Conditional*` for evolvable wiring, bean lifecycle (`@PostConstruct`, `ApplicationRunner`, `SmartInitializingSingleton`), Spring AOP (`@Aspect`, `@Around`), `@Transactional` as the canonical aspect, Spring Modulith for in-process modules, the `beans { }` Kotlin DSL, test slices, profile-aware integration tests. |
| `resources/ddd-systems.md` | System-level discipline through a DDD lens: composition root per bounded context, ACL adapters as the system seam between contexts, Modulith vs. microservices decision, command/event seam, aggregate construction (factories, not container-managed), domain DSLs (specifications, policies), strangler-fig migration of a monolith. |

## Anti-patterns at the system level

- **Big Design Up Front (BDUF).** Designing the read model, event bus, saga engine, and 4 microservices for a 2-week MVP. Solve today's story; add what tomorrow needs. Architectural change is cheap when seams are clean.
- **God `Application.kt` / `main`.** A bootstrap that grew to read 12 env vars, branch on 5 profiles, conditionally register 30 beans, set up logging, init metrics, prime caches. Split into `@Configuration` modules; move env reads to `@ConfigurationProperties`; let auto-configuration carry its weight.
- **Service locator in disguise.** Injecting `ApplicationContext`, `BeanFactory`, or a "service registry" everywhere. Same anti-pattern as `getBean(...)` with one more level of indirection.
- **Premature microservices.** Splitting a 3-team monolith into 12 microservices "for scale" before any service has a different deploy cadence, load profile, or team owner. **Modulith first**; split when a real boundary appears.
- **Cargo-cult standards.** Adopting GraphQL / EJB / event sourcing / Kafka / hexagonal because the conference talk said so. Adopt when *this* project's pain matches the standard's solution.
- **DSL theatre.** A DSL invented for code that has two callers and no domain expert reading it. The DSL is then maintained forever by engineers who could have read 6 lines of plain Kotlin.
- **Lazy-init as a workaround for cycles.** When a needs b and b needs a, `lazy { }` hides the cycle until production. Break the cycle (events, callbacks, a third object), don't paper over it.
- **One mega-`@Configuration`.** All beans in `ApplicationConfig.kt`. Co-locate beans with their module; co-locate config with the code it configures.
- **AOP for non-cross-cutting code.** An `@Aspect` for one method in one place. AOP is for **policies that apply uniformly**; one-off interception is a function call.
- **Decision deferral as decision *avoidance*.** Saying "we'll decide later" forever. Defer until the **last responsible** moment — when not deciding starts costing more than deciding wrong.
- **Test-only seams.** A composition root that's so framework-bound that the only way to test the core is `@SpringBootTest`. The core should be runnable from a 10-line POJO main.

## Related skills

| Skill | This not that |
|---|---|
| `architecture` | Front-of-funnel decision making (is architecture warranted? what level of rigor?); this skill assumes that question is answered and you're now wiring the system. |
| `architecture-patterns` | Picking the layout pattern (Layered / Onion / Clean) for a single module; this skill is the cross-module wiring + cross-cutting concerns layer. |
| `architecture-decision-records` | Capturing the system-level decisions this skill helps you make. |
| `spring-boot-mastery` | Deep Spring Boot internals (lifecycle, AOP mechanics, Modulith) — this skill applies them as Clean-Code rules. |
| `spring-security-and-auth` | Security as a system concern: filter chain, OAuth2 — this skill is *why* it's an aspect, that one is *how*. |
| `cqrs-implementation` | Architectural CQRS / projections — this skill includes when to reach for CQRS as part of incremental evolution. |
| `microservices-patterns-deep` | Once you've split into services, how to operate them; this skill is *whether and when* to split. |
| `clean-code-boundaries` | Function- and class-level boundary discipline (wrap third-party SDKs); this skill is the system-level analogue (composition root, aspects). |
| `clean-code-functions` / `clean-code-objects-and-data` | Inside-class / inside-function discipline; this skill is the wiring-between-classes layer. |
| `ddd-strategic-design` / `ddd-context-mapping` | Finding contexts and their relationships; this skill is how to wire and modularise them. |
| `karpathy-guidelines` | Don't refactor what you weren't asked to. Architectural change has the largest blast radius — surgical rule is strongest here. |
| `methodology-verification` | After any wiring change, re-run the proving command — broken bean wiring fails at startup, often invisibly until prod. |

## Limitations

- **Spring is one ecosystem of many.** The principles (DI, POJOs, aspects, DSLs, deferred decisions) apply to Ktor + Koin, Micronaut, Quarkus, Helidon, plain JVM apps. Examples are Spring-flavoured because that's the house stack; rules generalise.
- **Architecture is contextual.** A 2-engineer startup's "system" and a 200-engineer enterprise's "system" need very different rigor. Apply judgement; don't import enterprise patterns into a CLI tool.
- **Some standards are non-negotiable.** Industry compliance (HIPAA, PCI, GDPR), regulatory contracts, partner APIs — standards adoption is forced, not chosen. The "earn their place" rule applies to *optional* standards.
- **Aspects can hide too much.** A method annotated with `@Transactional`, `@Cacheable`, `@PreAuthorize`, `@Retry`, `@Timed`, `@Audited` is doing six things behind one signature. Aspects are powerful — apply them like spices, not soup base.
- **Decision deferral has a cost.** Some decisions get *more* expensive over time (data model, public API). For those, decide early with the best info you have; for tactical decisions (which cache library, which logging format), defer.
- **DSLs trade reading clarity for writing complexity.** A DSL the team can't extend is a maintenance trap. Build only DSLs you commit to maintaining.
