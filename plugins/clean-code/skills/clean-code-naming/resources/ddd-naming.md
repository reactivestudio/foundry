# DDD Naming Conventions

Domain-Driven Design has its own naming vocabulary, layered on top of universal and language-specific rules. This file is the conventions for code *inside* a bounded context — aggregates, value objects, domain events, commands, repositories, domain services, policies, and ACL adapters.

For strategic context (which bounded context owns what concept), see `ddd-strategic-design`. For tactical structure (where the aggregate boundary goes), see `ddd-tactical-patterns`. For relationships *between* contexts, see `ddd-context-mapping`.

> The first rule of DDD naming: take the name from the domain expert's mouth, not from your stack.

---

## Rule D1: Aggregate roots are bare domain nouns

**Principle**: An aggregate root is named the way the business names the concept. No `*Aggregate`, no `*Root`, no `*Entity` — those are technical labels, not domain labels.

**Bad**:
```kotlin
class OrderAggregate(...)
class OrderRoot(...)
class OrderEntity(...)
class OrderAggregateRoot(...)
```

**Good**:
```kotlin
class Order private constructor(...) {
    fun submit() { ... }
}
class Reservation private constructor(...) { ... }
class Invoice private constructor(...) { ... }
```

**Why**: The business says "Order"; the code says `Order`. If a reader has to mentally strip a suffix to get to the domain word, the suffix should not exist.

---

## Rule D2: Value objects are named for the *concept*, not the underlying value

**Principle**: A value object encodes a domain concept with its own invariants. Name it for that concept; don't expose the implementation type.

**Bad**:
```kotlin
@JvmInline value class MoneyValue(val amount: BigDecimal)
@JvmInline value class AmountInCents(val cents: Long)
@JvmInline value class EmailString(val raw: String)
data class CurrencyType(val code: String)
```

**Good**:
```kotlin
@JvmInline value class Money(val amount: BigDecimal, val currency: Currency)
@JvmInline value class Email(val raw: String) { init { require(raw.contains("@")) } }
@JvmInline value class Currency(val code: String)
@JvmInline value class CustomerId(val value: UUID)
```

**House rule**: When a value object is identity-bearing (`*Id`), the suffix `Id` is the exception to the "no stack-noise suffix" rule — `OrderId` is the domain name for "the identity of an Order".

---

## Rule D3: Domain events — past-tense verb + subject

**Principle**: Domain events describe *what happened*. They are facts, in past tense, attached to the subject they happened to.

**Bad**:
```kotlin
class OrderCreate(...)              // present tense — sounds like a command
class CreateOrderEvent(...)         // imperative + redundant Event suffix
class OrderCreation(...)            // gerund — vague
class NewOrder(...)                 // adjective + noun — ambiguous
class OrderCreatedEvent(...)        // redundant Event suffix
```

**Good**:
```kotlin
class OrderCreated(...)             // past-tense, subject-first
class OrderSubmitted(...)
class PaymentRefunded(...)
class ReservationCancelled(...)
class InvoiceIssued(...)
```

**Why**: `OrderCreated` reads as a sentence — "Order was created" — and aligns with how the business narrates the history. The `*Event` suffix is redundant: the past tense already says "this is an event."

