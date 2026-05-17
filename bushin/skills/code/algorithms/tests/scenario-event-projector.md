# Scenario — Order Projection / Event Handler

Idempotency-key shape and cache correctness. Probes the area v1 missed: semantic bugs in cache/idempotency keys that affect correctness, not just performance.

## Prompt (paste verbatim)

````
Code review event-handler'а проекций. Готов ли к merge?

```kotlin
@Service
class OrderProjectionService(
    private val orderProjectionRepo: OrderProjectionRepository,
    private val customerRepo: CustomerRepository,
    private val productCatalogRepo: ProductCatalogRepository,
) {
    private val projectionCache = ConcurrentHashMap<UUID, OrderProjection>()
    private val customerInfoCache = ConcurrentHashMap<String, CustomerInfo>()
    private val processedKeys = HashSet<IdempotencyKey>()

    data class IdempotencyKey(
        val eventType: String,
        var aggregateId: UUID,
        val tenantId: UUID,
    )

    fun handleEvent(event: OrderEvent): Boolean {
        val key = IdempotencyKey(event.type, event.orderId, event.tenantId)
        if (key in processedKeys) return false

        when (event.type) {
            "ORDER_CREATED" -> handleCreated(event)
            "ORDER_UPDATED" -> handleUpdated(event)
            "ORDER_SHIPPED"  -> handleShipped(event)
        }

        processedKeys.add(key)
        return true
    }

    private fun handleCreated(event: OrderEvent) {
        val customer = customerInfoCache.getOrPut(event.customerEmail) {
            val c = customerRepo.findByEmail(event.customerEmail)
            CustomerInfo(c.name, c.tier)
        }
        val items = event.itemIds.map { productCatalogRepo.findById(it).orElseThrow() }
        val total = items.sumOf { it.price }
        val projection = OrderProjection(
            id = event.orderId,
            customerName = customer.name,
            items = items.toMutableList(),
            total = total,
            status = "CREATED",
            createdAt = event.timestamp,
        )
        projectionCache[event.orderId] = projection
        orderProjectionRepo.save(projection)
    }

    private fun handleUpdated(event: OrderEvent) {
        val existing = projectionCache[event.orderId]
            ?: orderProjectionRepo.findById(event.orderId).orElseThrow()
        val items = event.itemIds.map { productCatalogRepo.findById(it).orElseThrow() }
        existing.items = items.toMutableList()
        existing.total = items.sumOf { it.price }
        projectionCache[event.orderId] = existing
        orderProjectionRepo.save(existing)
    }

    private fun handleShipped(event: OrderEvent) {
        val all = orderProjectionRepo.findAll()
        val existing = all.first { it.id == event.orderId }
        existing.status = "SHIPPED"
        existing.shippedAt = event.timestamp
        orderProjectionRepo.save(existing)
    }

    fun getRecentProjections(limit: Int): List<OrderProjection> {
        val all = orderProjectionRepo.findAll()
        return all.sortedByDescending { it.createdAt }.take(limit)
    }
}
```
````

## Rubric — 13 traps + 3 false positives

### Correctness — semantic shape bugs (4)

| # | Pattern | Where | Severity |
|---|---|---|---|
| 1 | **idempotency-key-incomplete** | `IdempotencyKey(eventType, orderId, tenantId)` — multiple legitimate `ORDER_UPDATED` events for same order are deduplicated after the first. Must include event ID or sequence/version. | 🔴 critical, silent dataloss |
| 2 | **mutable-key cache phantom** | `var aggregateId` in `IdempotencyKey` used in `HashSet<IdempotencyKey>`. Mutation makes the entry unreachable. | 🔴 critical |
| 3 | **HashSet thread safety** | `processedKeys = HashSet<>()` mutated by concurrent event handlers — race; can let duplicates through or throw `CME` | 🔴 critical |
| 4 | **mutation-through-cached-reference** | `existing.items = ...` mutates the `OrderProjection` held in `projectionCache`. If `save()` fails after, cache holds the new state but DB has the old. | 🟠 high, data integrity |

### Algorithmic shape (6)

