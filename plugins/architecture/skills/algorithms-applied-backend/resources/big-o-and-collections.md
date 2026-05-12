# Big-O and Collections — Kotlin/JVM

Complexity literacy. Picking the right structure. Common surprises.

---

## 1. Big-O cheat sheet

**Time complexity** = how the operation cost grows with input size N.

| Class | Growth | Tolerable at N ≈ |
|---|---|---|
| O(1) | Constant | Any N |
| O(log N) | Doubling N adds one step | Any N (10^18 → 60 steps) |
| O(N) | Linear | 10^7-10^8 per second in hot loop |
| O(N log N) | "N log N" — sorts | 10^6 fine, 10^8 borderline |
| O(N²) | Quadratic | 10^4 fine, 10^5 painful, 10^6 dead |
| O(N³) | Cubic | 500 fine, 1000 painful |
| O(2^N) | Exponential | N ≤ 20-25 max |
| O(N!) | Factorial | N ≤ 12 |

**Space complexity** = how memory grows. Often forgotten. A "constant time" hash lookup uses O(N) memory in the map.

**Allocation complexity** (JVM-specific) = how many objects are allocated. Distinct from time/space. Inner loops that allocate per iteration → GC pressure even if Big-O is fine.

---

## 2. Counting operations — practical examples

```kotlin
// O(N) — single pass
fun sum(xs: List<Int>): Int {
    var s = 0
    for (x in xs) s += x      // each element visited once
    return s
}

// O(N²) — nested loop
fun hasDuplicate(xs: List<Int>): Boolean {
    for (i in xs.indices) {
        for (j in i+1 until xs.size) {
            if (xs[i] == xs[j]) return true
        }
    }
    return false
}

// O(N) — same answer with HashSet
fun hasDuplicateFast(xs: List<Int>): Boolean {
    val seen = HashSet<Int>(xs.size)
    for (x in xs) {
        if (!seen.add(x)) return true   // add returns false if already present
    }
    return false
}

// O(N log N) — sort
fun sortByCreatedAt(orders: List<Order>) = orders.sortedBy { it.createdAt }

// O(N²) — naive dedup with contains
fun dedup(xs: List<Order>): List<Order> {
    val out = mutableListOf<Order>()
    for (x in xs) {
        if (!out.contains(x)) out += x   // contains is O(N) → O(N²) total
    }
    return out
}

// O(N) — same with Set
fun dedupFast(xs: List<Order>): List<Order> = xs.distinct()
```

---

## 3. Kotlin collection complexity table

### Sets

| Collection | contains | add | remove | iteration order |
|---|---|---|---|---|
| `HashSet` | O(1) avg | O(1) avg | O(1) avg | Insertion-unordered |
| `LinkedHashSet` | O(1) avg | O(1) avg | O(1) avg | Insertion order |
| `TreeSet` | O(log N) | O(log N) | O(log N) | Natural / comparator |
| `setOf(...)` (immutable) | O(1) avg | — | — | Implementation-specific (often LinkedHashSet) |

### Maps

| Collection | get | put | remove | iteration order |
|---|---|---|---|---|
| `HashMap` | O(1) avg | O(1) avg | O(1) avg | Unordered |
| `LinkedHashMap` | O(1) avg | O(1) avg | O(1) avg | Insertion or access |
| `TreeMap` | O(log N) | O(log N) | O(log N) | Natural / comparator |
| `ConcurrentHashMap` | O(1) avg | O(1) avg | O(1) avg | Unordered, thread-safe |
| `Collections.synchronizedMap(...)` | O(1) avg + lock | O(1) avg + lock | O(1) avg + lock | Coarse-grained lock; avoid |

### Lists

| Collection | get(i) | add(end) | add(front) | remove(end) | remove(front) |
|---|---|---|---|---|---|
| `ArrayList` (`mutableListOf`) | O(1) | O(1) amortised | O(N) | O(1) | O(N) |
| `LinkedList` | O(N) | O(1) | O(1) | O(1) | O(1) |
| `ArrayDeque` | O(1) | O(1) | O(1) | O(1) | O(1) |
| `CopyOnWriteArrayList` | O(1) | O(N) | O(N) | O(N) | O(N) |

`ArrayList` is the default. `LinkedList` is almost always worse (cache-unfriendly, bigger memory, slower in practice). `ArrayDeque` is the right deque.

### Queues

| Collection | offer | poll | peek | notes |
|---|---|---|---|---|
| `ArrayDeque` | O(1) | O(1) | O(1) | Not thread-safe |
| `PriorityQueue` | O(log N) | O(log N) | O(1) | Min-heap |
| `ConcurrentLinkedQueue` | O(1) | O(1) | O(1) | Lock-free |
| `LinkedBlockingQueue` | O(1) | O(1) | O(1) | Blocking, optional bound |
| `ArrayBlockingQueue` | O(1) | O(1) | O(1) | Blocking, fixed size |

