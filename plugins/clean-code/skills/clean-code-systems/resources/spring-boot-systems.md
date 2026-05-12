# Spring Boot System Patterns

Ch. 11 rules applied with Spring Boot's full machinery. Spring made everything Wampler argued for in 2008 idiomatic and cheap — POJOs, DI, declarative cross-cutting concerns, profile-driven evolvability. This file is the catalog of Spring affordances mapped to each system-level rule, with the gotchas and the house conventions.

> "The application has no knowledge of main or of the construction process. It simply expects that everything has been built properly." — Wampler. Spring Boot makes that the *default*.

## Quick map — Ch. 11 concern → Spring affordance

| Ch. 11 concern | Spring affordance |
|---|---|
| Composition root | `@SpringBootApplication` + `@Configuration` modules + auto-configuration |
| Construction phase | Bean lifecycle: instantiation → DI → `@PostConstruct` → `ApplicationRunner` |
| DI | Constructor injection (single ctor auto-detected since 4.3) |
| Optional collaborators | Default-argument values; `Optional<T>`-typed injection; `@ConditionalOn*` beans |
| Lazy beans | `@Lazy` annotation; smart prototype scope |
| Factories | `@Bean` methods in `@Configuration`; `@Component`-scanned `*Factory` classes |
| Cross-cutting concerns | `@Transactional`, `@Cacheable`, `@PreAuthorize`, `@Retry`, `@Timed`, `@Async` |
| Aspect mechanics | Spring AOP — JDK proxies for interfaces, CGLIB for classes (kotlin-spring plugin makes classes `open`) |
| Configuration | `@ConfigurationProperties` data classes + yaml |
| Environment-specific wiring | `@Profile`, `@ConditionalOnProperty`, `@ConditionalOnBean`, `@ConditionalOnClass` |
| In-process modularity | Spring Modulith (application modules + events + outbox) |
| Programmatic wiring (Kotlin) | `beans { }` DSL |
| Test the wiring | Test slices: `@WebMvcTest`, `@DataJpaTest`, `@JsonTest`; `@SpringBootTest` full context |
| DSLs | Spring Security DSL, RouterFunction DSL, MockMvc Kotlin DSL |

---

## 1. `@SpringBootApplication` — the canonical composition root

```kotlin
@SpringBootApplication
@EnableConfigurationProperties(OrderProperties::class, PricingProperties::class)
@EnableScheduling
@EnableAsync
class OrderServiceApplication

fun main(args: Array<String>) {
    runApplication<OrderServiceApplication>(*args)
}
```

`@SpringBootApplication` is `@Configuration` + `@EnableAutoConfiguration` + `@ComponentScan`. Three of Wampler's rules in one annotation: composition root (it's the wiring entry point), construction-vs-use separation (you never see `new`), and modularity (component scan picks up `@Configuration` and `@Component` classes per module).

**House rule for the application class**:
- Keep it as small as the snippet above. **No business logic, no manual bean declarations, no env reads.**
- Co-locate `@EnableConfigurationProperties` and feature-toggle enablers here — they're system-level concerns.
- The package of the application class is the **base scan package**. Place it at the highest namespace you want scanned.

---

## 2. Bean lifecycle — what runs when

Spring constructs the object graph in this order (per bean, per startup):

1. **Instantiate**: call the constructor (DI happens here for constructor injection).
2. **Property/setter injection** (if any — usually none in Kotlin).
3. **`BeanNameAware`, `ApplicationContextAware`** — discouraged; signals service-locator smell.
4. **`@PostConstruct`** / `InitializingBean.afterPropertiesSet()`.
5. **Bean is now ready for use.**
6. Once *all* beans are ready: `SmartInitializingSingleton.afterSingletonsInstantiated()`.
7. Once the context is fully refreshed: `ApplicationRunner` / `CommandLineRunner` beans run.
8. Application is ready.

**Where to put initialisation logic**:

