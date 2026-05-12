# DDD System Patterns

Clean Code Ch. 11 system rules applied through a Domain-Driven Design lens. DDD names what Wampler describes abstractly: **bounded contexts** are the module boundaries, **aggregates** are the POJO core, **ACLs** are the seams where construction-vs-use becomes context-vs-context, **command/event** is the cross-context communication pattern, and **specifications / policies** are the most natural domain DSLs.

> "Modularity and separation of concerns make decentralized management and decision making possible." — Wampler. In DDD, that decentralisation maps to: one composition root per bounded context, one team per bounded context, one set of decisions per bounded context.

## Quick map — Ch. 11 concern → DDD shape

| Wampler concept | DDD realisation |
|---|---|
| Module of concern | Bounded context |
| POJO at the core | Aggregate + value objects + domain services (zero framework imports) |
| Composition root | Per-context `@Configuration` (Modulith application module) |
| Construction vs use | Aggregate factory vs container-managed services |
| Factory pattern | Aggregate factory / repository factory method |
| Cross-cutting concern | Domain event + handler; never aggregate-internal cross-cutting |
| Aspect | `@Transactional` at the application-service / use-case boundary |
| Decoupling between modules | ACL + Open-Host Service + Published Language |
| DSL | Specification, policy, builder for value objects |
| Test-drive architecture | One context at a time; new context = new module, not a rewrite |
| Defer decisions | Strategic design defers the *split* until a boundary becomes real |
| Use standards wisely | DDD's own patterns are standards — apply where they earn their place |

---

## 1. The bounded context as the unit of system separation

A **bounded context** is a region of the system in which one ubiquitous language is consistent. Within a context, `Order` means one thing. Across contexts (Sales vs. Shipping vs. Finance), `Order` may mean different things — that's expected, and **the boundary is where translation happens**.

```
com.example.app/
├── orders/         ← bounded context "Order Management"
│   └── Order, OrderLine, OrderSubmitted, OrderApplicationService
├── shipping/       ← bounded context "Fulfilment"
│   └── Shipment, ShipmentDispatched, ShipmentApplicationService
└── finance/        ← bounded context "Billing"
    └── Invoice, Payment, ChargeRequested
```

**Each context has**:
1. Its own **composition root** (`@Configuration` class — or a Modulith application module).
2. Its own **public surface** (a few interfaces + domain events).
3. Its **internal** structure (aggregates, repositories, adapters) hidden.
4. Its own **ACL** for translating with neighbouring contexts.

**Cross-link**: `ddd-strategic-design` covers finding contexts; `ddd-context-mapping` covers the relationships between them; this skill is **how to wire and modularise once those contexts exist**.

---

## 2. One composition root per bounded context

Each context is its own self-contained module — its own `@Configuration`, its own `@ConfigurationProperties`, its own component scan boundary.

```kotlin
// orders/OrdersConfig.kt
@Configuration
@EnableJpaRepositories(basePackages = ["com.example.app.orders.infrastructure"])
@EntityScan("com.example.app.orders.infrastructure")
@ComponentScan("com.example.app.orders")
class OrdersConfig

// shipping/ShippingConfig.kt
@Configuration
@EnableJpaRepositories(basePackages = ["com.example.app.shipping.infrastructure"])
@ComponentScan("com.example.app.shipping")
class ShippingConfig
```

In Spring Modulith, each top-level package *is* the application module — no explicit `@Configuration` needed for scanning, but co-locating one helps express "this is where this context's wiring lives."

**Anti-pattern**:
```kotlin
// ✗ One global @ComponentScan picks up everything; module boundaries blur
@SpringBootApplication
@ComponentScan(basePackages = ["com.example.app"])   // ← everything in one scan
class Application
```

**Good**:
```kotlin
// app/Application.kt
@SpringBootApplication
@Import(OrdersConfig::class, ShippingConfig::class, FinanceConfig::class)
class Application
```

Each `*Config` is the context's own composition root. The app-level `@Import` is the composition root *for the composition roots*.

---

## 3. The aggregate is the POJO core — framework-free

Wampler's "POJOs at the core" maps directly onto DDD's aggregate root:

