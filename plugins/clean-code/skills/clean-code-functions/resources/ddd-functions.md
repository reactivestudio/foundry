# DDD Function Patterns

Clean Code Ch. 3 function rules applied to Domain-Driven Design code. The DDD layer is where Martin's rules pay off most — domain logic is what readers come back to read, where bugs cost the most, and where unclear functions corrupt the ubiquitous language with every commit.

> "Functions are the verbs of the language we design while writing a system." — Martin
>
> In DDD, those verbs are the ubiquitous language. `order.submit()` is not just a function — it's the word the business uses for the thing it does. Get the function shape wrong and the language drifts.

## Quick map — Martin rule applied at DDD layer

| Rule | DDD shape |
|---|---|
| §"Do one thing" | An aggregate method does one **domain transition** and emits the events that prove it. |
| §"Few arguments" | A command's parameters become a value-object — `SubmitOrder` carries everything needed; the method takes one. |
| §"Flag arguments" | Replaced by sealed command subtypes or distinct domain verbs. |
| §"Side effects" | Aggregates accumulate domain events; persistence happens at the repository, never as a side effect of a domain method. |
| §"Switch on type" | Sealed hierarchy with polymorphic behaviour on aggregate / VO / strategy. |
| §"CQS" | Aggregate **commands** mutate state and emit events; aggregate **queries** are pure derivations on its data. |
| §"Exceptions over codes" | Invariant violations throw `DomainError` subtypes. |
| §"Stepdown rule" | Application service → aggregate root method → entity / VO method → primitive. |

---

## 1. Aggregate behaviour methods — small verbs, one domain transition

An aggregate method is the place the ubiquitous language meets code. Each is **one verb** from the domain, **one state transition**, **one emit of the relevant event**.

```kotlin
class Order private constructor(
    val id: OrderId,
    val customerId: CustomerId,
    private val lines: MutableList<OrderLine>,
    private var status: OrderStatus,
) {
    private val events = mutableListOf<DomainEvent>()
    fun events(): List<DomainEvent> = events.toList()

    // ✓ One verb, one transition, one event
    fun submit(at: Instant) {
        check(status == OrderStatus.DRAFT) { "Order $id is not a draft" }
        check(lines.isNotEmpty()) { "Order $id has no lines" }
        status = OrderStatus.SUBMITTED
        events += OrderSubmitted(id, customerId, totalAmount(), at)
    }

    fun cancel(reason: CancellationReason, at: Instant) {
        check(status in cancellableStates) { "Order $id cannot be cancelled in $status" }
        status = OrderStatus.CANCELLED
        events += OrderCancelled(id, reason, at)
    }

    fun addLine(productId: ProductId, quantity: Quantity, price: Money) {
        check(status == OrderStatus.DRAFT) { "Cannot modify $status order" }
        require(lines.none { it.productId == productId }) { "Duplicate line for $productId" }
        lines += OrderLine(productId, quantity, price)
    }

    // ✓ Query — pure derivation, no mutation
    fun totalAmount(): Money = lines.fold(Money.zero) { acc, line -> acc + line.subtotal() }

    companion object {
        private val cancellableStates = setOf(OrderStatus.DRAFT, OrderStatus.SUBMITTED)

        fun create(customerId: CustomerId, idGen: IdGenerator): Order =
            Order(idGen.next(), customerId, mutableListOf(), OrderStatus.DRAFT)
    }
}
```

**Why this shape**:
- **Small** — each method does one transition.
- **One thing** — the precondition check + state change + event are *the* one thing. The event is the proof that the transition happened.
- **No flag arguments** — `cancel(reason)` doesn't take a `boolean force`. If "force cancel" exists, it's `cancelByAdmin(reason)` — a different verb.
- **No side effects beyond events** — the aggregate doesn't write to a database, send an email, or call another aggregate. Those follow from the event, asynchronously, in handlers.

**Anti-patterns**:
| Anti-pattern | Why bad |
|---|---|
| `order.save()` method on the aggregate | Aggregate doesn't know about persistence. Repo's job. |
| `order.submit(notifyCustomer: Boolean)` | Flag argument. Two domain concepts in one method. |
| `order.submit()` returns the `OrderSubmitted` event for the caller to publish | Couples application service to event publishing details. Accumulate, drain at the repository boundary. |
| `order.submit()` validates *and* persists *and* emails | Three things. Persists belongs in the repo; emails belong in a listener of `OrderSubmitted`. |
| Public setters | Bypass invariants. Mutate only through verbs. |

