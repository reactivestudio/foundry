# Applied Patterns — Pagination, Dedup, Sort, Graph, Sets

Algorithm shapes that recur in backend code. How to recognise them. How to implement them well in Kotlin.

---

## 1. Pagination — offset vs keyset

### Offset pagination — fine for small N, dies at scale

```kotlin
fun pageOffset(page: Int, size: Int): List<Order> =
    repo.findAll(PageRequest.of(page, size, Sort.by("createdAt").descending())).content
```

SQL behind it:
```sql
SELECT * FROM orders ORDER BY created_at DESC LIMIT 20 OFFSET 10000
```

**Complexity:** O(offset + limit). Postgres reads + discards 10000 rows. At page 1000, it's reading 20000 rows to return 20.

**Use when:** offset stays small (admin tables, < 1000 total items).

### Keyset (cursor) pagination — scales linearly

```kotlin
data class OrdersPage(val items: List<Order>, val nextCursor: String?)

fun pageKeyset(cursor: String?, size: Int): OrdersPage {
    val (lastCreatedAt, lastId) = decodeCursor(cursor)
    val rows = repo.findByCursor(lastCreatedAt, lastId, size + 1)   // fetch one extra
    val hasMore = rows.size > size
    val items = rows.take(size)
    val next = if (hasMore) encodeCursor(items.last().createdAt, items.last().id) else null
    return OrdersPage(items, next)
}
```

JPQL:
```kotlin
@Query("""
    SELECT o FROM Order o
    WHERE :cursor IS NULL 
       OR (o.createdAt, o.id) < (:lastCreatedAt, :lastId)
    ORDER BY o.createdAt DESC, o.id DESC
""")
fun findByCursor(lastCreatedAt: Instant?, lastId: UUID?, limit: Int): List<Order>
```

**Complexity:** O(log N + limit). Uses index `(created_at DESC, id DESC)`. Same speed at page 1 and page 10000.

**Cursor encoding:** base64 of `"$createdAt|$id"`. Opaque to clients.

**Trade-offs:**
- Pro: O(log N) regardless of depth
- Pro: stable under inserts (existing cursors still valid)
- Con: no "page 50 of 1000" UI (can only go next/prev)
- Con: no random access

**Use when:** infinite scroll, large tables, > 1000 items potentially.

---

## 2. Deduplication

### O(N²) naive
```kotlin
fun dedup(xs: List<Order>): List<Order> {
    val out = mutableListOf<Order>()
    for (x in xs) {
        if (!out.contains(x)) out += x   // O(N) per call → O(N²)
    }
    return out
}
```

### O(N) with set
```kotlin
fun dedup(xs: List<Order>) = xs.distinct()       // uses HashSet internally

fun dedupByKey(xs: List<Order>) = xs.distinctBy { it.id }   // dedup by field
```

### Dedup with priority (keep latest by some field)
```kotlin
// Keep one Order per customer, the latest
fun latestPerCustomer(xs: List<Order>): Map<UUID, Order> =
    xs.groupBy { it.customerId }
      .mapValues { (_, group) -> group.maxBy { it.createdAt } }
```

`groupBy` + `mapValues` is O(N + M) where M = result size.

---

## 3. Sort and merge

### Sorting once vs sorting in a loop

```kotlin
// O(N² log N) — sort in loop
for (x in items) {
    val sorted = others.sortedBy { distance(it, x) }
    process(sorted)
}

// O(N log N + N×M) — sort once if data allows
val sorted = others.sortedBy { it.priority }   // fixed key
for (x in items) {
    process(sorted)   // reuse
}
```

If the sort key depends on the loop variable, sort can't be hoisted. Look for alternative algorithms (priority queue, k-nearest neighbours indexed).

### Merging two sorted lists

