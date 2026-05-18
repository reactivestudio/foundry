# Tactical DDD — Diagnostic Playbook

The body's 10-point scan walked through in depth. Open when reviewing a non-trivial domain-touching diff (≥40 lines of domain + service code) and you want concrete signals + camouflages + clean shapes per step.

Each step: **Grep** (literal patterns to look for), **Camouflages** (how the smell hides), **Clean shape** (what the fix looks like), **Restraint** (when to NOT flag it).

---

## 1. Construction scan

**Grep:** `Entity().apply {`, empty constructor + chained public field assignments, `data class` for things that have invariants or lifecycle.

**Camouflages:**
- `class X { @Id var id = ""  /* and 10 others */ }` paired with `X().apply { ... }` at callsites — `apply { }` is the constructor in disguise.
- A `Builder` that doesn't validate (just sets fields).
- A `*Factory` class with one method that returns `Foo()`-then-mutate — calls itself a factory, isn't.

**Clean shape:**
```kotlin
class Order private constructor(val id: OrderId, ...) {
    companion object {
        fun create(id: OrderId, items: List<OrderLine>, ...): Order {
            require(items.isNotEmpty()) { "..." }
            return Order(id, items.toMutableList(), ...).also {
                it.pendingEvents += OrderCreated(...)
            }
        }
    }
}
```

**Restraint:** DTOs, projection rows, event payloads correctly have public constructors. The smell triggers for classes that own invariants or lifecycle.

---

## 2. State-type scan

**Grep:** `: String =` on fields named `status`, `state`, `type`, `phase`, `stage`; string literals appearing in `if (status == "X")` or `status = "Y"`.

**Camouflages:**
- `typealias OrderStatus = String` — still a String at runtime; no exhaustiveness.
- An "enum-named" class that is actually a String wrapper without sealed exhaustiveness.

**Clean shape:** `enum class OrderStatus { DRAFT, SUBMITTED, FULFILLED, CANCELLED }` or `sealed class` for richer per-state data. `when` over the enum gets compiler-enforced exhaustiveness; transitions become typed.

**Restraint:** free-form tags, user-input labels are correctly Strings. The smell triggers when the field has a **closed set of legal values** that encode a state machine.

---

## 3. Lifecycle scan

**Grep:** 3+ nullable `*At: Instant?` / `*Date: LocalDate?` fields on the same class.

**Camouflages:**
- "Optional audit fields" — they're really the state machine.
- One mandatory `createdAt` + several optional ones (`paidAt?`, `cancelledAt?`) where the null-pattern is checked elsewhere to decide state.

**Clean shape:** state is an enum/sealed class on the aggregate. Timestamps live on **domain events** that recorded the transition, not on the aggregate's mutable state. The event log answers "when was this paid?"; the aggregate answers "what state am I in now?".

**Restraint:** a single immutable `createdAt` for metadata is fine. The smell starts at **3+ co-existing optional timestamps** where some are null and the null-pattern carries meaning.

---

## 4. Mutation scan

**Grep:** `<lowercase>.<field> =` and `<lowercase>.<field> +=` in any class annotated `@Service` / `@Component` (or any non-aggregate class). Also: public setters on the aggregate.

**Camouflages:**
- `update(field1, field2, field3)` methods on the aggregate — LOOK like commands but mutate blindly with no invariant checks.
- A `withStatus(SUBMITTED)` copy method that returns a new instance with no validation.
- A "merge from DTO" method that overwrites all fields from input.

**Clean shape:** state transitions are intent-named verbs on the aggregate (`submit()`, `cancel(reason)`, `refund(amount)`), each enforcing its own preconditions. Setters are private or absent.

**Restraint:** read-only projections and DTOs correctly have public setters / vars. The smell is for classes that own invariants.

---

## 5. Reference scan

**Grep:** aggregate fields of type `Other` (another aggregate) instead of `OtherId`. JPA: `@ManyToOne`, `@OneToOne` of aggregate-typed targets. Plain Kotlin: any field whose type matches another aggregate root.

**Camouflages:**
- Lazy-loaded JPA references — the pointer still exists; lazy is not absent.
- Inline `Other` parameters in aggregate methods — `order.assignTo(customer: Customer)` should be `order.assignTo(customerId: CustomerId)`.

**Clean shape:** every cross-aggregate field is the ID type. Callers load the other aggregate explicitly via its repository when needed.

**Restraint:** value objects, owned inner entities, and ID types are correctly object-typed inside an aggregate. The smell is *only* for fields pointing **across aggregate boundaries**.

---

## 6. Repository scan

