# Practices — Anti-Patterns and One-Line Fixes

Each pattern has a fixed *signature* (the shape that triggers recognition), a one-line fix, and a measurable complexity drop. Examples use plain Kotlin syntax that maps 1:1 to Java.

## P1. `list.first { it.field == x }` (or `.any { ... }`) inside a loop → indexed `Map` / `Set`

```kotlin
// O(N×M)
val enriched = orders.map { o ->
    val c = customers.first { it.id == o.customerId }
    EnrichedOrder(o, c)
}

// O(N + M) — index once, look up in O(1)
val byId = customers.associateBy { it.id }
val enriched = orders.map { o ->
    val c = byId[o.customerId] ?: error("missing customer ${o.customerId}")
    EnrichedOrder(o, c)
}
```

The trigger to recognise: any inner loop search keyed on a field. `associateBy { it.field }` (or `mapTo(HashSet) { it.field }` for membership) is almost always the right primitive.

## P2. `sortedBy` inside a loop → hoist, or top-K heap

```kotlin
// O(N × M log M) — re-sorts every iteration
for (req in requests) {
    val ranked = candidates.sortedByDescending { score(it, req) }
    process(ranked.take(10))
}
```

Two fixes depending on whether the sort key depends on the loop variable:

```kotlin
// (a) Key independent of req — hoist out.
val ranked = candidates.sortedByDescending { it.baseScore }
for (req in requests) process(ranked.take(10))

// (b) Key depends on req — top-K heap, O(M log K) per request.
for (req in requests) {
    val pq = PriorityQueue<Candidate>(10, compareBy { score(it, req) })
    for (c in candidates) { pq.offer(c); if (pq.size > 10) pq.poll() }
    process(pq.sortedByDescending { score(it, req) })
}
```

Top-K with a heap: O(N log K) vs O(N log N) for full sort. Worth it when K is roughly 10× smaller than N. Reuse as a primitive whenever you only need the K best of N.

## P3. Offset pagination → keyset/cursor

Offset is O(offset + limit) — the database reads and discards every row before the offset.

```sql
-- Page 1000 of size 20: reads 20020 rows, returns 20.
SELECT * FROM orders ORDER BY created_at DESC LIMIT 20 OFFSET 20000;
```

Keyset uses an index to jump straight to the cursor — O(log N + limit), same speed on page 1 and page 10000.

```sql
SELECT * FROM orders
 WHERE (created_at, id) < (:cursor_created_at, :cursor_id)
 ORDER BY created_at DESC, id DESC
 LIMIT :size;
```

Cursor is `(createdAt, id)` encoded as opaque base64. Trade-off: gives next/prev but not random "page 50 of 1000". Default to keyset on any table expected to exceed ~1K rows.

## P4. N round-trips inside a loop → bulk

```kotlin
// N round-trips. Each call is "O(1)", but N latencies dominate.
ids.forEach { id -> repo.findById(id) }

// One round-trip.
val byId = repo.findAllById(ids).associateBy { it.id }
ids.map { byId[it] ?: error("missing $it") }
```

Same shape for HTTP, message queues, cache calls. **In distributed systems the unit of cost is the round-trip, not the per-call algorithmic complexity.** Look for the bulk variant first (`findAllById`, `saveAll`, `IN (:ids)`, batched publish) before declaring a loop "fine because each call is O(1)".

## P5. `findAll().filter { }` → push predicate to data source

```kotlin
// O(rows in the table) — loads everything, filters in memory.
fun activeOrdersOver(amount: BigDecimal): List<Order> =
    repo.findAll().filter { it.status == ACTIVE && it.total > amount }

// O(matching rows) — index does the work.
@Query("SELECT o FROM Order o WHERE o.status = 'ACTIVE' AND o.total > :amount")
fun findActiveOver(amount: BigDecimal): List<Order>
```

Same shape for file scans, HTTP "list all" endpoints, search backends. **Move the predicate to the layer that has the index.** The trap: diagnosing the loop body as O(N) and missing that *N is every row in production*. The complexity isn't in the loop — it's in what feeds the loop.

## P6. Document acceptable O(N²)

The discipline that turns a bug into a deliberate trade-off:

```kotlin
// Acceptable: order line items are capped at 100 by OrderService.MAX_LINES.
// If that bound is raised, switch to a HashSet-based conflict index.
fun detectConflicts(items: List<Item>): List<Conflict> {
    val out = mutableListOf<Conflict>()
    for (i in items.indices) {
        for (j in i + 1 until items.size) {
            if (conflicts(items[i], items[j])) out += Conflict(items[i], items[j])
        }
    }
    return out
}
```

The comment carries three pieces of information the code can't:
1. **What N is** (≤100), so future readers don't have to derive it.
2. **Where the bound is enforced** (`OrderService.MAX_LINES`), so they can verify it's still there.
3. **What to do when it lifts** (switch to indexed lookup), so the next person isn't starting from zero.

Without that comment, future engineers face a binary choice with no information: refactor it speculatively (waste + risk of regression), or leave it and ship a latent performance bug when the bound is lifted.

The comment is the cheapest line in the function and the highest-value one. Default to writing it whenever you accept bounded O(N²).

## Universal quadratic shapes (no example needed)

These are well-known enough that the signature is the whole skill — the fix follows reflexively.

- `list.contains(x)` inside a loop → build a `HashSet` once outside; lookup in the loop.
- `list.removeAll(otherList)` → `list.removeIf { it in otherSet }` after `otherList.toHashSet()`.
- `result = result + x` building a list in a loop → mutable accumulator (`mutableListOf` + `+=`, or `map { }`).
- `String` concat in a loop → `buildString { }`, `StringBuilder`, or `joinToString`.

All four are O(N²) → O(N) via the same mental move: stop building immutable copies, build the index/buffer once.