```kotlin
fun <T : Comparable<T>> merge(a: List<T>, b: List<T>): List<T> {
    val result = ArrayList<T>(a.size + b.size)
    var i = 0; var j = 0
    while (i < a.size && j < b.size) {
        if (a[i] <= b[j]) { result += a[i]; i++ } else { result += b[j]; j++ }
    }
    while (i < a.size) { result += a[i]; i++ }
    while (j < b.size) { result += b[j]; j++ }
    return result
}
```

O(N + M). Naive `(a + b).sorted()` is O((N+M) log (N+M)).

Use when merging paginated sorted result sets.

---

## 4. Set operations

```kotlin
val a = setOf(1, 2, 3, 4)
val b = setOf(3, 4, 5, 6)

a.intersect(b)         // {3, 4}    — O(N+M) average
a.union(b)             // {1..6}    — O(N+M) average
a - b                  // {1, 2}    — set difference, O(N+M)
a.subtract(b)          // {1, 2}    — same
b.subtract(a)          // {5, 6}    — order matters

a.symmetricDifference(b)  // not built-in; use (a - b) union (b - a)
```

For "is in", `Set.contains` is O(1) average. **Build a set once, query many times.**

```kotlin
// Bad: list contains in inner loop
val activeUsers: List<User> = repo.findActive()
val orders: List<Order> = repo.findAll()
val ordersForActive = orders.filter { o -> activeUsers.any { u -> u.id == o.customerId } }
// O(N orders × N users) = quadratic

// Good: index once
val activeIds: Set<UUID> = repo.findActive().map { it.id }.toSet()
val ordersForActive = orders.filter { it.customerId in activeIds }
// O(N users + N orders)
```

---

## 5. Binary search

For sorted arrays/lists where you want O(log N) lookup or "where would this go":

```kotlin
val sorted = listOf(10, 20, 30, 40, 50)
val idx = sorted.binarySearch(35)
// idx = -4 (insertion point: -(insertion_point + 1) = -(3 + 1) = -4)

if (idx >= 0) "found at $idx" else "would insert at ${-(idx + 1)}"
```

Uses include:
- Sorted lookup in cached lists
- Quantile / percentile computation
- Range queries ("orders between X and Y date")

Don't binary-search a `LinkedList` — O(log N) lookup × O(N) random access = O(N log N). Use `ArrayList`.

---

## 6. Top-K — when you don't need full sort

If you have 1M items and want the top 10:

```kotlin
// O(N log N) — full sort
val top10 = items.sortedByDescending { it.score }.take(10)

// O(N log K) — k-element heap
val pq = PriorityQueue<Item>(10, compareBy { it.score })
for (item in items) {
    pq.offer(item)
    if (pq.size > 10) pq.poll()   // remove smallest
}
val top10 = pq.toList().sortedByDescending { it.score }
```

For K=10 and N=1M:
- Full sort: ~20M comparisons
- K-heap: ~1M × log(10) ≈ 3.3M comparisons

For backend, full sort is usually fine if N < 100K. K-heap matters at scale.

---

## 7. Graph operations — DAG topological sort

When you have dependencies (e.g., module load order, task dependencies):

```kotlin
fun <T> topologicalSort(nodes: Set<T>, deps: Map<T, Set<T>>): List<T> {
    val visited = mutableSetOf<T>()
    val visiting = mutableSetOf<T>()
    val result = mutableListOf<T>()

    fun visit(n: T) {
        if (n in visited) return
        if (n in visiting) throw CycleException("Cycle through $n")
        visiting += n
        deps[n]?.forEach(::visit)
        visiting -= n
        visited += n
        result += n
    }

    nodes.forEach(::visit)
    return result
}
```

O(V + E). Use for:
- Loading order of modules / bundles
- Build dependency resolution
- Database migration ordering
- Task execution ordering

For cycle detection only (not full topo): `visiting` set + DFS.

---

## 8. Graph operations — shortest path / reachability

Mostly relevant when business code has graph structure:
- Service dependency graphs
- Role inheritance hierarchies
- Bounded context relationships

