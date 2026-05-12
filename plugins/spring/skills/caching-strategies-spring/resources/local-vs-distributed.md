# Local vs Distributed — Caffeine, Redis, and Two-Tier

How to pick, configure, and integrate each store. Serialization. Cluster modes. Two-tier (Caffeine L1 + Redis L2).

---

## 1. Decision tree

```
Need cross-instance consistency?
├── No  → CAFFEINE (in-process). Done.
└── Yes
    │
    Is the cache hot enough that 1ms Redis round-trip matters?
    ├── No  → REDIS only. Simple, shared, ~1ms.
    └── Yes
        │
        Tolerate brief per-instance staleness across invalidations?
        ├── Yes → TWO-TIER (Caffeine L1 + Redis L2 + pub/sub invalidation)
        └── No  → Pure REDIS + accept latency. Two-tier brings invalidation race conditions.
```

| Property | Caffeine | Redis | Two-tier |
|---|---|---|---|
| Access latency | 50ns | 0.5-2ms | 50ns hit / 1ms L2 fallback |
| Shared across instances | No | Yes | L2 yes, L1 per-instance |
| Survives restart | No | Yes (with persistence) | L2 yes |
| Memory cost | Per-instance heap | One Redis node | Both |
| Operational complexity | None | Medium | High |
| Best for | Per-instance hot reads | Shared state across instances | Read-heavy with strict latency + cross-instance dedup |

---

## 2. Caffeine — local in-process

### Build basics

```kotlin
val cache: Cache<UUID, OrderView> = Caffeine.newBuilder()
    .maximumSize(10_000)
    .expireAfterWrite(Duration.ofMinutes(15))
    .recordStats()
    .build()

cache.put(orderId, view)
val v: OrderView? = cache.getIfPresent(orderId)
val loaded: OrderView = cache.get(orderId) { loadFromDB(it) }
```

### Eviction policies

| Policy | Trigger |
|---|---|
| `maximumSize(N)` | LRU/LFU-hybrid (Window TinyLFU) — most recent + most frequent stay |
| `maximumWeight(W) + .weigher { _, v -> v.sizeBytes }` | Size-based for variable-weight entries (large blobs) |
| `expireAfterWrite(t)` | Hard TTL from insert; classic cache TTL |
| `expireAfterAccess(t)` | TTL refreshed on every read; for "hot if accessed" data |
| `expireAfter(Expiry)` | Per-entry custom expiry — different TTL per key |
| `refreshAfterWrite(t)` | Async refresh; old value served while new one loads |

### `refreshAfterWrite` for zero-stampede hot reads

```kotlin
val cache: LoadingCache<UUID, OrderView> = Caffeine.newBuilder()
    .maximumSize(10_000)
    .refreshAfterWrite(Duration.ofMinutes(5))   // refresh in background
    .expireAfterWrite(Duration.ofMinutes(15))   // hard TTL — never serve older than 15min
    .recordStats()
    .build { id -> loadFromDB(id) }

// Reads: always return cached. If older than 5min and concurrent load possible,
// trigger async reload but serve stale value. Hard cap at 15min.
val v = cache.get(orderId)!!
```

Killer for hot keys: no stampede, no staleness > hard TTL.

### Async loading (suspend / CompletableFuture)

```kotlin
val asyncCache: AsyncLoadingCache<UUID, OrderView> = Caffeine.newBuilder()
    .maximumSize(10_000)
    .expireAfterWrite(Duration.ofMinutes(15))
    .buildAsync { id, _ ->
        CompletableFuture.supplyAsync { loadFromDB(id) }
    }

// In a coroutine:
val view: OrderView = asyncCache.get(id).await()
```

For non-blocking workflows (WebFlux, coroutines), use `AsyncCache` to avoid blocking the load thread.

### Stats — Micrometer integration

```kotlin
@Bean
fun caffeineCacheConfig(): CacheManager =
    CaffeineCacheManager().apply {
        setCaffeine(Caffeine.newBuilder()
            .maximumSize(10_000)
            .expireAfterWrite(Duration.ofMinutes(15))
            .recordStats())                  // critical for Micrometer auto-binding
    }
```

