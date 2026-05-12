# System Design Pattern Library

Reusable patterns, organised by problem they solve. For each: when it applies, how it works, common variants, failure modes.

---

## Load balancing

### Problem
Distribute requests across N stateless service instances.

### Algorithms

| Algorithm | How | When |
|---|---|---|
| **Round-robin** | Rotate through instances | Default; works when load per request is uniform |
| **Least connections** | Pick instance with fewest active connections | Workloads with variable request duration |
| **Least response time** | Pick fastest-responding instance | When p99 matters; mitigates slow-instance impact |
| **IP hash / source-IP affinity** | Hash client IP → same instance | When session state isn't in shared store |
| **Consistent hashing** | Hash request key → instance, minimising rebalancing | Caching layers, sticky routing without state |
| **Weighted** | Assign weights based on instance capacity | Heterogeneous fleets |
| **Random** | Random pick | Surprisingly good baseline; cheap |

### L4 vs L7

- **L4 (TCP)** — fast, no app awareness. Examples: AWS NLB, HAProxy in TCP mode.
- **L7 (HTTP)** — header/path-aware routing, retries, response inspection. Examples: AWS ALB, Nginx, Envoy, Spring Cloud Gateway.

L7 wins for HTTP services. L4 for everything else.

### Failure modes

- **Cascading failure** — slow instances → load piles up → other instances slow → cluster dies. Mitigate with circuit breakers, load shedding.
- **Health check trap** — health check too lenient = traffic to dead instances; too strict = false rejection. Tune.
- **Imbalanced load** with sticky sessions when sessions are uneven (one whale customer holds 90% load).

---

## Sharding

### Problem
A single DB instance can't hold all data or handle all writes. Split into N "shards" that each own a partition.

### Strategies

| Strategy | How | Pros | Cons |
|---|---|---|---|
| **Range** | Shard 1: `id 1-1M`; Shard 2: `1M-2M`; etc. | Predictable, range queries efficient | Hotspot at "newest" shard |
| **Hash** | `shard = hash(key) % N` | Even distribution | Adding shards re-shards everything |
| **Consistent hash** | Keys on a circle; nodes on the circle; key → nearest node clockwise | Adding shard only moves 1/N keys | Slightly less even than mod-hash |
| **Directory-based** | Lookup table: `key → shard` | Flexible | Lookup overhead; lookup is bottleneck |
| **Geographic** | `shard by region` | Locality | Cross-region queries painful |

### Choosing a shard key

The most important system-design decision in a sharded system:

- **High cardinality** — millions of distinct values
- **Even distribution** — no single value dominates
- **Locality** — queries on related data hit the same shard
- **Stable** — doesn't change over time

Bad shard keys: `status`, `country`, `created_date`. Hotspots.
Good shard keys: `user_id`, `tenant_id`, `order_id`.

### Failure modes

- **Hotspot** — one shard has 90% of traffic. Fix: better key or sub-shard the hot one.
- **Cross-shard queries** — `SELECT * FROM orders WHERE customer_id IN (...)` scatters across shards. Expensive.
- **Re-sharding pain** — adding shards. Hash → all data moves. Consistent hash → 1/N moves. Plan from day 1.
- **Distributed transactions** — committing across shards is expensive. Avoid.

---

## Replication

### Problem
Single instance is SPOF. Multiple copies of data.

### Topologies

| Topology | How | Trade-off |
|---|---|---|
| **Leader-follower (master-slave)** | One writer, many readers; replication async/sync | Simple; reads scale; writes don't |
| **Multi-leader (active-active)** | Multiple writers, replicate to each other | Writes scale; conflict resolution needed |
| **Leaderless (Dynamo-style)** | All nodes accept writes; quorum reads | High availability; weaker consistency |

### Sync vs async replication
Covered in `tradeoff-framework.md` §9.

### Failover

