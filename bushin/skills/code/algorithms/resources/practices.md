# Practices — Named Anti-Patterns

Each pattern has a **name** (use it verbatim in output — verifiable catches), a **signature** (the syntactic shape that triggers recognition), and a **fix** with complexity drop. Examples use plain Kotlin transferable to Java; Spring/JPA-specific fixes live in [spring.md](spring.md).

## findAll-and-filter trap

**Signature**: `repo.findAll().filter { … }` — or any data source that loads everything, then filters in JVM.

```kotlin
// SMELL
val active = orderRepo.findAll().filter { it.status == ACTIVE && it.tenant == t }

// FIX — push the predicate to the source
val active = orderRepo.findByStatusAndTenant(ACTIVE, t)
```

**Complexity**: O(rows in table) → O(matching rows). Plus the loaded set never enters JVM memory.

A `.stream().filter` / `.asSequence().filter` immediately after `.findAll()` does **not** save you — the data is already loaded. The cost is the load, not the filter.

## N+1 cascade

**Signature**: any `for` / `map` / `flatMap` body containing a repo / service / HTTP call.

```kotlin
// SMELL
val enriched = orders.map { o ->
    EnrichedOrder(o, customerRepo.findById(o.customerId).orElseThrow())
}
```

**Fix**: bulk-fetch once outside the loop, build an index, look up inside.

```kotlin
val customerIds = orders.map { it.customerId }.toSet()
val byId = customerRepo.findAllById(customerIds).associateBy { it.id }
val enriched = orders.map { o -> EnrichedOrder(o, byId[o.customerId] ?: error(o.customerId)) }
```

**Complexity**: N round-trips → 1 round-trip + O(N+M) in JVM. The dominant cost is round-trip count in distributed systems, not the per-call algorithmic complexity.

## bulk-fetch missed

**Signature** (the fix for N+1 cascade): the loop iterates over identifiable keys, and a `findAllByXIn` / `findAllById` variant exists or could exist.

The named pattern matters because **recognising the bulk variant by name** is more reliable than reasoning "we should batch this." If Spring Data, look for derived methods like `findAllByXIn`. If a thin repository, add one.

## cartesian repo dance

**Signature**: a data-source call (`findAll`, `findByX`) inside a loop that iterates over another data set.

```kotlin
// SMELL — N calls × M rows each = N×M total work
val related = enriched.associate { e ->
    val others = productRepo.findAll().filter { it.id != e.product.id && shares(e, it) }
    e.product.id to others
}
```

**Fix**: load once outside, compute the relation in JVM.

```kotlin
val allProducts = productRepo.findByCategoryIn(enriched.map { it.product.categoryId }.toSet())
val related = enriched.associate { e ->
    e.product.id to allProducts.filter { it.id != e.product.id && shares(e, it) }
}
```

**Severity**: usually the worst trap in any service — easily 100× regressions.

## cartesian-with-filter

**Signature**: outer loop where the inner step filters a *constant* collection per iteration.

```kotlin
// SMELL — same .filter on `all` re-runs for every peer
val peerSummaries = peers.map { peer ->
    val peerTotal = all.filter { it.tenantId == peer.id }.sumOf { it.amount }
    PeerSummary(peer, peerTotal)
}
```

**Fix**: pre-group the constant once, lookup inside the loop.

```kotlin
val byTenant = all.groupBy { it.tenantId }
val peerSummaries = peers.map { peer ->
    val peerTotal = byTenant[peer.id].orEmpty().sumOf { it.amount }
    PeerSummary(peer, peerTotal)
}
```

**Complexity**: O(P × T) → O(T + P), where P = outer collection, T = constant inner collection.

## sort-then-take-K (active)

**Signature**: `xs.sortedBy { … }.take(K)` where `xs` is large (or unknown) and `K << xs.size`.

```kotlin
// SMELL at scale — full sort over a 100K-row map for the top 20
val popular = counters.entries.sortedByDescending { it.value }.take(20)

// FIX — top-K heap, O(N log K)
val top = PriorityQueue<Map.Entry<UUID, Int>>(20, compareBy { it.value })
counters.entries.forEach { top.offer(it); if (top.size > 20) top.poll() }
val popular = top.sortedByDescending { it.value }
```