`recordStats()` is **not free** (~5% overhead) but it's worth it for observability.

### Memory footprint pitfalls

- `maximumSize` is count, not bytes. 10K entries × 100KB each = 1GB heap.
- For variable-size values, use `maximumWeight()` + weigher.
- Soft / weak reference caches (`softValues`, `weakKeys`) — sound clever, behave unpredictably under GC pressure. Avoid in production unless you've measured.

---

## 3. Redis — distributed

### Setup

```kotlin
// build.gradle.kts
implementation("org.springframework.boot:spring-boot-starter-data-redis")
implementation("io.lettuce:lettuce-core")    // Lettuce: async/coroutines, default in Boot 3+
```

```yaml
spring:
  data:
    redis:
      host: redis.internal
      port: 6379
      password: ${REDIS_PASSWORD}
      timeout: 3s
      lettuce:
        pool:
          enabled: true
          max-active: 16
          max-idle: 8
          min-idle: 2
```

### Cache manager

```kotlin
@Bean
fun redisCacheManager(connectionFactory: RedisConnectionFactory): RedisCacheManager {
    val defaultConfig = RedisCacheConfiguration.defaultCacheConfig()
        .entryTtl(Duration.ofMinutes(15))
        .serializeKeysWith(RedisSerializationContext.SerializationPair.fromSerializer(StringRedisSerializer()))
        .serializeValuesWith(RedisSerializationContext.SerializationPair.fromSerializer(jsonSerializer()))
        .disableCachingNullValues()    // don't cache nulls
        .computePrefixWith { name -> "assista::cache::$name::" }

    val perCacheConfigs = mapOf(
        "orders"       to defaultConfig.entryTtl(Duration.ofMinutes(30)),
        "userSessions" to defaultConfig.entryTtl(Duration.ofHours(1)),
        "hotKeys"      to defaultConfig.entryTtl(Duration.ofSeconds(30)),
    )

    return RedisCacheManager.builder(connectionFactory)
        .cacheDefaults(defaultConfig)
        .withInitialCacheConfigurations(perCacheConfigs)
        .build()
}

private fun jsonSerializer(): RedisSerializer<Any> =
    GenericJackson2JsonRedisSerializer(
        jacksonObjectMapper()
            .registerModule(JavaTimeModule())
            .activateDefaultTyping(LaissezFaireSubTypeValidator.instance,
                                   ObjectMapper.DefaultTyping.NON_FINAL,
                                   JsonTypeInfo.As.PROPERTY)
    )
```

**Critical:**
- `computePrefixWith { name -> "assista::cache::$name::" }` — namespace your keys. Without this, multi-app on same Redis conflicts.
- `disableCachingNullValues()` — usually right; nulls are not data.
- `serializeValuesWith` — explicit serializer. Default JDK serialization is slow, brittle, and refuses polymorphic types.

### Serialization choice

| Serializer | Speed | Cross-version safety | Polymorphism |
|---|---|---|---|
| JDK (default) | Slow | Breaks on field add/remove | Fine |
| **`GenericJackson2JsonRedisSerializer`** | Medium | OK if backward-compatible | Needs `activateDefaultTyping` |
| `Jackson2JsonRedisSerializer<T>` | Medium | Same | Only for fixed type |
| `Kotlin Serialization` | Medium | Strict by `@SerialName` | Sealed classes work great |
| MessagePack / Protobuf | Fast, compact | Strong schema discipline | Yes |
| Snappy/LZ4 wrapper | Reduces network | Same | N/A |

**Default for Spring/Kotlin shops: `GenericJackson2JsonRedisSerializer` + Jackson Kotlin module.** Inspectable in `redis-cli` (JSON). Pin the Jackson version and treat the schema as a contract.

### Connection pool tuning

```yaml
spring:
  data:
    redis:
      lettuce:
        pool:
          max-active: 16      # ~ cores * 2
          max-idle: 8
          min-idle: 2
```

Lettuce is non-blocking and multiplexes commands on a single connection; pool size matters less than Jedis. Default is usually fine.

### Cluster mode

