# Kotlin-Specific System Patterns

Kotlin features that change which Ch. 11 rules still bite, which become trivial, and which need a Kotlin-shaped idiom. Each section identifies a system-level concern from Martin/Wampler and shows the Kotlin idiom that addresses it.

> "The language is part of the design." — paraphrase, applied to DSLs and system structure.

## Quick map — Kotlin feature attacks which system concern

| Ch. 11 concern | Kotlin feature | Effect |
|---|---|---|
| Separation of construction from use | `object` declarations | Compile-time singletons; no construction code at all. |
| Lazy-init | `by lazy { }` delegation | Thread-safe lazy property; no manual null check. |
| Dependency injection | Primary-constructor `val` properties | DI is the natural shape; no annotation needed. |
| Factories | `companion object` factory methods, sealed-class factories | Named constructors with invariant enforcement. |
| Setter injection (optional deps) | Constructor parameter with default value | One mechanism replaces overloads + setters. |
| Cross-cutting concerns | Inline higher-order functions (`measureTime`, `runCatching`, `transaction { }`) | Lightweight AOP-like wrappers without a proxy. |
| Cross-cutting concerns | Extension functions | Receivers gain behaviours without inheritance. |
| Cross-cutting concerns | Class delegation (`by`) | Forward to a delegate, override one method to add a concern. |
| DSLs | Type-safe builders (receiver-with-block lambdas, infix, operator overloading) | First-class. Kotlin was *designed* for DSLs. |
| `main` separation | `fun main(args)` is first-class | No class needed for entry point. Trivial in non-Spring apps. |
| Configuration values | `data class` + Spring `@ConfigurationProperties` | Typed config from yaml; immutable; testable. |
| DI alternative for non-Spring | **Koin** (Kotlin-native DI) | Lightweight DI without reflection / annotations / compile-time agents. |
| Coroutine scope as system boundary | `CoroutineScope`, structured concurrency | Lifetimes become explicit at a seam. |

---

## 1. `object` declarations — compile-time singletons

Kotlin's `object` keyword creates a thread-safe, lazy-initialised singleton. No constructor, no double-checked-locking pattern needed.

```kotlin
object Clocks {
    val system: Clock = Clock.systemUTC()
    val frozen: Clock = Clock.fixed(Instant.parse("2026-05-12T00:00:00Z"), ZoneOffset.UTC)
}
```

**When `object` is right**:
- Stateless utility (`object JsonMapper { fun parse(s: String): JsonNode = ... }`).
- A truly global value (a `Clock`, a `Random` with no seed dependence, a registry-of-registries).
- A `companion object` factory on a domain class.

**When `object` is wrong**:
- Anything stateful that varies per environment (use DI).
- Anything that has dependencies of its own (use DI).
- "I'll make it an `object` to avoid wiring it" — that's hiding the dependency.

**House rule**: `object` is for things that are singletons **by nature**, not for things that are singletons **because the framework manages them**. The Spring `@Service` / `@Component` lifecycle is the latter; DI is the right tool.

---

## 2. `by lazy { }` — controlled lazy-init

Kotlin's `lazy { }` delegate gives a thread-safe, single-init `val` whose computation runs only on first read.

```kotlin
class GeoCatalog(private val feed: GeoFeed) {
    val spatialIndex: SpatialIndex by lazy { SpatialIndex.from(feed.entries) }
}
```

**Rules for `lazy { }` at the system level**:
1. **`val`, not `var`**. Lazy is a one-shot computation.
2. **At a seam, not in business code**. A lazy property is fine for a derived value on a bean; it's wrong for a missing dependency (DI is the answer there).
3. **No I/O inside `lazy { }` for application beans**. Eager-eager-eager startup is debuggable; lazy I/O surfaces failures at the first call, often in prod.
4. **Mind the thread mode**. Default is `SYNCHRONIZED` (safe). `PUBLICATION` and `NONE` are optimisations — only use when you've measured contention.

```kotlin
// ✓ Derived index — cheap to compute, only used by a fraction of requests
class TaxJurisdictionResolver(private val rules: TaxRules) {
    private val byZipPrefix: Map<String, List<TaxRule>> by lazy {
        rules.all().groupBy { it.zipPrefix }
    }
    fun resolve(zip: ZipCode): List<TaxRule> = byZipPrefix[zip.prefix()].orEmpty()
}

// ✗ Lazy as DI workaround
class OrderService {
    private val payments: PaymentClient by lazy { PaymentClient.fromEnv() }   // ← inject
}
```

