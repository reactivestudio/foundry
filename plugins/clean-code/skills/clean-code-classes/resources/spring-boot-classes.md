# Spring Boot / JPA class rules

This file extends Martin's Ch. 10 with the day-to-day class-design choices that actually consume the rules in a Spring Boot codebase: constructor injection as practical DIP, thin controllers, the perennial god `*Service`, `@Entity` as persistence shape vs. domain aggregate, OCP-style bean variants, and modular SRP via Spring Modulith.

## 1. Constructor injection — DIP made automatic

Spring offers three injection styles. Only one preserves DIP cleanly:

```kotlin
// ✓ Constructor injection — dependencies explicit at the class boundary, immutable, testable without Spring
@Service
class SubmitOrder(
    private val orders: OrderRepository,
    private val payment: PaymentGateway,
    private val clock: Clock,
) {
    fun handle(command: SubmitOrderCommand): OrderId { ... }
}

// ✗ Field injection — invisible dependencies, mutable, untestable without Spring's reflection magic
@Service
class SubmitOrder {
    @Autowired private lateinit var orders: OrderRepository
    @Autowired private lateinit var payment: PaymentGateway
    @Autowired private lateinit var clock: Clock
}

// ✗ Setter injection — same problems as field, plus encourages re-wiring at runtime
```

### Why constructor injection is the right answer

1. **Dependencies are explicit.** The primary constructor's parameter list *is* the dependency inventory. A god service is visible at a glance — 9 parameters is 9 collaborators.
2. **Immutability.** `private val` fields can't be reassigned after construction — no surprise rewiring.
3. **Testability.** You can `SubmitOrder(fakeOrders, fakePayment, fixedClock)` in a JUnit test without Spring, without `@MockBean`, without `@SpringBootTest`. The class works as a plain Kotlin class.
4. **DIP enforced by the constructor.** The class can't *not* declare its dependencies, and it can't depend on a concrete `JpaOrderRepository` if the constructor takes the `OrderRepository` port.

### The dependency-count signal

When a constructor reaches **5 dependencies**, pause. **7+ is almost always a god class** — split by use case (see §3 below) or move to CQRS handlers (see `cqrs-implementation`).

The Spring shape `@Autowired lateinit var` hides this signal — the constructor is empty, and the 15 dependencies look like 15 individual decorations rather than one collective alarm. Constructor injection forces the visibility.

## 2. Thin `@RestController` — one responsibility: HTTP translation

A controller's **one** responsibility is to translate between HTTP and the domain. Specifically:

- **Bind** request body / query / path / headers to typed input.
- **Validate** structurally (Bean Validation: `@Valid`, `@NotNull`, `@Pattern`).
- **Dispatch** to a use case / service.
- **Map** result to HTTP response (status, headers, body shape).

It does **not**:

- Contain business rules.
- Talk to the database directly.
- Build aggregates.
- Decide what an idempotency-key collision means.
- Format `ProblemDetail` payloads case-by-case (`@RestControllerAdvice` does that — see `clean-code-error-handling`).

```kotlin
// ✓ Thin controller — one job, easy to read end-to-end
@RestController
@RequestMapping("/orders")
class OrderController(
    private val submit: SubmitOrder,
    private val cancel: CancelOrder,
    private val findById: FindOrderById,
) {

    @PostMapping
    fun submit(@Valid @RequestBody request: SubmitOrderRequest): ResponseEntity<OrderResponse> {
        val id = submit.handle(request.toCommand())
        return ResponseEntity.status(CREATED).body(OrderResponse(id))
    }

    @PostMapping("/{id}/cancel")
    fun cancel(@PathVariable id: OrderId, @Valid @RequestBody request: CancelOrderRequest) {
        cancel.handle(CancelOrderCommand(id, request.reason))
    }

    @GetMapping("/{id}")
    fun byId(@PathVariable id: OrderId): OrderResponse =
        findById.handle(id).toResponse()
}
```