| Logic | Where |
|---|---|
| "I need a derived field computed from my injected deps" | `init { }` block in the primary constructor (Kotlin). |
| "I need to register myself with some shared registry after wiring" | `@PostConstruct` method. |
| "I need every singleton to be wired before I do my thing" | Implement `SmartInitializingSingleton`. |
| "I need to do startup work that depends on the *full* context (e.g., warm a cache)" | `ApplicationRunner`. |
| "I need to do cleanup at shutdown" | `@PreDestroy` / `DisposableBean.destroy()`. |

**Anti-pattern**:
```kotlin
// ✗ @Autowired field — injected after constructor, so `init { }` sees null
@Service
class OrderService {
    @Autowired lateinit var orders: OrderRepository
    init { orders.warmUp() }   // ← NPE: not yet injected
}

// ✓ Constructor injection — available in init { }
@Service
class OrderService(private val orders: OrderRepository) {
    init { orders.warmUp() }
}
```

**Cross-link**: `spring-boot-mastery` for the deep lifecycle dive.

---

## 3. Constructor injection — the default, no exceptions

```kotlin
// ✓ Canonical Spring-Kotlin DI
@Service
class OrderApplicationService(
    private val orders: OrderRepository,
    private val publisher: ApplicationEventPublisher,
    private val clock: Clock,
)
```

**Rules**:
1. **Primary constructor only.** Multiple constructors confuse auto-wiring.
2. **All `val`, all `private`.** Dependencies don't change; they're implementation details.
3. **No `@Autowired`.** Single-ctor auto-detection has worked since Spring 4.3.
4. **No `lateinit var`.** That's field injection; same drawbacks as in Java.
5. **Default arguments for optional collaborators.**

**Cyclic dependency**:
Spring detects constructor-injection cycles at startup and fails loudly — that's a feature. If you see it, **break the cycle** (extract a third bean, use events, use a callback) rather than working around it with `@Lazy` or setter injection.

---

## 4. `@ConfigurationProperties` — typed config trumps `@Value` strings

```kotlin
@ConfigurationProperties("orders")
data class OrderProperties(
    val defaultCurrency: Currency,
    val retentionDays: Int,
    @field:DurationUnit(ChronoUnit.SECONDS)
    val submissionTimeout: Duration,
    val pricing: Pricing,
) {
    data class Pricing(
        val baseUrl: URI,
        val timeout: Duration,
        val maxRetries: Int = 3,
    )
}
```

**Anti-pattern** (`@Value` scatter):
```kotlin
// ✗ Strings scattered across many beans, untyped, untested
@Service
class OrderService(
    @Value("\${orders.default-currency}") private val defaultCurrency: String,
    @Value("\${orders.retention-days}") private val retentionDays: Int,
    @Value("\${orders.pricing.base-url}") private val pricingUrl: String,
)
```

**House rules**:
- **One `@ConfigurationProperties` per module**. Name it `<Module>Properties`.
- **Data class with `val`.** Immutable config.
- **Bean Validation annotations** (`@field:NotEmpty`, `@field:Min`) — fail at startup, not at first use.
- **Sub-`data class` for nested groups** — yaml structure mirrors Kotlin structure.

**Registration**:
```kotlin
@SpringBootApplication
@EnableConfigurationProperties(OrderProperties::class)
class OrderServiceApplication
```

or annotate the properties class with `@ConstructorBinding` (Spring Boot 3+ does this automatically for data classes).

---

## 5. `@Profile` / `@ConditionalOn*` — environment-specific wiring without `if`

The classical anti-pattern: profile-coupled `if/else` in business code.

```kotlin
// ✗ Profile check in business code
@Service
class PaymentService(@Value("\${spring.profiles.active}") private val profile: String) {
    fun charge(amount: Money) {
        if (profile == "dev" || profile == "test") {
            // fake charge
        } else {
            // real charge
        }
    }
}
```

**Good** — different beans per profile, business code unaware:

```kotlin
interface PaymentClient {
    fun charge(amount: Money): ChargeResult
}

@Component
@Profile("!production")
class FakePaymentClient : PaymentClient {
    override fun charge(amount: Money) = ChargeResult.success(ChargeId.random())
}

@Component
@Profile("production")
class StripePaymentClient(private val stripe: StripeApi) : PaymentClient {
    override fun charge(amount: Money) = ...
}

@Service
class PaymentApplicationService(private val payments: PaymentClient) {
    // doesn't know which implementation is wired
    fun charge(amount: Money) = payments.charge(amount)
}
```