- **Automatic** — replica promoted on primary failure (e.g., RDS Multi-AZ). Risk: split-brain if primary recovers.
- **Manual** — operator promotes after verification. Slower but safer.
- **Witness / quorum** — third node breaks ties. Avoids split-brain.

### Failure modes

- **Split-brain** — two primaries; data diverges. Use quorum / fencing.
- **Replication lag** — replicas behind. Stale reads. Monitor.
- **Promotion data loss** — async replica promoted, last few transactions gone. Use sync for critical data.

---

## Caching layers

### Problem
Source-of-truth is slow / expensive. Cache hot data closer.

### Layers (top to bottom)

```
Client → CDN/Edge → API Gateway → Reverse Proxy → App → App Cache → Distributed Cache → DB
```

Each layer adds latency drops:

| Layer | Hit latency | Storage |
|---|---|---|
| Client cache | 0 (local) | KB-MB |
| CDN | 5-50 ms | TB at edge |
| Reverse proxy cache (Varnish) | < 1 ms | GB in memory |
| App-in-process (Caffeine, Guava) | µs | MB-GB |
| Distributed (Redis, Memcached) | 1-5 ms | GB-TB |
| DB | 5-50 ms | TB-PB |

### Patterns
Covered in `tradeoff-framework.md` §6.

### Cache failure modes

- **Cache stampede** — see §6 above; mitigate with locks or pre-warm.
- **Hot key** — 90% traffic to one key. Replicate the key (multiple cache entries with different versions).
- **Cache poisoning** — bad data written into cache, served for hours. Validate on write; short TTL for sensitive caches.
- **Stale read after write** — read-your-writes broken if reader hits cache before invalidation propagates. Read from source for last-write user; use versioning.

---

## Message queues

### Problem
Decouple producers from consumers; smooth load; retry failures.

### Tools

| Tool | Type | When |
|---|---|---|
| **Kafka** | Distributed log | High throughput, event sourcing, replay |
| **RabbitMQ** | Traditional MQ (AMQP) | Complex routing, lower throughput, work queues |
| **AWS SQS** | Hosted queue | Simple, managed |
| **Redis Streams** | Lightweight log | Small scale, in-process |
| **Spring Modulith events** | In-process pub/sub + outbox | Same-process module decoupling |
| **NATS** | Pub/sub + JetStream | Cloud-native, low latency |

### Patterns

| Pattern | What |
|---|---|
| **Work queue** | Producers send tasks; one consumer per task; load balancing | One job done once |
| **Pub/sub** | One message → N subscribers | Notifications, fan-out |
| **Topic / partitioned log** | Ordered per-key; multiple consumers via offset | Event sourcing, replay |
| **Dead letter queue (DLQ)** | Failed messages go to a special queue for inspection | Poison-message handling |

### Failure modes

- **Lost messages** — async producers don't wait for ACK; mitigate with `acks=all` or transactional outbox (see `cqrs-implementation`).
- **Duplicate messages** — at-least-once delivery; consumer must be idempotent.
- **Out-of-order** — multiple partitions / brokers reorder. Order only guaranteed per partition (Kafka) or per queue (RabbitMQ).
- **Backpressure** — producer faster than consumer → queue fills → memory issues. Bound queues; reject or apply backpressure.
- **DLQ flood** — bug causes 100K messages to DLQ. Monitor DLQ depth.

---

## Idempotency

### Problem
Network failures cause retries. Operations must tolerate duplicates.

### Implementation

```kotlin
data class IdempotencyKey(val value: String)

class IdempotencyStore(...) {
    fun execute(key: IdempotencyKey, operation: () -> Result): Result {
        val cached = findResult(key)
        if (cached != null) return cached            // duplicate request
        val result = operation()
        record(key, result, ttl = Duration.ofHours(24))
        return result
    }
}
```

See `cqrs-implementation/resources/write-side-patterns.md` §6 for full Kotlin/Postgres implementation.

### Where it matters

- HTTP POSTs from external clients (`Idempotency-Key` header)
- Webhook receivers
- Async event consumers (at-least-once delivery)
- Payment operations