| # | Pattern | Where | Severity |
|---|---|---|---|
| 5 | **N+1 cascade** (created handler) | `event.itemIds.map { productCatalogRepo.findById(it).orElseThrow() }` | 🔴 critical |
| 6 | **N+1 cascade** (updated handler) | same pattern in `handleUpdated` | 🔴 critical |
| 7 | **bulk-fetch missed** (fix for #5 and #6) | `productCatalogRepo.findAllById(event.itemIds).associateBy { it.id }` | 🟠 high |
| 8 | **findAll-and-first** | `orderProjectionRepo.findAll().first { it.id == event.orderId }` in `handleShipped` — should be `findById`. Critical: full table scan to find one row. | 🔴 critical |
| 9 | **findAll-and-sort-take** | `orderProjectionRepo.findAll().sortedByDescending.take(limit)` in `getRecentProjections` — should be `findTopNByOrderByCreatedAtDesc` or `Pageable` | 🔴 critical, scales with N |
| 10 | **sort-then-take-K active call** | for #9, if `N` (projection count) is large and `limit` is small (e.g., 10), the JVM-side sort+take is `O(N log N)` over the whole DB. Fix is to push to DB. **Note**: this is *active* sort-then-take-K — opposite of the bounded-N restraint case. The discriminator is whether the skill correctly identifies which regime applies. | 🔴 critical |

### Kotlin / atomicity (1)

| # | Pattern | Where | Severity |
|---|---|---|---|
| 11 | **getOrPut atomic illusion** | `customerInfoCache.getOrPut(event.customerEmail) { customerRepo.findByEmail(...) }` on `ConcurrentHashMap` — non-atomic; under concurrent events for the same customer, `findByEmail` may run twice | 🟠 high |

### Lane discipline / adjacent (2)

| # | Pattern | Where | Skill should… |
|---|---|---|---|
| 12 | **cache-unbounded** (×3) | `projectionCache`, `customerInfoCache`, `processedKeys` — all unbounded, all grow per unique event | flag briefly, defer to caching skill |
| 13 | **in-memory idempotency not durable** | `processedKeys` is in-process; service restart loses idempotency state. Real systems need durable store. | flag briefly, defer to messaging skill |

### Restraint false-positives (3)

| # | Pattern | Where | Expected behavior |
|---|---|---|---|
| 14 | **`when` over event type** | `when (event.type) { "ORDER_CREATED" -> ... }` — fine; **don't** suggest strategy pattern / enum dispatch | leave |
| 15 | **cache-or-DB lookup** | `projectionCache[event.orderId] ?: orderProjectionRepo.findById(event.orderId).orElseThrow()` — clear, idiomatic | leave |
| 16 | **`items.sumOf { it.price }`** | bounded N (items per order ≤ 100ish typically), no need to refactor | leave |

### Procedure (1)

| # | Behavior | Expected |
|---|---|---|
| P1 | Asked event throughput / projection table size / typical `limit` before recommending | v2 must |

## Scoring sheet

```
| Trap | Baseline | v1 | v2 |
|------|----------|----|----|
|  1   |          |    |    |
|  2   |          |    |    |
| ...  |          |    |    |
| P1   |          |    |    |
```

## Predicted baseline behavior

Likely catches:
- 3 (HashSet thread safety — common idiom)
- 5, 6 (N+1 — visible)
- 8 (findAll for one row — visible)
- 9 (findAll for recent — visible)
- 12 (cache leak — common to mention)

Likely misses or weak:
- 1 (incomplete idempotency key — needs reasoning about event semantics; baseline often gives generic "use durable store" without naming the *key shape* bug)
- 2 (mutable var in idempotency key) — same kind of trap as catalog-search test 16; baseline sometimes catches there because v1 amplified the lesson; here baseline may pattern-match it
- 4 (mutation through cached reference) — subtle; baseline often misses the consistency consequence
- 10 (active sort-then-take-K — the *active* case, opposite of bounded-N restraint) — depends on whether baseline names the actual fix
- 11 (getOrPut atomicity) — v1's exclusive win
- P1 (named N) — no

This scenario is the **correctness-shape** test: traps 1–4 are about whether the skill catches semantic bugs that look like cache/idempotency code but are actually shape bugs. v1 missed the analogous bug (cache-key-incomplete) in catalog-search; v2 must catch it cleanly here.
