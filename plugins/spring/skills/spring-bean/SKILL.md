---
name: spring-bean
description: "Core Spring DI and bean management for Kotlin / Spring Boot 3+ services — what `@Component` / `@Service` / `@Repository` / `@Controller` / `@RestController` / `@Configuration` / `@Bean` actually do under the hood, constructor injection discipline, `@Component` scanning vs `@Bean` methods vs explicit registration, resolving ambiguity with `@Primary` / `@Qualifier` / `@Profile` / `@ConditionalOn*`, bean scopes (`singleton` / `prototype` / `request` / `session` / application), bean lifecycle ordering (`@PostConstruct` → `InitializingBean` → `SmartInitializingSingleton` → `ApplicationRunner` / `CommandLineRunner` → `@PreDestroy`), advanced extension points (`BeanPostProcessor`, `BeanFactoryPostProcessor`, `FactoryBean`, `ApplicationContextAware`), `@Lazy` / `@DependsOn` (when justified, when a smell), circular dependencies as a design smell, `ApplicationContext` hierarchy, and Kotlin specifics (primary-constructor as implicit DI, `kotlin-spring` all-open plugin, `final`-by-default trade-off, `object` vs `@Component`). Use when you're wiring beans, hitting `NoUniqueBeanDefinitionException` or `BeanCurrentlyInCreationException`, deciding `@Component` vs `@Bean`, choosing a scope, ordering startup logic, or refactoring `new SomeService()` / field `@Autowired` into proper DI. Boot-only concerns (auto-configuration, `application.yml`, `@ConfigurationProperties`, Boot profiles) live in `spring-boot`; AOP / `@Transactional` / proxy mechanics live in `spring-aop` and `spring-transactions`."
risk: safe
source: "custom — Spring DI and bean management for Kotlin"
date_added: "2026-05-12"
---

# Spring Beans & DI (Kotlin / Spring Boot 3+)

> A Spring bean is just an instance you didn't `new` yourself. Everything else — scope, lifecycle, proxies, configuration — is bookkeeping the container does on your behalf. Knowing the bookkeeping is the difference between trusting Spring and fighting it.

## Use this skill when

- Wiring a new service / repository / configuration class and deciding `@Component` vs `@Bean`
- Hitting `NoUniqueBeanDefinitionException`, `BeanCurrentlyInCreationException`, or "bean of type X not found"
- Choosing or debugging a bean scope (`singleton` / `prototype` / `request` / `session`)
- Ordering startup logic — `@PostConstruct` vs `ApplicationRunner` vs `SmartInitializingSingleton` vs `ApplicationReadyEvent`
- Refactoring `new SomeService(...)`, field `@Autowired`, or setter injection into proper constructor DI
- Reaching for `@Lazy` or `@DependsOn` and wondering whether it's the right tool
- Designing a `BeanPostProcessor` / `FactoryBean` / `ApplicationContextAware` — usually because you genuinely need it, occasionally because you don't
- Writing or reviewing Kotlin Spring code where `final`-by-default, `object`, or the `kotlin-spring` plugin are in play

## Do not use this skill when

- The question is about **auto-configuration**, starters, `application.yml` precedence, profiles in the Spring Boot sense, or `@ConfigurationProperties` deep — that's `spring-boot`
- The question is about `@Aspect`, pointcut expressions, advice ordering, or proxy mechanics for AOP-driven annotations — that's `spring-aop`
- The question is about `@Transactional` propagation / isolation / `rollbackFor` — that's `spring-transactions`
- The question is about `@Cacheable` / `@Scheduled` / `@Async` — those are `spring-cache` / `spring-scheduler` / `spring-async` respectively
- You're picking the architectural layout (Layered / Onion / Clean) — that's `architecture-patterns`

## Core principles