**Grep:** `class *Service(... private val *Repository, private val *Repository ...)` — count repositories. Inspect what each handles: is it a root or an inner entity?

**Camouflages:**
- A repository named after a root that actually fetches inner entities via specialised methods.
- An "abstraction" interface that exposes both root and inner-entity methods (`OrderRepository.findLineById(...)`).

**Clean shape:** one repository per aggregate root. Inner entities (`OrderLine`, `Scope`, `BountyBracket`) have **no repository** — they're loaded as part of the root and mutated through root methods.

**Restraint:** sometimes an "inner entity" turns out to have an independent lifecycle in real workflows — in which case **promote it to a root**. The smell triggers when the entity has no lifecycle outside its parent.

---

## 7. TX-boundary scan

**Grep:** `@Transactional` methods. For each, list the distinct aggregate types that receive `save()` (or implicit JPA flushes via mutation). Two or more = cross-aggregate TX save.

**Camouflages:**
- Two saves but only one is an aggregate write (the other is a projection / outbox row) — fine.
- "Service A calls service B inside the same TX" — the call chain still ends in two aggregate writes; the indirection doesn't help.

**Clean shape:** one command writes one aggregate per TX. Cross-aggregate effects flow via domain events + listeners in **separate** transactions (sagas / process managers when explicit coordination is needed).

**Restraint:** outbox writes, audit-log appends, and read-side projection updates inside the same TX are not "cross-aggregate writes" — they're persistence-layer concerns piggybacking the write.

---

## 8. Event-timing scan

**Grep:** `publishEvent(`, `applicationEventPublisher.publish*`, or any direct event emit inside a `@Transactional` method. Inspect whether emit happens before/after `repo.save(...)`, and whether listeners are `@TransactionalEventListener(phase = AFTER_COMMIT)`.

**Camouflages:**
- "Sync publish before commit" hidden as a call chain (`audit.record(event)` that internally publishes).
- A listener NOT annotated `AFTER_COMMIT` — Spring's default is BEFORE_COMMIT, which is the bug.

**Clean shape:** aggregate accumulates `pendingEvents` and exposes `pullEvents()`. Repository, in `save()`, calls `pullEvents()` *after* the underlying commit succeeds and publishes each. Or: handlers use `@TransactionalEventListener(AFTER_COMMIT)` for any side-effect listener.

**Restraint:** events emitted in the SAME transaction *into a database outbox table* are fine — they're written transactionally with the aggregate and replayed asynchronously by a worker. That's the outbox pattern.

---

## 9. Invariant-placement scan

**Grep:** in any service, find `if (...) throw`. For each, ask: does the rule use data from only one aggregate? If yes → it belongs on that aggregate.

**Camouflages:**
- Rules expressed as Bean Validation annotations (`@NotBlank`, `@Min`) on DTO classes — that's *input* validation, fine at the boundary. Domain invariants are different.
- Cross-aggregate validations that look like they need both aggregates but really only need one + an ID lookup — those collapse into one aggregate's method.

**Clean shape:** the aggregate's state-changing method enforces the rule. The service shrinks to `aggregate.method(...); repo.save(aggregate)`.

**Restraint:** cross-aggregate rules genuinely belong in a **domain service** (rare) or process manager. Not every `if (...) throw` belongs on an aggregate; some are orchestration concerns.

---

## 10. Primitives & projections scan

**Grep:**
- Method signatures: `String *Id`, `Long amount` + sibling `String currency`, `Int *Days`, `Long *At`.
- Aggregate fields: `var total*: Long`, `var sum*: Long`, `var last*: Instant` accumulated across method calls.

**Camouflages:**
- `data class` wrapping a single primitive (`data class UserId(val value: String)`) — better than raw String but not as cheap as `@JvmInline value class`.
- `typealias` — runtime is still the primitive; no type safety.

**Clean shape:**
- IDs: `@JvmInline value class UserId(val value: String)` — no runtime cost, types don't mix at call sites.
- Money: `data class Money(val amount: BigDecimal, val currency: Currency)` — never `Long amount` + `String currency` as separate params.
- Running totals that are read outside one aggregate's own method → projection over events, not aggregate field.

**Restraint:** generic measurements with no domain identity (`Long count`) are fine. The smell is for primitives **whose mix-up would survive review** — IDs of different entities, money / currency siblings, time/distance/weight units.

---

## After the scan

Diagnosis order in the response: **foundation (1-4) → boundary (5-8) → polish (9-10)**. Don't lead with primitive obsession when the model is anemic; don't lead with `@Version` when the boundary is wrong. The order reflects what causes what — foundation issues are how boundary issues *materialise* later.
