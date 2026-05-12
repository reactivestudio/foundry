---
name: algorithms-applied-backend
description: "Algorithmic thinking for backend / Kotlin / Spring engineers — Big-O reasoning (time, space, allocation), Kotlin collection complexity (List vs Sequence vs Array, mutable vs immutable), data-structure selection (HashMap vs TreeMap vs LinkedHashMap, ConcurrentHashMap), JPA query complexity (N+1, JOIN cost, index utilisation), sorting/searching/graph patterns applied to backend (pagination cursors, dependency resolution, request routing), Big-O-aware refactors. Use when assessing complexity of a piece of code, choosing a collection, designing a query, or in a code review questioning whether the algorithmic shape is right."
risk: safe
source: "custom — applied algorithms for Kotlin/Spring backend"
date_added: "2026-05-12"
---

# Applied Algorithms for Backend (Kotlin / Spring)

Most backend engineers don't write sort algorithms. They **pick** them, then live with the consequences. The skill is **complexity literacy**: knowing what's in the libraries, recognising algorithmic shape in business code, and refactoring O(N²) accidents.

> The fastest function is the one not called. The second fastest is the one with the right Big-O. The third fastest is the one with a tight constant factor. Optimise in that order.

## Use this skill when

- Code review: "what's the complexity of this loop?"
- Choosing a collection (`HashMap` vs `LinkedHashMap` vs `TreeMap` vs `ConcurrentHashMap`)
- Designing pagination (offset vs keyset/cursor)
- Designing a query (when JPA's `findAll().filter { }` is O(N²) over the DB)
- Implementing search, ranking, or dedup logic
- Refactoring slow code where the algorithm — not the framework — is the bottleneck
- Estimating worst-case for capacity planning
- Reasoning about correctness of concurrent / lock-free data structures

## Do not use this skill when

- The bottleneck is **the database**, not your code — see `database-design/resources/optimization.md`
- The bottleneck is **the JVM** (GC, allocation, JIT) — see `jvm-performance`
- The task is a true **competitive-programming algorithm** problem (Dijkstra, segment trees, FFT) — those rarely appear in backend code; if they do, fetch from a library
- You haven't measured — see `methodology-verification`. Don't optimise without numbers.

## Selective Reading Rule

| File | Description | When to read |
|---|---|---|
| `resources/big-o-and-collections.md` | Big-O notation, complexity classes, Kotlin/Java collection complexity (List/Set/Map/Sequence/Array, mutable vs immutable, thread-safe variants); when to pick which | Picking a data structure, reasoning about loop complexity |
| `resources/applied-patterns.md` | Pagination (offset vs keyset), deduplication, dependency resolution (DAG topological sort), set operations, sorting/merging, graph BFS/DFS as applied to business code (e.g., bounded context dependency); Kotlin idioms (Sequence vs List for chains) | Designing pagination, dedup, ordering, dependency resolution |
| `resources/refactoring-quadratic.md` | Diagnosing O(N²) accidents in business code; "loop within a loop with `contains`" anti-pattern; converting to indexed lookup, batched operations, set intersection; before/after benchmarks; JPA-specific N+1 as algorithmic shape | Refactoring slow code; reviewing for complexity issues |

## Core principles

1. **Know your collection's complexity.** Most performance bugs are picking the wrong collection. `list.contains(x)` is O(N); `set.contains(x)` is O(1) for `HashSet`. The fix is changing one line.
2. **Don't optimise without measuring.** Asymptotics matter at scale. Constants matter at small N. JMH (see `jvm-performance/resources/jit-and-warmup.md`) is the only honest measurement.
3. **Pagination is an algorithm, not a UI concern.** Offset pagination is O(offset + limit); doesn't scale. Cursor pagination is O(log N + limit); does.
4. **The same algorithm has different complexity in different containers.** `List.size()` is O(1); `Iterable.count()` may be O(N). Read the API contract.
5. **Most "slow Kotlin" is "wrong collection".** Map-instead-of-loop, set-instead-of-list-contains, primitive-array-instead-of-`List<Int>` — these are the wins.
6. **JPA `findAll().filter { it.x == y }` is unconditionally wrong.** Pulls all rows, filters in memory. That's not O(filter); it's O(rows in DB).
7. **The right primitive for sorted unique data is `TreeSet` / `TreeMap`** — not `List` you re-sort every time.
8. **Lazy collections (`Sequence`, streams) save allocations**, not algorithm time. Chain of `.map.filter.map` over a million-item `List` allocates many intermediate lists. Same chain over a `Sequence` allocates once.

## Anti-patterns

- **`list.contains(...)` inside a loop.** O(N²). Convert to `Set` if collection is read-many.
- **`map.values.find { ... }` instead of indexing by the field.** Linear scan when a separate map keyed by that field would be O(1).
- **`for (x in collection) { for (y in collection) ... }` without checking what's actually compared.** Quadratic. Often dedupable or indexable.
- **`list.sortedBy { ... }` inside a loop.** Re-sorts every iteration. Sort once outside, or use `TreeSet`.
- **Offset pagination on large tables.** `SELECT * FROM orders LIMIT 20 OFFSET 100000` — Postgres still reads 100000 rows. Use keyset.
- **`when (event) { is X -> ...; is Y -> ...; else -> ... }` with 30 cases in a hot path.** No exhaustiveness compile error. Use sealed + exhaustive `when` (compile error if not exhaustive).
- **`Map.get(k) ?: defaultValue` followed by `Map.put(k, computed)`.** Two map operations. Use `Map.getOrPut(k) { compute() }`.
- **`stream().collect(toList()).stream()...`** — collecting then re-streaming wastes the chain. Compose lazily.
- **Joining lists with `+`** in a loop. `list1 + list2` allocates a new list each time. Use `.flatMap { it }` or `MutableList.addAll`.
- **`ArrayList<Int>` for hot numeric loops.** Boxing every element. Use `IntArray`.
- **N+1 in JPA** — see `database-design`. Same algorithmic shape as `for o in orders; o.items` triggering `SELECT items WHERE o = ?` per order.

## What's in the standard library — quick reference

```kotlin
// Lookups (Set / Map of values)
HashSet                 // O(1) avg contains/add/remove; insertion-unordered
LinkedHashSet           // O(1) + maintains insertion order
TreeSet                 // O(log N), sorted by compareTo / Comparator

HashMap                 // O(1) avg get/put/remove
LinkedHashMap           // O(1) + insertion or access order
TreeMap                 // O(log N), sorted keys

ConcurrentHashMap       // O(1) avg, thread-safe (fine-grained locking)

// Ordered collections (List)
ArrayList               // get O(1), add O(amortised 1), remove O(N)
LinkedList              // get O(N), add at end O(1), remove O(1) if cursor known
ArrayDeque              // O(1) at both ends; replaces LinkedList for FIFO/LIFO

// Sorted structures
PriorityQueue           // O(log N) peek/poll; min-heap by default

// Concurrent
ConcurrentLinkedQueue   // lock-free FIFO
LinkedBlockingQueue     // blocking, bounded or unbounded
ArrayBlockingQueue      // blocking, bounded fixed-size

// Sequences
Sequence                // lazy, single-pass; chain of operations evaluates once per element
Flow                    // suspend-aware lazy stream (coroutines)
```

When in doubt: `HashMap`/`HashSet` for set membership; `ArrayList` for ordered storage; `ConcurrentHashMap` for shared mutable state.

## Big-O for Kotlin operations (common surprises)

| Operation | Complexity | Notes |
|---|---|---|
| `List.indexOf(x)` | O(N) | Linear scan |
| `List.contains(x)` | O(N) | Linear scan |
| `Set.contains(x)` (HashSet) | O(1) avg | Use for "is in" |
| `Map.containsKey(k)` (HashMap) | O(1) avg | |
| `Map.containsValue(v)` (HashMap) | O(N) | Linear scan of all values |
| `List.removeAt(i)` (ArrayList) | O(N) | Shifts subsequent elements |
| `List.removeLast()` (ArrayList) | O(1) | No shift |
| `List.add(x)` (ArrayList) | O(1) amortised | Occasional O(N) resize |
| `List.add(0, x)` (ArrayList) | O(N) | Inserts at front, shifts |
| `Map.entries.first()` | O(1) | But iteration order depends on map type |
| `List.sortedBy { ... }` | O(N log N) | Creates new list |
| `List.distinct()` | O(N) | Uses internal HashSet |
| `List.groupBy { ... }` | O(N) | Returns Map of buckets |
| `List.zip(other)` | O(min(this.size, other.size)) | |
| `List.partition { ... }` | O(N) | Single pass, two lists |
| `String.contains(substring)` | O(N × M) naive | Underlying may be smarter (Boyer-Moore) |
| `Sequence.toList()` | O(N) | Materialises lazy sequence |
| `Map.computeIfAbsent(k) { f }` | O(1) | Atomic in `ConcurrentHashMap` |

## Common complexity classes you'll meet

| Big-O | Real-world example |
|---|---|
| O(1) | HashMap get; field access; ArrayList[i] |
| O(log N) | TreeMap operations; binary search; B-tree index lookup |
| O(N) | List scan; copy; sum; filter |
| O(N log N) | Sorting; building a balanced tree from N elements |
| O(N²) | Nested loop with contains; bubble sort; naive substring search |
| O(N³) | Three nested loops; Floyd-Warshall on small graphs |
| O(2^N) | Naive recursion over all subsets; exponential blow-up |

For backend code: O(1), O(log N), O(N), O(N log N) are fine. O(N²) needs justification (small N? data-bounded?). Anything worse should never reach production without a strong reason.

## Related skills

- `database-design/resources/optimization.md` — algorithmic complexity of queries, JPA N+1
- `jvm-performance` — when algorithmic complexity is fine but constants kill (allocation, JIT)
- `caching-strategies-spring` — when memoization beats algorithm optimisation
- `clean-code/resources/smells-catalog.md` — long methods often hide algorithmic mistakes
- `methodology-verification` — measure before/after with JMH (see jvm-performance)
- `architecture-patterns` — sometimes the algorithm choice is determined by layout (Onion / event-driven)
- `debugging-systematic` — apply it to perf problems too

## Limitations

- This is **applied algorithms**, not competitive programming. No segment trees, suffix arrays, or FFT details. Use a library if you genuinely need them.
- Constants matter at small scale. At N = 10, O(N²) is still 100 operations — often fine. At N = 1M, even a 5× constant-factor difference matters.
- Stop and ask if the **N you're optimising for** is unknown — different N picks different algorithms.
