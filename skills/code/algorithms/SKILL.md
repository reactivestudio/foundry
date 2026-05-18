---
name: algorithms
description: "Name Big-O complexity, pick collections, refactor quadratic loops. NOT for competitive algorithms."
---

# Algorithms

Backend engineers rarely write algorithms — they pick them, then live with the consequences. This skill enforces a **mechanical pre-flight audit** against any code-review prompt, plus a vocabulary of named patterns so catches are verifiable.

Resources by axis: [practices](resources/practices.md) for general algorithmic-shape patterns, [kotlin](resources/kotlin.md) for language-specific footguns, [spring](resources/spring.md) for JPA / Spring Data specifics, [persistence](resources/persistence.md) for cache and idempotency correctness, [theory](resources/theory.md) for residual nuance.

## When to use

- Code review of services / handlers — catch algorithmic-shape bugs before merge.
- Picking a collection, designing pagination, deduplication, top-K, or aggregation.
- Refactoring slow code where the algorithm — not the framework or JVM — is the bottleneck.
- Capacity estimation under realistic N.

## Pre-flight checklist

For any code under review, walk this list. Each line is a mechanical audit, not a discipline. Route flagged items to the named pattern in resources.

1. **Every `repo.findAll()`** — name the production N or flag. Predicate that could go to SQL → `findAll-and-filter trap`.
2. **Every loop containing a repo / service / HTTP call** — bulk variant exists? → `N+1 cascade` + `bulk-fetch missed`.
3. **Every `repo.findAll()` inside a loop** → `cartesian repo dance`. Almost always the worst trap.
4. **Every `list.first { f == x }` / `.any` / `.find` in a loop** → `list.first in loop`; index by `f` once outside.
5. **Every `data class` used as Map / Set key** — all properties `val`? Any `var` → `mutable-key cache phantom`.
6. **Every `ConcurrentHashMap.getOrPut`** → `getOrPut atomic illusion`; use `computeIfAbsent`.
7. **Every `containsKey + put` / read-modify-write on a Map** → `containsKey-then-put`; use `merge` / `compute`.
8. **Every `associateBy { f }`** — is `f` uniquely keyed? If not → `associateBy silent dataloss`; usually `groupBy`.
9. **Every cache** — list every param the result depends on; each must be in the key. Missing → `cache-key incomplete`.
10. **Every idempotency check** — keyed by *message* identity (event id / version), not aggregate identity. Else → `idempotency-key incomplete`.
11. **Every `sort-then-take-K`** — is N bounded? Bounded → leave (false positive). Unbounded → top-K heap or push to DB.
12. **Every `+=` in loop on String / List / Set** — quadratic; mutable accumulator / `buildString` / `joinToString`.
13. **Every `.asSequence()` already in code** — chain ≤ 2 steps over bounded N → remove the wrap → `sequence-reflex removal`.
14. **Every `@Transactional` on a read** — has `readOnly = true`? Else → `@Transactional readOnly missing`.
15. **Every `@Transactional` over a save-loop** — chunked / `flush + clear`? Else → `Hibernate session swell`.
16. **Every `Pageable` + `JOIN FETCH`** → `Pageable in-memory fallback`.
17. **Every nested loop over the same collection with time-proximity check** → `time-window pairs`; sort + sliding window.
18. **Every nested loop where N is provably small (≤ 100)** — false positive; **document the bound** at the call site.

## Named patterns by resource

Use names verbatim in output — verifiable catches.

- [practices](resources/practices.md): *findAll-and-filter trap, N+1 cascade, bulk-fetch missed, cartesian repo dance, cartesian-with-filter, list.first in loop, findAll-then-first, sort-then-take-K (active vs bounded-N false positive), bounded-O(N²) acceptable, time-window pairs.*
- [kotlin](resources/kotlin.md): *getOrPut atomic illusion, containsKey-then-put, mutable-key cache phantom, associateBy silent dataloss, sequence-reflex removal.*
- [spring](resources/spring.md): *Hibernate session swell, @Transactional readOnly missing, @Transactional batch scope, Pageable in-memory fallback, stream-doesnt-push, top-N derived method, Sort.by without index, lazy-init-on-serialize, Specifications count-query.*
- [persistence](resources/persistence.md): *cache-key incomplete, idempotency-key incomplete, cache write-through staleness, N+1 across DTO graph, cache-unbounded.*

## Common false positives — leave them

Tempting refactors that **don't earn their cost**:

- `sort-then-take-K` on bounded N (page size, items per order) — heap is slower at small N.
- Bounded `O(N²)` over ≤ 100 elements — leave; document the bound.
- Simple `when` / `if-else` over a small enum — don't refactor to strategy.
- Clear averaging / null-check idioms (`if (xs.isEmpty()) 0.0 else xs.sumOf { … } / xs.size`) — don't replace with `takeIf` chains.
- Plain `for` over `.forEach` when the body has side effects or early returns.
- `.map { … }.toList()` on a small list — don't add `.asSequence()`.

If review time goes to these, the review is over-fitting.

## Beyond the algorithmic axis — flag, don't suppress

This skill is narrow. Adjacent concerns will surface in the same code: API-contract leaks (audit log returned in response DTO), magic strings, security, durability of in-process state, broken `equals` on non-data classes. **Flag each in one sentence and defer; don't try to solve them here, and don't suppress them.** A review that catches every algorithmic trap but misses an obvious contract bug is a worse review.

## When NOT to use

- True algorithm problems (Dijkstra, segment trees, FFT) — use a library.
- JVM tuning (GC, JIT, escape analysis) — different skill.
- Database tuning (query plans, indexes, statistics) — DB has its own Big-O story.
- Concurrency primitives design (thread pools, lock-freedom, backpressure) — adjacent skill.

## Source

Distilled from S. Skiena, *The Algorithm Design Manual* 3e (2020); T. Roughgarden, *Algorithms Illuminated* (2017–2020); M. Kleppmann, *Designing Data-Intensive Applications* (2017); J. Bloch, *Effective Java* 3e (2018). Spring/JPA section informed by the Hibernate User Guide and V. Schreiner's *High-Performance Java Persistence* 3e.