**SRP applied:** the controller depends on three use-case classes, not on `OrderRepository`, not on `EventPublisher`, not on `PaymentGateway`. Each use case is itself a small class with one responsibility.

## 3. `FooService` god class — split by use case

The most common SRP violation in real Spring codebases:

```kotlin
// ✗ God service — five unrelated use cases sharing nothing but the noun
@Service
class OrderService(
    private val orders: OrderRepository,
    private val payment: PaymentGateway,
    private val refunds: RefundGateway,
    private val csvExporter: CsvExporter,
    private val statisticsCache: StatisticsCache,
    private val auditLog: AuditLog,
    private val clock: Clock,
    private val mailer: Mailer,
    private val notifier: Notifier,
) {
    fun submit(...) { ... }      // depends on orders, payment, auditLog, clock, mailer
    fun cancel(...) { ... }      // depends on orders, auditLog, clock, notifier
    fun refund(...) { ... }      // depends on orders, refunds, auditLog
    fun exportToCsv(...) { ... } // depends on orders, csvExporter
    fun recomputeStats() { ... } // depends on orders, statisticsCache, clock
}
```

The cohesion test exposes it immediately: each method touches its own subset of dependencies, with little overlap. **Five use cases, five classes:**

```kotlin
@Service
class SubmitOrder(
    private val orders: OrderRepository,
    private val payment: PaymentGateway,
    private val auditLog: AuditLog,
    private val clock: Clock,
    private val mailer: Mailer,
) { fun handle(command: SubmitOrderCommand): OrderId { ... } }

@Service
class CancelOrder(
    private val orders: OrderRepository,
    private val auditLog: AuditLog,
    private val clock: Clock,
    private val notifier: Notifier,
) { fun handle(command: CancelOrderCommand) { ... } }

@Service
class RefundOrder(
    private val orders: OrderRepository,
    private val refunds: RefundGateway,
    private val auditLog: AuditLog,
) { fun handle(command: RefundOrderCommand) { ... } }

@Service
class ExportOrdersToCsv(
    private val orders: OrderRepository,
    private val csvExporter: CsvExporter,
) { fun handle(query: ExportOrdersQuery): CsvFile = ... }

@Service
class RecomputeOrderStatistics(
    private val orders: OrderRepository,
    private val statisticsCache: StatisticsCache,
    private val clock: Clock,
) { fun handle() = ... }
```

**Result:**

- Each class passes the 25-word test.
- Each class has 3–5 dependencies — visibly cohesive.
- A change to refund logic touches `RefundOrder`, not `OrderService`.
- A new use case (`ReassignOrder`) is a new class — no existing class changes (OCP at the service layer).
- Tests are pinpoint — you instantiate one use case with three fakes, not a god service with ten.

### Alternative — CQRS command handlers

If the codebase uses CQRS (see `cqrs-implementation`), the same split is expressed as one handler per command:

```kotlin
@Component
class SubmitOrderHandler(...) : CommandHandler<SubmitOrderCommand, OrderId> {
    override fun handle(command: SubmitOrderCommand): OrderId { ... }
}
```

The split is identical — what changes is the dispatch mechanism (command bus vs. controller-to-service call).

### When NOT to split

A service whose 4 methods all share the same 4 dependencies and touch the same domain concept is **not** a god class — it's a cohesive use case family. The cohesion test passes; leave it alone.

## 4. `@Entity` is the persistence shape, not the aggregate

This is the most consequential rule for JPA-based Spring services. A JPA `@Entity` has framework constraints that fight clean class design:

- **No-arg constructor required** (for Hibernate proxy creation).
- **Mutable fields** (Hibernate sets them via reflection on load).
- **Identity by `@Id`** (not by domain identity).
- **Public getters** required for JPQL / Spring Data projections.
- **Lifecycle annotations** (`@PrePersist`, `@PreUpdate`) couple persistence events to the class.

A class shaped by all that is a **data structure with persistence concerns**, not a domain aggregate.

### Two acceptable shapes

**Shape A — Lightweight: entity *is* the aggregate, accept the framework constraints.**