**`@ConditionalOn*` variants** (more specific than profiles):

| Annotation | When |
|---|---|
| `@ConditionalOnProperty(name = "feature.x", havingValue = "true")` | Bean only when a config flag is set. |
| `@ConditionalOnMissingBean(PaymentClient::class)` | Fallback bean; user-provided wins. |
| `@ConditionalOnClass("com.stripe.Stripe")` | Only when Stripe SDK is on classpath. |
| `@ConditionalOnBean(MetricsRegistry::class)` | Only when another bean exists. |

These are how Spring Boot's auto-configurations work. Use them for **feature toggles at the bean level** instead of `if (config.featureEnabled)` in business code.

---

## 6. `@Transactional` — the canonical aspect

`@Transactional` is Spring's clearest example of a declarative cross-cutting concern. The function reads as the verb; the transaction is policy.

```kotlin
@Service
@Transactional(readOnly = true)                       // class-level default: read
class OrderApplicationService(
    private val orders: OrderRepository,
    private val publisher: ApplicationEventPublisher,
) {
    @Transactional                                    // method override: write
    fun submit(command: SubmitOrder): OrderId {
        val order = Order.submit(command)
        orders.save(order)
        publisher.publishEvent(OrderSubmitted(order.id, ...))
        return order.id
    }

    fun byId(id: OrderId): OrderView =                // inherits class-level readOnly
        orders.findByIdOrThrow(id).let(OrderView::from)
}
```

**Rules** (the most-violated):
1. **One transactional boundary per use case** — at the application-service method, not the repository or controller.
2. **Read-only at the class level, write override at the method.** Flips the safety bias: forget to annotate a write → fails on flush; forget to annotate a query → harmless.
3. **No self-invocation.** `this.someTransactionalMethod()` bypasses the proxy. Call it through an injected bean.
4. **Mark class `open`** (or use the `kotlin-spring` plugin which does this automatically).
5. **Use `rollbackFor = Exception::class`** if your domain throws checked-ish patterns Spring won't roll back on by default (rare in Kotlin — unchecked-by-default).

**Cross-link**: `clean-code-error-handling` for `@Transactional` rollback rules; `clean-code-functions/resources/spring-boot-functions.md` for function-level transactional discipline.

---

## 7. Spring Modulith — in-process modularity, then extract when needed

Spring Modulith treats top-level packages as **application modules**. Each module:
- Has its own internal package structure (public API at the module root, `internal` packages hidden).
- Exposes a small public surface (interfaces, events, configs).
- Communicates with other modules via **events** (`ApplicationEventPublisher` + `@ApplicationModuleListener`).

```
com.example.app
├── orders/                     ← module
│   ├── Order.kt                ← public (aggregate)
│   ├── OrderApplicationService.kt
│   ├── OrderSubmitted.kt       ← public event
│   └── internal/
│       └── JpaOrderRepository.kt
├── payments/                   ← module
│   ├── PaymentApplicationService.kt
│   └── internal/
│       └── StripePaymentClient.kt
└── Application.kt
```

**Inter-module communication**:
```kotlin
// orders module emits
@Service
class OrderApplicationService(private val publisher: ApplicationEventPublisher) {
    @Transactional
    fun submit(command: SubmitOrder): OrderId {
        ...
        publisher.publishEvent(OrderSubmitted(order.id, ...))
        return order.id
    }
}

// payments module listens — Modulith routes async + outbox-backed
@Component
class PaymentTrigger(private val payments: PaymentApplicationService) {
    @ApplicationModuleListener
    fun on(event: OrderSubmitted) {
        payments.initiateForOrder(event.orderId)
    }
}
```