```yaml
spring:
  data:
    redis:
      cluster:
        nodes: redis-1.internal:6379, redis-2.internal:6379, redis-3.internal:6379
        max-redirects: 3
```

For sharded Redis. Keys are hashed across slots. Group related keys with hash tags: `user::{userId}::profile` and `user::{userId}::prefs` end up in the same shard (the `{}` is the hash tag).

### Sentinel mode (HA)

```yaml
spring:
  data:
    redis:
      sentinel:
        master: mymaster
        nodes: sentinel-1:26379, sentinel-2:26379, sentinel-3:26379
```

Single logical Redis with automatic failover.

### Fault tolerance

```kotlin
@Bean
fun cacheErrorHandler(): CacheErrorHandler = object : CacheErrorHandler {
    private val log = LoggerFactory.getLogger(javaClass)

    override fun handleCacheGetError(ex: RuntimeException, cache: Cache, key: Any) {
        log.warn("Cache GET error for {}: {}", cache.name, ex.message)
        // do NOT rethrow — fall through to underlying load
    }
    override fun handleCachePutError(ex: RuntimeException, cache: Cache, key: Any, value: Any?) {
        log.warn("Cache PUT error for {}: {}", cache.name, ex.message)
    }
    override fun handleCacheEvictError(ex: RuntimeException, cache: Cache, key: Any) { … }
    override fun handleCacheClearError(ex: RuntimeException, cache: Cache) { … }
}

@Configuration
@EnableCaching
class CachingConfig(private val cacheManager: CacheManager,
                    private val errorHandler: CacheErrorHandler) : CachingConfigurer {
    override fun errorHandler(): CacheErrorHandler = errorHandler
    override fun cacheManager(): CacheManager = cacheManager
}
```

Redis down ≠ application down. With this error handler, cache errors fall through to the underlying loader — the app continues without cache.

---

## 4. Two-tier: Caffeine L1 + Redis L2

When you want both **sub-millisecond local** and **cross-instance consistency**.

### Architecture

```
┌─ Instance A ─────────────┐       ┌─ Instance B ─────────────┐
│  Caffeine L1 (5min)      │       │  Caffeine L1 (5min)      │
│        │                 │       │        │                 │
└────────┼─────────────────┘       └────────┼─────────────────┘
         │ miss                              │ miss
         ▼                                   ▼
    ┌────────────────────────────────────────────┐
    │   Redis L2 (30min) + pub/sub channel       │
    └────────────────────────────────────────────┘
                          │ invalidation event
                          ▼
              All instances clear matching L1 entry
```

### Manual implementation

```kotlin
@Component
class TwoTierCache<K : Any, V : Any>(
    private val name: String,
    private val redisTemplate: RedisTemplate<String, V>,
    private val pubsub: ReactiveRedisOperations<String, String>,
) {
    private val local: Cache<K, V> = Caffeine.newBuilder()
        .maximumSize(5_000)
        .expireAfterWrite(Duration.ofMinutes(5))
        .recordStats()
        .build()

    private val invalidationChannel = "cache::invalidate::$name"

    init {
        pubsub.listenTo(ChannelTopic.of(invalidationChannel)).subscribe { msg ->
            val key = msg.message as? K ?: return@subscribe
            local.invalidate(key)
        }
    }

    fun get(key: K, loader: (K) -> V): V {
        local.getIfPresent(key)?.let { return it }
        val fromRedis = redisTemplate.opsForValue().get(redisKey(key))
        if (fromRedis != null) {
            local.put(key, fromRedis)
            return fromRedis
        }
        val loaded = loader(key)
        redisTemplate.opsForValue().set(redisKey(key), loaded, Duration.ofMinutes(30))
        local.put(key, loaded)
        return loaded
    }

    fun invalidate(key: K) {
        redisTemplate.delete(redisKey(key))
        local.invalidate(key)
        pubsub.convertAndSend(invalidationChannel, key.toString()).subscribe()
    }

    private fun redisKey(key: K) = "cache::$name::$key"
}
```

### Library option

For production, use a library that handles invalidation properly:

- **Caffeine + Redis combo with explicit invalidation pub/sub** (custom, as above)
- **Hazelcast** (alternative — JCache-compliant, has near-cache mode out of the box)

