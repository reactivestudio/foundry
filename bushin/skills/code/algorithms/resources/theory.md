# Theory — Big-O Nuance Beyond the Obvious

This file covers the parts of complexity reasoning that *aren't* in the standard Big-O cheat sheet — the ones Claude tends to gloss past.

## Three axes, not one

- **Time** — how ops grow with N. The classic axis.
- **Space** — how much memory grows with N.
- **Allocation** — how many *objects* per op. Distinct from space: the same total memory can come from one big array or a million tiny boxes, with very different GC cost on the JVM.

Optimising one without checking the others trades one bottleneck for another. "Performance" answers must name which axis they're improving.

## The regime change matters more than the formula

Everyone knows O(N²) is "bad". The non-obvious part: **the same algorithm changes regime as N grows**. O(N²) at N=100 is 10⁴ ops — instant. At N=10⁵ it's 10¹⁰ ops — minutes. Same code, different production reality.

When reasoning about a piece of code, name the **N at peak**, not the N in the test fixture. If the N you'll see is bounded and small, the "bad" algorithm is fine. If it grows, the "fine" algorithm becomes a load test in disguise.

## Amortized hides the spike

`ArrayList.add` is O(1) amortized; one in every several thousand calls is O(N) when the array resizes. Averaged: fine. Tail-latency p99: not. Under bounded latency, reserve capacity (`ArrayList(expectedSize)`) so resizes don't happen mid-request.

## Same operation, different container

The same-looking call can be O(1) or O(N) depending on the type. The ones that bite:

- `List.size()` O(1) vs **`Iterable.count()` O(N)** — accepting an `Iterable` parameter and calling `count()` is a hidden scan.
- `List.last()` O(1) on `ArrayList` vs **O(N) on `Sequence`** — chaining `.last()` after `asSequence()` defeats laziness.
- `Map.containsKey` O(1) on `HashMap` vs **O(log N) on `TreeMap`** vs **O(N) for `containsValue` on any map** — no map indexes its values.
- `List.removeAt(0)` O(N) on `ArrayList` vs O(1) on `ArrayDeque` — popping from the front is a different operation by container.

When in doubt about a call inside a hot loop, read the actual interface — not the variable name.

## The three sorted/concurrent maps exist for one reason each

If your problem doesn't match, use `HashMap`. Reaching for the others by reflex is the misuse.

- **`LinkedHashMap`** — iteration order is *load-bearing*. LRU caches (access-order constructor), reproducible debug output, ordered API responses.
- **`TreeMap`** — you query by *range or rank*: `ceilingKey`, `firstEntry`, `subMap`. If you only `get`/`put`, `HashMap` is faster.
- **`ConcurrentHashMap`** — shared mutable state. Has atomic `computeIfAbsent`, `merge`, `compute` that close the `if (!contains) put` race in one op. The standard for caches, registries, counters. `Collections.synchronizedMap` is coarse-grained and almost always wrong.

## Lazy ≠ faster — it changes allocation, not complexity

A chain `list.filter { }.map { }.filter { }` over a `List` allocates intermediate lists at each step. Over a `Sequence`, one. Time complexity is the same.

`asSequence()` wins only when **all three** hold:
- Three or more steps in the chain.
- Input is large (~1K+ elements).
- Early termination (`first`, `take`, `any`) — can short-circuit before materialising.

For a 5-item, 2-step pipeline, eager is faster (no wrapping overhead) *and* clearer. Don't suggest `asSequence()` as a performance fix without checking these three conditions.

## Bounded O(N²) is sometimes the right call

When N is provably small — items in one order, codes in an enum, days in a week — `O(N²)` is fine. The constants of a tight nested loop beat building a `HashMap`.

The discipline that makes this safe: **document the bound at the call site**.

```kotlin
// Acceptable: bundle promotions are capped at 50 items per order (BundleService.MAX_ITEMS).
for (i in items.indices) for (j in i + 1 until items.size) {
    checkConflict(items[i], items[j])
}
```

Without the comment, the next reader either (a) refactors speculatively because "nested loop is bad" — wasting effort, possibly introducing bugs — or (b) leaves a real quadratic problem unfixed when the bound is later lifted. The comment is the cheapest line in the function and pays for itself the first time someone reads it.

A refactor without checking the bound is the same mistake in the other direction. Always ask: *what's N here, and what bounds it?*

## Algorithms and data structures are one decision

"Switch `List` to `Set`" *is* the algorithm change, even though no logic moved. In backend code, container choice is algorithm choice; most algorithm improvements are one-line container edits.

Corollary: look at the container before designing a new algorithm. If `list.contains` shows up in a loop body, the algorithm is wrong because the container is wrong.
