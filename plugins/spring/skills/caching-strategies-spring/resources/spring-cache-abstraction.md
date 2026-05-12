# Spring Cache Abstraction

Annotation API + programmatic API + SpEL keys + sync mode + cache manager configuration.

---

## 1. Enabling

```kotlin
@SpringBootApplication
@EnableCaching
class AssistaApplication

@Configuration
class CacheConfig {
    @Bean
    fun cacheManager(): CacheManager = CaffeineCacheManager().apply {
        setCaffeine(
            Caffeine.newBuilder()
                .maximumSize(10_000)
                .expireAfterWrite(Duration.ofMinutes(10))
                .recordStats()
        )
        setCacheNames(listOf("orders", "users", "tenants"))   // pre-defined regions
    }
}
```

**Rules:**
- `@EnableCaching` enables AOP-based interception. Like all Spring AOP, it works **only across bean boundaries** — self-invocation inside the same class **bypasses** the proxy.
- Declare cache names up-front when possible. Dynamic cache names (`cacheNames = "#orderType"`) create unmanaged caches at runtime, harder to monitor.
- Always `recordStats()` on Caffeine — feeds Micrometer.

---

## 2. `@Cacheable` — read-through

```kotlin
@Service
class OrderQueryService(private val orders: OrderRepository) {

    @Cacheable(cacheNames = ["orders"], key = "#id")
    fun findById(id: UUID): OrderView? = orders.findById(id)?.toView()
}
```

**On call:**
1. Compute key (SpEL or default `SimpleKeyGenerator`).
2. Cache `get(key)`. Hit → return cached value, skip method body.
3. Miss → invoke method, cache result (including `null` unless `unless` excludes).

**Pitfalls:**
- **Self-invocation bypass.** `orderService.findById(id)` from outside hits the proxy → cache. Calling `findById(id)` from another method inside `OrderQueryService` bypasses → no cache. Refactor to separate bean or call through `applicationContext.getBean()` (ugly).
- **Caching `null` by default.** Use `unless = "#result == null"` if you don't want null-caching. Or `@CacheEvict` on `null` writes.
- **Mutable return values.** If callers mutate the returned object, they mutate the cached entry too. Return immutable DTOs.

---

## 3. `@CacheEvict` — explicit invalidation

```kotlin
@Service
class OrderCommandService(...) {

    @CacheEvict(cacheNames = ["orders"], key = "#id")
    fun cancel(id: UUID) {
        val order = orders.findById(id) ?: throw NotFoundException("Order", id)
        order.cancel()
        orders.save(order)
    }

    @CacheEvict(cacheNames = ["orders"], allEntries = true)
    fun bulkArchive(...) { … }       // nuke entire region
}
```

**Notes:**
- `allEntries = true` clears the region; use sparingly.
- `beforeInvocation = true` evicts even if the method throws. Default `false` evicts only on success.
- For multi-key invalidation: `@Caching(evict = [@CacheEvict("orders", key = "#id"), @CacheEvict("orderSummaries", key = "#id")])`.

---

## 4. `@CachePut` — write-through update

```kotlin
@CachePut(cacheNames = ["orders"], key = "#order.id")
fun updateOrder(order: Order): Order { … return orders.save(order) }
```

Always invokes method; replaces cache entry with return value. Use when:
- The write returns the new state and you want the cache populated without an extra round-trip.
- You want eventual consistency via cache repopulation.

**Don't confuse with `@Cacheable`:** `@CachePut` does NOT skip the method, it always runs and updates the cache.

---

## 5. `@Caching` — composite

```kotlin
@Caching(
    evict = [
        CacheEvict(cacheNames = ["orderById"], key = "#order.id"),
        CacheEvict(cacheNames = ["ordersByCustomer"], key = "#order.customerId"),
        CacheEvict(cacheNames = ["orderSearch"], allEntries = true),
    ],
    put = [
        CachePut(cacheNames = ["orderById"], key = "#order.id"),
    ],
)
fun updateOrderAffectingMultipleCaches(order: Order): Order = … 
```

For operations that touch multiple cache regions — declarative is cleaner than multiple separate methods.

---

## 6. SpEL keys

Default key = all method args (`SimpleKeyGenerator`). Customise:

```kotlin
// Single arg
@Cacheable("orders", key = "#id")
fun findById(id: UUID)

// Property of arg
@Cacheable("users", key = "#user.email")
fun findUser(user: UserRef)

// Composite
@Cacheable("orderByCustomerStatus", key = "#customerId + '_' + #status")
fun findByCustomerAndStatus(customerId: UUID, status: OrderStatus)

// Method, args, root
@Cacheable("X", key = "#root.methodName + '_' + #root.args[0]")

// Hash for many-arg
@Cacheable("Y", keyGenerator = "customHashKeyGen")
```

**Watch:** every distinct key is a cache entry. Bad key choices → unbounded cache growth.

Common bug: caching by a request DTO with many fields. The cache key becomes too specific; hit ratio collapses. Use specific scalar args or a tuple.

---

## 7. `condition` and `unless`

```kotlin
@Cacheable(
    cacheNames = ["orders"],
    key = "#id",
    condition = "#tenantTier != 'PREMIUM'",     // skip caching for premium tenant
    unless = "#result == null || #result.status == 'DRAFT'",  // don't cache certain results
)
fun findById(id: UUID, tenantTier: String): OrderView?
```

- `condition` evaluated **before** invocation — skip cache lookup entirely if false.
- `unless` evaluated **after** invocation — don't store result if true (still calls method).

---

## 8. `sync = true` — stampede protection at the abstraction level

```kotlin
@Cacheable(cacheNames = ["heavyComputation"], key = "#input", sync = true)
fun compute(input: String): Result = … expensive
```

