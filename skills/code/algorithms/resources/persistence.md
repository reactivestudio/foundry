# Persistence — Cache and Idempotency Shape

Algorithmic correctness in state-keeping primitives. Caches and idempotency stores look like performance tools but their *shape* — what they're keyed by, what they hold — is a correctness concern. The footguns below are the ones v1 of this skill missed because the framing was perf-only.

## cache-key incomplete

**Signature**: a cached function whose key omits a parameter that affects the result.

```kotlin
data class SearchKey(
    val queryNormalized: String,
    val categoryId: UUID?,
    val tenantId: UUID,
)

private val resultCache = ConcurrentHashMap<SearchKey, SearchResponse>()

fun search(req: SearchRequest): SearchResponse {
    val key = SearchKey(req.query?.lowercase()?.trim() ?: "", req.categoryId, req.tenantId)
    resultCache[key]?.let { return it }
    // … computes a paginated result that depends on req.page and req.size … 
}
```

**Bug**: the key has no `page` / `size`. Requesting page 2 returns the cached *page 1* response. No error, just wrong data.

**Fix**: enumerate every input that affects the output. If any value changes the result, it belongs in the key. For paginated results: `(query, categoryId, tenantId, page, size, sort)`. Better yet — make the key derive from the request, not be hand-rolled:

```kotlin
private val resultCache = ConcurrentHashMap<SearchRequest, SearchResponse>()  // request IS the key
```

**Audit rule**: for any cached function, list every parameter and ask "could this change the result?" If yes, key must include it.

## idempotency-key incomplete

**Signature**: an idempotency check whose key collapses distinct legitimate events.

```kotlin
data class IdempotencyKey(
    val eventType: String,
    val aggregateId: UUID,
    val tenantId: UUID,
)

if (key in processedKeys) return false
```

**Bug**: two `ORDER_UPDATED` events for the same order — different timestamps, different fields — produce the *same* idempotency key. The second update is silently dropped.

**Fix**: idempotency keys are about message identity, not aggregate identity. Include the event's own ID or sequence number:

```kotlin
data class IdempotencyKey(
    val eventId: UUID,                // ← message identity
    val tenantId: UUID,
)
```

The fix is the opposite of cache-key incompleteness: caches key by *what the result depends on*; idempotency keys key by *what made the message unique*.

## mutable-key cache phantom

Cross-reference [kotlin.md](kotlin.md). If your cache or idempotency key is a `data class` and any property is `var`, the entry becomes unreachable the moment that property mutates. Audit rule: every key type, every property `val`. No exceptions.

## cache write-through staleness

**Signature**: a cached object mutated in-place, then written back to a store.

```kotlin
// SMELL — mutates the cached instance
val existing = projectionCache[event.orderId]
    ?: orderProjectionRepo.findById(event.orderId).orElseThrow()
existing.items = newItems
existing.total = newItems.sumOf { it.price }
projectionCache[event.orderId] = existing
orderProjectionRepo.save(existing)
```

**Bug**: if `save()` fails (DB outage, constraint violation), the cache holds the new state but the DB has the old. Subsequent reads from cache return non-durable data.

**Fix**: copy or rebuild the object; write to the store *first*, then update cache only on success.

```kotlin
val updated = existing.copy(items = newItems, total = newItems.sumOf { it.price })
orderProjectionRepo.save(updated)            // throws on failure
projectionCache[event.orderId] = updated     // only reached on success
```

If the cached type is mutable and can't be `copy`'d, the cache itself is the smell.

## N+1 across DTO graph

**Signature**: a DTO field typed as a JPA-mapped collection (or transitively contains one) returned through serialization.

```kotlin
class OrderDto(val id: UUID, val items: List<Item>)   // items is @OneToMany

fun listOrders(): List<OrderDto> = repo.findAll().map { OrderDto(it.id, it.items) }
```

**Bug**: Jackson serialises each `OrderDto.items` — lazy collection access fires one query per order. Either `LazyInitializationException` (transaction closed) or N+1 (transaction held open via Open Session In View).

**Fix**: project to a flat DTO inside the transaction, eager-fetch via `@EntityGraph`, or use a fetch profile. See [spring.md](spring.md) for the JPA-side resolutions.

The algorithmic shape: any DTO graph whose leaf is a JPA collection is implicitly N+1 unless explicitly fetched.

## cache-unbounded (lane-discipline reminder)

Caches without `maximumSize` / TTL leak memory and eventually OOM. This is a real bug but the **fix is configuration**, not algorithm — defer to a caching library (Caffeine, Guava) and the project's caching skill if it exists. The role of *this* skill: flag at the cache definition site, in one sentence. Do not propose Caffeine wiring code.

---

## Quick recognition heuristics

1. Every cached function: list parameters. Each one that affects the result is in the key. Any *missing* parameter is a bug.
2. Every idempotency key: includes message identity (event ID / sequence number), not just aggregate identity.
3. Every key type: all properties `val`. No `var`. Cross-check [kotlin.md](kotlin.md).
4. Every cache write: is it write-through? If yes, the write to store must happen *before* the cache update, with rollback semantics if the store fails.
5. Every DTO returned from a service: contains no JPA-mapped collection unless `@EntityGraph` or projection guarantees the fetch. Defer detailed fix to [spring.md](spring.md).