---

## 2. Aggregate construction — factories, not constructors

The primary constructor of an aggregate is `private`. Construction is through a named factory function that:
- Enforces invariants (`require(...)`).
- Issues domain ids.
- Emits the "creation" event.

```kotlin
class Order private constructor(...) {
    companion object {
        fun create(
            customerId: CustomerId,
            initialLines: List<DraftLine>,
            ids: IdGenerator,
            now: Clock,
        ): Order {
            require(initialLines.isNotEmpty()) { "Order needs at least one line" }
            val order = Order(
                id = ids.next(),
                customerId = customerId,
                lines = initialLines.map { it.toLine() }.toMutableList(),
                status = OrderStatus.DRAFT,
            )
            order.events += OrderCreated(order.id, customerId, now.instant())
            return order
        }
    }
}
```

**Why a factory**:
- The constructor can't emit events (no `this.events` until super-call completes; awkward).
- Multiple creation paths (`create`, `restoreFromHistory`, `clone`) have **different invariants** and **different events** — separate named factories make the intent obvious.
- A factory takes **value objects**, not primitive args — sidesteps the polyad problem.

---

## 3. Factory pattern replaces switch on type — one `when` per hierarchy

Sub-Martin's "switch in a factory" pattern lands precisely on DDD's polymorphic-aggregate / polymorphic-policy case:

```kotlin
// Different shapes of payment behave differently — sealed hierarchy
sealed class PaymentMethod {
    abstract fun charge(amount: Money): Charge
    abstract fun refund(charge: Charge): Refund
}

class CreditCard(...) : PaymentMethod() {
    override fun charge(amount: Money): Charge = ...
    override fun refund(charge: Charge): Refund = ...
}
class BankTransfer(...) : PaymentMethod() { ... }
class StoreCredit(...) : PaymentMethod() { ... }

// Single factory — the only when over PaymentMethod subtypes
@Component
class PaymentMethodFactory {
    fun fromRequest(req: PaymentMethodRequest): PaymentMethod = when (req) {
        is PaymentMethodRequest.Card     -> CreditCard(req.number, req.cvv, req.expiry)
        is PaymentMethodRequest.Transfer -> BankTransfer(req.iban)
        is PaymentMethodRequest.Credit   -> StoreCredit(req.accountId)
    }
}

sealed interface PaymentMethodRequest {
    data class Card(val number: PAN, val cvv: CVV, val expiry: ExpiryDate) : PaymentMethodRequest
    data class Transfer(val iban: IBAN)                                    : PaymentMethodRequest
    data class Credit(val accountId: CreditAccountId)                      : PaymentMethodRequest
}
```

Adding `class ApplePay : PaymentMethod()`:
1. New subclass.
2. New `PaymentMethodRequest.Apple` variant.
3. Add one `when` branch in the factory.
4. Every `when (m: PaymentMethod)` elsewhere becomes a compile error until handled — exhaustiveness as your OCP enforcer.

---

## 4. Domain events — small, immutable, named for the past tense

Events are value objects. Each is a **small** data class — name, when, what's needed by handlers.

```kotlin
sealed interface DomainEvent {
    val occurredAt: Instant
}

data class OrderSubmitted(
    val orderId: OrderId,
    val customerId: CustomerId,
    val total: Money,
    override val occurredAt: Instant,
) : DomainEvent

data class OrderCancelled(
    val orderId: OrderId,
    val reason: CancellationReason,
    override val occurredAt: Instant,
) : DomainEvent
```

**Rules at function level**:
- Events are **named in past tense** (`OrderSubmitted`, not `SubmitOrder`).
- The event carries only what handlers need. **Don't dump the whole aggregate state**.
- A function emits an event; it does not publish it. **Aggregate appends to `events`; repository drains and forwards on save.** Keeps the aggregate free of `ApplicationEventPublisher`.

```kotlin
// At the persistence boundary — drain & publish
@Repository
class JpaOrderRepository(
    private val em: EntityManager,
    private val publisher: ApplicationEventPublisher,
) : OrderRepository {

    override fun save(order: Order): Order {
        em.persist(order.toEntity())                          // persist
        order.events().forEach(publisher::publishEvent)       // forward
        order.clearEvents()
        return order
    }
}
```

**Anti-pattern**:
```kotlin
// ✗ Aggregate method directly publishes — couples domain to Spring infra
class Order(private val publisher: ApplicationEventPublisher) {
    fun submit() {
        ...
        publisher.publishEvent(OrderSubmitted(...))   // ← domain knows about Spring
    }
}
```

