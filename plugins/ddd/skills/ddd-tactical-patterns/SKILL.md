---
name: ddd-tactical-patterns
description: "Tactical Domain-Driven Design in code: aggregates with private constructors and factories, value objects via inline classes, repositories at the aggregate-root boundary, domain events emitted from aggregates, ubiquitous-language naming inside one context. Kotlin/Spring focused. Use when refactoring an anemic model into behaviour-rich aggregates, designing an aggregate boundary that touches multiple entities, deciding where domain events fire and how they're collected, defining a repository contract (per-root, not per-entity), modelling primitives as value objects, or fixing invariants that escape into services. Use AFTER ddd-strategic-design has drawn the bounded contexts; for cross-context translation patterns, use ddd-context-mapping; for the wire-level REST/gRPC contract that exposes the aggregate, use api-design-principles."
risk: safe
source: custom
---

# DDD Tactical Patterns

> "The aggregate is where invariants live. Everything outside the aggregate is plumbing."

Tactical DDD is the code-level discipline of putting business rules where the data is, so callers can't accidentally produce invalid state. It pays off in domains with real invariants; in pure CRUD it overfits.

## Use this skill when
- Refactoring an anemic model (getter/setter bags) into behaviour-rich aggregates.
- Designing an aggregate boundary — what's *in* the aggregate, what's *referenced by ID* across aggregate boundaries.
- Deciding where domain events fire and how they're collected/dispatched (aggregate vs. service vs. transaction listener).
- Defining a repository contract (one per aggregate root, not one per entity).
- Modelling primitives as value objects (`UserId`, `Money`, `Currency`) instead of `String`/`Long`.
- Fixing the smell where validation rules live in every service and get re-implemented inconsistently.

## Do not use this skill when
- The bounded context itself is not yet defined → `ddd-strategic-design` comes first.
- The task is *between* contexts (ACL, OHS, Published Language) → `ddd-context-mapping`.
- The task is the wire-level contract that exposes the aggregate (REST resource shape, gRPC proto) → `api-design-principles`.
- The task is the JPA persistence shape (entities, columns, indexes) → `database-design`. Domain model and persistence model are separate; this skill is the former.
- The domain is **simple CRUD without invariants** — full tactical DDD overfits. An anemic `data class` + Spring Data repository is fine for that case; admit it instead of forcing aggregates.
- The task is generic responsibility assignment (which class should own this method) → `grasp-patterns` (Information Expert). DDD's aggregate root is *parallel to* GRASP, not a substitute.

## Core principles

1. **The aggregate is the consistency boundary.** Operations inside an aggregate execute in one transaction and enforce its invariants atomically. Cross-aggregate operations are eventual.
2. **One repository per aggregate root**, not one per entity. The root is the only entry point; internal entities are invisible to callers.
3. **Reference other aggregates by ID, not by reference.** A `Reservation` doesn't hold a `Customer` field; it holds a `CustomerId`. This is the seam that prevents aggregates from collapsing into one big aggregate.
4. **Invariants are enforced in the aggregate, at construction and at every state-changing method.** Not in services, not in validators, not in the database.
5. **Value objects encode constraints in types.** `Money(amount, currency)` is not interchangeable with two `Long`s; the type system catches unit mismatches.
6. **Domain events are emitted by the aggregate**, collected as a pending list, and dispatched by the persistence layer *after* the write transaction commits.
7. **No framework annotations on the domain.** No `@Entity`, no `@Component`, no `@Transactional` on aggregates. Domain testing should not need Spring or a database.

## Pattern layering: Principle / Kotlin idiom / Spring placement

Each tactical pattern has three faces. The **Principle** is language-agnostic DDD — the same in any tech stack. The **Kotlin idiom** is how the principle renders in idiomatic Kotlin. The **Spring placement** is where the persistence and wiring code lives. Keep them separate in your head; mixing them is how `@Entity` ends up on an aggregate.

