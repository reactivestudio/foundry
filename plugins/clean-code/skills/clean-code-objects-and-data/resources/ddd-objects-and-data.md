# DDD — Objects and Data Structures

Domain-Driven Design and Martin's "objects vs data structures" dichotomy are the same idea read from different angles. DDD names the categories more precisely (Aggregate, Entity, Value Object, Domain Event, Repository, Domain Service) and tells you *which side of the dichotomy each one lives on*. This file maps Ch. 6 onto DDD's vocabulary, with Kotlin/Spring forms.

For the tactical patterns in their own right, see `ddd-tactical-patterns`. For where DTOs sit between bounded contexts, see `ddd-context-mapping` and `api-design-principles`. This file is the **objects-vs-data view of the DDD building blocks**.

---

## DDD categories on Martin's dichotomy

| DDD category | Object or data? | Why |
|---|---|---|
| **Aggregate root** | Object (behaviour-rich) | Owns invariants. State is private; mutations go through verbs. |
| **Entity inside an aggregate** | Object | Same as the root, scoped to the aggregate's boundary. |
| **Value object** | Object (immutable, behaviour-rich) | Equality by value, but still hides representation — `Money.cents` is not the API, `money.plus(...)` is. |
| **Domain event** | Data structure | Carries facts across the publication boundary. `data class val …`. No behaviour. |
| **Command** | Data structure | Wire-shaped input to a use case. `data class val …`. |
| **DTO (request / response / payload)** | Data structure | The whole point — see `clean-code-objects-and-data` SKILL.md. |
| **Repository** | Object (behaviour-rich seam) | Tell-Don't-Ask: `save(aggregate)`, `findById(id)`. It does not expose its store. |
| **Domain service** | Object (stateless behaviour) | Behaviour that doesn't fit any single aggregate. Tells aggregates what to do; doesn't fetch state and decide externally. |
| **JPA `@Entity` row** | Data structure (persistence shape) | A mirror of a table; framework requires mutable fields and no-arg constructor. |
| **Anti-corruption layer (ACL) adapter** | Object (translation seam) | Hides upstream's structure; exposes a clean domain interface. |

The pattern is consistent: **behaviour-rich** for anything that owns invariants or makes domain decisions; **data structure** for anything whose job is to *cross a boundary*.

---

## Aggregate root — the canonical "object"

```kotlin
class Order private constructor(
    val id: OrderId,                                       // identity, public-readable
    private var status: OrderStatus,                       // state, behind a verb
    private val lines: MutableList<OrderLine>,             // child entities, owned
    private var submittedAt: Instant?,                     // derived from a transition
) {
    fun submit(now: Instant): OrderSubmitted {
        check(status == OrderStatus.DRAFT) { "Only DRAFT can be submitted" }
        require(lines.isNotEmpty()) { "Order requires at least one line" }
        status = OrderStatus.SUBMITTED
        submittedAt = now
        return OrderSubmitted(id, now)
    }

    fun cancel(reason: CancelReason, now: Instant): OrderCancelled {
        require(status in setOf(OrderStatus.DRAFT, OrderStatus.SUBMITTED)) { "Cannot cancel $status" }
        status = OrderStatus.CANCELLED
        return OrderCancelled(id, reason, now)
    }

    val summary: OrderSummary get() = OrderSummary(id, status, lines.sumOf { it.amount }, lines.size)

    companion object {
        fun place(customer: CustomerId, lines: List<OrderLine>): Order {
            require(lines.isNotEmpty()) { "Order must have at least one line" }
            return Order(OrderId.fresh(), OrderStatus.DRAFT, lines.toMutableList(), null)
        }
    }

    override fun equals(other: Any?): Boolean = other is Order && other.id == id    // identity, not value
    override fun hashCode(): Int = id.hashCode()
}
```

