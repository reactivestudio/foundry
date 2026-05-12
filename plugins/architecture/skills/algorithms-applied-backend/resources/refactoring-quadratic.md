# Refactoring O(N²) Accidents

The most common backend performance bug: hidden quadratic loops. How to spot them, how to fix, before/after benchmarks.

---

## 1. Diagnostic patterns — these scream O(N²)

### Pattern 1: nested loop + `contains`

```kotlin
// SMELL
fun matchUsers(usersA: List<User>, usersB: List<User>): List<User> {
    return usersA.filter { a -> usersB.any { b -> b.email == a.email } }
}
```

**Diagnosis:** for each of N users in A, scan all N in B → O(N²).

**Fix:**
```kotlin
fun matchUsers(usersA: List<User>, usersB: List<User>): List<User> {
    val bEmails: Set<String> = usersB.map { it.email }.toSet()    // O(N)
    return usersA.filter { it.email in bEmails }                  // O(N) × O(1) = O(N)
}
```

**Complexity drop:** O(N²) → O(N). At N=10K: 100M ops → 20K ops.

---

### Pattern 2: nested loop with field equality

```kotlin
// SMELL
fun enrichOrdersWithCustomers(orders: List<Order>, customers: List<Customer>): List<EnrichedOrder> =
    orders.map { o ->
        val c = customers.first { it.id == o.customerId }
        EnrichedOrder(o, c)
    }
```

**Diagnosis:** For each of N orders, scan all M customers → O(N×M). If both are large, quadratic.

**Fix:**
```kotlin
fun enrichOrdersWithCustomers(orders: List<Order>, customers: List<Customer>): List<EnrichedOrder> {
    val customerById: Map<UUID, Customer> = customers.associateBy { it.id }     // O(M)
    return orders.map { o ->
        val c = customerById[o.customerId] ?: error("missing customer ${o.customerId}")
        EnrichedOrder(o, c)
    }                                                                             // O(N)
}
```

**Complexity:** O(N×M) → O(N+M).

---

### Pattern 3: re-sorting in a loop

```kotlin
// SMELL
for (input in inputs) {
    val sorted = candidates.sortedBy { -score(it, input) }   // re-sort every iteration
    process(sorted.take(10))
}
```

**Diagnosis:** N iterations × M log M sort = O(N × M log M).

**Fix A:** if the sort key is independent of `input`, hoist out.

**Fix B:** if sort key depends on `input`, use top-K heap per iteration:

```kotlin
for (input in inputs) {
    val top10 = candidates.topK(10) { score(it, input) }   // O(M log 10) per iter
    process(top10)
}

fun <T> List<T>.topK(k: Int, scoreFn: (T) -> Double): List<T> {
    val pq = PriorityQueue<T>(k, compareBy(scoreFn))
    for (item in this) {
        pq.offer(item)
        if (pq.size > k) pq.poll()
    }
    return pq.toList().sortedByDescending(scoreFn)
}
```

**Complexity:** O(N × M log M) → O(N × M log k) — much better when k << M.

---

### Pattern 4: building a list with `+` in a loop

```kotlin
// SMELL
var result: List<Int> = emptyList()
for (x in xs) {
    result = result + transform(x)    // each + allocates new list
}
```

**Diagnosis:** Each `+` is O(result.size). Total: O(1 + 2 + 3 + ... + N) = O(N²).

**Fix:**
```kotlin
val result = mutableListOf<Int>()
for (x in xs) {
    result += transform(x)             // O(1) amortised
}

// Or idiomatically
val result = xs.map { transform(it) }
```

---

### Pattern 5: `removeAll(collection)` in a loop

```kotlin
// SMELL
val list = mutableListOf<Item>(...)
toRemove.forEach { item -> list.remove(item) }   // each remove is O(N) for ArrayList
```

**Diagnosis:** M removes × O(N) per remove = O(N×M).

**Fix:**
```kotlin
val toRemoveSet = toRemove.toHashSet()
list.removeIf { it in toRemoveSet }              // O(N + M) total
```

---

### Pattern 6: cartesian product accidentally

