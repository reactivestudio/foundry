---
name: caching-strategies-spring
description: "Caching strategies for Kotlin/Spring Boot — Spring Cache abstraction with Caffeine (local in-process), Redis (distributed), two-tier hybrid (Caffeine L1 + Redis L2). Covers @Cacheable / @CacheEvict / @CachePut, invalidation patterns (cache-aside, write-through, write-behind, refresh-ahead), cache stampede / dogpile mitigation, TTL strategy, serialization, and observability via Micrometer. Use when adding a cache, debugging cache inconsistency, designing read-side performance, or picking between local and distributed."
risk: safe
source: "custom — caching patterns for Kotlin/Spring with Caffeine + Redis"
date_added: "2026-05-12"
---

# Caching Strategies (Kotlin / Spring Boot)

Caching is the easiest way to make a slow system fast and the easiest way to ship a stale-data bug. This skill defines when each strategy wins, how to wire it cleanly in Spring, and how to avoid the common production failure modes.

> A cache miss is a feature, not a bug. The bug is the wrong value served from a cache.

## Use this skill when

- A read endpoint repeats the same expensive query and the data tolerates eventual consistency
- Designing a new feature where read latency targets are tight (< 10ms p99)
- Picking between **Caffeine (local in-process)**, **Redis (distributed)**, or a **two-tier hybrid**
- Investigating cache stampede / dogpile / thundering herd symptoms
- Designing invalidation strategy (TTL vs event-driven vs hybrid)
- Replacing handwritten memoisation with Spring Cache abstraction

## Do not use this skill when

- The data is **fundamental write throughput** — caching writes is rare and usually wrong
- The use case is **read-side CQRS projection** — that's a different abstraction (see `cqrs-implementation/resources/read-side-patterns.md`)
- You're trying to "cache a fix" for an unindexed query — fix the index first (see `database-design/resources/indexing.md`)
- You need **session storage** — that's not a cache, that's Spring Session (different concern)
- The task is **HTTP response caching** at the API layer — that's REST `Cache-Control` / ETag in `api-design-principles/references/rest-best-practices.md`

## Selective Reading Rule

Read the file matching your task.

| File | Description | When to read |
|---|---|---|
| `resources/spring-cache-abstraction.md` | `@Cacheable` / `@CacheEvict` / `@CachePut` / `@Caching`; SpEL keys & conditions; `sync = true`; programmatic API via `CacheManager` | Wiring a cache; choosing annotations vs explicit |
| `resources/local-vs-distributed.md` | Caffeine deep (size / expiry / refresh / async loading / stats); Redis (Lettuce / Jedis, serialization, TLS, cluster, fault tolerance); two-tier (L1 Caffeine + L2 Redis) decision | Picking store; configuring Caffeine or Redis cache |
| `resources/invalidation-patterns.md` | Cache-aside / read-through / write-through / write-behind / refresh-ahead; TTL strategy; event-driven invalidation; stampede / dogpile mitigation; cold-start strategies | Designing invalidation; debugging staleness; high-traffic protection |

## Core principles

1. **Caching is for reads, not writes.** Don't cache writes. Don't try to make writes "eventually consistent through cache"; that's an outbox / event pattern.
2. **Local first, distributed when forced.** A Caffeine cache in the same JVM serves at 50ns. Redis adds a network hop (~1ms). Default to Caffeine; reach for Redis only when you need cross-instance consistency or large data.
3. **TTL is the floor, not the ceiling.** Always set a TTL even if you also invalidate on events. TTL bounds staleness if events are missed.
4. **The most dangerous cache is the silent one.** Without metrics (`cache.gets{result=miss}`, `cache.size`, hit ratio), a degraded cache is invisible. Expose Micrometer metrics, alert on hit-ratio drops.
5. **Cache the read model, not the aggregate.** Aggregates change; their projections are cacheable. Caching live aggregates causes invariant violations on stale reads.
6. **`sync = true` for hot keys.** Stampede protection at the Spring Cache abstraction level. One miss → one load → all callers wait on the same Future.
7. **Serialisation is a contract.** A cache stored with one Jackson config and read with another silently corrupts. Pin the serializer.

## Anti-patterns (avoid)

- **Caching mutable entities returned by JPA.** Hibernate proxies, lazy collections, and the second-level cache fight each other. Cache DTOs, not entities.
- **Cache without TTL.** When events miss, you've manufactured a permanent staleness bug.
- **One cache for everything.** Cache regions exist for a reason — different access patterns need different sizes and TTLs.
- **Caching `null` "to avoid re-querying".** Spring Cache caches `null` by default (`unless = "#result == null"` to opt out). Most of the time you want to skip — repeated nulls usually mean the next call should retry.
- **Distributed cache for tiny lookups.** Configuration values, feature flags — these are 10 entries. A `ConcurrentHashMap` does it in nanoseconds. Don't pay 1ms Redis for that.
- **No cache invalidation event when the aggregate changes.** TTL works but is lazy; users see stale data for the TTL window. For write-followed-by-read flows, invalidate explicitly.
- **Cache stampede on cold start.** Service restarts → all caches empty → every request loads from DB simultaneously. Use cache warming or staggered expiry.
- **Storing JSON blobs > 1MB in Redis.** Redis is in-memory; large values destroy memory headroom. Use object storage for blobs, cache only the metadata.
- **Treating Spring Cache as "magic auto-correctness".** It caches; it doesn't reason about your domain. You still have to think.