| Pattern | Principle (general DDD) | Kotlin idiom | Spring / JPA placement |
|---|---|---|---|
| **Aggregate** | Cluster of entities sharing a transactional boundary; one root mediates all access; invariants enforced inside. | `class` with `private` constructor + `companion object` factory; `pendingEvents` list; state changes are intent-named methods. | Plain Kotlin in domain module — no JPA / Spring annotations. JPA `@Entity` class lives in persistence module; a mapper translates. |
| **Aggregate root** | The only legal entry point to an aggregate. | `public` factory + `public` state-changing methods on the root; inner entities have package-private / `internal` mutators reached through the root. | Repository contract is defined per root only; Spring Data interface (under the hood) is per JPA entity, but it's hidden behind the domain repository. |
| **Entity (non-root)** | Identity inside the aggregate; not reachable from outside; lifecycle bound to the root. | `class` (not `data class`) with an `@JvmInline value class` ID; constructor `internal` or via root-level factory. | Mapped together with the root in JPA; cascade lifecycle from root. Never expose via a separate repository. |
| **Value object** | No identity; equality by value; encodes constraints in types. | `@JvmInline value class Foo(val v: T)` for single-field IDs / wrappers; `data class` for multi-field (e.g. `Money(amount, currency)`). | `@Embeddable` or JPA `@Convert(AttributeConverter)` in the persistence mapper. Never persisted as standalone tables. |
| **Repository** | One per aggregate root; abstracts the persistence mechanism; contract owned by the domain. | `interface OrderRepository { fun findById(...); fun save(...) }` in domain module. | `@Repository class JpaOrderRepository(...)` in persistence module; delegates to Spring Data `JpaRepository`; runs the domain → entity mapper. |
| **Domain event** | A past-tense fact about something that happened inside the aggregate; named in ubiquitous language. | Sealed class hierarchy `sealed class DomainEvent`; `pendingEvents` list on the aggregate; `pullEvents()` drains it. | Dispatched by the repository / service *after* the write transaction commits — via `ApplicationEventPublisher`, or Modulith `@ApplicationModuleListener` for cross-module / cross-context fanout. Never inside the aggregate. |
| **Factory** | Construction that enforces invariants atomically — invalid states are unconstructible. | `companion object { fun create(...): T { require(...); return T(...).also { it.recordEvent(...) } } }`. | Domain-module Kotlin; no Spring needed. If construction needs collaborators (rare), inject via the constructor of an orchestrating domain service. |
| **Domain service** | Behaviour that doesn't belong on one aggregate but is still domain logic (e.g. cross-aggregate orchestration that doesn't need a saga). | Plain Kotlin `class` in domain module with constructor-injected ports (`interface OrderRepository`, etc.). | Wired as a Spring `@Component` only if it crosses the framework boundary; the *interface* still lives in the domain. |
| **Application service** | Thin orchestration: load aggregate → call method → save. Not domain logic. | Plain Kotlin in application module; no behaviour beyond load/call/save and event dispatch. | `@Service` + `@Transactional` lives here, not on the aggregate. This is the layer where Spring's transactional aspect bites. |

**The split that matters most**: a domain class is plain Kotlin with zero framework imports. The same business pattern has a separate JPA-mapped class in persistence. The two are translated by a mapper. Yes, it's more code than slapping `@Entity` on the aggregate — the win is that domain tests don't need a database, and the persistence shape can evolve independently of the domain shape.

## Aggregate boundary checklist

When drawing the line around an aggregate, all of these should hold. If two or more fail, the boundary is probably wrong.

- [ ] **Transactional invariants stay inside.** Any rule that must hold *at the moment of writing* lives within one aggregate's transaction.
- [ ] **Eventual rules cross boundaries.** Cross-aggregate rules ("when X happens, Y should eventually update") flow via domain events, not direct calls or shared transactions.
- [ ] **The root is the only entry point.** External code cannot reach into `aggregate.someInnerEntity.changeSomething()`; the root mediates every change.
- [ ] **References across aggregates are IDs, not objects.** `Order` has a `CustomerId`, not a `Customer` field.
- [ ] **The aggregate fits in memory.** If loading the root requires materialising 10,000 child entities, the boundary is too large. Move children to their own aggregate; reference by ID.
- [ ] **One operation, one aggregate written.** A single command should not write to two aggregates in the same transaction. If it must, the boundary is wrong (or use a saga / process manager).