Notes:
- `private constructor` + named factory `place(...)` — invariants enforced at the only legal construction path.
- `private var status` — visible to readers only through `summary`, mutated only by `submit`/`cancel`/`ship`.
- Methods return **domain events**, which are data structures (see below).
- `equals`/`hashCode` by identity, not by value. The same conceptual `Order` rehydrated twice is the same order, even if a `var` flips.

This is "objects hide data, expose behaviour" written in DDD's idiom.

---

## Entity inside an aggregate

Child entities live inside the aggregate boundary and **don't escape**. They have identity inside the aggregate but no global identity; outside callers shouldn't reach them.

```kotlin
class OrderLine internal constructor(
    val id: OrderLineId,                                 // identity within the order
    val productId: ProductId,
    private var quantity: Int,
) {
    val amount get() = ...
    internal fun updateQuantity(q: Int) { require(q > 0); quantity = q }
}
```

The aggregate root exposes operations that *touch* lines (`order.addLine(...)`, `order.adjustLineQuantity(lineId, qty)`); it never lets callers do `order.lines.first().updateQuantity(5)`. The line's mutator is `internal` for that reason — it's part of the order's encapsulated machinery.

Demeter violation when this is broken: `order.lines.first().updateQuantity(5)` reaches past the aggregate boundary. The fix is `order.adjustLineQuantity(lineId, 5)`.

---

## Value object — object with value-equality

A value object is **immutable, defined by its data, and equal-by-value** — but it is **still an object**, not a data structure. It hides representation and exposes operations.

```kotlin
@JvmInline
value class Money(val cents: Long) {                       // ← single-field value object
    operator fun plus(o: Money) = Money(cents + o.cents)
    operator fun minus(o: Money) = Money(cents - o.cents)
    operator fun times(n: Int) = Money(cents * n)
    val isPositive get() = cents > 0
    companion object { val ZERO = Money(0) }
}

data class DateRange private constructor(val from: LocalDate, val to: LocalDate) {
    init { require(!to.isBefore(from)) { "to ($to) before from ($from)" } }
    operator fun contains(d: LocalDate) = d in from..to
    fun overlaps(o: DateRange) = !(to.isBefore(o.from) || o.to.isBefore(from))
    companion object { fun between(from: LocalDate, to: LocalDate) = DateRange(from, to) }
}
```

Notes:
- `value class` for single-field VOs (no allocation in most paths).
- `data class` for multi-field VOs (auto `equals` / `hashCode` by value; private constructor + factory keeps invariants).
- Operations live on the VO (`money + money`, `range.contains(date)`); callers don't reach in for `.cents` to compute their own.

Why this is still an object, not a data structure:
- The **representation is not the API**. `Money.cents` is an implementation detail; future versions can switch to `BigDecimal` or a `(amount, currency)` pair without breaking callers.
- The invariants (`require(!to.isBefore(from))`) live with the value, not in every consumer.
- The operations (`plus`, `contains`, `overlaps`) speak the domain.

This is "value objects are objects" — Martin's dichotomy doesn't put them on the data-structure side just because they happen to be immutable.

---

## Domain event — data structure crossing a publication boundary

A domain event is a **fact** about something that happened, frozen at a moment in time, broadcast to whoever cares. It is a data structure: `data class val …`, no behaviour, immutable, serialisable.

```kotlin
sealed interface OrderEvent { val orderId: OrderId; val at: Instant }
data class OrderPlaced(override val orderId: OrderId, val customerId: CustomerId, val total: Money, override val at: Instant) : OrderEvent
data class OrderSubmitted(override val orderId: OrderId, override val at: Instant) : OrderEvent
data class OrderCancelled(override val orderId: OrderId, val reason: CancelReason, override val at: Instant) : OrderEvent
```

Why a data structure:
- It crosses time — a listener may handle it asynchronously, after a retry, in a different transaction.
- It crosses modules — a Spring Modulith `@ApplicationModuleListener` is not in the same context as the publisher.
- It crosses processes — an outbox-shipped event becomes a Kafka payload with a schema.

It would be a *hybrid* if it had methods. Don't put `OrderSubmitted.apply(o: Order)` on the event — that's the listener's job, and it requires the aggregate to be loadable anyway.