1. **Constructor injection always.** Single primary constructor, `val` properties, no `@Autowired` anywhere. Constructor injection is the only form that gives you immutability (`val`), testability (instantiate with mocks — no reflection), fail-fast startup (missing dep → context refuses to start, not NPE at request time), and required-by-default semantics. Setter and field injection break all four.
2. **One way to register a bean per class.** `@Component` (+ scanning) for your own classes. `@Bean` methods inside `@Configuration` for third-party classes you don't own. Never both for the same type. Never XML in 2026.
3. **Stereotype annotations are documentation that the framework respects.** `@Service` / `@Repository` / `@Controller` / `@RestController` are `@Component` with extra meaning — `@Repository` adds JPA exception translation, `@Controller` / `@RestController` register an MVC handler. Use the most specific one; it tells the reader (and tools) which layer the class lives in.
4. **Singletons by default. Mutable state on a singleton is a bug.** 99% of beans are singletons shared across all threads. Any `var` field on a singleton is a thread-safety problem waiting to happen. Push state into request-scope beans, parameters, or a dedicated store.
5. **Ambiguity is resolved at the call site, not the registration site.** If two beans satisfy a dependency, prefer `@Qualifier("name")` on the injection point. Reach for `@Primary` only when one bean is genuinely "the default" — overusing it makes wiring opaque.
6. **A circular dependency is a missing class.** Spring's "fix" (`@Lazy` on one side, setter injection, or constructor refactor) treats the symptom. The diagnosis is almost always that a third collaborator wants to exist between A and B. Extract it.
7. **`@Lazy` and `@DependsOn` are smells until proven otherwise.** Eager startup is a feature: it surfaces wiring errors at boot, not at the first request that touches the broken bean. Use `@Lazy` only for genuinely expensive beans rarely used (and prefer global lazy init in CLI tools). Use `@DependsOn` only when ordering can't be expressed by injecting the dep.
8. **Stay away from extension points until you can't.** `BeanPostProcessor`, `BeanFactoryPostProcessor`, `FactoryBean`, `ApplicationContextAware` are powerful and almost always overkill. If you're writing one in application code (as opposed to a library / starter), pause and check whether a `@Configuration` class with `@Bean` methods would do the job.

## The annotations that actually matter

11 annotations cover ~95% of Spring DI. Everything else (`@DependsOn`, `@Lazy`, `@Order`, `@DependsOn`, custom stereotypes) — read the source before adding.

| Annotation | What it really does | When |
|---|---|---|
| `@Component` | Marks a class for classpath scanning → Spring instantiates and manages it as a bean | Generic Spring-managed class with no more specific stereotype |
| `@Service` | `@Component` + semantic hint "this is a use-case / service-layer class" | Service / use-case classes |
| `@Repository` | `@Component` + JPA `PersistenceExceptionTranslationPostProcessor` rewrites JPA exceptions into Spring's `DataAccessException` hierarchy | Persistence adapters |
| `@Controller` / `@RestController` | `@Component` + MVC handler registration; `@RestController` also adds `@ResponseBody` to every method | Web layer |
| `@Configuration` | Marks a class as a source of `@Bean` method definitions; CGLIB-proxied so `@Bean` methods return the singleton on repeated calls | Wiring third-party classes; assembling beans that need code |
| `@Bean` | Method whose return value Spring registers as a bean; method name = bean name unless overridden | Inside `@Configuration` (or any `@Component`, but prefer `@Configuration`) |
| `@Primary` | "Among multiple beans of this type, prefer this one for autowiring" | One bean is genuinely the default |
| `@Qualifier("name")` | Pick a specific bean by name at the injection point | Multi-bean scenarios where neither is the default |
| `@Profile("...")` | Bean registers only when the named profile is active | Dev/test/prod variation, integration-test stubs |
| `@ConditionalOnX` | Bean registers only when condition holds (class on classpath, property present, bean missing) | Library auto-config; conditional wiring |
| `@ConfigurationProperties` | Binds external config to a typed Kotlin `data class` (depth lives in `spring-boot`) | All non-trivial config |

### `@Component` scanning vs `@Bean` methods vs explicit registration

```kotlin
// 1) @Component scanning — your own classes
@Service
class OrderService(
    private val orders: OrderRepository,
    private val clock: Clock,
)

// 2) @Bean method — third-party class you don't own
@Configuration
class ClockConfig {
    @Bean
    fun clock(): Clock = Clock.systemUTC()
}

// 3) Explicit registration — almost never in app code (used in tests / Spring internals)
ctx.registerBean(Clock::class.java, Supplier { Clock.systemUTC() })
```

Rule of thumb: if you can put `@Component` on the class, do that. If you can't (third-party, primitive, computed) → `@Bean` method in a `@Configuration` class. Programmatic registration is for tests, library internals, and Spring itself.

## Bean lifecycle — order of execution

