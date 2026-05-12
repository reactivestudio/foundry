# Tactical Pattern Checklist

Kotlin/Spring oriented. See `ddd-tactical-patterns/SKILL.md` for the canonical example.

## Aggregate design

- [ ] One aggregate root per transaction boundary
- [ ] Invariants enforced inside aggregate methods (`require` at creation, `check` at state transitions)
- [ ] Aggregate methods return events, not just mutate state
- [ ] Avoid cross-aggregate synchronous consistency rules — use eventual consistency via events
- [ ] Private constructor + factory method for non-trivial creation
- [ ] Status modelled as `enum` or `sealed class`, not `String`
- [ ] Mutable internal state is private (`MutableList`); public exposes read-only (`List` view)
- [ ] No JPA annotations on the domain entity — keep persistence shape separate (see `database-design/resources/schema-design.md`)

## Value objects

- [ ] Immutable by default — `data class` or `@JvmInline value class`
- [ ] Validation at construction (`init {}` block with `require`)
- [ ] Equality by value (Kotlin `data class` gives you this for free)
- [ ] Replace primitive types where the concept is real (`Email`, `OrderId`, `Money`)
- [ ] Use `@JvmInline value class` for single-field tagged primitives — no runtime cost
- [ ] Use `data class` for multi-field VOs (`Money(amountMinor, currency)`)

## Repositories

- [ ] Persist and load aggregate **roots** only — never load a child without its root
- [ ] Repository interface lives in `domain/` package
- [ ] Repository implementation lives in `infrastructure/` package (adapter)
- [ ] Domain interface returns domain objects; adapter translates from JPA entity
- [ ] Expose domain-friendly query methods (`findActiveOrdersForCustomer`, not `findByStatusAndCustomerId`)
- [ ] Do not leak `JpaRepository` types up the call stack to the application layer
- [ ] One repository per aggregate root — not per JPA entity

## Domain events

- [ ] Past-tense event names (`OrderSubmitted`, not `SubmitOrder` or `OrderSubmission`)
- [ ] Immutable — `data class` for the event
- [ ] Include minimal, stable payload (IDs and the facts that happened, not the whole aggregate state)
- [ ] Self-contained: a projection handler should be able to act on the event without re-loading the aggregate
- [ ] Version the event schema before breaking changes — add new event types rather than mutate existing ones
- [ ] If the event crosses bounded contexts, define it in the `contract/` package (Published Language) — see `ddd-context-mapping`

## Domain services

- [ ] Use only when behaviour spans multiple aggregates and doesn't naturally belong to any of them
- [ ] Stateless
- [ ] Live in `domain/` (or `application/` if the orchestration is use-case-specific)
- [ ] Don't use as a dumping ground for behaviour that should belong to an aggregate

## Anti-patterns

- **Anemic domain model.** Aggregates with only getters/setters, all logic in `@Service`. Move logic into the aggregate.
- **Public mutators.** `order.setStatus(OrderStatus.SUBMITTED)` bypasses invariants. The aggregate decides when state changes.
- **Cross-aggregate references by object.** `order.customer.address` — the aggregate references another aggregate **by ID**, not by object pointer.
- **Repository per entity.** `OrderRepository`, `OrderLineRepository`, `OrderItemAttachmentRepository` — the latter two are not aggregate roots; you don't need separate repositories.
- **Event with full aggregate snapshot.** Events are facts, not snapshots. `OrderSubmitted(orderId, total)` is enough; not `OrderSubmitted(theWholeOrderObject)`.
- **`!!` on aggregate-loaded fields.** Express absence in the type system; refactor the aggregate so the field is non-null by construction.
- **JPA `@Entity` doing aggregate work.** The JPA entity is a persistence shape. Aggregate behaviour belongs on a separate domain class.

## Kotlin/Spring specifics

- Use **`require`** for argument validation at the entry of public methods (throws `IllegalArgumentException`).
- Use **`check`** for state invariants — "this object's state allows this operation now" (throws `IllegalStateException`).
- Use **`requireNotNull`** / **`checkNotNull`** instead of `!!` to make the failure explicit.
- Use **`init {}`** in value objects for cross-field validation.
- Domain layer **must not** import `jakarta.persistence.*`, `org.hibernate.*`, `org.springframework.*` — verify with ArchUnit.
- Constructor injection in `@Service`; never field injection (see `clean-code-systems`).
- `@Transactional` boundary lives in the **application service** (use case), not in the aggregate.

## Pairing with other skills

- For the **CQRS write-side** specifics of how the aggregate publishes events through `ApplicationEventPublisher`, see `cqrs-implementation/resources/write-side-patterns.md` §4.
- For the **JPA persistence shape** of the aggregate, see `database-design/resources/schema-design.md` §1.
- For **Kotlin idioms** that support the patterns here, see the `kotlin-specific-*.md` resource in the relevant `clean-code-*` sibling: `clean-code-objects-and-data` (value classes, sealed); `clean-code-functions` (scope functions).