---

## 5. Specifications — composable query-only functions

A `Specification` is a function shaped as a predicate, named for the domain question it asks. No side effects, no mutation — pure CQS query.

```kotlin
// One specification = one named domain question
fun interface OrderSpecification {
    fun isSatisfiedBy(order: Order): Boolean
}

class IsHighValue(private val threshold: Money) : OrderSpecification {
    override fun isSatisfiedBy(order: Order) = order.total >= threshold
}

class IsForRegion(private val region: Region) : OrderSpecification {
    override fun isSatisfiedBy(order: Order) = order.shippingAddress.region == region
}

// Composition — and / or / not as small infix functions
infix fun OrderSpecification.and(other: OrderSpecification) =
    OrderSpecification { isSatisfiedBy(it) && other.isSatisfiedBy(it) }

infix fun OrderSpecification.or(other: OrderSpecification) =
    OrderSpecification { isSatisfiedBy(it) || other.isSatisfiedBy(it) }

fun not(spec: OrderSpecification) =
    OrderSpecification { !spec.isSatisfiedBy(it) }

// Usage reads like the business question
val priorityShipping = IsHighValue(Money(1000)) and IsForRegion(Region.EU)
val isPriority = priorityShipping.isSatisfiedBy(order)
```

**Function-level rules**:
- Each spec is **one tiny function**. Compose for complex questions instead of writing a 20-line predicate.
- Naming is **the domain question**, not "checker" / "validator" mush. `IsHighValue`, not `HighValueChecker`.
- Spec is a **query** (`isSatisfiedBy`) — no mutation.

---

## 6. Repository contract — one verb per query, no flag args, returns aggregates or `null`

Repository interfaces live at the domain layer; implementations at the infrastructure layer. Each method is one named verb.

```kotlin
interface OrderRepository {
    fun save(order: Order): Order
    fun findById(id: OrderId): Order?
    fun findActiveForCustomer(customerId: CustomerId): List<Order>
    fun existsForCustomerAndProduct(customerId: CustomerId, productId: ProductId): Boolean
}
```

**Rules**:
- **One aggregate type per repository**. `OrderRepository` returns `Order` or its absence. Not `OrderLine`, not `Customer`.
- **No flag args**. `findOrders(active: Boolean)` becomes `findActive` and `findAll`.
- **Return `Order?` for "may not exist"**; throw at the *use-case* layer with a `NotFound` domain exception.
- **Return immutable views or aggregates**; never expose persistence types (Hibernate entities) outside the repo.

```kotlin
// Helper extension on the interface for the throw-on-missing pattern
fun OrderRepository.findByIdOrThrow(id: OrderId): Order =
    findById(id) ?: throw NotFound("Order", id)
```

---

## 7. Domain service vs aggregate method — which gets the verb?

Some verbs don't belong on one aggregate. A domain service is the home for those — *one operation, named for a domain concept that spans two aggregates*.

```kotlin
// "Transfer" doesn't belong on Account — it's between two accounts.
class MoneyTransferService(private val accounts: AccountRepository) {

    fun transfer(from: AccountId, to: AccountId, amount: Money) {
        val source = accounts.findByIdOrThrow(from)
        val target = accounts.findByIdOrThrow(to)

        source.withdraw(amount)
        target.deposit(amount)

        accounts.save(source)
        accounts.save(target)
    }
}
```

**Decision rule**:
- The verb belongs **on the aggregate** if it operates only on that aggregate's data and invariants.
- The verb belongs **on a domain service** if it coordinates two aggregates or needs a domain dependency the aggregate shouldn't have (rates, policies, calendars).
- A domain service is **stateless** — one operation, no instance variables beyond injected dependencies.

**Anti-patterns**:
| Anti-pattern | Fix |
|---|---|
| `OrderService.submitOrder(order)` — orchestrator with a do-everything name | Aggregate method `order.submit()`; the service is the application service, not domain. |
| Domain service with 7 methods | The first method is real; the rest probably belong to specific aggregates. Re-shore. |
| Anaemic aggregate + thick `*Service` | Move behaviour back onto the aggregate. The service should be thin coordinator only. |

**Cross-link**: `ddd-tactical-patterns` for the deep dive on aggregate / VO / repo structure.

---

## 8. Value objects — small functions that compute, no mutation

Value objects (`Money`, `Email`, `Address`) are pure values. Their methods are pure functions.

