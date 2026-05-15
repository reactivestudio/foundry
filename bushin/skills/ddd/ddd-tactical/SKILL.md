---
name: ddd-tactical
description: "DDD tactical: aggregates, domain events, value objects, anemic models. NOT for pure CRUD."
---

# DDD Tactical

Code-level discipline that puts business rules where the data is so invariants can't be bypassed by services or callers. Operates one layer above class-shape (anemic-vs-behaviour-rich, JPA-vs-aggregate, value-object idioms — owned by `code/clean-code/resources/objects-and-data.md`). Once class shapes are right, this skill says **which classes cluster, where the transactional boundary sits, and how state changes leave the cluster**.

## When to use

- Refactoring an anemic model (getter/setter bags) into behaviour-rich aggregates.
- Designing an aggregate boundary — what's *in* the cluster, what's referenced *by ID* across boundaries.
- Placing domain events — where they fire, who collects them, when they dispatch.
- Defining a repository contract — one per aggregate root, not per entity.

## When NOT to use

- **Pure CRUD without invariants.** An anemic data class + framework repository is the honest shape. See [overkill gate](#when-tactical-ddd-is-overkill).
- **Bounded contexts not yet drawn.** Strategic comes first; without it you're modelling in the dark.
- **Between-context translation** (anti-corruption layer, published language) — that's `ddd-strategic` territory (future skill); the bridge is in [resources/ddd-strategic-bridge.md](resources/ddd-strategic-bridge.md).
- **JPA persistence shape** (entity rows, columns, indexes) — domain ≠ persistence. See `code/clean-code/resources/objects-and-data.md` for the two-class separation.
- **Generic "which class owns this method"** — that's `architecture/application/grasp` (Information Expert). Use this skill when the *bounded-context discipline* is the frame.

## Core principles

1. **Aggregate = transactional consistency boundary.** Operations inside execute in one transaction and atomically enforce invariants. Cross-aggregate is eventual.
2. **One command writes one aggregate.** Two aggregates in the same transaction → boundary is wrong, or you need a saga / process manager.
3. **References across boundaries are IDs, not object pointers.** `Order` holds `customerId`, never `customer`. This is the seam that prevents aggregate collapse into one big god-cluster.
4. **Invariants live inside the aggregate** — enforced at construction (factory) and at every state-changing method. Not in services, not in validators, not in the database.
5. **The root is the only entry point.** External code cannot reach `aggregate.someChild.changeSomething()`; the root mediates every change.
6. **Aggregates fit in memory.** If loading a root materialises 10 000 children, split. See [boundary checklist](resources/boundary-checklist.md).
7. **One repository per aggregate root**, not per inner entity. Inner entities are accessed *through* the root.
8. **Domain events emitted by the aggregate, dispatched after commit.** Aggregate collects pending events; the persistence layer pulls and publishes them *after* the write commits. Otherwise events fire on rolled-back state.
9. **Domain is framework-free.** No persistence, DI, or transactional annotations on aggregates. Domain tests must not boot a database or DI container.

## Construction discipline

- **Private constructor + factory method.** All paths into the aggregate go through one guarded entry; invalid states are unconstructible.
- **State changes are intent-named methods, not setters.** `order.submit()`, not `order.setStatus(SUBMITTED)`. The aggregate decides which transitions are legal; callers describe intent.
- **Value objects encode constraints in types.** Lift primitives whose meaning matters (`Money`, `Email`, `OrderId`). The *language-level idiom* is owned by `code/clean-code/resources/objects-and-data.md`; this skill covers *which* primitives deserve the lift.

## Pattern roster

| Pattern | What it is | Where it lives |
|---|---|---|
| Aggregate | Cluster of entities sharing a transactional boundary; root mediates access. | Domain. |
| Aggregate root | The only legal entry point to an aggregate. | Domain. Repository defined per-root only. |
| Entity (non-root) | Identity inside an aggregate; reachable only through the root. | Domain. Never gets its own repository. |
| Value object | No identity; equality by value; immutable; encodes constraints in types. | Domain. Persistence translates at the boundary. |
| Repository | Loads and saves aggregate roots; abstracts persistence. | Interface in domain; implementation in infrastructure. |
| Domain event | Past-tense fact about something that happened inside an aggregate. | Defined in domain; emitted by aggregate; dispatched post-commit. |
| Factory | Construction that enforces invariants atomically. | Domain (typically companion / static creator on the root). |
| Domain service | Cross-aggregate orchestration that doesn't fit a single aggregate (rare). | Interface in domain; wired at the application boundary. |
| Application service | Thin orchestration: load → call → save. No business logic. | Application layer — where the transactional boundary lives, not on the aggregate. |

## Boundary checklist

Quick form. Open [resources/boundary-checklist.md](resources/boundary-checklist.md) for the diagnostic per item.

- [ ] Transactional invariants stay inside one aggregate
- [ ] Eventual rules cross via domain events, not direct calls
- [ ] The root is the only entry point
- [ ] Cross-aggregate references are IDs
- [ ] The aggregate fits in memory
- [ ] One command writes one aggregate per transaction

Two or more failing → the boundary is wrong.

## Quick red flags

- A service method is 50 lines of `if`s, DB reads, and conditional updates → transaction script masquerading as domain logic. Move rules onto the aggregate.
- Method signatures full of `String userId, String currency, Long amount` → primitive obsession at domain edges. Lift to value objects.
- Events published by services after the save call → races between commit and publish. Move events onto the aggregate; dispatch after commit.
- `setStatus(SUBMITTED)` called from multiple callers, each checking preconditions → setter-driven invariants. The aggregate decides transitions.
- `order.customer.address.city` in business code → cross-aggregate object reference. Reference by ID; load explicitly if needed.
- One save method writes two aggregates in a single transaction → boundary too large, or a missing process manager.

Each smell is unpacked with bad → good examples in [resources/anti-patterns.md](resources/anti-patterns.md).

## When tactical DDD is overkill

The honest test before adopting:

- Same validation rule appears in 3+ places and drifts? → tactical DDD pays off.
- Experts describe invariants in their own language the code doesn't enforce? → pays off.
- Bugs cluster around "the system reached a state I didn't think was possible"? → pays off.
- None of the above? → an anemic data class + framework repository is the honest shape. Don't gold-plate.

Tactical DDD is a tax that compounds in domains with real invariants and overfits everywhere else. Honest restraint here is what separates a senior modeller from a pattern-tourist.

## Resources

| Open when | Resource |
|---|---|
| Need depth on *why* — Evans/Vernon vocabulary, ubiquitous language, aggregate-vs-transaction | [resources/theory.md](resources/theory.md) |
| Reviewing a smell — anemic model, setter-driven invariants, cross-aggregate refs, etc. | [resources/anti-patterns.md](resources/anti-patterns.md) |
| Sizing a new or existing aggregate boundary | [resources/boundary-checklist.md](resources/boundary-checklist.md) |
| Tactical fixes aren't sticking — same issues keep returning across aggregates | [resources/ddd-strategic-bridge.md](resources/ddd-strategic-bridge.md) |

## Related skills

| Skill | This not that |
|---|---|
| `code/clean-code` (`objects-and-data.md`) | Class shape: anemic-vs-behaviour-rich, JPA-vs-aggregate, value-object idioms. This skill is the boundary-shape layer above. |
| `architecture/application/solid` | SOLID is how to arrange classes; tactical DDD assumes SOLID holds and adds the consistency-boundary discipline. |
| `architecture/application/grasp` | GRASP's Information Expert is parallel to aggregate root — same question, no bounded-context frame. |
| `ddd-strategic` (future) | Where bounded contexts go. This skill is the code *inside* one context once those lines are drawn. |

## Source

Adapted from E. Evans, *Domain-Driven Design* (2003), Part II; V. Vernon, *Implementing Domain-Driven Design* (2013). Stack-specific idioms (Kotlin / Spring / JPA) live in their respective categories.