### Failure modes

- **Idempotency key not unique enough** — collisions. UUIDs are safe; short strings aren't.
- **TTL too short** — duplicate after TTL = unintended double-execute.
- **Different request body for same key** — should reject as 422.

---

## Rate limiting

### Problem
Protect resources from abuse, runaway clients, downstream over-saturation.

### Algorithms

| Algorithm | How | Use |
|---|---|---|
| **Token bucket** | Bucket fills at rate R, capacity B; request consumes 1 token or rejected | Default; allows burst up to B |
| **Leaky bucket** | Bucket drains at rate R; reject if full | Smooths bursts |
| **Fixed window** | Counter per minute; reset on minute boundary | Simple; spike at minute boundary |
| **Sliding window** | Approximate moving window | No edge spike; more complex |
| **Sliding log** | Store timestamps of all requests | Most accurate; memory-hungry |

### Distributed rate limiting

Counter must live in shared store (Redis with `INCR` + `EXPIRE`). Each instance reads from Redis.

For high-throughput, **client-side** rate limiting (each client allowed N req/s globally via a Bucket4j-Redis-based limit).

### Failure modes

- **Race condition** in counter increment-then-check. Use Redis Lua scripts or atomic counters.
- **Single Redis** as bottleneck for rate limiting. Use Redis cluster or distribute by key.
- **Spike when window resets** — fix with sliding window.

---

## Fan-out

### Problem
One event must reach many consumers / data destinations.

### Patterns

| Pattern | When |
|---|---|
| **Fan-out on write** | Producer pushes to each consumer's destination (e.g., Twitter user posts → write to follower feeds) | When read load >> write load; followers are few |
| **Fan-out on read** | Reader pulls from all relevant sources | When followers are many (millions); avoid write amplification |
| **Hybrid** | Fan-out for non-celebrities; fan-in-on-read for celebrities | Twitter / Instagram do this |

Fan-out-on-write means **a tweet by someone with 1M followers = 1M database writes**. Hybrid splits behaviour by celebrity-ness.

---

## Circuit breaker

### Problem
Downstream failure cascades into caller. Caller's threads pile up waiting on dead downstream.

### State machine

```
CLOSED ─── failures exceed threshold ───▶ OPEN
  ▲                                          │
  │                                          │ timeout
  │ test request succeeds                    ▼
HALF-OPEN ◀────────────────────── (test allowed)
```

In OPEN state, requests fail fast (no waiting). After timeout, allow a test request to probe.

### Tool

`Resilience4j` is the canonical JVM library. Spring Boot integration via `@CircuitBreaker`. See `architecture` Example 3.

### Failure modes

- **Tuned wrong** — opens too easily (false trips) or too slowly (cascading failure).
- **Doesn't help if every downstream is slow** — circuit breakers help isolate one bad dep; cascading failure across all deps needs different tooling.

---

## Bulkhead

### Problem
One slow / failing downstream uses all your threads. Other operations starve.

### Pattern

Separate thread pools per downstream:

```
ExecutorService paymentExec = newFixedThreadPool(20)
ExecutorService inventoryExec = newFixedThreadPool(50)
ExecutorService searchExec = newFixedThreadPool(100)
```

A payment outage drains payment's 20 threads but inventory + search keep working.

Resilience4j Bulkhead implements this.

---

## Retry with exponential backoff + jitter

### Problem
Naive retry on every failure overwhelms recovering downstream.

### Pattern

```
attempt 1: immediate
attempt 2: wait 1s + random(0..500ms)
attempt 3: wait 2s + random(0..1s)
attempt 4: wait 4s + random(0..2s)
attempt 5: wait 8s + random(0..4s)
```

**Exponential** to give downstream time. **Jitter** to spread retries across clients. Without jitter, all clients retry at exact same time = thundering herd.

Cap max wait (`maxBackoff = 30s`). Cap total attempts (`maxAttempts = 5`). Use Resilience4j Retry.

### When NOT to retry