```kotlin
@JvmInline value class Money(val amount: BigDecimal) : Comparable<Money> {
    init { require(amount.signum() >= 0) { "Money is non-negative" } }

    operator fun plus(other: Money) = Money(amount + other.amount)
    operator fun minus(other: Money): Money {
        val result = amount - other.amount
        require(result.signum() >= 0) { "Money cannot be negative" }
        return Money(result)
    }
    operator fun times(factor: BigDecimal) = Money(amount * factor)
    override fun compareTo(other: Money) = amount.compareTo(other.amount)

    companion object {
        val zero = Money(BigDecimal.ZERO)
    }
}
```

**Function-level rules**:
- Every method is a **query**, never a command. No setters. Operations return a new value.
- Invariants live in `init` blocks — once the value object exists, it's always valid.
- Operators where they read naturally (`a + b`); named methods when they don't.

---

## 9. Policies and strategies — small functions per domain rule

A "policy" is a function that decides something — pricing, eligibility, scheduling. Each policy is one small function (or one-method interface) named for the decision.

```kotlin
fun interface PricingPolicy {
    fun priceFor(order: Order): Money
}

@Component
class TieredPricingPolicy(private val tiers: List<Tier>) : PricingPolicy {
    override fun priceFor(order: Order): Money {
        val total = order.subtotal()
        val tier = tiers.firstOrNull { total in it.range } ?: tiers.last()
        return total * tier.multiplier
    }
}

@Component
class FlatPricingPolicy : PricingPolicy {
    override fun priceFor(order: Order): Money = order.subtotal()
}
```

**Rules**:
- **One interface method per policy**. If a policy needs two methods, it's two policies.
- **No flag arguments**. Variants are distinct implementations injected by Spring profile / qualifier.
- **Naming = the decision**, not "evaluator" or "calculator". `TieredPricingPolicy`, not `PriceCalculator`.

---

## 10. Anti-Corruption Layer (ACL) — translation functions, pure, no domain leakage

When integrating with an external system (vendor API, legacy DB), the ACL translates between *their* model and *yours*. Translation functions are **pure** — they take their model, return yours (or vice versa), and have no side effects.

```kotlin
// External vendor's model — not allowed to leak into our domain
class VendorAccount(val accountNumber: String, val tier: Int, val balanceUSD: Long) { ... }

// Our domain — clean
class Account(val id: AccountId, val tier: AccountTier, val balance: Money) { ... }

// Translation lives in the ACL adapter — small, named, pure
@Component
class VendorAccountTranslator {

    fun toDomain(vendor: VendorAccount): Account = Account(
        id = AccountId(UUID.nameUUIDFromBytes(vendor.accountNumber.toByteArray())),
        tier = vendor.tier.toAccountTier(),
        balance = Money(BigDecimal.valueOf(vendor.balanceUSD).movePointLeft(2)),
    )

    fun toVendor(account: Account): VendorAccountUpdateRequest = VendorAccountUpdateRequest(
        accountNumber = account.id.value.toString(),
        balanceCents = account.balance.amount.movePointRight(2).toLong(),
    )

    private fun Int.toAccountTier(): AccountTier = when (this) {
        1 -> AccountTier.BASIC
        2 -> AccountTier.PREMIUM
        3 -> AccountTier.PLATINUM
        else -> error("Unknown vendor tier $this")
    }
}
```

**Rules**:
- **Each direction is one function** (`toDomain`, `toVendor`). Don't bundle.
- **Translation functions are pure** — input → output, no IO.
- **The `when` over vendor codes is OK** — it's enumerating *their* closed set, not branching on our type.
- **Errors throw** (`error("Unknown vendor tier $this")`) rather than returning `null`/`Result` — unknown vendor data is a programming error in the ACL, not a domain error.

**Cross-link**: `ddd-context-mapping` for ACL as a context-mapping pattern.

---

## 11. Sagas / process managers — each step is a small function with one event in, zero or one out

A saga coordinates a long-running domain process across aggregates. Each step is one function reacting to one event.

```kotlin
@Component
class OrderShippingSaga(
    private val shippingClient: ShippingClient,
    private val publisher: ApplicationEventPublisher,
) {

    @ApplicationModuleListener
    fun onOrderPaid(event: OrderPaid) {
        val shipment = shippingClient.requestShipment(event.orderId, event.address)
        publisher.publishEvent(ShipmentRequested(event.orderId, shipment.trackingId))
    }

    @ApplicationModuleListener
    fun onShipmentDispatched(event: ShipmentDispatched) {
        publisher.publishEvent(OrderShipped(event.orderId, event.dispatchedAt))
    }

    @ApplicationModuleListener
    fun onShipmentFailed(event: ShipmentFailed) {
        publisher.publishEvent(OrderShippingFailed(event.orderId, event.reason))
    }
}
```