---

## 4. Sequence vs List

```kotlin
// Eager — allocates intermediate lists at every step
val result: List<Int> = users
    .map { it.age }            // allocate List<Int>
    .filter { it > 18 }        // allocate List<Int>
    .map { it * 2 }            // allocate List<Int>
    .take(10)                  // allocate List<Int>

// Lazy — single pass, no intermediate lists
val result: List<Int> = users.asSequence()
    .map { it.age }
    .filter { it > 18 }
    .map { it * 2 }
    .take(10)
    .toList()                  // materialise once
```

**Sequence wins when:**
- Many intermediate steps (3+)
- Large input (1000+ elements)
- Early termination (`.first { }`, `.take(N)`)

**List (eager) wins when:**
- 1-2 simple operations
- Small input (< 100 elements)
- Need to iterate the result multiple times
- Need `.size` or random access

**Rule of thumb:** for backend processing of result sets > 100 elements with > 2 transformations, use `asSequence()`. For 5-element lists, eager is fine and clearer.

```kotlin
// Kotlin Sequence vs Java Stream
list.asSequence().filter { ... }.map { ... }.toList()
list.stream().filter { ... }.map { ... }.collect(toList())
```

Sequences are slightly faster than Java Streams for sequential processing (no parallel split). Streams win for `.parallel()` workloads — but that's rare in backend, usually a smell.

---

## 5. Primitive collections — avoid boxing

Boxing each `Int` to `Integer` is ~16 bytes per element, adds indirection, GC pressure.

```kotlin
// Boxed
val xs: List<Int> = listOf(1, 2, 3, 4, 5)   // List<Integer> in bytecode
val sum = xs.sum()                            // unboxes each on iteration

// Primitive
val xs: IntArray = intArrayOf(1, 2, 3, 4, 5)
val sum = xs.sum()                            // no boxing
```

For hot loops over thousands of numbers, `IntArray`/`LongArray`/`DoubleArray` wins.

For maps/sets of primitives, the JVM has no built-in primitive collections. Use:
- **fastutil** (`it.unimi.dsi:fastutil`): `Int2IntOpenHashMap`, `IntOpenHashSet`
- **Koloboke**: similar
- **HPPC** (High Performance Primitive Collections)

When relevant:
- Storing 100K+ entries
- Hot lookup path
- Memory budget tight

---

## 6. Thread-safe collections

| Concern | Solution |
|---|---|
| Read-heavy, occasional write | `CopyOnWriteArrayList` / `CopyOnWriteArraySet` |
| Balanced read/write | `ConcurrentHashMap`, `ConcurrentLinkedQueue` |
| Map with atomic compute | `ConcurrentHashMap.compute`, `computeIfAbsent`, `merge` |
| Producer/consumer queue | `LinkedBlockingQueue` |
| Single producer, single consumer | `ArrayBlockingQueue` (fixed size) |
| Lock-free FIFO | `ConcurrentLinkedQueue` |

**Never use:**
- `Collections.synchronizedMap(...)` — coarse-grained lock, bad concurrency
- `Hashtable` — legacy, slower than `ConcurrentHashMap`
- `Vector` — legacy `ArrayList`-with-sync

**`ConcurrentHashMap` atomic ops:**
```kotlin
val cache = ConcurrentHashMap<UUID, Value>()

// Atomic: only computes if absent
cache.computeIfAbsent(key) { id -> loadValue(id) }

// Atomic merge
cache.merge(key, newValue) { old, new -> old + new }

// Atomic compute (any case)
cache.compute(key) { _, current -> current?.plus(1) ?: 1 }
```

These avoid the classic `if (!map.containsKey(k)) map.put(k, v)` race.

---

## 7. Allocation considerations

Picking O(1) data structures doesn't help if allocation dominates. Examples:

```kotlin
// Allocates new list each call
fun activeUsers(): List<User> = users.filter { it.active }

// Allocates intermediate list, then final list
fun topActive(): List<User> = users.filter { it.active }.sortedByDescending { it.score }.take(10)

// Sequence: one allocation (the result List)
fun topActiveLazy(): List<User> = users.asSequence()
    .filter { it.active }
    .sortedByDescending { it.score }
    .take(10)
    .toList()
```

Note: `sortedByDescending` in a sequence still allocates internally (sorts require full materialisation). Sequence avoids the `.filter` intermediate allocation but not the sort.

For hot inner loops where allocation matters, structure code to **reuse buffers**:

```kotlin
val buf = StringBuilder(256)
for (entry in entries) {
    buf.clear()
    buf.append(entry.key).append('=').append(entry.value)
    process(buf)
}
```