### Trade-offs

- **Read latency:** L1 hit = 50ns, L1 miss + L2 hit = ~1ms, both miss = load latency.
- **Invalidation race:** between Redis delete and pub/sub propagation, instances may briefly read stale L1 values. Acceptable for most use cases.
- **L1 size pressure:** if L1 is small relative to L2, eviction churn destroys benefit. Size L1 for working set.
- **Complexity:** every cache-coherence bug now has 3 places to investigate.

**Rule:** two-tier earns its keep only when (a) L1 latency dominates business value AND (b) cross-instance consistency is required. Most read-heavy services do fine with Redis alone.

---

## 5. Per-cache-name configuration patterns

```kotlin
@Configuration
class MultiCacheConfig {

    @Bean
    fun cacheManager(redisConnection: RedisConnectionFactory): CacheManager {
        val composite = CompositeCacheManager(
            // L1: hot small data
            CaffeineCacheManager().apply {
                setCaffeine(Caffeine.newBuilder().maximumSize(1000).expireAfterWrite(Duration.ofMinutes(5)).recordStats())
                setCacheNames(listOf("hotConfig", "featureFlags"))
            },
            // L2: cross-instance shared
            RedisCacheManager.builder(redisConnection)
                .cacheDefaults(redisCacheConfig(Duration.ofMinutes(15)))
                .withInitialCacheConfigurations(mapOf(
                    "userSessions" to redisCacheConfig(Duration.ofHours(1)),
                    "orderProjections" to redisCacheConfig(Duration.ofMinutes(30)),
                ))
                .build()
        )
        composite.setFallbackToNoOpCache(false)
        return composite
    }

    private fun redisCacheConfig(ttl: Duration) =
        RedisCacheConfiguration.defaultCacheConfig()
            .entryTtl(ttl)
            .computePrefixWith { name -> "assista::cache::$name::" }
            .disableCachingNullValues()
}
```

`@Cacheable("hotConfig")` resolves to Caffeine; `@Cacheable("orderProjections")` resolves to Redis. Composite cache manager picks the first manager that claims the name.

---

## 6. Stack mapping for assista-style polyglot

| Cache region | Store | TTL | Why |
|---|---|---|---|
| `featureFlags` | Caffeine | 30s (or reload-on-event) | Tiny, hot, per-instance is fine |
| `orderProjections` (read model) | Redis | 30min, event-invalidated | Cross-instance consistency for write-then-read |
| `userPrincipal` (post-JWT-validation) | Redis | 5min | Auth re-use across instances |
| `searchResultsPage1` | Caffeine | 2min | Hot, per-instance OK, tail pages don't cache |
| `analyticsRollupLastHour` | Redis | 5min | Shared across dashboard instances |
| `priceCalculation(productId, tier)` | Two-tier (Caffeine 30s L1 + Redis 5min L2) | | Sub-ms local + cross-instance dedup |
| `vendorApiResponses` (GitHub/Jira ACL) | Caffeine + circuit-breaker fallback | 1min | Vendor rate limits drive caching, per-instance OK |

---

## 7. Common pitfalls

- **JSON deserialization breaks on class refactor.** Add field → old cached entries still deserialize (null on new field). Remove field → old entries fail. Bump cache namespace (`assista::cache::v2::`) on schema change.
- **Polymorphic types in cache.** Without `activateDefaultTyping` (or Kotlin Serialization with `@SerialName`), Jackson loses the concrete type on deserialization. Carefully consider security of default typing.
- **Redis password leaks in stack traces.** Use environment variables, not config. Never log connection strings.
- **Connection pool exhaustion.** Lettuce single-connection multiplexing is usually fine; if you're seeing `LettuceConnection` saturation, your loader is slow and holding connections.
- **Caffeine `maximumSize` set wrong.** Too small → high churn, eviction in Micrometer; too big → heap pressure, GC.
- **Two-tier without invalidation pub/sub.** Each instance's L1 is independent. Without pub/sub, writes update L2 but instances see stale L1 for up to L1 TTL. Use one of: (a) tiny L1 TTL (30s-1min), (b) pub/sub invalidation, (c) accept the staleness.
