# Tactical DDD — Anti-Patterns

Nine smells you'll find in real reviews. Each has the **signal** (what tells you something is wrong), the **principle** it violates (linked back to `SKILL.md#core-principles`), and where useful a **bad → good sketch in vanilla Kotlin**. The Kotlin is for concreteness; the principle is language-agnostic.

For language-level idioms (`@JvmInline value class`, `sealed class`, `init` validation), see `code/clean-code/resources/objects-and-data.md`. This file is about **where the behaviour lives**, not **what types to spell it with**.

## MUST-check before closing a review

Before you sign off, scan the diff once more for these camouflage cases. Each is a smell wearing a costume:

- Anemic model dressed as "a coordinated set of `*Service` classes that each touch one entity".
- Setter-driven invariants dressed as `update*()` methods taking every field as a parameter.
- Cross-aggregate object references dressed as JPA `@OneToMany`/`@ManyToOne` (the pointer is still there, just lazy).
- Cross-aggregate transactional writes dressed as "the service just calls two repositories — it's fine, they're in the same `@Transactional`".

If you find one, name it and route to the matching section below.

---

## 1. Anemic domain model

**Signal:** entities are bags of getters/setters; logic lives in `*Service` classes; the same validation re-appears in every caller.

**Violates:** principle 4 — invariants live inside the aggregate.

```kotlin
// BAD — every caller has to remember the rules.
class Order {
    var id: String = ""
    var status: String = "DRAFT"
    var items: MutableList<OrderLine> = mutableListOf()
}
class OrderService {
    fun submit(order: Order) {
        if (order.items.isEmpty()) throw IllegalStateException("empty")
        if (order.status != "DRAFT") throw IllegalStateException("already submitted")
        order.status = "SUBMITTED"
    }
}
```

```kotlin
// GOOD — rules live where the data is.
class Order private constructor(
    val id: OrderId,
    private val items: MutableList<OrderLine>,
    private var status: OrderStatus = OrderStatus.DRAFT,
) {
    fun submit() {
        check(status == OrderStatus.DRAFT) { "already submitted" }
        check(items.isNotEmpty()) { "cannot submit empty" }
        status = OrderStatus.SUBMITTED
    }
}
```

---

## 2. Setter-driven invariants

**Signal:** `setStatus(...)`, `setTotal(...)`, etc. on the aggregate; callers each check preconditions before calling them and drift over time.

**Violates:** principle 4 + construction-discipline rule 2 (intent-named transitions).

```kotlin
// BAD — the transition rule is in callers, not the aggregate.
order.setStatus(OrderStatus.CANCELLED)  // who's checking it was DRAFT?
```

```kotlin
// GOOD — the verb is the rule.
order.cancel(reason)  // throws if state doesn't allow it
```

State changes are methods named in the ubiquitous language; the aggregate decides which transitions are legal.

---

## 3. Cross-aggregate references by object

**Signal:** an aggregate field holds another aggregate (`Order.customer: Customer`); business code navigates `order.customer.address.city`.

**Violates:** principle 3 — references across boundaries are IDs, not pointers.

```kotlin
// BAD — Order knows the full Customer; aggregates collapse into one cluster.
class Order(val customer: Customer, ...)

// GOOD — Order references Customer by ID. The caller loads explicitly if needed.
class Order(val customerId: CustomerId, ...)
```

The seam matters even when both aggregates live in the same database. Removing it later — when one of them moves to another service — is a refactor that touches every call site.

---

## 4. Aggregate loading thousands of children

**Signal:** loading the root pulls in 10k+ rows by default; the test suite gets slow even with `@DataJpaTest`; queries fan out into N+1s that you "fix" with cascade-fetch hints.

**Violates:** principle 6 — aggregates fit in memory.

The smallest correct fix is rarely "tune fetch". The correct fix is to split the aggregate: lift the high-cardinality children into their own aggregate root, referenced from the original by ID. Loading the original no longer pulls children. Each child aggregate is now small and can be operated on independently.

If you can't split (the children are genuinely part of one invariant), question whether the invariant should be enforced at write time at all. Sometimes "the sum of line totals must equal the order total" can be a projection, computed and rejected at read time, rather than a write-time invariant.

---

## 5. One repository per entity

**Signal:** `OrderRepository`, `OrderLineRepository`, `OrderLineAttachmentRepository` — all separately injectable; callers inject `OrderLineRepository` and skip the root entirely.

**Violates:** principle 7 — one repository per aggregate root only.