vs allocating a new `String` per iteration.

---

## 8. Hash function quality

`HashMap`/`HashSet` work O(1) only with good hashCode distribution. Bad hashCode → buckets collide → effective O(N) at worst.

**JDK 8+** uses red-black tree for buckets with > 8 collisions, so worst-case is O(log N) instead of O(N). Still: bad hash means slower than good hash.

```kotlin
// data class auto-generates hashCode from all fields → usually good
data class CompositeKey(val tenantId: UUID, val userId: UUID, val resource: String)
val map = HashMap<CompositeKey, Permission>()

// Custom hashCode — be careful
class BadKey(val a: Int, val b: Int) {
    override fun hashCode() = a   // ignores b → many collisions
}
```

**Test hashCode distribution:** generate 10K random keys, count unique hashCodes. If < 99%, your hash is suspect.

---

## 9. When O(N²) is actually OK

Constants matter at small N. O(N²) with a tight inner loop (no allocation, no I/O) is faster than O(N log N) with overhead when N < 50.

| Algorithm | N |
|---|---|
| Insertion sort | < 32 (JDK uses insertion sort for small `Arrays.sort` ranges) |
| Bubble sort | < 10 (educational only) |
| Naive substring search | Most cases (JIT-friendly, no setup) |
| Naive matrix multiply | < 64 |

So: O(N²) is **fine when N is bounded and small**. Document the bound.

```kotlin
// Acceptable: items in a single order are bounded (~< 100 typically)
fun calculateBundleDiscount(items: List<OrderItem>): Money {
    for (i in items.indices) {
        for (j in i+1 until items.size) {
            // pair comparison logic
        }
    }
    return ...
}
```

If items per order grew to 10K, this becomes 50M operations. Bound your assumptions or switch algorithms.

---

## 10. Common surprises

- **`.distinct()` order is preserved** (Kotlin uses LinkedHashSet internally). Java `.distinct()` on a parallel stream does NOT preserve order.
- **`.count()` on Sequence is O(N)** — it iterates. On `List` it's O(1) (`.size`).
- **`.last()` on Sequence is O(N)** but on `List` it's O(1).
- **`String.split(",")` for single-char delimiter** uses regex by default; slower than `.splitToSequence(",")`. Or use `Splitter` (Guava) / `splitBy`.
- **`String.replace(regex, replacement)`** compiles the regex every call if you pass a String pattern. Pre-compile `Regex(...)` and reuse.
- **`Stream.toList()` (Java 16+) is faster than `.collect(toList())`** — uses internal optimised constructor.
- **`mapOf("a" to 1, "b" to 2)` in Kotlin** creates a LinkedHashMap. Iteration order matches definition.
- **`List.toSet().toList()`** dedups + preserves order if input is `LinkedHashSet`-based; otherwise unspecified.

---

## 11. Quick decision: which collection?

```
Need to look up by key?                          → Map
   Iteration order matters (definition order)?   → LinkedHashMap
   Iteration order matters (sorted)?              → TreeMap
   Otherwise                                      → HashMap
   Thread-safe shared?                            → ConcurrentHashMap

Need to test membership?                          → Set (same variants as Map)

Need ordered, indexable?                          → List (ArrayList by default)
   Add/remove at front?                            → ArrayDeque

Need sorted access to top/bottom?                 → TreeSet / PriorityQueue

Need FIFO/LIFO with multiple producers?           → ConcurrentLinkedQueue
   Bounded with backpressure?                      → ArrayBlockingQueue / LinkedBlockingQueue

Need primitives (Int, Long, Double)?              → IntArray / LongArray / DoubleArray
   Or fastutil's Int2IntOpenHashMap-style structs

Need lazy chain of operations?                    → Sequence
   Suspending lazy?                                → Flow
```

---

## 12. Pitfalls

- **`mutableListOf<Int>()` for an algorithm that does math.** Boxes every element. Use `IntArray` or `MutableList<Int>` is still preferable for size flexibility despite boxing.
- **`HashMap` for small fixed sets.** Overhead dominates. Just use `List` with `contains` if N < 8.
- **Choosing `LinkedList` "because of O(1) add".** True for adds, false in practice (cache miss, bigger memory). Use `ArrayDeque`.
- **`Collections.synchronizedMap` instead of `ConcurrentHashMap`.** Coarse lock. Almost always wrong.
- **Iterating concurrent collections without copy.** `ConcurrentHashMap.entrySet()` is weakly consistent — iteration sees a snapshot but may miss concurrent modifications. Usually fine, but be aware.
- **`String.format` in inner loops.** Parses spec every call. Pre-build `Formatter` or use string templates.
- **Computing the same thing in a loop.** `for (i in xs.indices) { if (xs[i].x == compute()) ... }` — call `compute()` once outside.