**Discriminator**: this is the *active* case. The **bounded-N** version (next entry) is a false positive — leave it alone.

## sort-then-take-K (false positive — bounded N)

**Signature**: same syntactic shape (`xs.sortedBy { }.take(K)`), but `xs` is bounded by definition — page size, items per order, peer count.

```kotlin
// Page is bounded by req.size (≤100 typical)
val highlights = enrichedPage.sortedByDescending { it.rating }.take(3)
```

**Fix**: leave it. A heap at N≤100 is slower and harder to read. Heap pays off when K is ~10× smaller than N **and N is unbounded**.

The discriminator is **whether N is bounded**, not the syntactic shape. Always identify which regime applies before suggesting a heap.

## bounded-O(N²) acceptable

**Signature**: nested loop where N is provably small (≤ 100, bounded by domain invariant).

**Fix**: leave the loop, **document the bound at the call site** with three pieces of information:

```kotlin
// Acceptable: order line items capped at 100 by OrderService.MAX_LINES.
// If that bound lifts, switch to a HashSet-based conflict index.
fun detectConflicts(items: List<Item>): List<Conflict> {
    for (i in items.indices) for (j in i + 1 until items.size) { … }
}
```

The comment must carry: (1) what N is, (2) where the bound is enforced, (3) what to do if the bound lifts. Without all three, future readers either over-refactor or miss the time-bomb when the bound goes away.

Default to writing the comment whenever you accept bounded O(N²); the discipline turns a latent bug into an explicit trade-off.

## time-window pairs (cartesian over time series)

**Signature**: `for (a in xs) for (b in xs) if (timeProximity(a, b))` — looking for events within a time window via nested loop.

```kotlin
// SMELL — O(N²) even when only adjacent-in-time pairs can match
for (a in txns) for (b in txns) {
    if (a.id != b.id && a.accountId == b.accountId &&
        Duration.between(a.timestamp, b.timestamp).abs() < Duration.ofMinutes(1)) {
        pairs += a.id to b.id
    }
}

// FIX — sort by time, sliding window
val sorted = txns.sortedBy { it.timestamp }
for (i in sorted.indices) {
    var j = i + 1
    while (j < sorted.size && Duration.between(sorted[i].timestamp, sorted[j].timestamp) < Duration.ofMinutes(1)) {
        if (sorted[i].accountId == sorted[j].accountId) pairs += sorted[i].id to sorted[j].id
        j++
    }
}
```

**Complexity**: O(N²) → O(N log N + K) where K = matching pairs. Critical at txn-table scale.

## list.first / .any / .find in loop

**Signature**: `xs.first { it.f == y }` (or `.any`, `.find`) where the comparison field `f` is stable and the outer loop iterates over multiple `y` values.

```kotlin
// SMELL
val enriched = orders.map { o ->
    val c = customers.first { it.id == o.customerId }
    EnrichedOrder(o, c)
}

// FIX — index by the comparison field once
val byId = customers.associateBy { it.id }
val enriched = orders.map { o ->
    val c = byId[o.customerId] ?: error("missing customer ${o.customerId}")
    EnrichedOrder(o, c)
}
```

**Complexity**: O(N×M) → O(N+M). The index build is O(M); each loop lookup is O(1).

## findAll-then-first

**Signature**: `repo.findAll().first { it.id == x }` (or `.single`, `.filter { id }.first()`) — load every row to find one.

```kotlin
// SMELL
val target = orderRepo.findAll().first { it.id == event.orderId }

// FIX
val target = orderRepo.findById(event.orderId).orElseThrow()
```

Easy to miss because the `.first { }` looks like a clean filter. The cost is in the `findAll()`.

---

## Universal shapes — one-line reminders

For completeness; each is a quadratic O(N²) shape with an obvious mechanical fix Claude already knows:

- `list.contains(x)` inside a loop → build a `HashSet` once, `in` check is O(1).
- `result = result + x` in a loop → mutable accumulator or `map { }`.
- `String` concat in a loop → `buildString { }` / `joinToString`.
- `list.removeAll(otherList)` → `list.removeIf { it in otherSet }` after `otherList.toHashSet()`.

If you find yourself spending review time on these, the review is over-fitting. Mention briefly, move on.