With `sync = true`:
- Concurrent callers with the same key block on one in-flight computation.
- Only one DB hit / external call even under burst load.
- Other callers wait for the same `Future`.

**Without `sync = true`** (default false): N concurrent misses → N parallel computations → N DB hits → cache stampede.

Use for:
- Expensive computations
- External API calls
- DB queries with high concurrency

**Caveat:** `sync = true` is a synchronisation barrier — if the load takes 5s and 1000 callers wait, the 1001st is held 5s. Use circuit breakers / timeouts upstream.

---

## 9. Programmatic API — when annotations don't fit

```kotlin
@Service
class OrderQueryService(
    private val cacheManager: CacheManager,
    private val repository: OrderRepository,
) {
    fun findById(id: UUID): OrderView? =
        cacheManager.getCache("orders")!!.get(id, Callable {
            repository.findById(id)?.toView()
        })

    fun findByIdNoCacheIfStale(id: UUID): OrderView? {
        val cache = cacheManager.getCache("orders")!!
        val cached = cache.get(id)?.get() as? OrderView
        return when {
            cached != null && !isStale(cached) -> cached
            else -> repository.findById(id)?.toView()
                ?.also { cache.put(id, it) }
        }
    }
}
```

Use programmatic when:
- Cache decision depends on **return value content** (not just `unless`)
- Conditional caching across multiple regions with custom logic
- You need to inspect cache contents (debugging, eviction policies)

Programmatic API is verbose but explicit. Annotations are concise but magic.

---

## 10. Cache configuration — per-region settings

```kotlin
@Bean
fun cacheManager(): CacheManager {
    val mgr = CaffeineCacheManager()

    // Default for un-registered names
    mgr.setCaffeine(Caffeine.newBuilder()
        .maximumSize(1000)
        .expireAfterWrite(Duration.ofMinutes(5))
        .recordStats())

    // Per-region overrides
    mgr.registerCustomCache("orders", Caffeine.newBuilder()
        .maximumSize(50_000)
        .expireAfterWrite(Duration.ofMinutes(15))
        .recordStats()
        .build())

    mgr.registerCustomCache("hotKeys", Caffeine.newBuilder()
        .maximumSize(100)
        .expireAfterWrite(Duration.ofSeconds(30))
        .recordStats()
        .build())

    return mgr
}
```

Or via properties (`application.yml`):

```yaml
spring:
  cache:
    type: caffeine
    cache-names: orders, users, tenants
    caffeine:
      spec: maximumSize=10000,expireAfterWrite=10m,recordStats
```

But per-region tuning needs the programmatic config above.

---

## 11. Observability — Micrometer auto-binding

With Caffeine `.recordStats()` + Micrometer:

```kotlin
@Bean
fun cacheMetricsRegistrar(meterRegistry: MeterRegistry, cacheManager: CacheManager) =
    CacheMetricsRegistrar(meterRegistry, cacheManager).also { registrar ->
        cacheManager.cacheNames.forEach { registrar.bindCacheToRegistry(cacheManager.getCache(it)!!) }
    }
```

Exposes:
- `cache.gets{cache="orders",result="hit"}` / `result="miss"`
- `cache.size{cache="orders"}`
- `cache.evictions{cache="orders"}`
- `cache.puts{cache="orders"}`
- `cache.load{cache="orders"}` — load times (Caffeine only)

Prometheus rules:

```yaml
# alert on degraded hit ratio
- alert: CacheHitRatioLow
  expr: |
    sum(rate(cache_gets_total{result="hit"}[5m])) by (cache)
      /
    sum(rate(cache_gets_total[5m])) by (cache) < 0.5
  for: 10m
```

A cache with no instrumentation is invisible. **Always** wire metrics.

---

## 12. Testing cached methods

```kotlin
@SpringBootTest
@ActiveProfiles("test")
class OrderCacheTest {

    @Autowired private lateinit var service: OrderQueryService
    @Autowired private lateinit var cacheManager: CacheManager
    @MockkBean private lateinit var repo: OrderRepository

    @BeforeEach
    fun clearCaches() {
        cacheManager.cacheNames.forEach { cacheManager.getCache(it)!!.clear() }
    }

    @Test
    fun `second call hits cache, repo not invoked twice`() {
        val id = UUID.randomUUID()
        every { repo.findById(id) } returns mockOrderEntity(id)

        service.findById(id)
        service.findById(id)

        verify(exactly = 1) { repo.findById(id) }
    }
}
```

For unit tests of the service **without** Spring context, bypass the cache layer — the proxy doesn't exist outside the container. Use `@SpringBootTest` for cache-specific tests, plain JUnit for logic.

---

## 13. Pitfalls quick reference

- **Self-invocation bypasses cache.** Same class → no proxy → no cache. Extract to a separate bean or call through application context.
- **Cache annotations on `private` methods.** Don't work — Spring AOP can't proxy them. Use `public` or `internal` (which is public in JVM).
- **`@Transactional` + `@Cacheable` ordering.** Default: `@Transactional` outer, `@Cacheable` inner. The transaction wraps the cache lookup — usually fine, but a long DB load inside the cache load extends the transaction. For sync caches with long loads, consider `@Transactional(propagation = NOT_SUPPORTED)` on the cached method.
- **Mutating cached return values.** Cached entry is the same reference. Subsequent callers see mutations. Use `Collections.unmodifiable*` or copy on return.
- **Cache region named identically across modules.** Two services with `@Cacheable("users")` share the cache. Often unintended. Namespace: `@Cacheable("billing.users")`.
- **`@CacheEvict(allEntries = true)` after every write.** Defeats the cache. Use targeted keys.