For simple CRUD-shaped domains where the entity has trivial behaviour (`recompute()`, `markDeleted()`), keep the entity as the aggregate. Apply class-level discipline as far as the framework allows: `private` setters where possible, factory methods on a companion, encapsulate mutators behind named operations.

```kotlin
@Entity
@Table(name = "orders")
class Order private constructor() {
    @Id @GeneratedValue lateinit var id: OrderId; private set

    @Column(name = "status") @Enumerated(EnumType.STRING)
    var status: OrderStatus = OrderStatus.DRAFT
        private set

    @OneToMany(mappedBy = "order", cascade = [ALL])
    private val _lines: MutableList<OrderLine> = mutableListOf()
    val lines: List<OrderLine> get() = _lines.toList()

    fun submit() {
        require(status == DRAFT) { "Order $id already submitted" }
        status = SUBMITTED
    }

    companion object {
        fun draft(lines: List<OrderLine>): Order = Order().apply { _lines.addAll(lines) }
    }
}
```

This is a *compromise*: invariants are partially exposed (`var` for the ORM, private setter), but the public API is behavioural. Acceptable for small domains.

**Shape B — Two-class: entity as persistence shape, aggregate as domain class.**

For non-trivial domains where business invariants are rich, keep the entity and the aggregate **separate**, with mappers between them. The entity is a pure persistence DTO; the aggregate has the real invariants.

```kotlin
// Persistence shape — Hibernate-friendly, no behaviour
@Entity
@Table(name = "orders")
class OrderRow(
    @Id val id: UUID,
    @Column(name = "status") var status: String,
    @OneToMany(mappedBy = "order") val lines: MutableList<OrderLineRow>,
) {
    constructor() : this(UUID.randomUUID(), "DRAFT", mutableListOf())
}

// Domain aggregate — Kotlin-flavoured, behaviour-rich
class Order private constructor(
    val id: OrderId,
    private val lines: MutableList<OrderLine>,
    private var status: OrderStatus,
) {
    fun submit() { ... }
    fun cancel(reason: CancelReason) { ... }
    fun lines(): List<OrderLine> = lines.toList()
    companion object { ... }
}

// Mapper at the persistence boundary
@Component
class OrderRepositoryImpl(private val jpa: OrderJpaRepository) : OrderRepository {
    override fun findById(id: OrderId): Order? = jpa.findById(id.value)?.toDomain()
    override fun save(order: Order) { jpa.save(order.toRow()) }
}
```

This is the **`clean-code-objects-and-data`** rule applied: the `@Entity` is a data structure, the aggregate is an object — never both at once.

**Decision:** prefer Shape A for simple CRUD modules; promote to Shape B when business invariants become non-trivial or the entity gains methods that don't relate to persistence. See `ddd-tactical-patterns` and `architecture-patterns` for when each fits.

## 5. `@ConfigurationProperties` — the smallest possible cohesive class

A `@ConfigurationProperties` is one of the cleanest classes Spring lets you write:

```kotlin
@ConfigurationProperties(prefix = "payment.gateway")
data class PaymentGatewayProperties(
    val baseUrl: URI,
    val apiKey: String,
    val timeout: Duration = 5.seconds.toJavaDuration(),
    val retries: Int = 3,
)
```

- One reason to change: the contract with `application.yml`.
- All fields used by every consumer that injects this object (typically one — the adapter).
- Type-safe: `Duration` and `URI` parsed at startup, not at first use.
- Immutable.
- Easy to test by construction (no need for `@SpringBootTest`).

**Rule:** every external configuration concern (a third-party endpoint, a feature flag set, retry parameters) gets its own `@ConfigurationProperties` data class. Don't lump unrelated configs into a `ServiceProperties` god class with 30 fields.

## 6. Spring Modulith — SRP at module scope

Inside one Spring Boot app, **Spring Modulith** enforces module boundaries that map naturally to bounded contexts:

```
src/main/kotlin/
  app/
    orders/                 ← module: orders
      package-info.kt       ← @ApplicationModule
      api/
        OrderId.kt          ← public types
      internal/             ← visible only inside orders
        Order.kt
        SubmitOrder.kt
        OrderRow.kt
    billing/                ← module: billing
      api/
      internal/
    notifications/          ← module: notifications
      api/
      internal/
```

Each module is an SRP unit at the **module level**: one reason to change, one cohesive set of types. Modulith verifies the structure in a test:

```kotlin
class OrderModuleTests {
    @Test
    fun `module structure is valid`() {
        ApplicationModules.of(Application::class.java).verify()
    }
}
```

**Class-design implication:** classes that don't belong to the module's responsibility shouldn't live in it. A `OrderEmailTemplate` belongs in `notifications`, not in `orders`. Modulith's `verify()` doesn't catch *all* SRP violations, but it catches the structural ones — cross-module dependencies that shouldn't exist.

See `spring-boot-mastery` for the deep-dive on Modulith.

## 7. OCP — `@ConditionalOnProperty`, `@Profile`, `@Primary`, List-of-Strategy

Spring's DI is a natural fit for OCP-style class design. Several mechanisms:

### Strategy beans — the textbook case

```kotlin
interface PaymentMethod {
    fun supports(request: PaymentRequest): Boolean
    fun charge(request: PaymentRequest): PaymentResult
}

@Component class CardPayment : PaymentMethod { ... }
@Component class SepaPayment : PaymentMethod { ... }

// new variant: @Component class CryptoPayment : PaymentMethod — DI picks it up automatically

@Service
class PaymentDispatcher(private val methods: List<PaymentMethod>) {
    fun charge(request: PaymentRequest): PaymentResult =
        methods.firstOrNull { it.supports(request) }?.charge(request)
            ?: throw NoApplicablePaymentMethod(request)
}
```

Adding a new payment method **doesn't touch the dispatcher**. OCP via constructor-injected `List<Strategy>`.

### `@ConditionalOnProperty` — variants by configuration

```kotlin
@Component
@ConditionalOnProperty("notifications.channel", havingValue = "email")
class EmailNotifier(...) : Notifier { ... }

@Component
@ConditionalOnProperty("notifications.channel", havingValue = "slack")
class SlackNotifier(...) : Notifier { ... }
```

Different deployments wire different notifier without code changes.

### `@Profile` — variants by environment

```kotlin
@Component @Profile("test") class InMemoryOrderRepository : OrderRepository { ... }
@Component @Profile("!test") class JpaOrderRepository(...) : OrderRepository { ... }
```

Test environments substitute the in-memory adapter; production uses JPA. **The domain class never changes.**

### `@Primary` — picking a winner among several implementations

When a bean has several implementations and one is the default, `@Primary` selects it for injection without removing the others. Combine with `@Qualifier` for the non-default cases.

### When to apply

These mechanisms are **OCP made practical** — adding a variant doesn't edit existing code. Apply them at **boundaries where variants are real**: integrations, environments, deployments, feature toggles. **Don't** wrap every class in `@ConditionalOnProperty` "just in case" — that's speculative OCP, indistinguishable from premature abstraction.

## 8. Wrapping external integrations — DIP in practice

Every external system (third-party API, message broker, cloud SDK, identity provider) is a candidate for the **port-adapter** shape:

```kotlin
// 1. Port — the domain owns the interface
interface PaymentGateway {
    fun charge(amount: Money, instrument: Instrument): ChargeResult
    fun refund(chargeId: ChargeId, amount: Money): RefundResult
}

// 2. Adapter — translates port to vendor API
@Component
class StripePaymentGateway(
    private val client: StripeClient,
    private val properties: StripeProperties,
) : PaymentGateway {
    override fun charge(amount: Money, instrument: Instrument): ChargeResult { ... }
    override fun refund(chargeId: ChargeId, amount: Money): RefundResult { ... }
}

// 3. Domain code depends on the port, not the adapter
@Service
class SubmitOrder(
    private val payment: PaymentGateway,  // not StripePaymentGateway
    ...,
) { ... }
```

