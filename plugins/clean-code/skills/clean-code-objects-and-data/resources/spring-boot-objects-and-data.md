# Spring / JPA — Objects and Data Structures

Spring and JPA pull the codebase toward Martin's *worst* shape: classes with mutable fields, no-arg constructors, public accessors, and business logic scattered across services that manipulate those fields. Most "Spring services" in real codebases are *procedures* operating on *data structures* labelled `@Entity` — which is fine as a label, but disastrous when the team thinks they're writing object-oriented domain code.

This file is the catalogue of how to apply Ch. 6's discipline in a Spring/Boot/JPA codebase without fighting the framework you depend on.

---

## The cast of types in a Spring/Boot service

A well-layered Spring service distinguishes at least four kinds of classes:

| Layer | Type kind | Shape | Mutability | Owner |
|---|---|---|---|---|
| HTTP boundary | Request / Response DTO | `data class val …` | immutable | `clean-code-objects-and-data`, `api-design-principles` |
| Domain | Aggregate / Value Object / Domain Event | `class` with private state and behaviour | encapsulated mutation | `ddd-tactical-patterns` |
| Persistence | JPA `@Entity` (row mirror) | mutable, no-arg constructor, framework-shaped | framework-controlled | this file + `database-design` |
| Cross-layer | Mapper | extension functions or MapStruct | stateless | this file |

Mixing those roles into a single class is the standard Spring smell. The rest of this document is the list of specific ways it happens and the corresponding fix.

---

## JPA `@Entity` is a persistence shape, not an aggregate

Hibernate / JPA imposes:

- A no-arg constructor (visible to the persistence provider).
- Mutable fields with setter access (or backing-field magic) so the proxy can hydrate them.
- An identity field with an annotation (`@Id`) — *not* a domain identity.
- Lazy proxies for relations, fetched on first access (not on demand).

That set of constraints is the **opposite** of a behaviour-rich aggregate (private constructor, immutable where possible, named factory, invariants from the first moment). Treating the `@Entity` as if it were an aggregate guarantees a hybrid (Rule 3 in `general-objects-and-data-rules.md`).

Two clean strategies:

### Strategy A — Separate aggregate and persistence shape (cleanest)

Two classes; the entity is internal to the persistence module; mapping is explicit.

```kotlin
// --- Domain side ---
class Order private constructor(
    val id: OrderId,
    private var status: OrderStatus,
    private val items: MutableList<OrderItem>,
) {
    fun submit(now: Instant): OrderSubmitted { /* invariants */ }
    val view: List<OrderItem> get() = items.toList()

    companion object {
        fun place(items: List<OrderItem>): Order = Order(OrderId.fresh(), OrderStatus.DRAFT, items.toMutableList())
        internal fun rehydrate(row: OrderRow): Order = ...
        internal fun snapshot(order: Order): OrderRow = ...
    }
}

// --- Persistence side ---
@Entity
@Table(name = "orders")
internal class OrderRow(
    @Id var id: UUID,
    @Enumerated(EnumType.STRING) var status: OrderStatus,
    @OneToMany(cascade = [ALL], orphanRemoval = true) var items: MutableList<OrderItemRow>,
) {
    protected constructor() : this(UUID.randomUUID(), OrderStatus.DRAFT, mutableListOf())
}

interface OrderRepository {
    fun save(order: Order)
    fun findById(id: OrderId): Order?
}

@Repository
internal class JpaOrderRepository(private val jpa: OrderJpaRepository) : OrderRepository {
    override fun save(order: Order) { jpa.save(Order.snapshot(order)) }
    override fun findById(id: OrderId): Order? = jpa.findById(id.value).orElse(null)?.let(Order::rehydrate)
}
```

Trade-offs:
- ✓ Domain class is clean — no JPA annotations, no proxies, no no-arg constructor.
- ✓ Tests for `Order` need no Spring or database.
- ✓ Persistence shape can evolve independently (move to a different store, denormalise, archive old rows).
- ✗ Two classes and a mapper per aggregate — overhead for small CRUD systems.
- ✗ Lazy loading of relations is harder to take advantage of; bulk hydration may pull more than needed.