**Naming the timestamp field**: `occurredAt` (not `eventTime`, not `timestamp` alone, not `createdAt` — the *event* didn't create itself; the *order* was created).

---

## Rule D4: Commands — imperative verb + subject

**Principle**: A command is a request to change state. It is in imperative form, with the subject (aggregate or entity) following the verb.

**Bad**:
```kotlin
class OrderSubmit(...)              // subject-first imperative is unidiomatic
class OrderSubmitCommand(...)       // redundant suffix
class SubmittingOrder(...)          // present continuous — sounds like an event in progress
class DoSubmitOrder(...)            // "Do" is filler
```

**Good**:
```kotlin
class SubmitOrder(val orderId: OrderId)
class CancelReservation(val reservationId: ReservationId, val reason: String)
class IssueInvoice(val orderId: OrderId)
```

**Sealed command hierarchies** — when one aggregate has multiple commands, use a sealed interface and short variant names:

```kotlin
sealed interface OrderCommand {
    val orderId: OrderId

    data class Submit(override val orderId: OrderId) : OrderCommand
    data class Cancel(override val orderId: OrderId, val reason: String) : OrderCommand
    data class Refund(override val orderId: OrderId, val amount: Money) : OrderCommand
}
```

Inside the sealed type, `Submit` / `Cancel` / `Refund` are unambiguous — the parent provides context.

---

## Rule D5: Repositories — one per aggregate, named for the aggregate

**Principle**: One `<Aggregate>Repository` per aggregate root. Internal entities are accessed *through* the root and have no repository of their own.

**Bad**:
```kotlin
interface OrderRepository
interface OrderLineRepository          // OrderLine is internal to the Order aggregate
interface OrderItemRepository
interface OrderHistoryRepository       // not an aggregate either
```

**Good**:
```kotlin
interface OrderRepository {
    fun findById(id: OrderId): Order?
    fun save(order: Order): Order
}

// OrderLine is loaded as part of the Order; no separate repository.
```

**Naming the methods**:
- `findById(id)` returns `Order?` — null on miss
- `getById(id)` returns `Order` — throws on miss (use sparingly, prefer `findById`)
- `save(order)` for both insert and update
- `delete(order)` or `deleteById(id)`
- `findBy<Criteria>(...)` for query methods

**Bad method names**:
- `loadOrder` — `load` is implementation-leaky (suggests IO)
- `fetchOrder` — same
- `retrieve` — synonym proliferation; pick `find` or `get`

---

## Rule D6: Domain services — verb-er or specific noun, never `*Service`

**Principle**: A *domain service* in DDD is a piece of domain logic that doesn't naturally belong to any single aggregate (e.g., funds transfer between two accounts). Name it for the *operation* it performs, with `*er` / `*or` suffix from the verb, or with a domain noun.

**Bad**:
```kotlin
class TransferService(...)              // service of what? for whom?
class OrderService(...)                 // bag-of-methods
class PaymentLogicService(...)          // 'Logic' is filler
```

**Good**:
```kotlin
class FundsTransferer(...)              // domain service: transfer between two Accounts
class PaymentReconciler(...)            // reconciles internal records with vendor reports
class OrderApprovalPolicy(...)          // policy is the domain term for a decision rule
class ReservationPricer(...)            // computes price from rules
class TaxCalculator(...)                // calculator works as a -or suffix
```

**Why "*Service" is the default trap**: Spring's `@Service` stereotype encourages using the suffix; DDD distinguishes between *application service* (orchestrates use cases, lives in the application layer) and *domain service* (a piece of stateless domain logic). The latter rarely deserves `*Service` — it deserves a name that says what operation it embodies.

**House rule**: A class named `XService` should orchestrate. If it contains arithmetic, decision logic, or domain rules, rename it for the operation.

---

## Rule D7: Policies, specifications, factories — use the term only when the pattern is real

**Principle**: `*Policy`, `*Specification`, `*Factory` are DDD pattern names with specific meanings. Use them only when the pattern is genuinely applied.

| Term | When to use | Example |
|---|---|---|
| `*Policy` | A pluggable business rule. Different policies = different behaviour. | `OrderApprovalPolicy`, `LateFeePolicy` |
| `*Specification` | A reified predicate used in the Specification pattern. | `EligibleForRefundSpecification` |
| `*Factory` | Complex construction logic with multiple steps or external dependencies. | `OrderFactory` (only if a `companion object` factory is insufficient) |
| `*Strategy` | An algorithm variant. | `ShippingCostStrategy` |
| `*Builder` | Step-by-step construction; rare in Kotlin (named arguments cover most cases). | — |

**Bad**:
```kotlin
class OrderFactory {
    fun createOrder(...): Order = Order(...)     // a one-line wrapper; should be companion object
}

class CustomerPolicy {
    fun isActive(c: Customer): Boolean = c.status == ACTIVE    // a single predicate is not a Policy
}
```

**Good**:
```kotlin
// Companion factory is enough; no separate factory class needed
class Order {
    companion object {
        fun create(...): Order = Order(...)
    }
}

// Policy with multiple implementations chosen at runtime
sealed interface OrderApprovalPolicy {
    fun shouldApprove(order: Order): Boolean
}
class AutoApprovePolicy : OrderApprovalPolicy { ... }
class ManualApprovalPolicy : OrderApprovalPolicy { ... }
class RiskBasedApprovalPolicy(...) : OrderApprovalPolicy { ... }
```

---

## Rule D8: Aggregate operations — verbs, never setters

**Principle**: State transitions on an aggregate are operations with intent — they're not just setters. The name describes the business meaning of the change.

**Bad**:
```kotlin
order.setStatus(SUBMITTED)
order.setApprovedBy(userId)
reservation.setCancelled(true)
```

**Good**:
```kotlin
order.submit()
order.approve(by = userId)
reservation.cancel(reason = "Customer request")
```

**Why**: `setStatus(SUBMITTED)` puts the burden of knowing the rules on the caller. `submit()` puts the rules where they belong — inside the aggregate, which can enforce preconditions and emit the right event.

---

## Rule D9: Anti-Corruption Layer — `*Adapter` + `*Translator`

**Principle**: An ACL has two roles: the *adapter* talks to the upstream model; the *translator* converts between upstream and domain models. Both names belong in the persistence / infrastructure layer.

**Good**:
```kotlin
// Domain port (in domain module)
interface PaymentGateway {
    fun chargeOrder(order: Order, amount: Money): PaymentResult
}

// ACL adapter (in infrastructure module)
@Component
class StripePaymentAdapter(
    private val stripeClient: StripeClient,
    private val translator: StripePaymentTranslator,
) : PaymentGateway {
    override fun chargeOrder(order: Order, amount: Money): PaymentResult {
        val request = translator.toStripeCharge(order, amount)
        val response = stripeClient.charges.create(request)
        return translator.toDomain(response)
    }
}

@Component
class StripePaymentTranslator {
    fun toStripeCharge(order: Order, amount: Money): StripeChargeRequest = ...
    fun toDomain(response: StripeCharge): PaymentResult = ...
}
```

**Why `*Adapter` + `*Translator` together**: separation of concerns — adapter handles the *protocol* (call/response, retry, idempotency); translator handles the *vocabulary* (Stripe types ↔ domain types). One file each, both in the same package.

---

## Rule D10: Don't repeat the bounded-context name in the class

**Principle**: If a class lives in package `pricing`, the package already says it's about pricing. Don't repeat the context in the class name.

**Bad**:
```kotlin
// package pricing
class PricingCalculator(...)
class PricingPolicy(...)
class PricingService(...)
class PricingRule(...)
```

**Good**:
```kotlin
// package pricing
class Calculator(...)            // ambiguous alone; FQN pricing.Calculator is precise
class Policy(...)
class Rule(...)
```

**Caveat**: When a concept is imported across contexts, the FQN already carries the package — but for *readability in code that imports the class*, you may need to disambiguate at the import:

```kotlin
import com.example.pricing.Calculator
import com.example.shipping.Calculator as ShippingCalculator
```

If disambiguation becomes frequent, that's a signal the concept names are too generic — `pricing.Calculator` might become `pricing.PriceCalculator` only when readers actually need help telling them apart.

---

## Rule D11: Same concept, different bounded contexts = different classes

**Principle**: A `User` in the Identity context is not the same concept as a `User` in the Billing context. Don't share a class across contexts; let each have its own definition.

**Bad**:
```kotlin
// in shared module
data class User(
    val id: UUID,
    val email: String,
    val billingAddress: Address?,
    val roles: Set<Role>,
    val subscription: Subscription?,
)
// imported everywhere — every context's view of "User" is now coupled
```

**Good**:
```kotlin
// in identity context
class User(val id: UserId, val email: Email, val roles: Set<Role>) { ... }

// in billing context — same person, different concept
class Customer(val id: CustomerId, val billingAddress: Address, val subscription: Subscription) { ... }
```

The conversion (`UserId` ↔ `CustomerId`) happens at the bounded-context seam. See `ddd-context-mapping`.

---

## Rule D12: Ubiquitous language sourcing

**Principle**: Names come from the domain glossary, which comes from conversations with domain experts. When you don't know what a thing is called, ask — don't invent.

**Workflow**:
1. Find the closest domain expert.
2. Listen to how they describe the concept.
3. Use that exact word, even if it sounds odd to engineers (`Beneficiary`, `Underwriter`, `Cohort`, `Pod`).
4. Capture it in the bounded context's glossary.
5. Reject technical synonyms ("user record" → no; "Customer" or whatever the business says → yes).

**Anti-pattern**: inventing names because the business term sounds "unprofessional" or "too long". The business term wins. If it's truly ambiguous, the *business* needs to disambiguate — the engineer's job is to record the decision.

See `ddd-strategic-design` for the workshop techniques that surface ubiquitous language.

---

## Summary checklist (DDD-specific)

- [ ] Aggregate root: bare domain noun, no `*Aggregate` / `*Root` / `*Entity` suffix.
- [ ] Value object: named for concept (`Money`), not for type (`MoneyValue`, `BigDecimalAmount`).
- [ ] Identity value objects: `*Id` suffix is permitted (`OrderId`).
- [ ] Domain event: past-tense + subject (`OrderSubmitted`), no `*Event` suffix.
- [ ] Command: imperative + subject (`SubmitOrder`), no `*Command` suffix when inside a sealed parent.
- [ ] Repository: one per aggregate root, methods use `find` / `save` / `delete`.
- [ ] Domain service: `*er` / `*or` from the verb (`Reconciler`, `Calculator`), not `*Service`.
- [ ] Aggregate operations: verbs (`submit()`, `cancel()`), never setters (`setStatus(...)`).
- [ ] `*Policy` / `*Specification` / `*Factory` only when the pattern is real.
- [ ] ACL: `*Adapter` + `*Translator`, both in infrastructure layer.
- [ ] Bounded-context name not repeated in classes inside the context's package.
- [ ] Same word, different contexts = different classes.
- [ ] Names sourced from the domain glossary, not invented.