## Canonical Kotlin example

```kotlin
@JvmInline value class OrderId(val value: UUID)
@JvmInline value class CustomerId(val value: UUID)
data class Money(val amount: BigDecimal, val currency: Currency)

class Order private constructor(
    val id: OrderId,
    val customerId: CustomerId,                  // reference across aggregates
    private val items: MutableList<OrderLine>,
    private var status: OrderStatus = OrderStatus.DRAFT,
) {
    private val pendingEvents = mutableListOf<DomainEvent>()

    companion object {
        fun create(id: OrderId, customerId: CustomerId, items: List<OrderLine>): Order {
            require(items.isNotEmpty()) { "Order cannot be created empty" }
            return Order(id, customerId, items.toMutableList()).also {
                it.pendingEvents += OrderCreated(id, customerId, it.total())
            }
        }
    }

    fun submit() {
        check(status == OrderStatus.DRAFT) { "Order already submitted" }
        check(items.isNotEmpty()) { "Order cannot be submitted empty" }
        status = OrderStatus.SUBMITTED
        pendingEvents += OrderSubmitted(id, total())
    }

    fun total(): Money = items.map { it.subtotal() }.reduce { acc, m -> acc + m }

    fun pullEvents(): List<DomainEvent> =
        pendingEvents.toList().also { pendingEvents.clear() }
}
```

What this demonstrates:
- **Private constructor + factory** — the only way to build a valid `Order` is through `create`, which enforces invariants atomically.
- **`require` for entry validation** (creation parameters), **`check` for state invariants** (transitions from one state to another). Different concerns, different operators.
- **Status is a state machine via enum**, not a string. The type system rules out invalid states.
- **`@JvmInline value class` for IDs** — zero runtime cost, but `OrderId` and `CustomerId` cannot be confused at the call site.
- **`customerId: CustomerId`, not `customer: Customer`** — Customer is a different aggregate; we reference by ID.
- **Events collected on the aggregate** and pulled by the persistence layer after `save`. Avoids the trap of side effects leaking out of `submit()`.
- **No JPA annotations.** This is the domain. The JPA-mapped row is a separate class in the persistence module — see `database-design`.

## Repository contract pattern

```kotlin
// In the domain module — no JPA, no Spring annotations
interface OrderRepository {
    fun findById(id: OrderId): Order?
    fun save(order: Order): Order
}

// In the persistence module — implementation depends on the framework
@Repository
class JpaOrderRepository(
    private val jpa: JpaOrderEntityRepository,   // Spring Data interface
    private val mapper: OrderMapper,
) : OrderRepository {
    override fun findById(id: OrderId): Order? =
        jpa.findById(id.value).map(mapper::toDomain).orElse(null)

    override fun save(order: Order): Order {
        val saved = jpa.save(mapper.toEntity(order))
        order.pullEvents().forEach { eventPublisher.publish(it) }
        return mapper.toDomain(saved)
    }
}
```

Notice: **the repository interface lives with the domain; the implementation lives with persistence**. The dependency points inward. The domain has no idea Spring exists.

## Anti-patterns