**Reachability (BFS):**
```kotlin
fun <T> reachable(start: T, neighbors: (T) -> Set<T>): Set<T> {
    val seen = mutableSetOf<T>()
    val queue: ArrayDeque<T> = ArrayDeque()
    queue += start
    while (queue.isNotEmpty()) {
        val node = queue.removeFirst()
        if (!seen.add(node)) continue
        neighbors(node).forEach { queue += it }
    }
    return seen
}
```

O(V + E). Linear in graph size.

For shortest path: BFS (unweighted) or Dijkstra (weighted) — use a library (e.g., JGraphT) for non-trivial graphs.

---

## 9. Lazy sequence patterns

For chains of operations on large or infinite data:

```kotlin
// Eager — bad for chains over big data
fun firstActiveOrderOver1000(): Order? =
    repo.findAll()                            // loads all
        .filter { it.status == "ACTIVE" }     // intermediate list
        .filter { it.total > 1000 }           // intermediate list
        .firstOrNull()                        // takes first, others discarded

// Lazy — better
fun firstActiveOrderOver1000(): Order? =
    repo.findAll().asSequence()
        .filter { it.status == "ACTIVE" }
        .filter { it.total > 1000 }
        .firstOrNull()
```

But: this still loads everything from DB. The right answer is pushing the filter to SQL:
```kotlin
fun firstActiveOrderOver1000(): Order? =
    repo.findFirstByStatusAndTotalGreaterThan("ACTIVE", BigDecimal(1000))
```

**Rule:** filter as close to the data source as possible. Sequence is for "I already loaded; now I'm chaining" not for "I haven't filtered the DB query yet."

---

## 10. Bulk operations vs single

```kotlin
// Single inserts — N round-trips
ids.forEach { id -> repo.findById(id) }   // N queries

// Bulk fetch — 1 query
val map = repo.findAllById(ids).associateBy { it.id }
ids.map { map[it] ?: throw NotFoundException(it) }
```

Same for inserts (`saveAll`), updates (custom JPQL `UPDATE ... WHERE id IN (:ids)`).

For Kafka / RabbitMQ:
```kotlin
// Single
events.forEach { rabbit.convertAndSend("ex", "key", it) }  // N publishes

// Bulk-friendly via channel pipelining
events.chunked(100).forEach { batch ->
    batch.forEach { rabbit.convertAndSend("ex", "key", it) }
}
// Or send a list as one message if semantically appropriate
```

---

## 11. Cache key composition

When composing cache keys, watch complexity:

```kotlin
// Bad: huge dynamic key with many fields
val key = "user.${user.id}.preferences.${prefsHash(user)}.tenant.${tenant.id}.role.${role}"

// Better: scalar key + value-based composition
val key = "user-prefs::${user.id}::${tenant.id}::${role}"
```

Long keys make cache lookups slower and waste memory. Compose deterministically; keep short.

---

## 12. Idempotency keys

When a client retries, you need to detect "same request" vs "different request":

```kotlin
@Service
class IdempotencyService(private val store: IdempotencyStore) {

    fun <T> withIdempotency(key: IdempotencyKey, body: () -> T): T {
        store.findResult<T>(key)?.let { return it }    // O(1) hash lookup
        val result = body()
        store.record(key, result)
        return result
    }
}
```

Backend: `idempotency_keys (key PK, result_json, expires_at)`. Lookup is O(1) HashMap or O(log N) DB index. TTL cleanup is O(N) scheduled.

See `cqrs-implementation/resources/write-side-patterns.md` §6 for full pattern.

---

## 13. Group-by + aggregate

```kotlin
// O(N) — group + sum
fun totalRevenuePerCustomer(orders: List<Order>): Map<UUID, Money> =
    orders.groupBy { it.customerId }
          .mapValues { (_, group) -> group.sumOf { it.total } }
```