**Class-design implications:**

- The **port interface lives in the domain layer**; the adapter lives in the infrastructure layer. The dependency direction is **domain ← infrastructure** (DIP).
- Changing payment vendor means writing a new adapter (`AdyenPaymentGateway`) and rewiring DI. **No domain class changes** — that's OCP at the integration boundary.
- Tests use a fake adapter. **No mocking framework needed** if the port is small enough.

See `clean-code-boundaries` for the full Wrap-Don't-Pass pattern and `clean-code-objects-and-data` for keeping vendor types from leaking through.

## 9. ArchUnit / Modulith fitness tests — enforce class rules in CI

Some of the rules in this skill can be enforced mechanically:

```kotlin
// no @Entity outside of *.persistence packages
@ArchTest
val entitiesLiveInPersistence: ArchRule = classes()
    .that().areAnnotatedWith(Entity::class.java)
    .should().resideInAPackage("..persistence..")

// no controller depends on a JPA repository directly
@ArchTest
val controllersUseUseCasesOnly: ArchRule = noClasses()
    .that().resideInAPackage("..controller..")
    .should().dependOnClassesThat().resideInAPackage("..persistence..")

// classes ending in *Manager are forbidden (weasel-suffix ban)
@ArchTest
val noManagerClasses: ArchRule = noClasses()
    .should().haveSimpleNameEndingWith("Manager")

// no class has more than 7 constructor parameters
@ArchTest
val constructorParamCap: ArchRule = classes()
    .should(notHaveTooManyConstructorParameters(7))
```

This is the **mechanical** half of SRP enforcement. The **judgement** half (is this class's responsibility actually one thing?) still needs human review — but the structural traps (wrong-layer dependencies, banned suffixes, parameter explosion) can be caught at CI time.

See `testing-strategy-kotlin-spring` for the broader ArchUnit setup.

## 10. Smell → fix quick reference, Spring-flavoured

| Smell | Fix |
|---|---|
| `@Service class FooService` with 9 dependencies and 6 unrelated methods | Split into use-case-narrow `@Service`s (`SubmitFoo`, `CancelFoo`, …) or CQRS handlers. |
| `@Autowired lateinit var` hiding the dependency count | Migrate to constructor injection so the count is visible at the class boundary. |
| Controller method 60 lines long, doing validation + persistence + email + audit | Move the logic into a use-case service; controller does only HTTP translation. |
| `@Entity` with 15 business methods that mutate `var` fields | Promote to two-class shape: `EntityRow` (persistence) + `Aggregate` (domain). |
| `application.yml` mapped via `@Value` strings across 8 files | Consolidate into `@ConfigurationProperties data class`. |
| Adding a third payment provider means editing `PaymentService` | Refactor to `interface PaymentMethod` + per-provider `@Component`. |
| Test for `OrderService.submit` needs `@SpringBootTest`, Testcontainers, WireMock | Use case is too coupled — narrow it, inject ports, build it as a plain Kotlin class in the test. |
| Cross-module call from `notifications.OrderEmailSender` directly to `orders.internal.Order` | Move the cross-module type to `orders.api`, or send via a Modulith event. |
| `OrderManager` ranked highly in the codebase | Find the real responsibility split; rename and split into multiple domain-named classes. |

## Cross-references

- Martin's canonical rules: `resources/general-classes-rules.md`.
- Kotlin idioms: `resources/kotlin-specific-classes.md`.
- Aggregate / VO / Repository shapes: `resources/ddd-classes.md`.
- Constructor injection deep-dive, `@ConfigurationProperties`, Modulith: `spring-boot-mastery`.
- Splitting a god service into CQRS handlers: `cqrs-implementation`.
- Wrapping vendor SDKs / external APIs: `clean-code-boundaries`.
- ArchUnit / Modulith / Testcontainers test setup: `testing-strategy-kotlin-spring`.
- Domain shapes for the patterns referenced here: `ddd-tactical-patterns`.
- Error-handling concerns at controller / service boundaries: `clean-code-error-handling`.
