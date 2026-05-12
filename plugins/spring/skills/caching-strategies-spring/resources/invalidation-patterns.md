# Invalidation Patterns

When and how to invalidate. TTL strategy. Cache-aside vs read-through vs write-through vs write-behind vs refresh-ahead. Stampede / dogpile / thundering herd mitigation.

---

## 1. The five canonical patterns

```
┌─────────────────────┐
│  Cache-aside        │  App manages: read miss → load → put; write → update store, evict cache
│  (lazy loading)     │  Default. Most flexible.
├─────────────────────┤
│  Read-through       │  Cache library loads on miss; app just calls cache.get(key)
│                     │  Caffeine LoadingCache. Spring @Cacheable.
├─────────────────────┤
│  Write-through      │  Write hits cache AND store synchronously, in same operation.
│                     │  Used when cache must reflect every write immediately.
├─────────────────────┤
│  Write-behind       │  Write hits cache; background flushes to store async.
│  (write-back)       │  Fast writes, risk of loss on crash.
├─────────────────────┤
│  Refresh-ahead      │  Cache proactively reloads near-expiry entries before they expire.
│                     │  Caffeine refreshAfterWrite. Zero-staleness for hot keys.
└─────────────────────┘
```

### Which to pick

| Use case | Pattern |
|---|---|
| Read-heavy, tolerate staleness | Cache-aside or read-through with TTL |
| Write-then-immediate-read | Cache-aside with explicit `@CacheEvict` or `@CachePut` |
| Hot keys with strict latency | Refresh-ahead (Caffeine `refreshAfterWrite`) |
| Audit / accumulation writes | Write-behind (queue + bulk flush) — but consider message queue instead |
| Fundamentally synchronous semantics | Write-through (or no cache at all) |

**Default: cache-aside + TTL + event-driven invalidation.** Write-behind is rare in correct implementations.

---

## 2. TTL strategy

### Always set a TTL, even when invalidating on events

```
TTL is the floor of consistency guarantees.
Events are the optimisation that reduces staleness below TTL.
If events miss → TTL bounds the damage.
```

```kotlin
// Right
@Cacheable(cacheNames = ["orders"], key = "#id")     // 15min TTL configured on cache
fun findById(id: UUID): OrderView? = …

@CacheEvict(cacheNames = ["orders"], key = "#event.orderId")
@EventListener
fun onOrderChanged(event: OrderChanged) { … }       // event-driven invalidation
```

If `OrderChanged` event is dropped, stale data resolves itself within 15 minutes.

### Picking TTL

| Data type | Suggested TTL | Rationale |
|---|---|---|
| Static reference (country list) | 24h | Rarely changes; if it does, deploy bumps it |
| User profile (rarely updated by user) | 1h with event invalidation | Long TTL acceptable; events reduce real staleness |
| Order state | 5min | Updates frequently; users notice latency |
| Pricing (frequent recompute) | 30s | Acceptable freshness window |
| Authorisation tokens | match token lifetime | Don't cache past validity |
| Search results page 1 | 2min | Search is approximate anyway |

### Stagger TTLs to avoid synchronised expiry storm

If a cache fills at startup, all entries expire ~simultaneously and trigger a load spike. Add jitter:

```kotlin
.expireAfter(object : Expiry<Any, Any> {
    override fun expireAfterCreate(key: Any, value: Any, currentTime: Long): Long {
        val baseSeconds = 900L                                  // 15min base
        val jitter = ThreadLocalRandom.current().nextLong(0, 120) // +/- 2min
        return Duration.ofSeconds(baseSeconds + jitter).toNanos()
    }
    override fun expireAfterUpdate(key: Any, value: Any, currentTime: Long, currentDuration: Long) = currentDuration
    override fun expireAfterRead(key: Any, value: Any, currentTime: Long, currentDuration: Long) = currentDuration
})
```

---

## 3. Cache-aside — the default pattern

```kotlin
@Service
class OrderService(
    private val cache: Cache<UUID, OrderView>,
    private val repo: OrderRepository,
) {
    fun findById(id: UUID): OrderView? =
        cache.getIfPresent(id) ?: loadAndCache(id)

    fun update(id: UUID, mutation: (Order) -> Unit) {
        val order = repo.findById(id) ?: throw NotFoundException("Order", id)
        mutation(order)
        repo.save(order)
        cache.invalidate(id)            // evict on write; next read loads fresh
    }

    private fun loadAndCache(id: UUID): OrderView? = repo.findById(id)
        ?.toView()
        ?.also { cache.put(id, it) }
}
```