Use this when the domain has real invariants, the team has the discipline to keep the mapping current, and the cost of a leaky `@Entity` model would hurt (long-lived service, high test value, audit-critical domain).

### Strategy B — Single class, framework-shaped, behaviour-aware (pragmatic)

One class, shaped by JPA, but with **encapsulated mutators** and **factory methods** for business operations. Accept that the persistence shape is the public shape; pay for discipline in `private set` and `protected` JPA hooks.

```kotlin
@Entity
@Table(name = "orders")
class Order private constructor(
    @Id val id: UUID,
    @Enumerated(EnumType.STRING)
    var status: OrderStatus = OrderStatus.DRAFT,
        protected set,
    @OneToMany(cascade = [ALL], orphanRemoval = true, fetch = FetchType.LAZY)
    private val _items: MutableList<OrderItem> = mutableListOf(),
) {
    val items: List<OrderItem> get() = _items.toList()

    fun submit(now: Instant): OrderSubmitted {
        check(status == OrderStatus.DRAFT) { "Only DRAFT can be submitted" }
        require(_items.isNotEmpty()) { "Order must have items" }
        status = OrderStatus.SUBMITTED
        return OrderSubmitted(OrderId(id), now)
    }

    protected constructor() : this(UUID.randomUUID())                     // JPA's no-arg
    companion object {
        fun place(items: List<OrderItem>) = Order(UUID.randomUUID()).apply { _items.addAll(items) }
    }
}
```

Trade-offs:
- ✓ One class, less ceremony, fits a small/medium codebase.
- ✓ JPA mutability is hidden behind `protected set` and `private val _items`.
- ✗ The class is still shaped by JPA — primary-constructor `var`, no-arg ctor for proxies, etc.
- ✗ Public API leaks `@Entity`, which means callers can pass it to anything that wants JPA — and Jackson can still serialise it directly. Disciplined `@JsonAutoDetect(NONE)` or a separate response DTO is mandatory.
- ✗ Lazy-loading surprises (LazyInitializationException) can still bite when the entity escapes the transaction.

This is the right answer for many real codebases. Treat it as "as close to clean as the framework allows," not as "the cleanest solution full stop."

### Strategy ⚠ — JPA entity with business methods, mutable fields, no encapsulation

```kotlin
@Entity
class Order(
    @Id var id: UUID = UUID.randomUUID(),
    @Enumerated(EnumType.STRING) var status: OrderStatus = OrderStatus.DRAFT,
    @OneToMany(...) var items: MutableList<OrderItem> = mutableListOf(),
) {
    fun submit() { check(status == OrderStatus.DRAFT); status = OrderStatus.SUBMITTED }
}
```

This is the **canonical hybrid** and the default shape of most JPA codebases. The `submit()` method is a polite suggestion that any caller can ignore with `order.status = OrderStatus.SUBMITTED`. The invariant is in one place but enforced nowhere. Avoid.

---

## Anemic domain model — the inverse hybrid

The mirror image of an over-rich entity is the **anemic** one: data on `@Entity`, behaviour on `@Service`.

```kotlin
// ✗ Anemic — Order is a passive bag of fields, all logic lives in OrderService
@Entity
class Order(@Id var id: UUID, var status: OrderStatus, @OneToMany var items: MutableList<OrderItem>)

@Service
class OrderService(private val repo: OrderRepository, private val clock: Clock, private val events: ApplicationEventPublisher) {
    @Transactional
    fun submitOrder(orderId: UUID) {
        val order = repo.findById(orderId).orElseThrow()
        check(order.status == OrderStatus.DRAFT) { "Only DRAFT orders can be submitted" }
        require(order.items.isNotEmpty()) { "Order must have items" }
        order.status = OrderStatus.SUBMITTED
        order.submittedAt = clock.instant()
        repo.save(order)
        events.publishEvent(OrderSubmitted(order.id))
    }

    @Transactional
    fun cancelOrder(orderId: UUID, reason: CancelReason) {
        val order = repo.findById(orderId).orElseThrow()
        check(order.status in setOf(OrderStatus.DRAFT, OrderStatus.SUBMITTED)) { "Cannot cancel ${order.status}" }
        order.status = OrderStatus.CANCELLED
        order.cancelledReason = reason
        repo.save(order)
    }
}
```