```
1. Bean definition discovered          (via @Component scan, @Bean method, or programmatic registration)
2. BeanFactoryPostProcessor runs       (can mutate definitions; e.g. PropertySourcesPlaceholderConfigurer)
3. Bean instantiated                   (primary constructor called)
4. Dependencies injected               (constructor injection — only option for val fields)
5. *Aware callbacks                    (BeanNameAware, ApplicationContextAware, …)
6. BeanPostProcessor#postProcessBeforeInitialization
7. @PostConstruct methods              (JSR-250)
8. InitializingBean#afterPropertiesSet (legacy; equivalent to @PostConstruct, avoid)
9. @Bean(initMethod = "…")             (explicit init hook on a @Bean method)
10. BeanPostProcessor#postProcessAfterInitialization   ← AOP proxy is wrapped HERE
11. (per-bean init done)
   …all singletons created…
12. SmartInitializingSingleton#afterSingletonsInstantiated   ← all singletons exist, callback fires once
13. ContextRefreshedEvent published
14. ApplicationRunner.run / CommandLineRunner.run            ← ordered by @Order
15. ApplicationStartedEvent
16. ApplicationReadyEvent              ← ready to serve traffic
   …app runs…
   Shutdown signal
17. ContextClosedEvent
18. @PreDestroy methods
19. DisposableBean#destroy             (legacy)
20. @Bean(destroyMethod = "…")
21. JVM exits
```

### Picking the right hook

| Hook | Fires | Use for |
|---|---|---|
| `@PostConstruct` | After this bean's deps are wired | Per-bean init that needs only this bean's own deps |
| `InitializingBean#afterPropertiesSet` | Same time as `@PostConstruct` | **Avoid** — couples your class to the Spring API; `@PostConstruct` is JSR-250 and framework-neutral |
| `SmartInitializingSingleton#afterSingletonsInstantiated` | After **all** singletons are instantiated, before runners | Cross-bean init that needs the whole graph (e.g. registering handlers from every other bean) |
| `ApplicationRunner` / `CommandLineRunner` | After context refresh, before `ApplicationReadyEvent` | Top-level coordinated startup work (verify migrations, ping externals, warm caches) — order with `@Order` |
| `@EventListener(ApplicationReadyEvent)` | After all runners, app ready to serve | "Do X when the app is fully ready" — preferred over `CommandLineRunner` for runtime-side effects you don't want to block readiness |
| `@PreDestroy` | Graceful shutdown only (skipped on `kill -9`) | Flush, close, release |

`ApplicationRunner` vs `CommandLineRunner`: identical except for the arg type (`ApplicationArguments` vs raw `String[]`). Prefer `ApplicationRunner` — typed parsed args.

### Example

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

@Component
@Order(1)
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

Gotchas:
- `@PostConstruct` is **synchronous** during startup. A slow one delays readiness. Don't call external APIs from it.
- Throwing from `@PostConstruct` or a runner **aborts startup**. Use deliberately.
- `@PreDestroy` may be skipped on `kill -9` — never rely on it for durability. Persist before, not on shutdown.

## Bean scopes — pick by lifecycle of state

| Scope | Lifecycle | When to use |
|---|---|---|
| `singleton` (default) | One per `ApplicationContext`, lives for the app lifetime | 99% of beans. Stateless services, repositories, configuration, clients |
| `prototype` | New instance per `getBean` / injection | Stateful, short-lived objects with non-trivial construction. Rare in modern Spring — usually a plain class plus a factory is clearer |
| `request` | One per HTTP request | Per-request context (correlation ID, current user, tenant) when you can't (or won't) pass it as a parameter |
| `session` | One per HTTP session | Per-user state in stateful web apps. Most JWT-stateless APIs don't need this |
| `application` | One per `ServletContext` (broader than `singleton` in multi-context apps) | Rare; useful when multiple `ApplicationContext`s share a `ServletContext` |

```kotlin
@Component
@Scope(value = "prototype")
class StatefulBuilder(...)

@Component
@Scope(value = "request", proxyMode = ScopedProxyMode.TARGET_CLASS)
class RequestContext(...)
```

Gotchas:
- **Injecting `prototype` into `singleton`** doesn't do what you think. The singleton holds **one** reference to one prototype instance. Fix: inject `ObjectProvider<T>` / `Provider<T>` and call `.getObject()` each time, or use `@Lookup`.
- **Web scopes (`request` / `session`) injected into `singleton`** need a proxy (`proxyMode = ScopedProxyMode.TARGET_CLASS`) so each call resolves to the current request's instance.

## Resolving ambiguity

When `ApplicationContext` finds two beans that satisfy a dependency:

### `@Primary` — one bean is the canonical default