A small allowance: a `sealed interface OrderEvent` with shared identity / timestamp fields is convenient. That's still a data structure; the interface is grouping, not behaviour.

---

## Command — data structure as a use-case input

Commands are DTOs shaped for one use case. Same rules as any other DTO:

```kotlin
data class SubmitOrderCommand(
    val customerId: CustomerId,
    val items: List<OrderLineCommand>,
)

data class OrderLineCommand(val productId: ProductId, val quantity: Int)
```

The command **is not** the aggregate. The use-case handler reads the command, calls a factory or repository, then invokes a domain method. It maps from the request DTO (HTTP-shaped) to the command (use-case-shaped) and from the command to whatever the domain needs.

In simple systems the request DTO and the command are the same shape — you can collapse them. In a CQRS system or a Modulith with multiple inbound channels (HTTP, Kafka, scheduled jobs), keeping them separate pays off; the command is the *internal* contract, and HTTP / Kafka each carry their own DTOs that map into it.

For full CQRS treatment, see `cqrs-implementation`.

---

## Repository — Tell-Don't-Ask seam at the aggregate root

A repository is a behaviour-rich object that *looks* like a collection but hides persistence. The Tell-Don't-Ask shape is built into the contract:

```kotlin
interface OrderRepository {
    fun save(order: Order)                       // tell
    fun findById(id: OrderId): Order?            // tell (a query, but no state leaks)
    fun findByCustomerId(id: CustomerId): List<Order>
}
```

Anti-patterns to keep out:
- **Returning maps or tuples** — callers must know column names; that's a Demeter violation in spirit.
- **Exposing the `EntityManager` or `JdbcTemplate`** — pushes persistence concerns onto callers.
- **Repository methods that contain business logic** (`findOrdersToRefund()` with non-trivial filtering) — those rules belong on the aggregate or a domain service; the repository should be a thin retrieval layer.