Symptoms:
- Every state transition (`submitOrder`, `cancelOrder`, `shipOrder`, `refundOrder`) has the same shape: load, check, mutate, save, maybe publish.
- The state machine ("DRAFT can become SUBMITTED or CANCELLED; SUBMITTED can become CANCELLED or SHIPPED; ...") is spread across N methods of `OrderService`.
- A second caller (a Kafka listener, a scheduled job) can either reuse `OrderService` or — much more commonly — copy the load-check-mutate-save pattern, drifting silently.
- A typo like `order.status = SHIPPED` anywhere in the codebase corrupts state with no compile-time defence.

Fix: **push the state-machine and the precondition into the aggregate**.

```kotlin
// ✓ Order owns its invariants; service is a thin orchestrator
class Order private constructor(...) {
    fun submit(now: Instant): OrderSubmitted { /* invariant + mutation + event */ }
    fun cancel(reason: CancelReason, now: Instant): OrderCancelled { /* idem */ }
    fun ship(at: Instant): OrderShipped { /* idem */ }
}

@Service
class OrderService(private val repo: OrderRepository, private val clock: Clock, private val events: ApplicationEventPublisher) {
    @Transactional
    fun submit(orderId: OrderId) {
        val order = repo.findById(orderId) ?: throw OrderNotFound(orderId)
        val event = order.submit(clock.instant())
        repo.save(order)
        events.publishEvent(event)
    }
}
```

The service shrinks to **load → call → save → publish**; new transitions are new methods on `Order`, not new procedural ladders in the service.

### When anemic is the right answer

- **CRUD admin tools** with no real domain rules ("create category", "rename product", "soft-delete user"). A behavioural aggregate is overhead with no payoff.
- **Reporting / read-side projections** that exist to be queried, not mutated. The "aggregate" is just a view.

The rule of thumb: if every method of the service does something the entity could be asked to do, you have an anemic domain. If the methods are largely about coordinating multiple aggregates, services, or external systems, the service is doing service-shaped work — that's fine.

---

## DTOs at every boundary

Boundaries are everywhere in a Spring service: HTTP controllers, Kafka listeners, scheduled tasks, internal Modulith events, gRPC handlers, external clients. **Each one gets its own DTOs.** Do not let domain or persistence types travel through them.

### HTTP request / response

```kotlin
// ✓ Request DTO — Bean Validation at the boundary, `data class val` shape
data class SubmitOrderRequest(
    @field:NotEmpty val items: List<@Valid OrderItemRequest>,
    @field:NotNull val customerId: UUID,
)

data class OrderItemRequest(
    @field:NotNull val productId: UUID,
    @field:Min(1) val quantity: Int,
)

// ✓ Response DTO — has no relationship to @Entity or aggregate; shaped for the consumer
data class OrderView(
    val id: UUID,
    val status: String,
    val placedAt: Instant,
    val totalCents: Long,
    val currency: String,
    val items: List<OrderItemView>,
)

@RestController
@RequestMapping("/orders")
class OrderController(private val service: OrderService) {
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    fun submit(@Valid @RequestBody req: SubmitOrderRequest): OrderView =
        service.submit(req.toCommand()).toView()
}

// Mapping lives near the DTO (extension function); easy to test, easy to evolve
fun SubmitOrderRequest.toCommand(): SubmitOrderCommand =
    SubmitOrderCommand(customerId = CustomerId(customerId), items = items.map { OrderLineCommand(ProductId(it.productId), it.quantity) })

fun Order.toView(): OrderView = OrderView(id = id.value, status = status.name, ...)
```