```kotlin
@Configuration
class ClockConfig {
    @Bean @Primary
    fun systemClock(): Clock = Clock.systemUTC()

    @Bean
    fun fixedClock(): Clock = Clock.fixed(Instant.parse("2026-01-01T00:00:00Z"), ZoneOffset.UTC)
}

@Service
class Orders(private val clock: Clock)   // → systemClock injected
```

Use when one bean is genuinely "the default" everyone wants unless they say otherwise. Don't sprinkle `@Primary` to silence "no unique bean" errors — that's just hiding the real question.

### `@Qualifier` — pick by name at the injection site

```kotlin
@Configuration
class HttpClients {
    @Bean fun internalClient(): RestClient = ...
    @Bean fun publicClient(): RestClient = ...
}

@Service
class Sync(
    @Qualifier("internalClient") private val internal: RestClient,
    @Qualifier("publicClient") private val public: RestClient,
)
```

Preferred when there's no "default" — both are equally legitimate, each call site picks what it wants. You can also define custom qualifier annotations (`@Internal`, `@Public`) for type-safer wiring.

### `@Profile` — active-profile-dependent registration

```kotlin
@Configuration
@Profile("!test")
class RealPaymentConfig {
    @Bean fun payments(): PaymentGateway = StripeGateway(...)
}

@Configuration
@Profile("test")
class StubPaymentConfig {
    @Bean fun payments(): PaymentGateway = StubGateway()
}
```

Use for environment-specific wiring (real Stripe vs stub, in-memory vs real Redis in tests). Deep profile rules and precedence are in `spring-boot`.

### `@ConditionalOnX` — registration depends on runtime conditions

```kotlin
@Configuration
class FeatureXConfig {
    @Bean
    @ConditionalOnProperty(name = ["features.x.enabled"], havingValue = "true")
    fun featureX(): FeatureX = FeatureX(...)
}
```

`@ConditionalOnProperty`, `@ConditionalOnClass`, `@ConditionalOnMissingBean` are the workhorses. Used heavily inside Boot starters; useful in app code for feature flags and optional integrations. The full family lives in `spring-boot`.

## Extension points — use sparingly

These are powerful, framework-author-grade tools. In application code you should almost never need them — and if you do, you usually have a design problem rather than a Spring problem. Listed here so you recognise them when you see them.

### `BeanPostProcessor`

Hook into bean creation: `postProcessBeforeInitialization` (after DI, before `@PostConstruct`) and `postProcessAfterInitialization` (after init — **this is where AOP proxies are installed**). Use when you genuinely need to wrap or mutate **every** bean of some shape — e.g. registering custom metrics on every `@Service`. App-code uses are rare; almost everything is covered by AOP or `@Bean` methods. See `spring-aop` for the proxy story.

### `BeanFactoryPostProcessor`

Runs **before** any bean is instantiated. Can mutate bean definitions themselves (e.g. resolve `${...}` placeholders → that's what `PropertySourcesPlaceholderConfigurer` is). If you find yourself writing one in app code, you're probably trying to do auto-configuration. Put it in a starter, not in app code.

### `FactoryBean<T>`

A bean whose job is to produce another bean. `getObject()` returns the actual bean Spring exposes; `getObjectType()` reports its type. Useful when bean construction is genuinely complex (e.g. `LocalSessionFactoryBean`). In Kotlin/Boot app code, a `@Bean` method is almost always simpler and clearer.

### `ApplicationContextAware`

Implement to get the `ApplicationContext` injected via a callback. Almost always wrong in app code — it's the service-locator pattern in disguise (you fetch beans by name at runtime instead of declaring them as deps). Constructor-inject what you actually need. Legitimate uses: framework-level utilities, generic dispatchers / registries that genuinely need to enumerate beans.

## `@Lazy` and `@DependsOn` — when, and the smell

### `@Lazy`

By default every singleton is eagerly instantiated at startup — a feature, because wiring errors and missing config surface at boot, not at the first request.

`@Lazy` defers instantiation until first use:

```kotlin
@Component
@Lazy
class SeldomUsedExpensiveBean(...)
```

Justified for: genuinely expensive beans rarely used (large in-memory dataset, heavy external client). Also used as a circular-dependency band-aid (`@Lazy` on one side of an A↔B cycle) — but see below.

Global lazy init (`spring.main.lazy-initialization=true`) is fine for dev / CLI tools where startup speed matters more than early error detection. Don't enable it in production — you trade startup-time errors for first-request errors.

### `@DependsOn`

Forces bean B to initialise after bean A even when there's no direct injection:

```kotlin
@Component
@DependsOn("databaseMigrator")
class CachingLayer(...)
```

Almost always a smell. Better forms:
- **Constructor-inject** the dep — then DI handles order automatically.
- **`ApplicationRunner`** for ordered runtime initialisation (verify migrations, then warm caches, in named order).

Reach for `@DependsOn` only when ordering can't be expressed through injection (e.g. one bean's `@PostConstruct` must run before another registers some external trigger).