**Why this is the path between monolith and microservices**:
- Same JVM, same database (or one per module if you want), **module boundaries enforced at build time**.
- Architecture tests (`ApplicationModules.of(Application::class.java).verify()`) fail if a module reaches into another module's `internal/`.
- Events are persisted via Modulith's `event_publication` table — at-least-once delivery, no message broker required.
- When *one* module's deploy cadence or scaling profile genuinely diverges, **extract it to a separate service** consuming the same events — most code stays put.

**House rule**: start with Modulith. Split when there's a real reason. See `cqrs-implementation` for the projection-store side of this.

---

## 8. Spring AOP — when to write your own `@Aspect`

Spring's built-in aspects (`@Transactional`, `@Cacheable`, `@PreAuthorize`, `@Async`, `@Retry`, `@Timed`, ...) cover most needs. Write your own when:

- The concern is **domain-specific** (audit-logging *with domain context*, idempotency-token tracking).
- The policy is **uniform** across many call sites — otherwise inline.

**Example — audit aspect**:
```kotlin
@Aspect
@Component
class AuditAspect(private val audit: AuditLog) {

    @Around("@annotation(Audited)")
    fun audit(joinPoint: ProceedingJoinPoint): Any? {
        val user = SecurityContextHolder.getContext().authentication?.name ?: "anonymous"
        val signature = joinPoint.signature.toShortString()
        return try {
            joinPoint.proceed().also {
                audit.log(AuditEvent.Success(user, signature, joinPoint.args))
            }
        } catch (e: Exception) {
            audit.log(AuditEvent.Failure(user, signature, joinPoint.args, e.message))
            throw e
        }
    }
}

annotation class Audited
```

**Anti-pattern (AOP for one-off interception)**:
```kotlin
// ✗ Aspect for a single method in a single service
@Aspect
@Component
class LogOrderSubmitAspect {
    @Around("execution(* com.example.orders.OrderApplicationService.submit(..))")
    fun logIt(...) { ... }   // ← just inline a logger call
}
```

**Aspects multiply hiding**. Six aspects on one method = six things happening invisibly. Use sparingly and always test the wired-together behaviour, not just the aspect in isolation.

---

## 9. `@Async` — fire-and-forget, properly

```kotlin
@Service
class ReceiptNotifier(private val mailer: Mailer) {
    @Async
    fun notifyReceiptIssued(orderId: OrderId, email: Email) {
        mailer.sendReceipt(email, orderId)
    }
}
```

**Rules**:
1. **Enable globally**: `@EnableAsync` on a `@Configuration`.
2. **Configure the executor**: provide an `Executor` bean named `taskExecutor` (or `@AsyncConfigurer.getAsyncExecutor()`). Default is a `SimpleAsyncTaskExecutor` — unbounded, no real pool. **Always configure**.
3. **Return type**: `Unit` / `void` for fire-and-forget, `CompletableFuture<T>` when the caller needs the result. **Not `T` directly** — the value would be unrelated.
4. **No self-invocation** (proxy gotcha).
5. **No `@Async` + `@Transactional` in the same bean** without careful thought: the transaction's `SecurityContext`, MDC, request-scoped beans don't propagate to the async thread by default.

**Better default than `@Async` for many cases**: emit a domain event, let `@TransactionalEventListener(AFTER_COMMIT)` handle the side effect. Cleaner separation, transactional safety, retry/outbox semantics via Modulith.

---

## 10. Test slices vs. `@SpringBootTest` — load only what you're testing

Spring Boot's test slices are the practical realisation of Wampler's "test-drive the architecture":

| Slice | What it loads | When to use |
|---|---|---|
| `@JsonTest` | Jackson + the JSON config | Testing serialisation contracts. |
| `@DataJpaTest` | JPA + Hibernate + DataSource (H2 by default; Testcontainers for fidelity) | Testing repositories and JPA queries. |
| `@WebMvcTest(SomeController::class)` | Spring MVC + the one controller + filter chain | Testing the HTTP layer + ControllerAdvice. |
| `@WebFluxTest` | WebFlux + handlers | Reactive HTTP. |
| `@RestClientTest` | RestTemplate / WebClient infrastructure | Testing a Feign / RestTemplate client. |
| `@SpringBootTest` | Full context | Genuine wiring concerns; reach for it last. |