```kotlin
// orders/domain/Order.kt — no framework imports
class Order private constructor(
    val id: OrderId,
    val customerId: CustomerId,
    private val lines: MutableList<OrderLine>,
    private var status: OrderStatus,
) {
    private val events = mutableListOf<DomainEvent>()
    fun events(): List<DomainEvent> = events.toList()
    fun clearEvents() { events.clear() }

    fun submit(at: Instant) {
        check(status == OrderStatus.DRAFT)
        check(lines.isNotEmpty())
        status = OrderStatus.SUBMITTED
        events += OrderSubmitted(id, customerId, totalAmount(), at)
    }

    fun totalAmount(): Money = lines.fold(Money.zero) { acc, line -> acc + line.subtotal() }

    companion object {
        fun create(...): Order { ... }
    }
}
```

**Rules** (echoing Wampler's POJO-at-the-core advice):
- Domain package imports nothing from `org.springframework.*`, `jakarta.persistence.*`, `com.fasterxml.jackson.*`.
- JPA mapping lives in a **separate adapter class** (`OrderEntity` / `OrderRow`) with a converter.
- HTTP mapping lives in `OrderView` / `SubmitOrderRequest`.
- The aggregate **emits events**; the repository **drains** them on save. Aggregate never publishes.

**Cross-link**: `ddd-tactical-patterns` for aggregate / value-object / repository discipline; `clean-code-functions/resources/ddd-functions.md` for the verb-level discipline inside the aggregate.

---

## 4. Aggregate factories — the "factories" rule from Ch. 11, named

Wampler's "factory pattern when the application controls when an object is created" is **exactly** the aggregate-factory pattern:

```kotlin
class Order private constructor(...) {
    companion object {
        fun create(
            customerId: CustomerId,
            initialLines: List<DraftLine>,
            ids: IdGenerator,            // ← dependency the constructor can't have
            clock: Clock,                // ← another dependency
        ): Order {
            require(initialLines.isNotEmpty()) { "Order needs at least one line" }
            val order = Order(
                id = ids.next(),
                customerId = customerId,
                lines = initialLines.map { it.toLine() }.toMutableList(),
                status = OrderStatus.DRAFT,
            )
            order.events += OrderCreated(order.id, customerId, clock.instant())
            return order
        }
    }
}
```

**Application service uses it**:
```kotlin
@Service
class OrderApplicationService(
    private val orders: OrderRepository,
    private val ids: IdGenerator,
    private val clock: Clock,
) {
    @Transactional
    fun create(command: CreateOrder): OrderId {
        val order = Order.create(command.customerId, command.lines, ids, clock)
        return orders.save(order).id
    }
}
```

Wampler's "the application controls *when*, the factory controls *how*" — exactly this shape. The factory enforces invariants, supplies the id, emits the creation event. The application service decides when.

---

## 5. Cross-cutting concerns at the boundary, not inside the aggregate

The aggregate never knows about transactions, security, or persistence. Those concerns live at the **boundary** — the application service or the adapter.

```kotlin
@Service
class OrderApplicationService(...) {
    @Transactional                       // ← persistence concern
    @PreAuthorize("hasRole('CUSTOMER')") // ← security concern
    @Timed("orders.submit")              // ← observability concern
    fun submit(command: SubmitOrder): OrderId {
        val order = orders.findByIdOrThrow(command.orderId)
        order.submit(clock.instant())    // ← pure domain call
        orders.save(order)
        return order.id
    }
}
```

The aggregate's `submit()` doesn't know about Spring, transactions, security, or metrics. **All those concerns attach declaratively at the application-service method.**

**Anti-pattern (concerns inside the aggregate)**:
```kotlin
// ✗ Aggregate aware of persistence
class Order(...) {
    fun submit(@Autowired publisher: ApplicationEventPublisher) {
        ...
        publisher.publishEvent(OrderSubmitted(...))   // ← domain knows Spring
    }
}
```

---

## 6. ACL — the Anti-Corruption Layer as the composition root *between* contexts

Within a context, the composition root is `@Configuration`. Between contexts, the composition root is the **ACL adapter** — a small set of classes whose only job is translation.

```kotlin
// pricing/ — neighbouring context with its own model
data class PricingResponse(val productId: String, val priceMinor: Long, val currency: String)

// orders/infrastructure/pricing/ — our ACL for pricing
@Component
class PricingAdapter(
    private val client: PricingClient,                 // ← vendor / context client
) : PriceCatalog {                                     // ← our domain's port
    override fun priceFor(productId: ProductId): Money {
        val response = client.fetch(productId.value.toString())
        return response.toMoney()                      // ← translation here, nowhere else
    }

    private fun PricingResponse.toMoney(): Money =
        Money(BigDecimal(priceMinor).movePointLeft(2), Currency.getInstance(currency))
}
```

**Why this is the system-level pattern, not just a function-level concern**:
- The ACL **isolates** the pricing context's model changes from our domain. Their team renames `priceMinor` to `amountCents` — only `PricingAdapter` changes.
- The ACL **isolates** their failures. Pricing service down → `PricingAdapter` decides whether to fall back (Special Case Pattern), retry (Resilience4j), or fail.
- The ACL **is where the standards earn their place**: their REST contract, their auth scheme, their idempotency convention — all hidden behind one port interface.

**House rule**: **one ACL per neighbouring context**, named `<Context>Adapter`, located in `<our-context>/infrastructure/<their-context>/`. The domain talks to the **port** (`PriceCatalog`), never to the adapter directly.

**Cross-link**: `clean-code-boundaries` for the Wrap-Don't-Pass discipline inside the adapter; `ddd-context-mapping` for the strategic ACL pattern.

---

## 7. Command + event as the cross-context wire format

Wampler's "wire components together" + "standards earn their place" maps onto DDD's command/event pattern:

- **Commands** flow *into* a context (synchronous, typed, return id/Unit/View). They carry intent: "do this".
- **Events** flow *out of* a context (asynchronous, past-tense, fact). They carry outcome: "this happened".

```kotlin
// orders/ context emits
data class OrderSubmitted(
    val orderId: OrderId,
    val customerId: CustomerId,
    val total: Money,
    val occurredAt: Instant,
) : DomainEvent

// shipping/ context listens — through Modulith's outbox
@Component
class ShipmentInitiator(private val shipping: ShipmentApplicationService) {
    @ApplicationModuleListener
    fun on(event: OrderSubmitted) {
        shipping.initiateShipment(event.orderId, event.customerId)
    }
}
```

**System-level rules**:
- **Events are owned by the producing context** — the schema lives there. Consumers conform.
- **Commands are owned by the receiving context** — the schema lives there. Senders conform.
- **No shared kernel by accident** — if a class is imported across context boundaries, that's an event payload (acceptable) or a leak (fix).
- **Persisted publication** for inter-context events. Spring Modulith does this with the `event_publication` table; **at-least-once delivery** with consumer idempotency is the contract.

**Cross-link**: `cqrs-implementation` for command-bus mechanics + projections; `messaging-rabbitmq-spring` for the broker-backed variant.

---

## 8. Specifications and policies — the DSLs of the domain

Wampler's "domain-specific languages" mostly become **specifications** and **policies** at the DDD level. These are the small, focused languages domain experts can read.

```kotlin
// Specifications — predicates the business can read
fun interface OrderSpecification {
    fun isSatisfiedBy(order: Order): Boolean
}

class IsHighValue(private val threshold: Money) : OrderSpecification {
    override fun isSatisfiedBy(order: Order) = order.total() >= threshold
}
class IsForRegion(private val region: Region) : OrderSpecification {
    override fun isSatisfiedBy(order: Order) = order.shippingAddress.region == region
}

infix fun OrderSpecification.and(other: OrderSpecification) =
    OrderSpecification { isSatisfiedBy(it) && other.isSatisfiedBy(it) }

// Usage reads as the business rule
val priorityShipping = IsHighValue(Money(1000)) and IsForRegion(Region.EU)
```

```kotlin
// Policies — decisions the business can read
fun interface PricingPolicy {
    fun priceFor(order: Order): Money
}

@Component
class TieredPricingPolicy(private val tiers: List<Tier>) : PricingPolicy {
    override fun priceFor(order: Order): Money {
        val subtotal = order.subtotal()
        return tiers.firstOrNull { subtotal in it.range }?.let { subtotal * it.multiplier }
            ?: subtotal
    }
}
```

**Why these are the right DSLs for DDD**:
- Domain experts can read predicates and policies named in their vocabulary.
- They compose (`and`, `or`, `not`) into bigger rules without code growth.
- They're testable in isolation — no framework.

**When to bother**: when the rule is **policy-shaped** (a closed set of inputs, a deterministic decision) and varies (pricing tiers change quarterly; eligibility rules change with regulation). For one-off logic with no variation, plain code is simpler.

---

## 9. Modulith vs. microservices — the decision Wampler implicitly defers

Wampler argues for incremental architecture: "start naïvely simple, add infrastructure as scale demands". For DDD specifically:

| When | Use |
|---|---|
| One team, one deploy, one database | Monolith. Modules in packages. |
| Multiple teams, one deploy, one database | **Spring Modulith.** Modules in packages, events between them, architecture tests enforce boundaries. |
| Multiple teams, separate deploys, separate databases | **Microservices**, one per context. Events over Kafka/RabbitMQ. |
| One context has a wildly different scaling profile (analytics, search) | Extract *that* context. Leave the rest in the modulith. |

**House rule**: **Modulith first.** Split when a *real* reason appears — different deploy cadence, different scaling, different team ownership. The split is **additive** if the modulith already used events for inter-context communication.

**Anti-pattern**: starting with 8 microservices because the architecture diagram looked clean. The team rebuilds the monolith inside Kubernetes with extra network hops and distributed-transaction problems. **Distributed monolith** — Wampler's BDUF in microservices clothing.

**Cross-link**: `architecture`, `architecture-patterns`, `microservices-patterns-deep` for the deeper decision frameworks; this skill is the *when and how* of splitting.

---

## 10. Open-Host Service and Published Language — the "standards" of one context

Wampler's "use standards wisely" finds its DDD shape:
- **Open-Host Service** — a context publishes a stable API for many consumers (the standard is the API).
- **Published Language** — a context publishes a stable wire format (JSON schema, Protobuf, Avro — the standard is the schema).

```kotlin
// orders publishes a stable HTTP API — Open-Host Service
@RestController
@RequestMapping("/api/v1/orders")
class OrderController(private val service: OrderApplicationService) { ... }

// orders publishes a stable event schema — Published Language
data class OrderSubmitted(
    val orderId: String,            // ← simple types in the wire format
    val customerId: String,
    val totalAmountMinor: Long,
    val currency: String,
    val occurredAt: Instant,
) {
    fun toDomain(): InternalOrderSubmitted = ...
}
```

**Rules**:
- The **published format is stable**. Add fields backward-compatibly; deprecate before remove; version when you must break.
- The **internal model can change freely** — that's the *whole* point of the published language.
- **Consumers translate** the published language at their boundary (their ACL).

**House rule**: when a third consumer arrives, the spec stabilises. Before that, change freely.

---

## 11. Strangler-fig migration — the practical "test-drive architecture" with legacy

When inheriting a monolith, the Ch. 11 advice "no BDUF" applies in reverse: don't rewrite. Strangle.

```
Step 1: Legacy monolith handles all traffic.
Step 2: New context-shaped service stood up, takes a slice of traffic (one endpoint, one event).
Step 3: New service grows; legacy service shrinks. Routing layer (API gateway, feature flag) directs traffic.
Step 4: Last legacy endpoint moves. Decommission monolith.
```

**At the system level, the strangler-fig requires**:
- A **routing seam** (API gateway, reverse proxy, Spring Cloud Gateway) — the composition-root-level switch between old and new.
- **Event-bridge ACLs** in both directions — old emits something the new consumes; new emits something the old consumes.
- **A "parallel write" period** for write paths — both systems persist, reconcile asynchronously.
- **Observability on both sides** — drift, lag, error rate per route.

**This is incremental architecture in its hardest form.** No BDUF: each step is one slice, one feature flag, one rollback path.

**Cross-link**: `microservices-patterns-deep` for strangler in operational depth.

---

## 12. Domain-context system anti-patterns

| Anti-pattern | Why bad | Fix |
|---|---|---|
| Shared mutable database across contexts | "Shared database = shared coupling = no contexts." | Each context owns its tables; events for cross-context state. |
| One JPA entity used in three contexts | Concept means different things; shared class hides divergence. | Per-context entity; ACL translates. |
| Anaemic aggregate (data only) + thick application service | Domain logic leaked out; reuse impossible across services. | Move verbs to the aggregate. |
| Cross-context REST calls inside aggregate | Domain pulled into network reality. | Inject a port; ACL in infrastructure. |
| Event consumer mutating producer's aggregate | Reverse-coupling; producer is no longer authoritative. | Consumer keeps its own state; reacts via events. |
| `@SpringBootTest` to test domain logic | Slow, framework-coupled, hides the point. | Unit-test the aggregate; integration-test the wiring once. |
| One Modulith module growing to 60% of the codebase | Bounded context drift; the module is no longer "bounded". | Re-split using event-storming with domain experts. |
| Distributed transactions across context APIs | Two-phase commit, etcetera — leaks. | Saga + compensating actions; eventual consistency. |
| ACL adapter is just a thin client wrapper, no translation | Foreign model leaks into the domain. | Translate types and concepts at the adapter. |
| Domain events with framework / serialisation annotations | Couples events to wire format. | Domain event + DTO event for the wire; mapper between them. |

---

## 13. The DDD/system checklist

1. **Each bounded context has its own composition root** — `@Configuration` and `@ConfigurationProperties` co-located.
2. **Domain packages have zero framework imports.** No `org.springframework.*`, no `jakarta.persistence.*` inside the aggregate.
3. **Aggregates have factories**, not exposed constructors with public mutators.
4. **Repositories return aggregates** or their absence; never persistence types.
5. **Cross-context calls go through a port + ACL adapter**, never directly into the other context's repository.
6. **Inter-context communication is event-based** by default; commands are synchronous calls only into the receiving context's application surface.
7. **One Modulith module per bounded context**; `ApplicationModules.verify()` test enforces boundaries.
8. **`@Transactional` at the application-service method**, not on the aggregate or the repository.
9. **Specifications and policies** are the project's DSLs — composable, named for the business question.
10. **Strangler-fig** is the migration tool of choice when modifying a monolith; no rewrites.

---

## 14. Worked example — a context's wiring end to end

```kotlin
// orders/domain/Order.kt — POJO domain
class Order private constructor(...) {
    fun submit(at: Instant) { ... }
    companion object { fun create(...): Order { ... } }
}

// orders/domain/OrderRepository.kt — port
interface OrderRepository {
    fun save(order: Order): Order
    fun findById(id: OrderId): Order?
}

// orders/domain/PriceCatalog.kt — port to neighbouring context
interface PriceCatalog {
    fun priceFor(productId: ProductId): Money
}

// orders/application/OrderApplicationService.kt — use cases, cross-cutting concerns attached
@Service
class OrderApplicationService(
    private val orders: OrderRepository,
    private val prices: PriceCatalog,
    private val clock: Clock,
) {
    @Transactional
    fun create(command: CreateOrder): OrderId {
        val order = Order.create(...)
        return orders.save(order).id
    }

    @Transactional
    fun submit(id: OrderId) {
        val order = orders.findById(id) ?: throw NotFound("Order", id)
        order.submit(clock.instant())
        orders.save(order)   // ← drains events, publishes via ApplicationEventPublisher
    }
}

// orders/infrastructure/jpa/JpaOrderRepository.kt — adapter
@Repository
class JpaOrderRepository(
    private val em: EntityManager,
    private val publisher: ApplicationEventPublisher,
) : OrderRepository { ... }

// orders/infrastructure/pricing/PricingAdapter.kt — ACL to neighbouring context
@Component
class PricingAdapter(private val client: PricingClient) : PriceCatalog {
    override fun priceFor(productId: ProductId): Money =
        client.fetch(productId.value.toString()).toMoney()
}

// orders/api/OrderController.kt — HTTP boundary
@RestController
@RequestMapping("/api/v1/orders")
class OrderController(private val service: OrderApplicationService) { ... }

// orders/OrdersConfig.kt — the context's composition root
@Configuration
@EnableConfigurationProperties(OrderProperties::class)
@EnableJpaRepositories
@ComponentScan("com.example.app.orders")
class OrdersConfig

// app/Application.kt — the application-level composition root
@SpringBootApplication
@Import(OrdersConfig::class, ShippingConfig::class, FinanceConfig::class)
class Application

fun main(args: Array<String>) {
    runApplication<Application>(*args)
}
```

Every Ch. 11 rule visible:
- **Separate construction from use** — `OrdersConfig` and `Application` wire; nothing else `new`s a service.
- **DI** — every service takes its deps by constructor.
- **POJOs at the core** — `Order` has no framework imports.
- **Cross-cutting concerns as aspects** — `@Transactional` declares the policy.
- **Modular** — each context has its own composition root and surface.
- **Test-drivable** — domain unit-testable in milliseconds; integration tests only for wiring.
- **Decision-deferral** — start as a modulith; extract `shipping/` only when its profile actually diverges.
- **DSL where it pays** — specifications/policies inside the domain; the rest is plain Kotlin.

That's the destination Wampler's chapter and DDD point at, in the same picture.