## Circular dependencies — what they really mean

```kotlin
@Service class A(val b: B)
@Service class B(val a: A)   // BeanCurrentlyInCreationException
```

Spring 2.6+ fails fast on circular constructor deps by default. The "fixes" — `@Lazy` on one side, setter injection, or `@DependsOn` — all treat the symptom.

The diagnosis is almost always: **there is a third concept** that wants to live between A and B, and the cycle is the two of them reaching across that missing collaborator. Examples:

- A "knows" how to do X, B "knows" how to do Y, and a shared workflow needs both → extract `Workflow` that depends on A and B.
- A publishes domain events, B listens → use `ApplicationEventPublisher` instead of a direct reference (see `spring-events`).
- A and B share a piece of state → extract a `Store` they both depend on.

When you do the extraction the cycle dissolves and the code reads better. The cycle was the design talking.

## `ApplicationContext` hierarchy (briefly)

Most Spring Boot apps have **one** `ApplicationContext` — created by `SpringApplication.run(...)`, holds every bean.

A parent–child hierarchy exists in two common cases:
- **Spring Web MVC** (legacy XML era): root context + child `DispatcherServlet` context. Boot collapses this in `@SpringBootApplication` so you rarely see it.
- **Spring Boot test slices** (`@WebMvcTest`, `@DataJpaTest`): each test slice builds a smaller context with just the relevant infrastructure.

Beans in a child context can see parent beans, not vice versa. In practice for Boot app code, treat the context as flat. Slices live in `testing-strategy-kotlin-spring`.

## Anti-patterns