Why DTOs at the HTTP boundary matter:
- **Wire stability.** Renaming a private field of `Order` would break every API consumer if the entity were serialised directly.
- **No accidental data leak.** A `@JsonIgnore` on the entity is a footgun — every new field is exposed by default. With a separate response DTO, every field is exposed *deliberately*.
- **Validation belongs at the edge.** Bean Validation annotations on the DTO; domain invariants live on the aggregate. Two layers, two responsibilities.
- **Versioning.** v1 and v2 of the API can have different DTOs without forking the domain.

### Kafka / event payloads

```kotlin
// ✓ Outbox / Kafka payload — schema-evolution-aware DTO
data class OrderSubmittedV1(
    val orderId: UUID,
    val submittedAt: Instant,
    val customerId: UUID,
)
```

Domain events on the aggregate (`OrderSubmitted`) and outbound payloads (`OrderSubmittedV1`) are usually **different types**. The first is in your ubiquitous language; the second is a wire contract with a schema registry. Map between them on publication.

### `@ConfigurationProperties`

Spring Boot 3.x supports immutable `@ConstructorBinding` DTOs:

```kotlin
@ConfigurationProperties(prefix = "billing")
data class BillingProperties(
    val invoicePrefix: String,
    val retryAttempts: Int = 3,
    val timeout: Duration = Duration.ofSeconds(10),
)

@Configuration
@EnableConfigurationProperties(BillingProperties::class)
class BillingConfig
```

Validate at boot if needed:

```kotlin
@ConfigurationProperties(prefix = "billing")
@Validated
data class BillingProperties(
    @field:NotBlank val invoicePrefix: String,
    @field:Min(1) val retryAttempts: Int,
)
```

`@ConfigurationProperties` is exactly the role of a DTO in Martin's sense: a typed view of an external data source (here, the configuration tree). No methods, all `val`, immutable.

### Projections — read-side data structures

For query endpoints, *never* fetch the aggregate just to map it to a view. Use a JPA projection or a `@Query`-returned `data class`:

```kotlin
data class OrderSummary(
    val id: UUID,
    val status: OrderStatus,
    val totalCents: Long,
    val itemCount: Int,
)

interface OrderJpaRepository : JpaRepository<OrderRow, UUID> {
    @Query("""
        select new com.example.OrderSummary(o.id, o.status, sum(i.priceCents), count(i))
        from OrderRow o left join o.items i where o.customerId = :cid group by o.id, o.status
    """)
    fun listSummariesFor(cid: UUID): List<OrderSummary>
}
```

The projection is a data structure; the controller returns it (or maps it to a response DTO). No aggregate is hydrated, no proxies are dereferenced, no Tell-Don't-Ask discipline is bent — there's no domain operation happening, just data being read.

---

## MapStruct or hand-rolled mappers — pick by cost

For tiny services (a controller, two DTOs, one aggregate), **hand-rolled extension functions are fastest**:

```kotlin
fun SubmitOrderRequest.toCommand(): SubmitOrderCommand = ...
fun Order.toView(): OrderView = ...
```

For services with 20+ DTOs across multiple controllers and outbound publishers, **MapStruct** (or Mappie for Kotlin) pays for itself — it generates the boilerplate, fails the build when a field is missed, and supports nested mapping without you handling every nullable.

```kotlin
@Mapper(componentModel = "spring")
interface OrderMapper {
    fun toCommand(request: SubmitOrderRequest): SubmitOrderCommand
    fun toView(order: Order): OrderView
}
```

Either way, the **mapper is stateless** and **doesn't enforce invariants** — it's a translation step. Validation goes on the request DTO (Bean Validation). Domain rules go on the aggregate. The mapper is the seam, not a third place to put logic.