```kotlin
// SMELL: triple loop with shared state
for (a in groupA) {
    for (b in groupB) {
        for (c in groupC) {
            if (constraint(a, b, c)) process(a, b, c)
        }
    }
}
```

**Diagnosis:** O(A × B × C). At each 100, that's 1M iterations.

**Fix:** depends on the constraint. Often:
- Pre-filter by key: index A by some field, narrow down B options per A
- Mathematical reformulation: instead of triple loop, compute pairwise then merge

```kotlin
// Example: find triples where a + b + c = K (3-sum problem)
// Brute: O(N³)
// Better: sort, for each a, two-pointer on b+c → O(N²)
```

---

### Pattern 7: JPA N+1 (the algorithmic shape of)

```kotlin
// SMELL
val orders = orderRepo.findAll()
for (o in orders) {
    val items = o.items                      // lazy load → SELECT per order
    process(o, items)
}
```

**Diagnosis:** 1 + N queries. Even though each query is fast, N round-trips dominate for large N.

**Fix:** see `database-design/resources/optimization.md` §3. JOIN FETCH, EntityGraph, @BatchSize, or pre-fetch:

```kotlin
@Query("SELECT o FROM Order o JOIN FETCH o.items WHERE ...")
fun findAllWithItems(): List<Order>
```

---

### Pattern 8: `String` concatenation in a loop

```kotlin
// SMELL — Java-style
var result = ""
for (x in xs) {
    result = result + transform(x)        // each + copies entire string
}
```

**Diagnosis:** Each `+` is O(result.length). Total: O(N²).

Kotlin/JIT often optimises this to StringBuilder, but not always — explicit is safer:

**Fix:**
```kotlin
val result = buildString(initialCapacity = xs.size * 16) {
    xs.forEach { append(transform(it)) }
}

// Or
val result = xs.joinToString("") { transform(it) }
```

---

## 2. Before-and-after with JMH

For non-trivial refactors, verify with JMH:

```kotlin
@State(Scope.Benchmark)
open class DedupBenchmark {

    @Param("100", "1000", "10000")
    var size: Int = 0

    private lateinit var data: List<Order>

    @Setup
    fun setup() {
        data = (1..size).map { fakeOrder() }
    }

    @Benchmark
    fun quadratic(): List<Order> {
        val out = mutableListOf<Order>()
        for (x in data) if (!out.contains(x)) out += x
        return out
    }

    @Benchmark
    fun linear(): List<Order> = data.distinct()
}
```

Sample results:
```
size: 100        quadratic: 12 µs       linear: 8 µs       (1.5× faster)
size: 1000       quadratic: 1.2 ms      linear: 80 µs      (15× faster)
size: 10000      quadratic: 122 ms      linear: 0.8 ms     (152× faster)
```

The quadratic version's slope is N²; linear's is N. The crossover is the practical break-even point.

---

## 3. When `O(N²)` is acceptable

| Situation | Why OK |
|---|---|
| N is bounded by definition (items per order ≤ 100) | Even with O(N²), at N=100 → 10K ops |
| N is small in practice (config map, menu items) | Constants of HashMap might exceed the gain |
| Code runs once at startup | Not in hot path |
| Algorithmic clarity > microsecond gain | Maintainability wins |

**Document** the bound. `// Acceptable: at most 100 items per order; O(N²) for clarity`.

If the bound is violated later, you have a starting point. Without documentation, future engineers fix things that didn't need fixing or miss things that did.

---

## 4. Step-by-step refactor methodology

1. **Profile first.** Don't fix what isn't slow. `async-profiler` flame graph reveals hot O(N²) loops.
2. **Identify the shape.** What's the inner loop? What does it compare?
3. **Find the indexing key.** Usually a field used in `==`, `contains`, `.find { }`.
4. **Build the index.** `associateBy`, `toSet`, `groupBy`.
5. **Rewrite the loop** using the index.
6. **JMH benchmark before / after** on realistic data sizes.
7. **Add tests** to verify behaviour preserved.
8. **Commit with measurable improvement** in the message.

---

## 5. Common false positives

### "Nested loops" that aren't O(N²)

```kotlin
for (group in groups) {           // M groups, total N items across all
    for (item in group.items) {   // varies per group
        process(item)
    }
}
```