- **Field `@Autowired`** — `@Autowired lateinit var orders: OrderRepository`. Breaks immutability (can't be `val`), breaks plain-Kotlin testability (need reflection to set), breaks fail-fast startup (NPE at request time, not boot), and obscures the dependency surface. Use the primary constructor.
- **Setter injection** — `@Autowired fun setOrders(o: OrderRepository) { … }`. Same problems as field injection plus extra noise. Used to be Spring's recommendation pre-4.x; isn't anymore.
- **`new SomeService(...)` inside another `@Service`** — bypasses DI completely. No AOP, no `@Transactional`, no proxies, no lifecycle, no scope. The non-managed instance silently runs without any cross-cutting behaviour. Inject the bean.
- **Mutable `var` state on a singleton** — concurrent requests share one instance. State must be thread-safe (and usually shouldn't exist on the bean at all — push it into the request or the data store).
- **Sprinkling `@Primary`** to silence "no unique bean" errors. Hides the wiring decision. Use `@Qualifier` at the call site.
- **`@SpringBootApplication` in the default package** — classpath scanning starts from the annotated class's package. Default package = "scan everything", which silently picks up unintended classes. Always put `@SpringBootApplication` in a top-level named package.
- **Multiple `@SpringBootApplication`** classes in one runtime — Boot only runs one. The other is a footgun for tests and IDE run configs.
- **`@ComponentScan` overriding the default** — usually wrong. The default scans the `@SpringBootApplication` class's package and below; overriding it almost always breaks something subtle.
- **`@Lazy` to mask a circular dependency** — treats the symptom. Extract the missing collaborator.
- **`ApplicationContextAware` in app code** — service-locator in disguise. Constructor-inject what you need.
- **Self-invocation expecting an AOP-driven annotation to fire** — `this.method()` skips the proxy, so `@Transactional` / `@Async` / `@Cacheable` silently don't apply. The DI-side fix is "inject `self: MyService` and call `self.method()`", but the deeper question is usually "why does this class need two layered behaviours?" — see `spring-aop`.

## Kotlin specifics

- **Primary constructor is implicit DI.** Spring picks up `class OrderService(private val orders: OrderRepository, private val clock: Clock)` with no `@Autowired`, no secondary constructor — that single constructor IS the injection point. Keep it that way. Add a secondary constructor only when you need to (e.g. JPA `@Entity` needs a no-arg one — handled by `kotlin-jpa`).
- **`kotlin-spring` (`all-open`) compiler plugin** is mandatory for any AOP-driven annotation. Kotlin classes are `final` by default; Spring AOP needs to subclass them via CGLIB. The plugin opens classes annotated with `@Component` / `@Service` / `@Repository` / `@Controller` / `@RestController` / `@Configuration` / `@Async` / `@Transactional` / `@Cacheable` automatically. Without it, you'll get cryptic runtime errors when an AOP-driven annotation fires.
- **Final-by-default trade-off.** It's a good Kotlin default — invariants by inheritance are fragile and YAGNI. The cost is exactly the `all-open` plugin above. Pay the cost; don't manually mark everything `open`.
- **`object` vs `@Component`.** A Kotlin `object` is a JVM singleton constructed by the JVM, not Spring. It can't be DI-managed, can't have constructor-injected deps, can't be `@Transactional`, can't be proxied. Use `object` for pure stateless utilities (constants, simple functions). For anything Spring needs to manage (deps, lifecycle, scope, proxies) use `@Component` / `@Service` etc.
- **`data class` for `@ConfigurationProperties`** is the discipline — immutable, typed, validated. Pointer only; depth lives in `spring-boot`.

## Concrete examples

### Idiomatic DI

```kotlin
@Service
class OrderService(
    private val orders: OrderRepository,
    private val events: ApplicationEventPublisher,
    private val clock: Clock,
) {
    fun place(req: PlaceOrderRequest): Order {
        val order = Order.new(req, clock.instant())
        orders.save(order)
        events.publishEvent(OrderPlaced(order.id))
        return order
    }
}
// Test: OrderService(mockk(), mockk(relaxed = true), Clock.fixed(...))
```

No `@Autowired`. No setters. `val` properties. Tests instantiate directly with mocks — no Spring context needed.

### Wiring a third-party class

```kotlin
@Configuration
class TimeConfig {
    @Bean
    fun clock(): Clock = Clock.systemUTC()
}

@Configuration
class HttpConfig {
    @Bean
    fun stripeClient(props: StripeProperties): StripeClient =
        StripeClient.builder()
            .apiKey(props.apiKey)
            .timeout(props.timeout)
            .build()
}
```

You don't own `Clock` or `StripeClient`, so `@Component` isn't an option. `@Bean` method inside `@Configuration` is the right tool.

### Scope-aware request context

```kotlin
@Component
@Scope(value = "request", proxyMode = ScopedProxyMode.TARGET_CLASS)
class RequestContext {
    var tenantId: TenantId? = null
    var correlationId: String? = null
}

@Service
class Reports(private val context: RequestContext) {
    fun fetch(): Report = ...   // sees the current request's RequestContext via proxy
}
```

The proxy resolves to the current request's instance every time `context` is touched. Without `proxyMode`, the singleton `Reports` would hold one frozen `RequestContext` from whichever request happened to be active at startup.

## Related skills

- `spring` — router for the family; cross-cutting principles
- `spring-boot` — auto-configuration, `@ConfigurationProperties`, profiles in the Boot sense, `application.yml` precedence, `ApplicationRunner` / `CommandLineRunner` in the Boot bootstrap context
- `spring-aop` — `@Aspect`, pointcuts, advice ordering, the proxy mechanics behind AOP-driven annotations, self-invocation / `final` / `private` gotchas
- `spring-transactions` — `@Transactional` propagation / isolation / `rollbackFor`, transaction boundary on the service layer, proxy gotchas applied to transactions
- `spring-async`, `spring-scheduler`, `spring-events`, `spring-cache` — all sit on AOP proxies over Spring beans
- `clean-code-systems` — composition root, constructor injection discipline, separating construction from use
- `clean-code-classes` — primary-constructor properties as bean fields, encapsulation defaults
- `solid-principles` — DIP and constructor injection; OCP via `@Profile` / `@ConditionalOnX`

## Limitations

- Targets Spring Boot **3+** on Kotlin 2.x / JVM 21+. Boot 2.x users will find most of this applicable but specific APIs (`SmartInitializingSingleton`, `@ConfigurationProperties` constructor binding) differ.
- Doesn't cover **classic XML / Java-config-heavy** legacy Spring — assumes annotation-driven configuration.
- Doesn't cover **GraalVM Native Image** bean-registration quirks (reflection hints, `@RegisterReflectionForBinding`) — that's a `spring-boot` / native-image concern.
- Doesn't cover **WebFlux-specific bean scopes** — `request` / `session` are servlet-stack concepts; WebFlux uses different equivalents.