---

## Spring Data repository as a tell-don't-ask seam

Spring Data repositories naturally enforce a Tell-Don't-Ask pattern at the persistence boundary: you `save(order)` or `findById(id)`, you don't ask the repository for the SQL connection. Keep it that way.

```kotlin
// ✓ Repository deals in aggregates (or persistence rows in option A above)
interface OrderRepository : JpaRepository<OrderRow, UUID> {
    fun findByCustomerId(customerId: UUID, page: Pageable): Page<OrderRow>
}
```

Anti-patterns to keep out of repositories:
- **Returning `Map<String, Any?>` or `List<Tuple>`.** These force the caller to know column names — Demeter violation through a different door.
- **Exposing `EntityManager` or `JdbcTemplate`** to a service that then writes its own queries. Each repository should own a focused set of queries against one aggregate root.
- **Business logic in repository methods.** If you find yourself filtering or counting in a repository method whose name contains a domain verb (`findOrdersThatShouldBeRefunded`), the rule belongs on the aggregate or a domain service, not on the persistence interface.

For projections (read-side), a separate `OrderQueryRepository` is fine — split commands and queries at the repository level if the surface grows enough to justify it. See `cqrs-implementation`.

---

## Modulith / event boundaries — DTO again

When a Spring Modulith module publishes an event to another module via `ApplicationEventPublisher`, the event is a **DTO crossing a module boundary**.

```kotlin
// ✓ Inside the Order module — aggregate emits a domain event
class Order private constructor(...) {
    fun submit(now: Instant): OrderSubmitted = OrderSubmitted(id, now)
}

// ✓ Event itself is a data structure — `data class val`, no behaviour, no leakage
data class OrderSubmitted(val orderId: OrderId, val at: Instant)

// ✓ Receiving module reads it through @ApplicationModuleListener
@Component
class OrderShippingListener(private val shipping: ShippingService) {
    @ApplicationModuleListener
    fun on(event: OrderSubmitted) {
        shipping.prepareForOrder(event.orderId)
    }
}
```

The listener treats the event as a data structure: it reads the fields, calls into its own module's services, and that's it. It does **not** reach back into the publishing module's aggregates.

For cross-context (cross-service) events, see `ddd-context-mapping` — the same principle applies, but the DTO becomes a wire contract with a schema registry and a versioning policy.

---

## Spring-specific anti-patterns to refuse

| Anti-pattern | Why it's wrong | Fix |
|---|---|---|
| `@Entity` exposed directly from `@RestController` via Jackson | Wire contract becomes a function of the schema; every rename breaks consumers; lazy proxies serialise junk; `Hibernate.initialize` ladders multiply | Add a response DTO; map at the controller |
| `OrderService.getOrder(id): Order` returns the entity to a controller | Aggregate leaks into HTTP, JSON, Kafka, scheduled tasks alike | Return the aggregate only inside the module; map to view at boundaries |
| `Order.save()` method on the entity | Hybrid; Active Record anti-pattern; couples domain to persistence | `OrderRepository.save(order)` outside the aggregate |
| `@Transactional` on the entity / aggregate | Mixes business and transactional concerns; defeats the proxy | `@Transactional` on the service method that orchestrates the use case |
| Public no-arg constructor + bare `var` fields on an aggregate "because Hibernate needs it" | Frames the entire domain as a hybrid | Use Strategy A or Strategy B above |
| Manual `BeanUtils.copyProperties(request, entity)` | Treats both as data structures, skips validation, breaks on rename | Explicit extension function or MapStruct |
| `Order.equals` comparing every field | Aggregates have identity, not value-equality; breaks across-session comparisons after JPA proxies | `override fun equals(other: Any?) = other is Order && other.id == id` |
| `@JsonProperty` annotations all over the entity to control serialisation | Entity is doing wire-format work; one rename re-breaks the API | Response DTO; map at boundary |
| Lombok `@Data` ported habit (Kotlin equivalent: `data class` aggregate) | Generates equals/hashCode based on every field, exposes `copy(...)` to mutate by accident | `class` with private state + `override fun equals`/`hashCode` by identity |