---

## 3. Primary-constructor `val` properties — DI without ceremony

Kotlin's primary constructor expresses required dependencies in the most natural form possible:

```kotlin
@Service
class OrderApplicationService(
    private val orders: OrderRepository,
    private val publisher: ApplicationEventPublisher,
    private val clock: Clock,
)
```

No `@Autowired`, no field declarations, no setter methods, no `lateinit`. The class declares what it needs and Spring (or Koin, or a hand-rolled `main`) provides it.

**The Kotlin-Spring constructor-injection idiom**:
- **All `val`** — once wired, dependencies don't change.
- **`private`** — collaborators are implementation details.
- **No `@Autowired`** — Spring auto-detects since 4.3 (single constructor).
- **No `lateinit var`** for dependencies — that's the field-injection footgun.

**Default arguments handle "optional collaborator" without setter injection**:

```kotlin
@Service
class OrderApplicationService(
    private val orders: OrderRepository,
    private val publisher: ApplicationEventPublisher,
    private val clock: Clock = Clock.systemUTC(),     // ← sensible default
)
```

In tests:
```kotlin
val service = OrderApplicationService(
    orders = InMemoryOrderRepository(),
    publisher = NoOpEventPublisher,
    clock = Clock.fixed(Instant.parse("2026-05-12T00:00:00Z"), ZoneOffset.UTC),
)
```

No mocking framework, no container — just direct construction.

---

## 4. `companion object` factories — named constructors with invariants

Replace exposed constructors with named factory methods that enforce invariants and document intent.

```kotlin
class Order private constructor(
    val id: OrderId,
    private val lines: MutableList<OrderLine>,
    private var status: OrderStatus,
) {
    companion object {
        fun create(customerId: CustomerId, lines: List<DraftLine>, ids: IdGenerator, now: Clock): Order {
            require(lines.isNotEmpty()) { "Order needs at least one line" }
            return Order(
                id = ids.next(),
                lines = lines.map { it.toLine() }.toMutableList(),
                status = OrderStatus.DRAFT,
            ).also { it.events += OrderCreated(it.id, customerId, now.instant()) }
        }

        fun restoreFromHistory(snapshot: OrderSnapshot): Order = ...   // ← different creation path
    }
}
```

**When `companion object` factory beats the bare constructor**:
- Multiple creation paths with different invariants (`create` vs `restoreFromHistory`).
- The creation needs domain dependencies (`IdGenerator`, `Clock`).
- You want to emit an event on construction.
- You want a named verb at the call site (`Order.create(...)` reads better than `Order(...)`).

**Cross-link**: `ddd-tactical-patterns` and `clean-code-functions/resources/ddd-functions.md` for the aggregate-factory deep dive.

---

## 5. Inline higher-order functions — lightweight cross-cutting

Kotlin's `inline` higher-order functions let you write tiny "around" wrappers without Spring's proxy machinery. They compose by calling the wrapped block.

```kotlin
inline fun <T> timed(name: String, block: () -> T): T {
    val start = System.nanoTime()
    try {
        return block()
    } finally {
        Metrics.timer(name).record(Duration.ofNanos(System.nanoTime() - start))
    }
}

// Use
fun submit(command: SubmitOrder): OrderId = timed("orders.submit") {
    val order = Order.submit(command)
    orders.save(order).id
}
```

**When this is right**:
- A genuinely small, generic concern (timing, simple retry, audit-log around a unit of work).
- The wrapped block reads naturally in code (no @-annotation overhead).
- You want to be explicit about what's wrapped vs. what isn't.

