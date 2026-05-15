---
name: algorithms
description: "Name Big-O complexity, pick collections, refactor quadratic loops. NOT for competitive algorithms."
---

# Algorithms

Backend engineers rarely *write* algorithms — they pick them, then live with the consequences. This skill is **complexity literacy**: naming the shape of a piece of code in seconds, choosing the standard-library primitive that matches it, and recognizing the small set of quadratic accidents that cause most real-world slowdowns.

Resources by axis: [theory](resources/theory.md) for complexity nuance beyond standard Big-O, [practices](resources/practices.md) for named anti-patterns with the one-line fix, [kotlin](resources/kotlin.md) for language-specific footguns (Sequence pitfalls, atomicity, data-class hashing). Open the relevant file when reasoning about a specific question.

## When to use

- Code review: "what's the complexity of this loop?" or "is this fast enough at production N?"
- Picking a collection — when `List` / `Set` / `Map` / sorted / concurrent each fit differently.
- Designing pagination, deduplication, top-K, or aggregation over expected-to-grow data.
- Refactoring slow code where the **algorithm**, not the framework, is the bottleneck.
- Capacity estimation — "if N goes from 10K to 1M, does this still work?"

## The big four

Acceptable backend complexities, in descending order of preference: **O(1) → O(log N) → O(N) → O(N log N)**. Anything worse — O(N²), O(N³), exponential — demands a written justification: bounded N, one-off batch, or a small known input. ([theory](resources/theory.md))

## Five shapes → library primitives

Most backend code is one of these. Map the shape to the primitive **before** writing anything custom.

| Shape | Primitive | Cost |
|---|---|---|
| Lookup by key / membership | `HashMap` / `HashSet` (`Tree*` if sorted) | O(1) avg / O(log N) |
| Pagination over a growing table | Keyset / cursor (not offset) | O(log N + limit) |
| Deduplication | `distinct()` / `toSet()` | O(N) |
| Top-K from N | `PriorityQueue` of size K | O(N log K) |
| Group + aggregate | `groupBy { }.mapValues { }` or SQL `GROUP BY` | O(N + groups) |

Re-implementing any of these is almost always a mistake. ([practices](resources/practices.md))

## Procedure

1. **Name the largest plausible N.** If you can't, stop — you don't know the algorithm yet. Worst case in production, not the test fixture.
2. **Identify the hot operation.** What runs once per outer iteration? Lookup, comparison, write, round-trip? That's the cost driver.
3. **Read the container's API contract.** `List.contains` is O(N); `Set.contains` is O(1). Same call, different shape. ([theory](resources/theory.md))
4. **If the shape is wrong, change the container — not the algorithm.** `List` → `Set` is one line and turns O(N²) into O(N). ([practices](resources/practices.md))

## Restraint defaults

Most "performance work" makes code busier without making it faster. Default answers when tempted:

- **Optimize a slow loop?** No, until you've **profiled** it. The hot path is rarely where you think. Optimizing the wrong loop costs reading effort and buys nothing.
- **Suggest `asSequence()` / `stream()` "for performance"?** No. Sequences change *allocation*, not time complexity. Only win: large N + many steps + early termination. ([theory](resources/theory.md))
- **Replace a clear O(N²) when N is bounded and small?** No. Tight nested loops over 10–100 items are fine and readable. Document the bound (`// at most 100 items per order`); don't refactor. ([practices](resources/practices.md))
- **Switch `List` to `Set` "to be safe"?** No, unless you actually do `contains` / `find` on it. A `Set` you only iterate is a `List` with weaker ordering guarantees and more hashing.

Asymptotics always win at scale; constants always win at small N. Don't conflate the two regimes.

## Anti-pattern signatures

One-line smell each. Full fix in [practices.md](resources/practices.md). Listed in order of how often they slip past code review.

- `list.first { it.id == other.id }` (or `.any { it.x == y }`) inside a loop → O(N×M). Build an indexed `Map` / `Set` once outside.
- `sortedBy { keyDependentOnLoopVar }` inside a loop → re-sorts every iteration. Top-K heap if you only need K.
- Offset pagination on a table that will exceed ~1K rows → O(offset + limit). Use keyset/cursor.
- N round-trips (DB / HTTP / MQ) inside a loop → N+1, even when each call is O(1). Bulk-fetch.
- `repo.findAll().filter { ... }` → O(rows in table). Push the predicate to SQL/index.
- `list.contains` / `list.removeAll(otherList)` / `result = result + x` / string concat in a loop → all O(N²); reach for `Set`, `removeIf`, mutable accumulator, `buildString`.

## When NOT to use

- **True algorithm problems** (Dijkstra, segment trees, FFT, graph isomorphism) — rare in backend; reach for a library (JGraphT, etc.) when they appear.
- **JVM tuning** — GC, JIT, escape analysis. Different skill; complexity is fine but constants kill.
- **Database tuning** — query plans, indexes, statistics. The DB has its own Big-O story; this skill stops at "push the predicate to SQL".
- **Concurrency design** — thread pools, lock-freedom, backpressure. Algorithmic shape matters there too, but isn't the primary concern.

## Source

Distilled from S. Skiena, *The Algorithm Design Manual* 3e (2020); T. Roughgarden, *Algorithms Illuminated* (2017–2020); M. Kleppmann, *Designing Data-Intensive Applications* (2017); J. Bloch, *Effective Java* 3e (2018), items on collections and streams.