| Anti-pattern | Signal | Fix |
|---|---|---|
| **Anemic domain model** | Entities are getter/setter bags; logic lives in `*Service` classes; same validation re-implemented in every caller. | Move behaviour onto the aggregate. Make fields private; expose intent-named methods (`submit()`, `cancel(reason)`) not setters. |
| **Setter-driven invariants** | `order.setStatus(SUBMITTED)` with checks scattered in callers. | State changes are methods (`submit()`); the aggregate enforces transitions internally. |
| **Cross-aggregate references by object** | `Order.customer: Customer` instead of `Order.customerId: CustomerId`. | Reference by ID. Force the caller to load the other aggregate explicitly. |
| **Aggregate that loads thousands of children** | `order.items` is a `List<OrderLine>` and orders can have 100k items. | Split: a `LineItem` aggregate with its own root, referenced from `Order` by `LineItemId`. |
| **One repository per entity** | `OrderRepository`, `OrderLineRepository`, `OrderEventRepository` — all separately injectable. | One repository per aggregate root only. Inner entities are accessed *through* the root. |
| **Transaction-script masquerading as service** | A `OrderService` method has 50 lines of `if`s, DB reads, and conditional updates. | The business logic is the aggregate's job. The service is thin orchestration: load, call method, save. |
| **Events emitted from services** | `orderService.submit(id) { /* DB save */; publisher.publish(OrderSubmitted(...)) }` | Events come from the aggregate (`pendingEvents`). The service pulls and publishes after save. This guarantees the event always reflects committed state. |
| **Primitive obsession at domain edges** | Method signatures full of `String userId, String currency, Long amount`. | Value objects: `UserId`, `Currency`, `Money`. The type system catches mix-ups; the IDE renames safely. |
| **JPA leaking into the domain** | `@Entity` on the aggregate; testing the domain requires booting a DB. | Domain class is plain Kotlin. JPA-mapped class lives in persistence; a mapper translates. Yes, it's more code; yes, it's worth it past a CRUD-light threshold. |
| **Forcing DDD on simple CRUD** | A 3-field configuration table has an aggregate, factory, events, and a repository interface. | Use Spring Data directly. DDD is a tax; it pays off when invariants exist, not when they don't. |
| **Cross-aggregate transactional save** | One method writes to `Order` and `Inventory` in the same `@Transactional`. | One aggregate per transaction. Use a domain event + listener (eventual) or an explicit process manager / saga. |

## When tactical DDD is overkill

Be honest: an internal-tools dashboard with 4 tables and no domain logic does not need aggregates. The signals that tactical DDD pays off:

- The domain has rules that must hold *at write time* (financial, regulatory, safety-critical).
- The same validation rule appears in 3+ places and tends to drift.
- Domain experts can describe invariants in their own language ("an order cannot be submitted empty"); the code does not enforce them.
- Bugs cluster around "the system got into a state I didn't think was possible."

If none of these apply, an anemic model + Spring Data repository is the right shape. Don't gold-plate.

## Selective reading rule

| File | When to read |
|---|---|
| `references/tactical-checklist.md` | Detailed per-pattern checklists: aggregate design, value object idioms, repository conventions, domain event lifecycle, common Kotlin/Spring pitfalls. |

## Related skills

| Skill | This not that |
|---|---|
| `ddd` | Router + glossary + "is DDD worth it here?" gate for the ddd-* family. Use it when the stage is unclear or DDD vocabulary needs a single source of truth. |
| `ddd-strategic-design` | Where the bounded context lines go. This skill is what happens inside one context once those lines are drawn. |
| `ddd-context-mapping` | Relationships *between* contexts. This skill is the code inside one. |
| `api-design-principles` | The wire shape that exposes an aggregate to the outside world. DTOs are not aggregates; the contract is owned by the API layer. |
| `database-design` | The JPA persistence shape under the aggregate. The domain class and the entity class are *not* the same class. |
| `architecture-patterns` | Where tactical DDD fits inside an Onion/Clean overlay. |
| `cqrs-implementation` | When the read model diverges from the aggregate shape — aggregates remain the write side; queries hit projections. |
| `grasp-patterns` | GRASP's Information Expert is the responsibility-assignment vocabulary parallel to DDD's aggregate root. Use that skill for general responsibility questions; use this one when DDD's *bounded-context discipline* is the frame. |
| `clean-code-objects-and-data` | Kotlin idioms (`@JvmInline value class`, sealed, immutable collections) that make tactical DDD ergonomic in Kotlin. |