The internal entities have no business being separately injectable. If they are, callers will modify them without going through the root, and the root's invariants are bypassed. The fix is structural: remove the repositories for non-root entities; the application layer must reach inner state through the root.

This is also why even when the underlying JPA layer has multiple Spring Data interfaces (one per `@Entity`), only the *root's* domain repository is exposed beyond the persistence module.

---

## 6. Transaction-script masquerading as service

**Signal:** a `*Service` method is 50 lines of `if`s, DB reads, conditional updates, then a `save()`; the business rules are interleaved with the orchestration.

**Violates:** principle 4 + the application-service / domain-logic split.

```kotlin
// BAD — orchestration AND logic in one place; testing requires a DB.
fun cancelOrder(orderId: String, reason: String) {
    val order = repo.findById(orderId) ?: throw NotFoundException()
    if (order.status == "CANCELLED") return
    if (order.status == "SHIPPED") throw IllegalStateException("too late")
    if (reason.isBlank()) throw IllegalArgumentException("reason required")
    order.status = "CANCELLED"; order.cancellationReason = reason
    repo.save(order)
}

// GOOD — application service is thin; the rules live on the aggregate.
fun cancelOrder(orderId: OrderId, reason: CancellationReason) {
    val order = repo.findById(orderId) ?: throw NotFoundException()
    order.cancel(reason)   // throws if state forbids it; sets fields internally
    repo.save(order)
}
```

---

## 7. Events emitted from services

**Signal:** the service does `repo.save(order); publisher.publish(OrderSubmitted(...))`. Two failure modes follow: events fire when the save rolls back, or no event fires when the save succeeds (the publisher line throws).

**Violates:** principle 8 — events emitted by the aggregate, dispatched after commit.

```kotlin
// BAD — fires on rollback, or fails to fire on success.
order.submit(); repo.save(order)
publisher.publish(OrderSubmitted(order.id, order.total()))

// GOOD — aggregate records, repo dispatches after the JPA commit succeeds.
class Order(...) {
    private val pendingEvents = mutableListOf<DomainEvent>()
    fun submit() { /* ... */ pendingEvents += OrderSubmitted(id, total()) }
    fun pullEvents(): List<DomainEvent> = pendingEvents.toList().also { pendingEvents.clear() }
}
// In OrderRepository.save(), after the underlying commit:
order.pullEvents().forEach(publisher::publish)
```

---

## 8. Primitive obsession at domain edges

**Signal:** public method signatures full of `String userId, String currency, Long amount`; argument-order bugs that the compiler doesn't catch (passing `currency` where `userId` was expected, both strings).

**Violates:** construction-discipline rule 3 — value objects encode constraints in types.

The fix is to lift the primitives that *mean something domain-specific* into value object types. Not every primitive needs lifting — only the ones whose meaning matters (IDs, currencies, money, emails). For *what* the type spelling looks like in Kotlin, see `code/clean-code/resources/objects-and-data.md`. For *which* primitives deserve it, the rule is: any primitive whose mix-up would survive review and explode in production.

**Special case — multi-currency running totals.** If a `total*: Long` field accumulates across documents with different currencies (program A pays in USD, program B in EUR, summed into one Long) the field is already broken regardless of whether you lift it to `Money`. Combine with anti-pattern #11 — the field shouldn't live on the aggregate at all; it's a currency-aware projection on the read side. Single-currency totals can still be `Money` and live on the aggregate if the invariant requires write-time enforcement.

---

## 9. Cross-aggregate transactional save

**Signal:** one application method writes to two aggregates inside one `@Transactional`. The pattern hides behind names like "atomic order/inventory update" or "coordinated save".

**Violates:** principle 2 — one command writes one aggregate.

There are three honest fixes, in order of typical effort:

1. **The aggregates are wrong.** They're really one aggregate, drawn artificially apart. Merge.
2. **The consistency rule is wrong.** It doesn't need to be enforced at write-time — it can be a projection (read-time) or a reconciliation (after-the-fact).
3. **You need a process manager / saga.** The aggregates stay separate, the write to one fires a domain event, a saga listens and triggers a compensating write to the other. The system is now eventually consistent and the business has to explicitly accept that.

Cross-aggregate `@Transactional` doesn't make the data more correct; it makes the failure mode silent. The lock contention shows up later as a production incident, not at design time.

---

## 10. State-machine-as-dates fields

**Signal:** an aggregate has 3+ nullable `*At: Instant?` fields (`submittedAt`, `acceptedAt`, `paidAt`, `rejectedAt`, `cancelledAt`) — the state machine is derived from "which timestamps are non-null".