**House rule**:
- **Unit test the domain** with no Spring at all (POJO constructors).
- **Slice test** the adapter (controller, repository, JSON serialiser).
- **`@SpringBootTest` for one or two integration scenarios** that prove the wiring works end-to-end.
- **Don't `@SpringBootTest` every test.** A 30s test suite becomes a 5-minute test suite, and "test-drive the architecture" stops working.

**Architectural tests with Modulith**:
```kotlin
class ModularityTest {
    @Test
    fun `modules respect boundaries`() {
        ApplicationModules.of(OrderServiceApplication::class.java).verify()
    }
}
```

That single test enforces module-boundary discipline at every build — the architecture becomes a *test*.

**Cross-link**: `testing-strategy-kotlin-spring`, `clean-code-unit-tests`.

---

## 11. The `beans { }` Kotlin DSL — functional bean definitions

For Kotlin projects that want functional bean wiring without `@Configuration` annotation soup:

```kotlin
fun beans() = beans {
    bean<JpaOrderRepository>()
    bean<OrderApplicationService>()
    bean { Clock.systemUTC() }
    bean<OrderSubmittedNotifier>()

    profile("production") {
        bean<StripePaymentClient>()
    }
    profile("!production") {
        bean<FakePaymentClient>()
    }
}

class OrderServiceApplication

fun main(args: Array<String>) {
    runApplication<OrderServiceApplication>(*args) {
        addInitializers(beans())
    }
}
```

**Pros**: explicit, type-checked, no `@Component`/`@Configuration` scattering, fewer hidden annotations.
**Cons**: less idiomatic in mixed Spring shops; auto-configuration still relies on `@ConditionalOn*` annotations.

**When to use**: small or medium Kotlin-first apps; library code that needs to ship a `beans { }` block consumers can apply.

---

## 12. Spring Security DSL — declarative chain, not procedural

Modern Spring Security in Kotlin is a DSL:

```kotlin
@Configuration
@EnableMethodSecurity
class SecurityConfig {
    @Bean
    fun chain(http: HttpSecurity): SecurityFilterChain = http {
        authorizeHttpRequests {
            authorize("/actuator/health", permitAll)
            authorize("/api/admin/**", hasRole("ADMIN"))
            authorize(anyRequest, authenticated)
        }
        oauth2ResourceServer { jwt { } }
        sessionManagement { sessionCreationPolicy = SessionCreationPolicy.STATELESS }
        csrf { disable() }
    }.build()
}
```

The DSL reads as policy. No `HttpSecurity.builder().chain().chain().chain()` plumbing.

**Cross-link**: `spring-security-and-auth` for the deep dive.

---

## 13. RouterFunction DSL — functional WebFlux routes

```kotlin
@Configuration
class OrderRoutes(private val handler: OrderHandler) {
    @Bean
    fun routes() = coRouter {
        "/api/v1/orders".nest {
            POST("", handler::submit)
            GET("/{id}", handler::byId)
            GET("", handler::list)
        }
        accept(MediaType.APPLICATION_JSON).nest {
            // ...
        }
    }
}
```

An alternative to `@RestController` for reactive apps. Same Clean-Code rules — small handler, single concern.

---

## 14. MockMvc Kotlin DSL — testing the HTTP layer in DSL form

```kotlin
@WebMvcTest(OrderController::class)
class OrderControllerTest(@Autowired private val mockMvc: MockMvc) {

    @Test
    fun `POST returns 201 with location header`() {
        mockMvc.post("/api/v1/orders") {
            contentType = MediaType.APPLICATION_JSON
            content = """{"customerId": "...", "lines": [...]}"""
        }.andExpect {
            status { isCreated() }
            header { exists("Location") }
            jsonPath("$.id") { exists() }
        }
    }
}
```

Reads as the HTTP exchange. The DSL is the API contract test.

---

## 15. Spring smell-to-fix at the system level