**When Spring AOP is right**:
- The concern applies to many methods uniformly (e.g., every controller method should be `@Timed`).
- The policy is declarative, not call-site-specific.
- The orchestration matters (transactions, security — Spring's lifecycle integration).

**Anti-pattern (reinventing AOP)**:
```kotlin
// ✗ A bespoke transaction wrapper hand-rolled to avoid Spring
inline fun <T> transactional(block: () -> T): T = ...   // ← Spring does this
```

---

## 6. Extension functions — cross-cutting receivers

Add a cross-cutting capability to a type *you don't own* without modifying it:

```kotlin
// Add a domain-shaped query to a Spring Data repository
fun OrderRepository.findByIdOrThrow(id: OrderId): Order =
    findById(id) ?: throw NotFound("Order", id)

// Add an "audited save" semantic at the call site without invasive change
fun OrderRepository.saveAudited(order: Order, by: UserId): Order {
    audit.log("save", order.id, by)
    return save(order)
}
```

**House rule**:
- Extensions for **utility** on types you don't own (Spring's, JDK's) — fine.
- Extensions for **cross-cutting policy** that should apply uniformly — use Spring AOP / annotations; extensions are call-site-explicit and easy to forget.
- Extensions to add **domain behaviour** to a class you own — put it on the class as a member.

---

## 7. Class delegation (`by`) — decorators without boilerplate

Kotlin's `by` keyword forwards every interface method to a delegate. Override one or two to add a concern.

```kotlin
class CachingOrderRepository(private val delegate: OrderRepository) : OrderRepository by delegate {
    private val cache = Caffeine.newBuilder().maximumSize(1000).build<OrderId, Order>()

    override fun findById(id: OrderId): Order? =
        cache.getIfPresent(id) ?: delegate.findById(id)?.also { cache.put(id, it) }
}
```

`OrderRepository by delegate` forwards every other method. Only the changed one is overridden. **Decorator pattern, zero boilerplate**.

**When to use**:
- A cross-cutting concern (caching, logging, metrics) needs to attach to one collaborator instance, not the whole codebase.
- The concern is too specific for an aspect (e.g., "this one client gets retries; the others don't").

**When Spring AOP is still better**:
- The same wrapping logic applies to many beans uniformly (`@Cacheable` over a `@Component`).

---

## 8. Kotlin DSLs — first-class system-design tool

Kotlin's type-safe-builder syntax (receiver-with-block lambda + `@DslMarker`) makes domain-specific languages cheap and safe. Examples from real projects:

**Gradle Kotlin DSL** (build config):
```kotlin
plugins { kotlin("jvm") version "2.2.20" }

dependencies {
    implementation("org.springframework.boot:spring-boot-starter-web")
    testImplementation("org.springframework.boot:spring-boot-starter-test")
}
```

**Spring `beans { }` DSL** (functional bean definition):
```kotlin
fun beans() = beans {
    bean<OrderApplicationService>()
    bean<JpaOrderRepository>()
    bean { Clock.systemUTC() }
}
```

**Spring Security DSL**:
```kotlin
@Configuration
class SecurityConfig {
    @Bean
    fun chain(http: HttpSecurity): SecurityFilterChain = http {
        authorizeHttpRequests {
            authorize("/api/public/**", permitAll)
            authorize(anyRequest, authenticated)
        }
        oauth2ResourceServer { jwt { } }
        csrf { disable() }
    }.build()
}
```

**Building a small domain DSL** (pricing rules — illustrative):
```kotlin
@DslMarker
annotation class DiscountDsl

@DiscountDsl
class DiscountRules {
    private val rules = mutableListOf<Rule>()
    infix fun forTier(tier: Tier) = TierBuilder(tier, rules)
    infix fun overSubtotal(threshold: Money) = SubtotalBuilder(threshold, rules)
    fun apply(order: Order): Money = rules.fold(Money.zero) { acc, r -> acc + r.apply(order) }
}

fun discountRules(block: DiscountRules.() -> Unit) = DiscountRules().apply(block)

// Use
val policy = discountRules {
    forTier(GOLD) rebate 10.percent
    overSubtotal(Money(1000)) rebate Money(50)
}
```

**DSL building blocks in Kotlin**:
- **Receiver-with-block lambdas** — `block: T.() -> Unit`.
- **Trailing-lambda call syntax** — `name { ... }` reads like a block.
- **Infix functions** — `forTier(GOLD) rebate 10.percent`.
- **Extension functions** — add DSL verbs without modifying the receiver.
- **`@DslMarker`** — prevents nested-receiver capture confusion.

**When a DSL earns its place** (Ch. 11 rule restated):
- Domain experts read or write the DSL.
- The structure varies more often than the engine.
- There are ≥ 5 distinct uses.

**When NOT to build a DSL**:
- One caller; two callers; a single test.
- An engineer-only audience and ordinary Kotlin would read just as well.
- You haven't found a good name yet — DSL is the wrong layer to decide names.

---

## 9. Koin — Kotlin-native DI without Spring

For non-Spring Kotlin apps (Ktor servers, Compose Desktop, CLI tools, libraries), Koin offers Kotlin-native DI without reflection or compile-time agents:

```kotlin
val orderModule = module {
    single<OrderRepository> { JpaOrderRepository(get()) }
    single<OrderApplicationService> { OrderApplicationService(get(), get(), get()) }
    single<Clock> { Clock.systemUTC() }
}

fun main() {
    startKoin { modules(orderModule) }
    val service = KoinJavaComponent.get(OrderApplicationService::class.java)
}
```

**When Koin is right**:
- A non-Spring app where you want DI without Spring's weight.
- A library that needs to be DI-friendly without forcing Spring on the consumer.
- A multi-platform Kotlin project (Spring is JVM-only).

**When Spring is right**:
- Anything Spring already does well: auto-configuration, security, transactions, Modulith.
- An enterprise stack where hiring & ecosystem matter.

**Same Ch. 11 rules apply** — Koin or Spring, the discipline is identical: composition root, constructor injection, POJOs at the core, declarative cross-cutting.

---

## 10. Coroutine scopes as system seams

`CoroutineScope` represents a lifetime — a unit of work that can be cancelled together. At the system level, it's a **seam between asynchronous regions**.

```kotlin
@Service
class OrderApplicationService(
    private val orders: OrderRepository,
    private val pricing: PricingClient,
    private val inventory: InventoryClient,
) {
    suspend fun submit(command: SubmitOrder): OrderId = coroutineScope {
        // Two independent suspend calls run concurrently; both must succeed
        val price = async { pricing.priceFor(command.lines) }
        val available = async { inventory.checkAvailability(command.lines) }

        require(available.await()) { "Items not available" }
        val order = Order.submit(command, price.await())
        orders.save(order).id
    }
}
```

**Rules at the system level**:
- **`coroutineScope { }`** at the entry to an async unit of work — concurrent children share its lifetime; failure of one cancels the others.
- **Don't leak scopes** through your domain — domain code is `suspend fun` or plain; the scope is owned by the application service or controller.
- **Test isolation**: `runTest { }` from `kotlinx-coroutines-test` gives a virtual time scope — perfect for testing concurrent system behaviour without flakiness.

**Anti-pattern**: storing a `CoroutineScope` as a field on a long-lived bean and launching ad-hoc jobs into it — that's a leak; jobs outlive request boundaries. Use `@Async` (Spring) or a properly-scoped supervisor scope at the seam.

---

## 11. `application.yml` typing — `@ConfigurationProperties` + data class

Spring's typed configuration meets Kotlin's data class for safe, testable, immutable config:

```yaml
# application.yml
orders:
  default-currency: EUR
  retention-days: 365
  pricing:
    base-url: https://pricing.internal
    timeout: 5s
```

```kotlin
@ConfigurationProperties("orders")
data class OrderProperties(
    val defaultCurrency: Currency,
    val retentionDays: Int,
    val pricing: Pricing,
) {
    data class Pricing(
        val baseUrl: URI,
        val timeout: Duration,
    )
}
```

```kotlin
@SpringBootApplication
@EnableConfigurationProperties(OrderProperties::class)
class OrderServiceApplication

@Service
class OrderApplicationService(private val properties: OrderProperties) { ... }
```

**Why this beats `@Value("${...}")` strings everywhere**:
- **Typed**: `Currency`, `URI`, `Duration` parsed by Spring's converters.
- **Discoverable**: one data class, one place, IDE-navigable.
- **Testable**: construct the data class directly in tests.
- **Immutable** by default (`val`).

**House rule**: any env-var/yaml-derived value used in business code goes through a `@ConfigurationProperties` data class. **No `System.getenv()` in services.**

---

## 12. Module organisation — Gradle subprojects + Kotlin `internal`

A composition root **per Gradle subproject** + `internal` visibility lets you build modular monoliths without Spring Modulith's full machinery.

```
build.gradle.kts (root)
modules/
  orders/
    src/main/kotlin/com/example/orders/
      domain/ (no Spring)
      adapters/jpa/...
      adapters/api/...
      OrdersConfig.kt   ← @Configuration; only exported beans are public
  payments/
    ...
  app/
    src/main/kotlin/com/example/app/
      Application.kt    ← @SpringBootApplication
```

**Rules**:
- Each module is a Gradle subproject.
- Module exports a small public API (a few interfaces, a `@Configuration`); everything else is `internal`.
- The `app` module wires modules together — that's the composition root.

**Why this matters**: it enforces Rule 5 (POJOs at core) at the build level — the domain subproject literally cannot depend on Spring if its `build.gradle.kts` doesn't include it.

**Cross-link**: `architecture-patterns` covers Layered / Onion / Clean module layouts; this skill covers cross-module wiring.

---

## 13. Multi-module Kotlin/Spring app skeleton

```kotlin
// modules/orders/build.gradle.kts
dependencies {
    api("org.springframework.boot:spring-boot-starter")
    implementation(project(":modules:common"))
    // NO Spring Web here — orders is the domain + JPA, no HTTP
}

// modules/orders/src/main/kotlin/.../OrdersConfig.kt
@Configuration
@EnableJpaRepositories
@ComponentScan("com.example.orders")
class OrdersConfig

// modules/app/build.gradle.kts
dependencies {
    implementation(project(":modules:orders"))
    implementation(project(":modules:payments"))
    implementation("org.springframework.boot:spring-boot-starter-web")
    implementation("org.springframework.boot:spring-boot-starter-actuator")
}

// modules/app/src/main/kotlin/.../Application.kt
@SpringBootApplication
class Application

fun main(args: Array<String>) {
    runApplication<Application>(*args)
}
```

**Result**: domain modules compile without Web. Tests for the domain are fast (no `@SpringBootTest`, no embedded servlet container). The composition root in `app/` puts them together.

---

## 14. Common Kotlin/system anti-patterns

| Anti-pattern | Why bad | Fix |
|---|---|---|
| `object` for a stateful or dependent thing | Hidden global state; impossible to swap in tests. | DI bean. |
| `lateinit var` for a Spring-injected dependency | NPE risk; defeats `val`; can't construct in unit tests. | Constructor injection with `val`. |
| Storing `ApplicationContext` in a class | Service locator anti-pattern; class becomes Spring-aware everywhere. | Inject the specific beans. |
| `CoroutineScope` stored as a field on a singleton bean | Jobs outlive request boundaries; leak. | Scope lives in the caller / use `@Async`. |
| Top-level `val` initialised from `System.getenv()` | Untyped, untested, can throw at class-load time. | `@ConfigurationProperties` data class. |
| `companion object` doing I/O at class-load (`val client = HttpClient.from(...)`) | Static init order; failures invisible until first use. | Spring bean, eager init. |
| DSL with `var` mutability hidden inside | `forTier(GOLD)` returns a builder whose mutation leaks; threading nightmare. | Immutable DSL — build a value, evaluate it. |
| `inline fun` that captures Spring beans | The inlining unrolls into business code, dragging Spring imports. | Don't inline framework wrappers; let Spring AOP handle it. |
| Koin + Spring in the same module | Two DI containers; bean resolution becomes a coin flip. | Pick one per module; Koin for non-Spring, Spring for everywhere else. |
| `by lazy { }` for the only entry point of a heavyweight resource | Failures appear at the *first* request, not at startup. | Eager `@Bean` initialisation. |

---

## 15. Checklist before merging a Kotlin/system change

1. **No `object` for a stateful or dependent singleton** — DI it.
2. **No `lateinit var` for dependencies** — primary-constructor `val`.
3. **No `System.getenv()` in services** — `@ConfigurationProperties`.
4. **No `ApplicationContext` field** — inject specific beans.
5. **`@Configuration` co-located with its module** — not in a global `config/`.
6. **`lazy { }` only at seams, only `val`, no I/O** — eager startup for I/O.
7. **Constructor injection without `@Autowired`** — single primary constructor.
8. **Default-argument values for optional deps** — not setter injection.
9. **Domain module's `build.gradle.kts` has no `spring-boot-starter-web`** — POJO domain enforced at build.
10. **A DSL has ≥ 5 callers or a non-engineer reading it** — if not, write plain Kotlin.
