# Kotlin — Complexity Footguns

Kotlin-specific traps where the API reads fine but the cost or atomicity differs from what the syntax suggests. Each item is a real bug or wasted optimization that the language-agnostic body can't warn against.

## Sequences are single-pass when the source is

`asSequence()` on a `Collection` is reusable; the underlying list is the truth. But a Sequence from a generator (`sequence { yield(...) }`, `BufferedReader.lineSequence()`, `generateSequence { }`) is **one-shot**:

```kotlin
val lines = file.bufferedReader().lineSequence().filter { it.isNotBlank() }
val count = lines.count()          // OK
val first = lines.first()          // ⚠ throws — the source is consumed
```

If you build a pipeline and consume it more than once, materialise it first (`.toList()`) — once. Don't treat all `Sequence` values as repeatable.

## Several Sequence operations don't stream

`asSequence()` is often suggested for memory reasons. But these terminal/intermediate ops materialise the whole input before yielding anything:

- `sorted`, `sortedBy`, `sortedDescending` — full O(N) memory pass.
- `distinct`, `distinctBy` — builds a `HashSet` of all seen elements.
- `groupBy` — builds the full result `Map` before returning.
- `toList`, `toSet`, `toMap`, `count`, `last`, `max`, `min` — terminal materialisation by definition.

If the chain has any of these mid-way and the motivation for `asSequence()` was "stream to save memory," the saving is already gone. Use a `List` and accept the eager allocations — simpler and no clearer regression.

## `getOrPut` is NOT atomic on `ConcurrentHashMap`

The classic race:

```kotlin
val cache = ConcurrentHashMap<UUID, Value>()

// ⚠ Two threads can both observe absence and both put.
cache.getOrPut(key) { compute(key) }
```

`getOrPut` is a stdlib extension that does `get` then conditionally `put` — two operations. For thread-safe single-shot init, use the platform method directly:

```kotlin
cache.computeIfAbsent(key) { compute(key) }   // atomic on ConcurrentHashMap
```

Same trap with `put(key, value)` after a manual `containsKey` check. `getOrPut` is fine on non-concurrent maps; on a `ConcurrentHashMap` it silently breaks the atomicity guarantee the container offers.

## `data class` auto-hashes every property — including `var`

```kotlin
data class CartLine(var qty: Int, val sku: String)

val set = hashSetOf<CartLine>()
val line = CartLine(1, "A")
set.add(line)
line.qty = 2
set.contains(line)   // false — the entry is unreachable, still in the set
```

`data class` generates `equals`/`hashCode` from every property in the primary constructor. A `var` property mutated after `put`/`add` changes the hash; the entry becomes a leak.

If a data class is ever used as a `Map` key or `Set` element, all primary-constructor properties must be `val`. Mixing in a single `var` is a footgun waiting on a code path you didn't test.

## `associateBy` silently overwrites duplicates

```kotlin
val byCustomer = orders.associateBy { it.customerId }   // last wins on collision
```

If `customerId` isn't unique, you lose every order but the last per customer — with no error, no warning, no log. Two safer choices depending on intent:

```kotlin
// Expecting duplicates → group them.
val byCustomer: Map<UUID, List<Order>> = orders.groupBy { it.customerId }

// Expecting uniqueness → enforce it.
val byId = orders.associateBy { it.id }
require(byId.size == orders.size) { "duplicate order ids in input" }
```

Default to `groupBy` whenever uniqueness isn't part of the invariant the caller has already established.

## `buildList { }` over `mutableListOf().toList()`

```kotlin
// Two allocations + a copy of every element.
val out = mutableListOf<Int>().apply { … }.toList()

// One allocation; the builder's backing array is sealed in place.
val out = buildList { … }
```

`buildList` / `buildSet` / `buildMap` (Kotlin 1.6+) hand the builder's underlying array directly to the immutable view — no element copy. The cost difference is small per call but is free for the choosing.

## `IntArray` over `List<Int>` for numeric hot paths

`List<Int>` is `List<Integer>` in JVM bytecode; every element is a 16-byte boxed object on the heap. For tight numeric loops over thousands of values this dominates — both space and allocation axes.

```kotlin
val xs: IntArray = intArrayOf(…)   // int[]; no boxing
val xs: List<Int> = listOf(…)      // List<Integer>; each int boxed
```

Reach for `IntArray` / `LongArray` / `DoubleArray` when:

- The loop is hot (called often, or large N per call).
- Memory budget is tight (~10K+ elements).
- You don't need List operations on it.

Otherwise `List<Int>` is fine and clearer. Don't switch reflexively — only when the numeric loop is the profiled bottleneck.
