# DDD class rules

When the domain is rich enough to justify Domain-Driven Design, the rules from Ch. 10 of *Clean Code* sharpen into concrete tactical shapes: **aggregate roots**, **value objects**, **repositories**, **domain services**, **factories**, **anti-corruption translators**. This file is the bridge between Martin's general class-design discipline and the DDD tactical vocabulary. For the deeper DDD patterns, defer to `ddd-tactical-patterns` and `ddd-strategic-design`; this file is specifically about *how the class-design rules apply when you're building those patterns*.

## 1. Aggregate root as a cohesive small class

An aggregate root is the entry point for an invariant boundary. It is the canonical "small class with one responsibility" in a domain layer:

- **One reason to change** — the invariants this aggregate guards.
- **One transaction boundary** — saving and loading the aggregate is one DB transaction.
- **Methods that mutate state are commands**; methods that answer questions are queries (CQS at class scope, see `clean-code-functions`).
- **State is private**; access is via behavioural methods (`order.submit()`), never via setters (`order.setStatus(SUBMITTED)`).
- **Factory methods on the companion** replace constructor overload explosions.

```kotlin
class Order private constructor(
    val id: OrderId,
    private val lines: MutableList<OrderLine>,
    private var status: OrderStatus,
    private var submittedAt: Instant?,
) {

    // Behavioural API — verbs from the ubiquitous language
    fun submit(now: Instant) {
        require(status == DRAFT) { "Order $id already submitted" }
        require(lines.isNotEmpty()) { "Order $id has no lines" }
        status = SUBMITTED
        submittedAt = now
    }

    fun cancel(reason: CancelReason) {
        require(status == SUBMITTED) { "Only submitted orders can be cancelled (was $status)" }
        status = CANCELLED
    }

    // Queries — read-only, no state change
    fun isSubmitted(): Boolean = status == SUBMITTED
    fun lines(): List<OrderLine> = lines.toList()  // defensive copy

    // Factory on companion — clean replacement for constructor overloads
    companion object {
        fun draft(id: OrderId, lines: List<OrderLine>): Order {
            require(lines.isNotEmpty()) { "Cannot draft an order with no lines" }
            return Order(id, lines.toMutableList(), OrderStatus.DRAFT, submittedAt = null)
        }

        // for repository rehydration — module-internal
        internal fun rehydrate(
            id: OrderId,
            lines: List<OrderLine>,
            status: OrderStatus,
            submittedAt: Instant?,
        ): Order = Order(id, lines.toMutableList(), status, submittedAt)
    }
}
```

**25-word test:** *"Represents a customer order with its lifecycle and invariants — drafting, submitting, cancelling."* No `and` between unrelated responsibilities. The `and` between *drafting, submitting, cancelling* is the *same* responsibility (the order lifecycle), not multiple.

### When aggregate methods grow past the single-responsibility limit

If `Order` accumulates methods like `recomputeShippingEstimate()`, `applyDiscountCampaign()`, `auditChange()`, the class is taking on responsibilities that **don't belong to its invariant boundary**. Those concerns belong on:

- **Domain services** when the logic spans aggregates (`ShippingEstimator.estimate(order, address)`).
- **Application services / use cases** when the logic orchestrates aggregates and external systems.
- **Domain events + listeners** when the logic is a reaction to a change (`OrderSubmitted` → audit listener).

The aggregate stays focused on **its** invariants; everything else is somewhere else.

## 2. Value object — the smallest single-responsibility class

A value object holds an invariant for a domain primitive:

```kotlin
@JvmInline
value class Email private constructor(val value: String) {
    companion object {
        private val PATTERN = Regex("[^@\\s]+@[^@\\s]+\\.[^@\\s]+")
        fun of(raw: String): Email {
            require(raw.matches(PATTERN)) { "Invalid email: $raw" }
            return Email(raw.lowercase())
        }
    }
}

@JvmInline value class OrderId(val value: UUID)

data class Money(val amount: BigDecimal, val currency: Currency) {
    init {
        require(amount.scale() <= currency.defaultFractionDigits) {
            "Money amount $amount has too many decimal places for $currency"
        }
    }
    operator fun plus(other: Money): Money {
        require(currency == other.currency) { "Cannot add $currency to ${other.currency}" }
        return Money(amount + other.amount, currency)
    }
}
```

- **One responsibility**: hold a validated domain primitive (or a small tuple of them).
- **Cohesion is maximal** — every method touches every field.
- **Immutable** by definition.
- **Equality by value** (free with `data class` / `value class`).
- **No persistence concerns** — value objects are not entities; they have no identity.

A class that wraps three fields representing a single concept (`Address` = street + city + zip; `Period` = start + end) is a value object, not an entity. Apply class-design rules with one extra check: **the value object has no lifecycle**. If you find yourself adding a method like `markRevoked()` on `Email`, it's not a value object — it's an entity in disguise.

## 3. Repository — DIP at the aggregate boundary

A repository is **the** standard DIP application in DDD:

```kotlin
// Port — lives in the domain, no framework imports
interface Orders {
    fun findById(id: OrderId): Order?
    fun save(order: Order)
    // optionally: findByCustomer(id: CustomerId): List<Order>
}

// Adapter — infrastructure layer, depends on Spring Data / JPA
@Repository
class JpaOrders(private val jpa: OrderJpaRepository) : Orders {
    override fun findById(id: OrderId): Order? =
        jpa.findById(id.value).orElse(null)?.toDomain()

    override fun save(order: Order) {
        jpa.save(order.toRow())
    }
}
```

**Rules from Ch. 10 applied:**

1. **One repository per aggregate root**, not one per entity. `OrderLineRepository` is almost always wrong — `OrderLine` is reached through `Order`. (SRP: a repository's one responsibility is to persist *one* aggregate type.)
2. **The port lives in the domain layer**, the adapter in infrastructure. Dependency direction is **domain ← infrastructure** (DIP).
3. **The port's vocabulary is the ubiquitous language.** `findById`, `save`, `cancel` — not `selectOrderByPk`, `mergeOrderRow`. The interface speaks the domain, not the DB.
4. **Small surface area.** A repository with 30 query methods is almost always either: (a) leaking query-shape responsibilities that belong in a read model (CQRS — see `cqrs-implementation`), or (b) collecting unrelated queries that should be split between several repositories.

## 4. Domain service — when behaviour belongs to no single aggregate

Some behaviour requires several aggregates and doesn't naturally belong on any one of them:

```kotlin
class TransferFunds(
    private val accounts: Accounts,
    private val clock: Clock,
) {
    fun execute(from: AccountId, to: AccountId, amount: Money) {
        val source = accounts.findById(from) ?: throw AccountNotFound(from)
        val target = accounts.findById(to) ?: throw AccountNotFound(to)
        source.withdraw(amount, clock.now())
        target.deposit(amount, clock.now())
        accounts.save(source)
        accounts.save(target)
    }
}
```

**Class-design rules:**

- **SRP:** the domain service does **one operation**. `TransferFunds.execute()` is not `AccountService.transferAndAuditAndNotify()`.
- **The class name is a verb**, not a noun, when the service is a single use case (`TransferFunds`, `SubmitOrder`, `CalculateShipping`). This signals that the class **does** something rather than **is** something.
- **No state.** Domain services are stateless — they receive aggregates via repositories, operate on them, and persist via repositories.
- **DIP:** constructor-injected ports (the `Accounts` repository, the `Clock`).

### Don't reach for domain services as the default

Most behaviour belongs **on the aggregate**, not on a service. Reach for a domain service only when:

- The operation legitimately spans aggregates (the transfer above).
- The operation depends on infrastructure (a `Clock`, a `PaymentGateway`) that an aggregate shouldn't know about.
- The operation is shared logic between several use cases.

A domain service that does a single-aggregate operation (`AccountService.withdraw(account, amount)`) is the **anaemic-domain anti-pattern** — push the behaviour back onto the aggregate.

## 5. Factory — the constructor-overload escape hatch

When constructing an aggregate has multiple legitimate variants, factory methods on the companion (or a dedicated factory class) replace constructor overloads:

```kotlin
class Subscription private constructor(
    val id: SubscriptionId,
    private var plan: Plan,
    private var status: SubscriptionStatus,
    private var renewsAt: Instant?,
) {
    companion object {
        fun start(plan: Plan, now: Instant): Subscription =
            Subscription(SubscriptionId.next(), plan, ACTIVE, plan.nextRenewal(now))

        fun trial(plan: Plan, trialEnd: Instant): Subscription =
            Subscription(SubscriptionId.next(), plan, TRIAL, trialEnd)

        fun reactivate(previous: Subscription, now: Instant): Subscription =
            Subscription(SubscriptionId.next(), previous.plan, ACTIVE, previous.plan.nextRenewal(now))

        internal fun rehydrate(...): Subscription = ...  // repository use only
    }
}
```

- Each factory has a **descriptive name** signalling intent (`start`, `trial`, `reactivate`).
- The aggregate's primary constructor stays **private**.
- The aggregate cannot be instantiated in an invalid state — every entry path enforces the invariants.

When factory logic is itself complex (consulting policies, computing initial state from external data), promote the factory to **its own class**:

```kotlin
class SubscriptionFactory(
    private val pricing: PricingPolicy,
    private val clock: Clock,
) {
    fun start(customer: Customer, planChoice: PlanChoice): Subscription {
        val plan = pricing.resolve(customer, planChoice)
        return Subscription.start(plan, clock.now())
    }
}
```

Class-design rule: a factory class still has **one responsibility** — building one aggregate type. Avoid `EverythingFactory.makeFoo() / makeBar() / makeBaz()`.

## 6. ACL translator — OCP at the bounded-context boundary

When two bounded contexts integrate (your `orders` context consuming a vendor's `inventory` API), the **anti-corruption layer (ACL)** translates between the vendor's vocabulary and yours:

```kotlin
// Vendor SDK shape leaks "ItemPayload" / "QtyOnHand" — don't let it into the domain
class InventoryTranslator(
    private val vendor: VendorInventoryClient,
) : InventoryAvailability {  // port owned by your domain

    override fun available(sku: Sku): Quantity {
        val payload = vendor.fetchItem(sku.value)
        return Quantity.of(payload.qtyOnHand)
    }
}
```

**Class-design rules:**

- The translator is **one class** with **one responsibility**: turn the vendor shape into the domain shape (and vice versa).
- The **port** (`InventoryAvailability`) lives in your domain; the translator is the **adapter**.
- When the vendor adds a new endpoint, the translator changes — **the domain doesn't**.

This is OCP and DIP together: new vendor variants = new translator classes; the domain stays closed for modification.

See `ddd-context-mapping` for the full set of integration patterns and `clean-code-boundaries` for the broader Wrap-Don't-Pass discipline.

## 7. The DDD-shaped 25-word test

Apply the 25-word test in DDD terms:

| Pattern | Acceptable sentence shape | Failing shape |
|---|---|---|
| Aggregate | *"Represents a customer Order with its lifecycle invariants — draft, submit, cancel."* | *"Holds the order data **and** sends emails **and** writes audit logs."* |
| Value object | *"A validated email address."* | *"An email address **and** the customer's preferences."* |
| Repository | *"Persists and retrieves Order aggregates."* | *"Persists Orders **and** runs reports **and** caches lookups."* |
| Domain service | *"Transfers funds between two accounts."* | *"Transfers funds **and** notifies the customer **and** updates statistics."* |
| Factory | *"Constructs a Subscription from a customer and a plan choice."* | *"Constructs Subscriptions **and** Orders **and** Invoices."* |
| ACL translator | *"Translates vendor inventory payloads into the domain Inventory port."* | *"Calls the vendor **and** maps **and** retries **and** logs."* |

A failing shape isn't necessarily wrong code — it might be a *use case* that legitimately coordinates several steps. But if the *class* claims the responsibility for all of them, it's a god in DDD costume. Push each step onto the right shape.

## 8. Cohesion within an aggregate — the partial-field test

For aggregates with many fields (15+), the cohesion test is more nuanced. Most fields cluster around the same invariant; some are present *only* for a subset of operations.

```kotlin
class Order(
    val id: OrderId,
    private val lines: List<OrderLine>,
    private var status: OrderStatus,
    // ↓ used only by submit / pricing
    private val pricing: PricingSnapshot,
    // ↓ used only by ship / track
    private var trackingNumber: TrackingNumber?,
    private var shippedAt: Instant?,
    // ↓ used only by refund
    private var refundedAt: Instant?,
    private var refundReason: RefundReason?,
)
```

When the field clusters split cleanly along lifecycle phases, consider:

- **State pattern (sealed hierarchy)** — `sealed class OrderState { class Draft; class Submitted(...); class Shipped(...); class Refunded(...) }`. Each state carries the fields it needs; transitions return a new state.
- **Sub-aggregates** — a `Shipment` value object inside `Order` holding tracking number and shipped timestamp; a `Refund` value object holding refund details.

This is OCP + cohesion together: adding a new state (e.g., `PartiallyShipped`) is a new subclass; the aggregate stays cohesive within each state.

See `gof-patterns` for the State pattern and `ddd-tactical-patterns` for the aggregate-internal value-object pattern.

## 9. Ubiquitous language as the naming filter

Every class in the domain layer must read in the ubiquitous language. Apply the test from `clean-code-naming`:

- ✓ `Order`, `submit`, `cancel`, `Shipment`, `RefundReason`
- ✗ `OrderEntity`, `OrderDto`, `OrderManager`, `OrderUtil`, `OrderHelper`, `submitOrderInternally`
- ✗ `OrderRow` — *unless* you've explicitly chosen Shape B (entity-as-row + aggregate-as-domain-class), in which case `OrderRow` lives in the persistence layer, never in the domain.

The 25-word test and the ubiquitous-language test reinforce each other: a class whose name reads like the domain is usually a class with a single domain responsibility. A class named `OrderProcessor` has neither.

## 10. Cross-references

- General class rules (Martin's Ch. 10): `resources/general-classes-rules.md`.
- Kotlin idioms: `resources/kotlin-specific-classes.md`.
- Spring/JPA shapes (entity, controller, service-split): `resources/spring-boot-classes.md`.
- Tactical DDD deep-dive (aggregates, factories, repositories, domain events): `ddd-tactical-patterns`.
- Bounded contexts, ubiquitous language, subdomain classification: `ddd-strategic-design`.
- Context-mapping patterns (ACL, OHS, Conformist, Published Language): `ddd-context-mapping`.
- Anaemic domain / behaviour-on-entity vs. data-on-entity decision: `clean-code-objects-and-data`.
- CQRS handlers as another shape for use-case splitting: `cqrs-implementation`.
- Naming aggregates, value objects, repositories in domain terms: `clean-code-naming`.