**Rules:**
- Reads check cache first; load from store on miss.
- Writes update the store, then **invalidate** the cache (don't write to cache directly — race with concurrent reads).
- Subsequent read loads the new value lazily.

### Why invalidate (not update) on write

```
Time   Thread A (write)       Thread B (read)         Cache state
t=0    update DB to V2                                 has V1
t=1                            check cache → V1        has V1
t=2    cache.put(V2)                                   has V2
t=3                            return V1 to caller     has V2  ← STALE
```

If you `cache.put(V2)` on write, a concurrent read might have just fetched V1 from cache before the put. The reader returns V1, then future reads correctly get V2 — but the one caller already saw V1.

Invalidation makes the next reader **load fresh from DB**, eliminating the race window. Trade-off: extra DB hit. For OLTP this is usually acceptable.

---

## 4. Read-through — cache library loads

```kotlin
val cache: LoadingCache<UUID, OrderView> = Caffeine.newBuilder()
    .maximumSize(10_000)
    .expireAfterWrite(Duration.ofMinutes(15))
    .build { id -> repo.findById(id)?.toView() ?: throw NoSuchElementException() }

val view = cache.get(orderId)   // loads on miss, caches result
```

Spring `@Cacheable` is read-through underneath. Use when:
- The mapping from key to value is straightforward (single repo lookup).
- All callers want the same view.

Don't use when:
- Different callers want different projections of the same data.
- The load fails for reasons callers want to handle differently.

---

## 5. Write-through — cache + store, synchronously

```kotlin
fun update(id: UUID, mutation: (Order) -> Unit) {
    val order = repo.findById(id) ?: throw NotFoundException("Order", id)
    mutation(order)
    repo.save(order)
    cache.put(id, order.toView())    // synchronous update — write-through
}
```

Trade-offs vs cache-aside-with-invalidate:
- **Pro:** subsequent reads find the new value already in cache. Saves a DB round-trip.
- **Con:** race with concurrent writers — if two threads both compute new views and both call `put`, last writer wins (which is usually fine but watch consistency).
- **Con:** put might fail (Redis down) — what do you do? Cache-aside is more robust because invalidation failure is acceptable (TTL recovers).

Use for hot read keys where the write-then-read window matters.

---

## 6. Write-behind — async flush

```kotlin
// Pseudo-pattern
class WriteBehindCache {
    private val queue: BlockingQueue<UpdateOp> = LinkedBlockingQueue(10_000)

    fun update(id: UUID, mutation: (Order) -> Unit) {
        cache.put(id, mutation(cache.get(id)!!))     // hit cache immediately
        queue.offer(UpdateOp(id, mutation))           // queue store update
    }

    @Scheduled(fixedDelay = 1000)
    fun flush() {
        val batch = queue.drainTo(mutableListOf(), 100)
        repo.saveAll(batch.map(::resolveToEntity))    // bulk write
    }
}
```

**Risks:**
- Loss on crash (queued writes not persisted).
- Reordering (concurrent updates queued out of order).
- Disk-spill if queue grows unboundedly.

**Most write-behind implementations are better expressed as a message queue + worker:**

```
Service → Kafka/RabbitMQ topic → Worker (consumes, batches, writes)
```

Use a real message bus, not a JVM in-memory queue.

---

## 7. Refresh-ahead — zero-stampede for hot keys

Caffeine `refreshAfterWrite`:

```kotlin
val cache: LoadingCache<UUID, OrderView> = Caffeine.newBuilder()
    .maximumSize(10_000)
    .refreshAfterWrite(Duration.ofMinutes(5))     // refresh in background after 5min
    .expireAfterWrite(Duration.ofMinutes(15))     // hard expiry at 15min
    .recordStats()
    .build { id -> repo.findById(id)?.toView() ?: throw NoSuchElementException() }
```

**Behaviour:**
- Read younger than 5min → return cached value.
- Read 5-15min old → return current cached value AND trigger async reload (caller doesn't wait).
- Read older than 15min → cache miss; reload synchronously.

Result: hot keys are continuously refreshed in the background; readers never wait beyond the first miss.

Killer for high-traffic hot keys (top products, popular search terms).

---

## 8. Cache stampede / dogpile / thundering herd

**Symptom:** a key expires, N concurrent readers all see the miss, all call the loader, the DB falls over.

### Mitigation 1: `sync = true` (Spring Cache)

```kotlin
@Cacheable(cacheNames = ["expensive"], key = "#input", sync = true)
fun expensive(input: String): Result = …
```

Concurrent callers block on one in-flight `Future`. Built into Spring Cache.

### Mitigation 2: probabilistic early expiration (XFetch)

For Redis cache, bug-fix at the algorithm level: each reader has a small probability of refreshing **before** TTL expires, distributing load.

```kotlin
fun get(key: String): T? {
    val entry = redis.get(key)
    if (entry != null) {
        val xfetch = -entry.delta * ln(Random.nextDouble())   // beta=1
        if (now + xfetch >= entry.expiresAt) {
            // refresh now even though entry still valid
            return refresh(key)
        }
        return entry.value
    }
    return refresh(key)
}
```

Original paper: *"Optimal Probabilistic Cache Stampede Prevention"* (Vattani et al., 2015). Library implementations exist for Redis.

### Mitigation 3: refresh-ahead (preferred)

See section 7. Background async reload eliminates the miss spike entirely. **Best option** when supported by your cache (Caffeine yes; Redis needs custom code).

### Mitigation 4: distributed lock (last resort)

```
Reader sees miss → acquires Redis lock on the key →
  loads value from DB →
  writes to cache →
  releases lock
Other concurrent readers wait on the lock
```

Painful. Locks can deadlock or expire mid-load. Use only when stampede is catastrophic and other mitigations don't apply.

### Mitigation 5: jittered TTL

Already covered in section 2.

---

## 9. Cold-start cache warming

**Problem:** service restart → all caches empty → first 1000 requests all miss → DB overwhelmed.

### Strategy A: pre-load on startup

```kotlin
@Component
class CacheWarmer(
    private val orderService: OrderService,
    private val hotKeys: HotKeysProvider,
) {
    @EventListener(ApplicationReadyEvent::class)
    fun warm() {
        hotKeys.topNOrders(1000).forEach { id ->
            orderService.findById(id)   // triggers cache load
        }
    }
}
```

**Caveats:**
- Slows startup time. For containers with health checks, the readiness probe should pass only after warming.
- Choosing "hot keys" is the hard part — usually from production-traffic analysis.

### Strategy B: rolling deploys (capacity-aware)

Don't restart all instances simultaneously. Rolling deploy: replace 1/N instances at a time. The cold instance has warm peers to redirect traffic until it warms up.

### Strategy C: keep-warm endpoint + traffic shaping

After deploy, gradually ramp traffic to new instance (10% → 50% → 100%) so its cache fills naturally without a thunder of misses.

---

## 10. Event-driven invalidation

For accuracy, combine TTL with explicit invalidation on the events that matter:

```kotlin
@Component
class OrderCacheInvalidator(private val cache: CacheManager) {

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    fun onOrderUpdated(event: OrderUpdated) {
        cache.getCache("orders")?.evict(event.orderId)
        cache.getCache("ordersByCustomer")?.evict(event.customerId)
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    fun onOrderCancelled(event: OrderCancelled) {
        cache.getCache("orders")?.evict(event.orderId)
    }
}
```

**Critical:** `AFTER_COMMIT` — invalidate **after** the DB commit, not before. Pre-commit invalidation creates a window where readers populate cache from uncommitted state.

For Spring Modulith, `@ApplicationModuleListener` runs after commit by default (it's transactional async).

### Cross-instance invalidation

If you're using local Caffeine on N instances, **DB event** invalidates only one instance's cache. Other instances serve stale until their TTL.

Options:
- **Use Redis instead** for shared state.
- **Two-tier with pub/sub** (see `local-vs-distributed.md` section 4).
- **Short TTL** — accept staleness within TTL window.
- **Cluster-aware cache** (Hazelcast, Apache Ignite) — heavy.

---

## 11. Negative caching (`null` results)

```kotlin
@Cacheable(cacheNames = ["orders"], key = "#id", unless = "#result == null")
fun findById(id: UUID): OrderView? = repo.findById(id)?.toView()
```

`unless = "#result == null"` means **don't cache nulls**. Reasonable default.

**When to cache nulls:** lookups for non-existent entities flood the DB. Cache the null briefly to absorb the storm.

```kotlin
@Cacheable(cacheNames = ["orders"], key = "#id")   // caches null by default
fun findById(id: UUID): OrderView? = repo.findById(id)?.toView()
```

**Caveats:**
- Use a separate cache region with shorter TTL for nulls. Otherwise stale "doesn't exist" persists for 15min after the entity is created.
- Better solution: bloom filter at the cache layer to short-circuit known-missing keys without a cache lookup.

---

## 12. Pitfalls quick reference

- **No TTL.** Permanent staleness when event is missed.
- **Invalidate before commit.** Reader populates cache from uncommitted state.
- **Cache `null` with same TTL as real entries.** "Doesn't exist" persists too long.
- **Write-through with two writers.** Last writer wins; might be different from DB final state.
- **Cache `Entity` not DTO.** Hibernate proxy + cache = LazyInitializationException at read.
- **All caches expire at the same time.** Synchronised storm. Jitter TTL.
- **No cache warming after deploy.** Cold start floods DB.
- **No metrics on cache hit ratio.** Degradation invisible.
- **Distributed cache for tiny data.** 10 entries don't deserve Redis.
- **In-process cache for cross-instance data.** Inconsistency.
- **Refresh-ahead without hard expiry.** If refresh fails, you serve stale forever.
- **Two-tier without pub/sub invalidation.** L1s diverge.
- **No fallback when cache is down.** Cache failure = app failure. Wrong.
