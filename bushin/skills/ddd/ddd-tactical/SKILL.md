---
name: ddd-tactical
description: "DDD tactical: aggregates, domain events, value objects, anemic models. NOT for pure CRUD."
---

# DDD Tactical

Code-level discipline that puts business rules where the data is, so invariants can't be bypassed by services or callers. Operates one layer above class-shape (anemic-vs-behaviour-rich, JPA-vs-aggregate, value-object idioms — owned by `code/clean-code/resources/objects-and-data.md`). Once class shapes are right, this skill says **which classes cluster, where the transactional boundary sits, and how state changes leave the cluster**.

## When to use

- Refactoring an anemic model (getter/setter bags) into behaviour-rich aggregates.
- Designing an aggregate boundary — what's *in* the cluster, what's referenced *by ID* across boundaries.
- Placing domain events — where they fire, who collects them, when they dispatch.
- Defining a repository contract — one per aggregate root, not per entity.

## When NOT to use

- **Pure CRUD without invariants** — see [Restraint gate](#restraint--what-it-means-and-what-it-doesnt).
- **Bounded contexts not yet drawn** — strategic comes first; without it you're modelling in the dark.
- **Between-context translation** (anti-corruption layer, published language) — `ddd-strategic` territory; bridge at [resources/ddd-strategic-bridge.md](resources/ddd-strategic-bridge.md).
- **JPA persistence shape** — domain ≠ persistence. See `code/clean-code/resources/objects-and-data.md`.
- **Generic "which class owns this method"** — `architecture/application/grasp` (Information Expert).

## Review procedure — the 10-point scan

When reviewing a domain-touching diff, walk **all ten checks in order**. **No silent skips.** For each step: either name the smell + route via the smell table below, or write "not found". For grep patterns, camouflages, and clean shapes per step, open [resources/diagnostic-playbook.md](resources/diagnostic-playbook.md).

1. **Construction** — `Entity().apply { ... }` or public empty ctor → no factory.
2. **State type** — `var status: String` / status string literals → state-as-string.
3. **Lifecycle** — 3+ nullable `*At: Instant?` on aggregate → state-as-dates.
4. **Mutations** — `entity.field = ...` outside private aggregate methods → setter-driven invariant.
5. **References** — aggregate field holds another aggregate object (not ID) → cross-agg ref.
6. **Repositories** — `*Repository` injected for an entity that always lives inside another → one-repo-per-inner.
7. **TX boundary** — `@Transactional` writes ≥2 distinct aggregate types → cross-agg TX save.
8. **Event timing** — `publishEvent(...)` inside `@Transactional` before commit → events on rollback.
9. **Invariant placement** — `if (...) throw` in service using one aggregate's data → move to that aggregate.
10. **Primitives & projections** — `String *Id`, `Long amount`+`String currency`, accumulated `var total*` → VO lift / projection.

**Diagnosis order:** foundation (1-4) → boundary (5-8) → polish (9-10). Foundation findings are **not "cosmetic"** — they are how the boundary leaks later. Apply restraint to *inventing* patterns, not to *finding* listed ones.

## Symbol-level smell table

| Code symbol | Smell | Open |
|---|---|---|
| `EntityName().apply { ... }`, empty/public ctor | No factory; invalid states constructible | anti-patterns.md #1 |
| `var status: String` + `status = "X"` from outside | State-as-string + setter-driven invariant | anti-patterns.md #2 |
| 3+ nullable `*At: Instant?` on an aggregate | State-machine-as-dates | anti-patterns.md #10 |
| `@ManyToOne var x: OtherAgg?` field | Cross-aggregate object reference | anti-patterns.md #3 |
| `@OneToMany ... fetch = EAGER` on user-driven collection | Aggregate loads thousands | anti-patterns.md #4 |
| `*Repository` for entity that never lives without parent | One-repo-per-inner-entity | anti-patterns.md #5 |
| `*Service { ...save... save... }` 30+ lines | Transaction script | anti-patterns.md #6 |
| `publishEvent(...)` inside `@Transactional` | Events before commit | anti-patterns.md #7 |
| `Long amount` + sibling `String currency` in signature | Primitive obsession (Money) | anti-patterns.md #8 |
| Two `repo.save(...)` for different aggregates in one TX | Cross-agg TX save | anti-patterns.md #9 |
| `var total*: Long` accumulated on aggregate | Running scalar; should be projection | anti-patterns.md #11 |
| `@Entity` / `@OneToMany` / `@Component` on domain class | Domain depends on framework | anti-patterns.md #12 |
| `*Id: String` + `@ManyToOne var ref: Other?` same class | Double FK source-of-truth (JPA pitfall) | anti-patterns.md #12 |

## Core principles

1. **Aggregate = transactional consistency boundary; one command writes one aggregate.** Cross-aggregate is eventual. Two aggregates in one TX → boundary is wrong, or a saga / process manager.
2. **References across boundaries are IDs, not object pointers.** `Order` holds `customerId`, never `customer`. Prevents aggregate collapse into one big god-cluster.
3. **Invariants live inside the aggregate** — enforced at construction (factory with private ctor) and at every intent-named state-changing method. The root is the only entry point; external code cannot reach `aggregate.child.mutate()`.
4. **Aggregates fit in memory.** If loading a root materialises 10 000 children, split.
5. **One repository per aggregate root.** Inner entities are accessed *through* the root, never via their own repo.
6. **Domain events emitted by the aggregate, dispatched after commit.** Aggregate collects pending events; persistence layer publishes them *after* the write commits — never inside the TX.
7. **Domain is framework-free.** No persistence, DI, or transactional annotations on aggregates. Domain tests must not boot a DB or DI container.

## Pattern roster

| Pattern | Role |
|---|---|
| Aggregate / root | Cluster sharing a transactional boundary; root mediates all access. |
| Entity (non-root) | Identity inside an aggregate; reachable only through the root; no separate repo. |
| Value object | No identity; equality by value; immutable; encodes constraints in types. |
| Repository | Loads and saves aggregate roots; interface in domain, implementation in infra. |
| Domain event | Past-tense fact emitted by aggregate, dispatched post-commit. |
| Factory | Construction that enforces invariants atomically; private ctor + named creator. |
| Domain service | Cross-aggregate orchestration not fitting one aggregate (rare). |
| Application service | Thin orchestration: load → call → save. Transactional boundary lives here. |

## Boundary checklist

Two or more failing → boundary is wrong. Diagnostic per item in [resources/boundary-checklist.md](resources/boundary-checklist.md).

- [ ] Transactional invariants stay inside one aggregate
- [ ] Eventual rules cross via domain events, not direct calls
- [ ] The root is the only entry point
- [ ] Cross-aggregate references are IDs
- [ ] The aggregate fits in memory
- [ ] One command writes one aggregate per transaction

## Restraint — what it means and what it doesn't

**Means:** code with no invariants (config tables, admin views, projection read-models) does not need aggregates, factories, value objects. An anemic data class + framework repository is the honest shape.

**Does NOT mean:** when the listed anti-patterns are PRESENT in code that HAS invariants — money, identity, lifecycle states, business-named rules — deprioritise them as "cosmetic". Primitive obsession in a money/identity field is a latent bug, not a style preference. A `var status: String` mutated from callers is a missing invariant, not a refactor opportunity.

The 10-point scan applies regardless. Restraint is **avoid inventing patterns the code doesn't have**, not **avoid finding patterns it does**.

## Resources

| Open when | Resource |
|---|---|
| Reviewing a domain-touching diff — grep patterns, camouflages, clean shapes per scan step | [resources/diagnostic-playbook.md](resources/diagnostic-playbook.md) |
| Investigating a specific smell — bad → good in vanilla Kotlin | [resources/anti-patterns.md](resources/anti-patterns.md) |
| Sizing a new or existing aggregate boundary | [resources/boundary-checklist.md](resources/boundary-checklist.md) |
| Depth on *why* — Evans/Vernon vocabulary, ubiquitous language, aggregate-vs-transaction | [resources/theory.md](resources/theory.md) |
| Tactical fixes aren't sticking — same issues keep returning across aggregates | [resources/ddd-strategic-bridge.md](resources/ddd-strategic-bridge.md) |

## Related skills

| Skill | This not that |
|---|---|
| `code/clean-code` (`objects-and-data.md`) | Class shape: anemic-vs-behaviour-rich, JPA-vs-aggregate, VO idioms. This skill is the boundary-shape layer above. |
| `architecture/application/solid` | SOLID is how to arrange classes; tactical DDD assumes SOLID holds and adds consistency-boundary discipline. |
| `architecture/application/grasp` | GRASP's Information Expert is parallel to aggregate root — same question, no bounded-context frame. |
| `ddd-strategic` | Where bounded contexts go. This skill is the code *inside* one context once those lines are drawn. |

## Source

Adapted from E. Evans, *Domain-Driven Design* (2003), Part II; V. Vernon, *Implementing Domain-Driven Design* (2013). Stack-specific idioms (Kotlin / Spring / JPA) live in their respective categories.