A repository is **per aggregate root, not per entity**. `OrderLineRepository` is wrong (the line isn't an aggregate); `OrderRepository.saveLine(...)` is wrong (lines mutate through `Order`); `OrderRepository.save(order)` is right.

---

## Domain service — object that doesn't fit on any single aggregate

When an operation involves multiple aggregates or external systems and doesn't naturally live on any one of them, it becomes a **domain service**. Domain services are stateless behaviour-rich objects:

```kotlin
class TransferFunds(private val accounts: AccountRepository) {
    fun execute(from: AccountId, to: AccountId, amount: Money) {
        val source = accounts.findById(from) ?: throw AccountNotFound(from)
        val target = accounts.findById(to)   ?: throw AccountNotFound(to)
        val withdrawn = source.withdraw(amount)             // tells
        target.deposit(amount)                              // tells
        accounts.save(source); accounts.save(target)
    }
}
```

The service **orchestrates tells**; it does not fetch state and apply business logic externally. If you find a domain service computing balances, validating limits, or making decisions that depend on aggregate state, push those decisions into the aggregates.

`@Service` in Spring is *not* automatically a domain service — Spring's annotation is just a marker. Application services (use-case orchestrators), domain services (multi-aggregate behaviour), and infrastructure services (sending emails, calling external APIs) all wear the same `@Service` annotation but live in different layers and have different rules. The objects-vs-data lens still applies to each.

---

## Anti-corruption layer — the boundary between contexts

When two bounded contexts speak different languages — different entity names, different invariants, different identifiers — the receiving context puts an **anti-corruption layer (ACL)** at the seam. The ACL takes the upstream's wire format (a DTO) and produces the downstream's domain type (an aggregate or value object).

```kotlin
// Upstream: external CRM has its own Customer shape (DTO from their HTTP API)
data class CrmCustomerDto(
    @JsonProperty("first_name") val firstName: String,
    @JsonProperty("last_name") val lastName: String,
    @JsonProperty("email_addr") val email: String,
    @JsonProperty("crm_id") val crmId: String,
)

// Downstream: our Order context has its own Customer aggregate
class Customer private constructor(val id: CustomerId, val name: PersonName, val email: Email) { ... }

// ACL: translates upstream DTO into our domain type
class CrmCustomerAcl(private val crm: CrmHttpClient) : CustomerLookup {
    override fun lookup(externalId: ExternalId): Customer? =
        crm.fetchCustomer(externalId.value)?.toCustomer()

    private fun CrmCustomerDto.toCustomer(): Customer =
        Customer.from(
            id    = CustomerId.fresh(),
            name  = PersonName.of(firstName, lastName),
            email = Email.of(email),
        )
}
```

The pattern:
- Upstream DTO is a data structure (`data class val`) — it's a wire format we don't own.
- Downstream aggregate is an object — invariants live inside, our context's vocabulary.
- ACL is itself an object — `CustomerLookup` interface inside our domain, `CrmCustomerAcl` implementation that knows about the external system.

The ACL is **where Demeter is most relevant**: callers in our context should never reach `crmAcl.crm.fetchCustomer(...).firstName`. They call `crmAcl.lookup(externalId)` and get our domain type back.

See `ddd-context-mapping` for the full set of context-mapping patterns and how to choose between ACL, Conformist, Customer-Supplier, etc.

---

## Identity vs equality

A recurring confusion at the objects-vs-data boundary:

| Kind | Equality semantics | Why |
|---|---|---|
| Aggregate root | by identity (`id`) | The "same conceptual order" is the same order across time and persistence |
| Child entity | by identity within the aggregate | Same as root, narrower scope |
| Value object | by value (all fields) | Two `Money(500)` are the same money; identity is meaningless |
| DTO | by value (all fields) | They're shapes, not things; auto-`equals` from `data class` is right |
| Domain event | by value (all fields) | Same fact, regardless of where it was constructed |

When this gets crossed (aggregate with value-equality, value object with identity), the bugs are subtle and persistent — JPA proxy comparisons fail intermittently, Sets contain "duplicate" orders, equality after `copy(...)` is surprising. Pick the right one explicitly:

```kotlin
class Order(...) {
    override fun equals(other: Any?) = other is Order && other.id == id
    override fun hashCode() = id.hashCode()
}

data class Money(...)              // value-equality automatic
data class SubmitOrderRequest(...) // value-equality automatic; that's fine for a DTO
```

---

## Quick mapping — when you read DDD, you read Ch. 6

| When the DDD book says... | Read it as... |
|---|---|
| "Aggregate" | Object — encapsulated state + behaviour |
| "Entity" | Object — identity + behaviour, inside an aggregate or as an aggregate root |
| "Value object" | Object — immutable, value-equality, but the API is operations not fields |
| "Domain service" | Object — stateless behaviour that orchestrates aggregates |
| "Repository" | Object — Tell-Don't-Ask seam for persistence |
| "Domain event" | Data structure — fact crossing time/process |
| "DTO" | Data structure — bag of fields crossing a boundary |
| "Anti-corruption layer" | Object whose job is to translate from a data structure (upstream DTO) to an object (downstream aggregate) |
| "Anemic domain model" | The standard Spring hybrid: data structures pretending to be aggregates |

If the DDD reading list and Clean Code Ch. 6 ever seem to disagree, they don't — they're naming the same dichotomy at two levels of abstraction.

---

## Related skills (one-line each)

- `ddd-tactical-patterns` — full treatment of aggregate / VO / repository **patterns**; this file is the objects-vs-data **lens** on those patterns.
- `ddd-context-mapping` — relationships *between* contexts; ACL details and the DTO-at-the-seam discipline.
- `cqrs-implementation` — command vs. query side at architectural scale; commands as DTOs, projections as DTOs, aggregates on the write side.
- `api-design-principles` — DTO shapes at the *external* API boundary, REST/gRPC.
- `architect-review` — auditing a module for anemic domains and hybrid classes.