**Violates:** principle 3 (invariants live inside the aggregate). The state machine is implicit, undefended, and any caller can mutate any timestamp in any order. The aggregate cannot answer "what state am I in?" without inspecting null-patterns of unrelated fields.

```kotlin
// BAD — state is the null-pattern of 5 fields; no transition guard.
class Report {
    var submittedAt: Instant? = null
    var acceptedAt: Instant? = null
    var paidAt: Instant? = null
    var rejectedAt: Instant? = null
    var cancelledAt: Instant? = null
}
// Anyone can do: report.acceptedAt = Instant.now() then report.cancelledAt = Instant.now()
//                without ever transitioning through a "valid" state.

// GOOD — state is typed and guarded; timestamps live on events.
enum class ReportStatus { SUBMITTED, ACCEPTED, PAID, REJECTED, CANCELLED }
class Report private constructor(...) {
    private var status: ReportStatus = SUBMITTED
    fun accept(...) { check(status == SUBMITTED); status = ACCEPTED; events += ReportAccepted(at = clock.now(), ...) }
}
```

**Restraint:** one immutable `createdAt` is metadata, not state. The smell triggers at **3+ co-existing optional timestamps** where their null-pattern carries lifecycle meaning.

---

## 11. Running scalar that should be projection

**Signal:** an aggregate has a field accumulated via `+=` across multiple state-changing methods — `var totalEarned: Long`, `var totalRefundsIssued: Money`, `var lastSeenAt: Instant`. The field is derived from event history but stored as write-time aggregate state.

**Violates:** principle 1 — the aggregate's consistency unit duplicates what already lives in payment / event history. Three failure modes that always follow:

1. **Drift under partial failure.** Save fails midway; `totalEarned` updated, payout not created. Reconciliation job, support tickets, manual corrections.
2. **Drift under retry.** Retry hits the increment again; total is double-counted.
3. **Multi-source nonsense.** When the source is multi-currency / multi-tenant / multi-aggregate, a single Long collapses incompatible values.

```kotlin
// BAD — aggregate stores a running scalar derived from elsewhere.
class Researcher {
    var totalEarned: Long = 0   // sums payouts; drifts on every partial failure
}
service.acceptAndPay() {
    researcher.totalEarned += amount   // race condition + drift waiting to happen
}

// GOOD — aggregate doesn't store it; read-side projects from events.
class Researcher private constructor(...) { /* no totalEarned field */ }
// Read model:
class ResearcherEarningsProjection { /* updates on PayoutSent event, currency-aware */ }
```

**Restraint:** a derived field that is **never read outside one aggregate's own method** (e.g., a cache for performance within a single TX, recomputed on load) is not this smell. Test: does any code outside the aggregate read the field? If yes — projection.

---

## 12. Domain depends on framework

**Signal:** aggregate classes carry persistence, DI, or serialization annotations — `@Entity`, `@OneToMany`, `@ManyToOne`, `@Component`, `@Service`, `@JsonProperty`, `@ConfigurationProperties`. Domain tests need to boot a database or DI container.

**Violates:** principle 7 — domain is framework-free. The aggregate's shape is now governed by JPA's no-arg-ctor and mutable-field requirements; behavioural design has to bend around persistence concerns.

The fix is the **two-class split** documented in `code/clean-code/resources/objects-and-data.md` (Option B):

```kotlin
// Domain — pure Kotlin in domain/, no framework imports.
class Order private constructor(val id: OrderId, ...) {
    fun submit() { /* invariants */ }
}

// Persistence — JPA-shaped, in persistence/.
@Entity class OrderRow(@Id var id: String = "", var status: String = "", ...)

// Mapper at the repository edge — translates between the two.
class OrderMapper { fun toDomain(row: OrderRow): Order = ...; fun toRow(order: Order): OrderRow = ... }
```

**Sub-smell — double FK source-of-truth.** `var programId: String` *AND* `@ManyToOne var program: Program?` on the same class. Two sources of truth diverge on `merge()` / partial loads / lazy initialization. Pick one — and if you keep the JPA pointer, the class is **not** your domain aggregate; the domain aggregate is the separate class (Option B above).

**Restraint:** for **read-only DTOs**, **projection rows**, and **event payloads on the wire**, framework annotations are appropriate — those classes are not aggregates. The smell triggers only when annotations land on a class that has **behaviour + invariants** (i.e., the aggregate itself).