**Rules**:
- **One listener per event type**. Don't share a body with a `when (event)`.
- **Each step does one thing**: invoke an external action, emit the resulting domain event.
- **No try/catch** — let retries / dead-letters be handled by Modulith / messaging infrastructure.

**Cross-link**: `cqrs-implementation` and `messaging-rabbitmq-spring` for the projection / saga reliability story.

---

## 12. Worked example — `Order.submit()` end-to-end function sizes

A clean DDD flow, every function ≤ 10 lines:

```kotlin
// Application service (Spring layer) — orchestrates the use case
@Service
class OrderApplicationService(
    private val orders: OrderRepository,
    private val products: ProductRepository,
    private val clock: Clock,
) {
    @Transactional
    fun submit(command: SubmitOrder): OrderId {
        val order = orders.findByIdOrThrow(command.orderId)
        order.submit(clock.instant())
        orders.save(order)              // repo drains events here
        return order.id
    }
}

// Aggregate root — the verb
class Order(...) {
    fun submit(at: Instant) {
        check(status == OrderStatus.DRAFT) { "Order $id is not a draft" }
        check(lines.isNotEmpty())        { "Order $id has no lines" }
        status = OrderStatus.SUBMITTED
        events += OrderSubmitted(id, customerId, totalAmount(), at)
    }

    fun totalAmount(): Money = lines.fold(Money.zero) { acc, line -> acc + line.subtotal() }
}

// Value object — pure operations
class OrderLine(...) {
    fun subtotal(): Money = price * quantity.value.toBigDecimal()
}

// Listener — one event, one side effect, separate module
@Component
class OrderReceiptNotifier(private val mailer: Mailer) {
    @ApplicationModuleListener
    fun on(event: OrderSubmitted) {
        mailer.sendReceipt(event.customerId, event.orderId)
    }
}
```

Each function:
- Reads top-down (application service → aggregate → value object).
- Does one thing.
- Has zero or one argument (event, command).
- Has no flag arguments, no output arguments, no error codes.

That's the destination Martin's Ch. 3 is pointing at, with DDD's structural support.

---

## 13. Anti-patterns specific to DDD function shape

| Anti-pattern | Why bad | Fix |
|---|---|---|
| `*Service` doing all the work; aggregate has only getters | Anaemic domain — function-level smell rolling up to architectural. | Move verbs onto the aggregate. Service becomes thin orchestrator. |
| Repository returning DTOs, not aggregates | Couples domain to presentation. | Repo returns aggregate or `null`. Mapping to DTO is at the application/HTTP layer. |
| Aggregate method takes `Clock` / `Now` as a parameter on every call | Time leaks into every signature. | Pass `Instant` once at the boundary (`order.submit(now)`). Use a `Clock` in the service. |
| Domain method publishing events directly | Couples to Spring. | Accumulate; repo drains. |
| Specifications with side effects | Predicate that mutates is not a predicate. | Make pure. Mutation belongs to a command. |
| Translator (`*Mapper`) doing IO | ACL functions must be pure. | Lift IO out; mapper takes data, returns data. |
| Cross-aggregate mutation from one aggregate method | Breaks the consistency boundary (one aggregate, one transaction). | Application service coordinates two saves, or use an event-driven projection. |
| `when (event)` in one listener handling 4 event types | Same anti-pattern as a `switch` on type. | Four listeners, one per event. |

---

## 14. Checklist before merging a domain function

1. **One verb from the ubiquitous language.** If you can't say the method name as the business says it, rename.
2. **Aggregate method ≤ 10 lines.** Precondition + state change + event = three short blocks.
3. **No persistence call inside the aggregate.** Repository's job.
4. **No `ApplicationEventPublisher` inside the aggregate.** Events accumulate; repo drains.
5. **No flag arguments.** Two verbs or a sealed mode.
6. **No `Boolean` return on a mutating method.** That's "did it work?" — throw on failure.
7. **Value object operations are pure.** No mutation, no IO.
8. **Domain service is stateless** and has one operation, named for a domain concept that spans two aggregates.
9. **Specifications are pure predicates** and named for the domain question.
10. **ACL translation functions are pure** — vendor IO lives at the adapter, not in the translator.