---

## Putting it together — a one-aggregate vertical slice

```kotlin
// --- API ---
data class SubmitOrderRequest(@field:NotEmpty val items: List<@Valid OrderItemRequest>, @field:NotNull val customerId: UUID)
data class OrderView(val id: UUID, val status: String, val placedAt: Instant, val totalCents: Long, val items: List<OrderItemView>)

@RestController @RequestMapping("/orders")
class OrderController(private val service: OrderService) {
    @PostMapping @ResponseStatus(CREATED)
    fun submit(@Valid @RequestBody req: SubmitOrderRequest): OrderView = service.submit(req.toCommand()).toView()
}

// --- Application ---
@Service
class OrderService(private val orders: OrderRepository, private val clock: Clock, private val events: ApplicationEventPublisher) {
    @Transactional
    fun submit(cmd: SubmitOrderCommand): Order {
        val order = Order.place(cmd.customerId, cmd.items)
        val event = order.submit(clock.instant())
        orders.save(order)
        events.publishEvent(event)
        return order
    }
}

// --- Domain ---
class Order private constructor(
    val id: OrderId,
    private val customerId: CustomerId,
    private var status: OrderStatus,
    private val items: List<OrderItem>,
    private var submittedAt: Instant?,
) {
    val view get() = OrderSnapshot(id, status, submittedAt, items.sumOf { it.priceCents }, items)

    fun submit(now: Instant): OrderSubmitted {
        check(status == OrderStatus.DRAFT) { "Only DRAFT can be submitted" }
        require(items.isNotEmpty()) { "Order must have items" }
        status = OrderStatus.SUBMITTED
        submittedAt = now
        return OrderSubmitted(id, customerId, now)
    }

    companion object {
        fun place(customerId: CustomerId, lines: List<OrderLineCommand>) =
            Order(OrderId.fresh(), customerId, OrderStatus.DRAFT, lines.map(::toOrderItem), null)
    }
}

data class OrderSubmitted(val orderId: OrderId, val customerId: CustomerId, val at: Instant)

// --- Persistence (Strategy A) ---
@Entity @Table(name = "orders")
internal class OrderRow(
    @Id var id: UUID,
    var customerId: UUID,
    @Enumerated(EnumType.STRING) var status: OrderStatus,
    var submittedAt: Instant?,
    @OneToMany(cascade=[ALL], orphanRemoval=true) var items: MutableList<OrderItemRow>,
) { protected constructor() : this(UUID.randomUUID(), UUID.randomUUID(), OrderStatus.DRAFT, null, mutableListOf()) }

@Repository
internal class JpaOrderRepository(private val jpa: OrderJpaRepository) : OrderRepository {
    override fun save(order: Order) { jpa.save(order.toRow()) }
    override fun findById(id: OrderId): Order? = jpa.findById(id.value).orElse(null)?.toAggregate()
}
```

Each layer has one job; each class is on one side of the object/data dichotomy; train wrecks have nowhere to start because consumers don't know each other's internals.

---

## When to deviate

- **A throwaway admin tool, a hackathon spike, a one-page CRUD page**: anemic `@Entity` + thin `@Service` is fine. The skill exists so you can choose deliberately, not so you build six layers around `User.firstName`.
- **A read-heavy reporting service**: data classes and free functions all the way down — that's the right side of the anti-symmetry.
- **A team unfamiliar with DDD**: don't introduce Strategy A in one PR. Pick one bounded context, migrate incrementally, write a characterisation test first.

The opinion this skill encodes is: **when invariants exist, encapsulate them; when transport is happening, keep the transport dumb; when persistence is involved, keep persistence on its own side of a mapping seam.** Reach for the lighter shape when none of those forces are present.