This is O(total items) = O(N), not O(M²). Reading literally as "nested loop" is misleading.

### Sequence chains that look nested

```kotlin
val result = items.flatMap { x ->
    others.filter { it.matches(x) }    // looks O(N×M)
}.toList()
```

This IS O(N×M). But:

```kotlin
val others = repo.findAll().asSequence()   // already filtered upstream
val result = items.asSequence().flatMap { x ->
    others.filter { it.matches(x) }    // still O(N×M) iterations, but lazy
}.toList()
```

Sequence doesn't change complexity, just allocation. Lazy can be a footgun: if you `.toList()` and pass around, you've materialised; subsequent ops are over a list.

---

## 6. Memory complexity is also a thing

```kotlin
// Memory: O(N²) — pairs allocated
val pairs = items.flatMap { a -> items.map { b -> a to b } }

// vs
items.flatMap { a -> items.asSequence().map { b -> a to b } }   // lazy, less memory at any moment
```

If you don't need all pairs in memory at once, use sequences for the inner.

---

## 7. Refactoring case study — applicability tagging

### Before (O(N×M))

```kotlin
fun tagOrdersByCustomerType(orders: List<Order>, customers: List<Customer>): List<TaggedOrder> {
    return orders.map { order ->
        val customer = customers.first { it.id == order.customerId }
        val isPremium = customer.tier == "PREMIUM"
        TaggedOrder(order, isPremium)
    }
}
```

100K orders × 50K customers = 5B comparisons (worst case). Will time out.

### After (O(N+M))

```kotlin
fun tagOrdersByCustomerType(orders: List<Order>, customers: List<Customer>): List<TaggedOrder> {
    val premiumCustomers: Set<UUID> = customers
        .filter { it.tier == "PREMIUM" }
        .mapTo(HashSet(customers.size)) { it.id }

    return orders.map { order ->
        TaggedOrder(order, order.customerId in premiumCustomers)
    }
}
```

100K orders + 50K customers = 150K operations. Three orders of magnitude faster.

### What changed
- Replaced `customers.first { ... }` (O(M)) with `Set.contains` (O(1))
- Pre-built index once outside loop
- Filtered to only what's needed (premium customers, not all)

---

## 8. The Cartesian-product anti-pattern in business logic

```kotlin
// Computing "all pairs of items that could conflict"
for (a in items) {
    for (b in items) {
        if (a != b && conflicts(a, b)) markConflict(a, b)
    }
}
```

If `conflicts` is symmetric and irreflexive, halve work:
```kotlin
for (i in items.indices) {
    for (j in i+1 until items.size) {
        if (conflicts(items[i], items[j])) markConflict(items[i], items[j])
    }
}
```

Still O(N²) in worst case, but 2× faster. Sometimes that's enough.

For truly large N, use **spatial / hash partitioning**:
- Group items by some "bucket key"
- Only compare within buckets

```kotlin
// E.g., conflicts only within same time window
val buckets = items.groupBy { it.dayOfYear }
for ((_, group) in buckets) {
    for (i in group.indices) for (j in i+1 until group.size) {
        // ...
    }
}
```

If items spread across ~365 buckets evenly, comparisons drop from O(N²) to O(N²/365). Bucketing as algorithmic optimisation.

---

## 9. Pitfalls

- **"Looks linear because Kotlin syntax is concise."** `items.filter { it in others }` is `items.size × others.size` if `others` is a `List`. Make `others` a `Set`.
- **`distinct()` on huge data.** Builds full HashSet. If data is 100M, memory matters; consider DB `SELECT DISTINCT` or streaming dedup.
- **Refactoring without benchmark.** "Should be faster" → measure.
- **Over-indexing.** Building a Map for 10 elements is more overhead than a linear scan.
- **Hash collision attack.** If keys come from user input, malicious data can force O(N) per hash op → O(N²) total. Use random-seeded hashing or move to TreeMap for adversarial inputs.
- **Inflating O(N²) into O(N×M).** When M ≠ N, label clearly. M=1000 with N=1M is 10⁹ ops — same problem as O(N²) but easier to miss.