## Quick reference — which cache for which use case

| Use case | Store | Why |
|---|---|---|
| Per-request memoisation of expensive computation | `ConcurrentHashMap` field, no Spring needed | In-flight, transient |
| Hot read across the same instance | **Caffeine** | 50ns access; LRU/LFU eviction |
| Hot read across many instances, same DC | **Redis (single)** | ~1ms; shared state |
| Hot read, multi-DC / global | **Redis Cluster + read replicas** | Shared at scale |
| Tiny config / feature flags | In-memory atomic ref or `@ConfigurationProperties` reload | Not really a cache |
| Big blobs (image bytes, PDF) | Object storage (S3) + CDN | Wrong fit for Redis |
| Two-tier: ms-fast local + cross-instance consistency | **Caffeine L1 + Redis L2** | Best of both, complex invalidation |
| HTTP response caching | `Cache-Control` / ETag headers + CDN | Different layer |

## Cache hit ratio expectations

| Workload | Healthy hit ratio | Action if lower |
|---|---|---|
| User profile lookups (read-heavy, slow churn) | > 95% | Investigate eviction (cache too small?) |
| Search result first page | 70-85% | Acceptable; long tail of queries |
| Real-time pricing | 50-70% | Bound TTL; balance freshness vs hit rate |
| Reference data (currencies, countries) | > 99% | Eviction means cache too small or wrong eviction policy |
| Authorisation tokens | > 90% | If lower, JWT cache misconfigured |

## Stack mapping for assista-style polyglot

| Workload | Cache layer |
|---|---|
| `OrderDetail` view served from Postgres | Caffeine (per instance, 5min TTL) + event-driven invalidation on `OrderUpdated` |
| User session principals / roles | Redis (cross-instance, 15min TTL) |
| Elasticsearch search results (page 1) | Caffeine (5min, small) — tail pages don't cache |
| Clickhouse analytics dashboard last-N-hours rollup | Redis (15min) — shared across all dashboard instances |
| Feature flags | Reloadable `@ConfigurationProperties` (no Redis needed) |
| External vendor (GitHub/Jira) API responses | Caffeine + Redis L2 — local fast path, cross-instance dedup |

## Spring Boot integration headlines

- **Annotation-based** (`@Cacheable`, `@CacheEvict`, `@CachePut`) — declarative; needs `@EnableCaching` and a `CacheManager` bean.
- **Programmatic** — inject `CacheManager`; `cacheManager.getCache("orders").get(key, () -> load(key))`. Better for conditional caching.
- **Caffeine integration** — `spring-boot-starter-cache` + `com.github.ben-manes.caffeine:caffeine`. Configure per-cache via properties or `Caffeine.newBuilder()` spec.
- **Redis integration** — `spring-boot-starter-data-redis`. Default `RedisCacheManager`. Use Lettuce (non-blocking, async/coroutines-friendly) over Jedis.
- **Two-tier** — `org.springframework.cache.support.CompositeCacheManager` or libraries like Caffeine+Redis combo (Caffeine local L1, Redis distributed L2, with pub/sub invalidation).
- **Metrics** — Micrometer `CacheMetricsRegistrar` auto-wires hit/miss/size/eviction metrics per cache.

## Related skills

- `database-design/resources/optimization.md` — when "add a cache" is the wrong answer; fix indexes / N+1 first
- `cqrs-implementation/resources/read-side-patterns.md` — projections to ES/CH are a different pattern, not a cache
- `api-design-principles/references/rest-best-practices.md` — HTTP-layer caching (`Cache-Control`, ETag)
- `architecture` — when cache is the right architectural answer vs read replica vs CQRS
- `spring-boot-mastery/resources/configuration-and-profiles.md` — `@ConfigurationProperties` for cache settings
- `clean-code/resources/smells-catalog.md` — feature-envy in a service that's really a cache adapter

## Limitations

- Patterns assume Spring Boot 3+ with `spring-boot-starter-cache`. Older versions have different `CacheManager` types.
- No coverage of **HTTP CDN-layer** caching (CloudFront, Cloudflare) — out of scope; see `api-design-principles` for HTTP cache headers.
- Stop and ask if the **acceptable staleness window** is unclear — it drives every TTL and invalidation decision.