| Smell | Fix |
|---|---|
| `ApplicationContext` injected somewhere | Inject the specific beans. Service-locator anti-pattern. |
| `@Autowired var` field | Constructor injection with `val`. |
| Profile/env check in business code (`if (env == "prod")`) | `@Profile` / `@ConditionalOnProperty` on alternative beans. |
| `@Value("${...}")` strings scattered | `@ConfigurationProperties` data class. |
| `@Transactional` on every repository method | One boundary per use case at the application service. |
| Self-invocation of `@Transactional` / `@Async` / `@Cacheable` | Call via an injected bean (or extract a sub-service). |
| One mega-`@Configuration` with 80 beans | Split per module: `OrderModuleConfig`, `PaymentModuleConfig`. |
| `@SpringBootTest` everywhere | Use slices: `@WebMvcTest`, `@DataJpaTest`. |
| Manual `for retry ... try ... catch ... continue` | `@Retry` (Resilience4j) or `RetryTemplate`. |
| `for (...) submit(item)` doing N transactions | One transactional method per logical use case, or chunked processing with explicit boundaries. |
| Bean cycle worked around with `@Lazy` | Break the cycle (event, callback, third bean). `@Lazy` is the smell. |
| `System.getenv()` / `System.getProperty()` in services | `@ConfigurationProperties`. |
| Manual `Logger.start(...)` / `Counter.increment()` boilerplate | `@Timed`, `@Counted` (Micrometer Aspects). |
| `@RestController` returning `Map<String, Any?>` | DTO data class. |
| Hand-rolled JWT parsing in a filter | OAuth2 Resource Server (Spring Security). |
| Inter-module communication via shared mutable state | Spring Modulith events. |

---

## 16. The Spring composition-root structure — recommended layout

```
src/main/kotlin/com/example/orders/
├── OrderServiceApplication.kt        ← @SpringBootApplication; 2 lines
├── config/
│   ├── OrderProperties.kt            ← @ConfigurationProperties
│   ├── PricingProperties.kt
│   └── WebConfig.kt                  ← @Configuration for cross-module HTTP concerns
├── orders/                           ← module
│   ├── api/
│   │   ├── OrderController.kt
│   │   ├── SubmitOrderRequest.kt
│   │   └── OrderView.kt
│   ├── application/
│   │   └── OrderApplicationService.kt
│   ├── domain/
│   │   ├── Order.kt                  ← POJO; no Spring imports
│   │   ├── OrderRepository.kt        ← interface
│   │   └── OrderSubmitted.kt         ← domain event
│   └── infrastructure/
│       ├── JpaOrderRepository.kt     ← @Repository
│       └── OrderEntity.kt            ← @Entity (separate from Order!)
├── payments/                         ← module (same shape)
└── shared/                           ← cross-module values (Money, IDs, errors)
```

Mapping to Ch. 11:
- `Application.kt` is "main" (Rule 2).
- `config/` is the per-system config (Rule 4).
- `<module>/domain/` is POJOs (Rule 5).
- `<module>/application/` is the cross-cutting-concerns surface (`@Transactional`, `@PreAuthorize` here) (Rule 6).
- `<module>/infrastructure/` is the adapters that talk to JPA, HTTP, message brokers (Rule 4 from the other side).

---

## 17. Checklist before merging a Spring system change

1. **`@SpringBootApplication` class is ≤ 5 lines.**
2. **One `@ConfigurationProperties` per module**; no `@Value` strings in services.
3. **Constructor injection only**; no `@Autowired var`, no `lateinit var` deps.
4. **No `if (profile == ...)` in business code**; use `@Profile` / `@Conditional*`.
5. **One `@Transactional` boundary per use case** at the application-service method.
6. **No self-invocation** of `@Transactional` / `@Async` / `@Cacheable`.
7. **`@Configuration` co-located with the module** it configures.
8. **Test slices used** — `@SpringBootTest` only when wiring is actually under test.
9. **`ApplicationModules.verify()` test exists** if you use Modulith.
10. **Spring Security as DSL**, not procedural builder chains.
11. **`@Async` executor configured** explicitly (no `SimpleAsyncTaskExecutor` default).
12. **Custom `@Aspect` justified** by ≥ 3 uniform applications.