For DB-backed data, push to SQL:
```sql
SELECT customer_id, SUM(total) FROM orders GROUP BY customer_id
```

In-memory `.groupBy` makes sense only when:
- Data already in memory for other reasons
- Group cardinality is small (~100s) — fits in memory
- DB query would be N+1 or unindexed

---

## 14. Streaming large datasets

If you can't fit N in memory, stream:

```kotlin
// Spring Data: stream
@Query("SELECT o FROM Order o WHERE o.tenantId = :t")
fun streamByTenant(@Param("t") tenantId: UUID): Stream<Order>

@Transactional(readOnly = true)
fun process(tenantId: UUID) {
    repo.streamByTenant(tenantId).use { stream ->
        stream.forEach { order ->
            process(order)
            entityManager.detach(order)   // free first-level cache to avoid OOM
        }
    }
}
```

**Critical:** `entityManager.detach(order)` (or use `clear()` periodically). Otherwise Hibernate's first-level cache retains every entity → OOM at large N.

For Kotlin Flow + reactive: similar concept, suspend-based.

---

## 15. Concurrency patterns

### Fork-join (parallel-stream alternative)

```kotlin
// Sequential
val results = items.map { expensive(it) }   // each takes 100ms; total N×100ms

// Parallel — Java parallel stream
val results = items.parallelStream().map { expensive(it) }.toList()
// uses ForkJoinPool.commonPool()

// Kotlin coroutines — preferred for I/O-bound
val results = items.map { async { expensive(it) } }.awaitAll()
```

**Watch:** `parallelStream` uses the common pool, which may be shared with other code → starvation. For Spring services, explicit `Executors.newFixedThreadPool(N)` is safer.

**For I/O-bound work** (HTTP calls, DB queries): coroutines (`Dispatchers.IO`) beat parallel streams.
**For CPU-bound work** (computation): parallel streams or `Dispatchers.Default` are fine.

### Bounded concurrency

```kotlin
val semaphore = Semaphore(10)   // max 10 concurrent

items.map { async {
    semaphore.withPermit { externalCall(it) }
}}.awaitAll()
```

Prevents overwhelming external service (vendor API rate limits, internal service capacity).

---

## 16. Quick decision: what algorithmic shape do I have?

| Pattern in code | Shape |
|---|---|
| Single loop over N items | O(N) — fine |
| Nested loop with `contains` | O(N²) — fix with index |
| Loop with `sortedBy` inside | O(N² log N) — hoist or use heap |
| Loop calling repo per item | N+1 — bulk fetch |
| Cache hit on every read | O(1) per op — done |
| `firstOrNull` with `.filter` on large data | O(N) worst case; fine, but consider DB query |
| Hash lookup | O(1) avg, O(log N) worst (JDK 8+ red-black) |
| Tree lookup | O(log N) |
| BFS / DFS on graph | O(V + E) |
| Cartesian product / pair generation | O(N²) — usually rethink |
| Recursion on N | check stack; usually O(N) but be aware of depth |

---

## 17. Pitfalls

- **`list.contains` inside a loop.** O(N²). Always fix with Set.
- **`map.values.find` repeatedly.** Use a secondary index map.
- **Sorting large data in memory when SQL `ORDER BY + LIMIT` is available.** Push to DB.
- **`for ... { repo.findById(id) }`.** N+1. Bulk fetch.
- **`Stream` operations without realising allocations.** Each step allocates intermediate. Sequence may not but sort still does.
- **`list.indexOf` then `list[idx]`.** Two scans. Just `list.first { ... }`.
- **`HashMap` with mutable keys.** Mutating after putting → key hashes differently → entries become invisible.
- **Re-computing the same expensive value in a loop.** Hoist.
- **`distinct` on `data class` without proper equals/hashCode.** Won't dedup. (data classes auto-generate; non-data classes don't.)
- **Sorting then filtering when filter-then-sort is cheaper.** If filter reduces N significantly, do it first.