- 4xx errors (client error — retry won't help)
- POST without idempotency key (creates duplicates)
- After timeout already exceeded

---

## CDN / edge caching

### Problem
Static assets / cacheable API responses are served from origin every time → high latency for far clients, high origin load.

### How
Reverse proxies at edge POPs (CloudFlare, Fastly, AWS CloudFront) cache responses by URL. Cache hit at edge → ~30ms even for users 1000s of km away.

### Cache control

- `Cache-Control: public, max-age=3600` — cache anywhere for 1h
- `Cache-Control: private, no-cache` — browser only, revalidate
- `ETag: "..."` + `If-None-Match` — conditional GET, 304 Not Modified

### Failure modes

- **Cache misses concentrated on origin** — origin overload after deploy / purge
- **Stale content** — TTL too long, purge slow. Use `stale-while-revalidate` for soft refresh.
- **Cache key includes query params** — accidentally cache-bust by adding tracking params. Strip or sort params.

---

## Idempotent counters / approximate counting

### Problem
Counters (page views, likes) get hammered. Strict counting is expensive.

### Solutions

- **Eventually consistent** — Redis `INCR`, async flush to DB
- **Sharded** — counter split across N keys; aggregate on read
- **Probabilistic (HyperLogLog)** — approximate unique counts in tiny memory
- **Time-bucketed** — increments aggregated per minute; downsample to hourly older

For "page views" — eventual consistency is fine. For "bank balance" — sharded counters fail; use proper transactional accounting.

---

## Search index (denormalised projection)

### Problem
Source DB query is expensive (joins, full-text, faceted filters).

### Pattern

Project source events into Elasticsearch (or similar). See `cqrs-implementation/resources/read-side-patterns.md`.

Failure modes:
- Projection lag (eventual consistency by design)
- Schema migrations require rebuild
- Drift between source and index

---

## Outbox pattern

### Problem
Need to atomically: change DB state AND publish event. Two-phase commit is expensive; race conditions if done naively.

### Pattern

1. In one transaction: update domain table + insert into `outbox` table
2. Separate relay process polls `outbox` and publishes to Kafka
3. Mark outbox row published

Spring Modulith ships outbox out of the box via `event_publication` table. See `cqrs-implementation/resources/write-side-patterns.md` §7.

---

## Materialised views

### Problem
A query is too slow to compute on read; computed often enough that caching expires quickly.

### Pattern

DB-level: `CREATE MATERIALIZED VIEW ... AS SELECT ...; REFRESH MATERIALIZED VIEW CONCURRENTLY ...` (Postgres).

Application-level: a projection table updated by events.

Trade-off: stale data (refresh interval).

---

## Read-through CDC (Change Data Capture)

### Problem
Streaming changes from primary DB to other systems without app-level event publication.

### Tools
Debezium (Postgres → Kafka), AWS DMS, MongoDB change streams.

### When to use

- Backfill another store
- Audit log from existing tables
- Materialised views for cross-team consumers without code changes

Adds operational complexity. Outbox is simpler if you control the app.

---

## Saga (long-running distributed transaction)

### Problem
Operation spans multiple services; can't 2PC.

### Pattern

Sequential local transactions + compensating actions if any fails.

```
1. Reserve inventory (success)
2. Charge payment (success)
3. Create shipment (FAIL)
   → Refund payment (compensation)
   → Release inventory (compensation)
```

**Orchestration** (central coordinator) vs **choreography** (services react to events). Choreography simpler at small scale; orchestration clearer at large scale.

(Detailed Kotlin/Spring saga patterns deserve their own skill — TBD.)

---

## How to use this library

In design discussions:
- "Read-heavy → cache" — name the cache pattern: cache-aside? write-through?
- "Decouple → queue" — name the queue type: Kafka topic? RabbitMQ? Modulith events?
- "Tolerate failure → circuit breaker" — name the bulkhead too

Patterns are vocabulary. Name them precisely. Don't reach for one without the problem.
