# Pattern Library

Vocabulary, indexed by the problem each pattern solves. Naming patterns precisely is what makes a system-design conversation move — "we'll use cache-aside" is a decision; "we'll add caching" is a wish.

## Load balancing (PT1)

| Algorithm | When |
|---|---|
| Round-robin | Default; uniform request cost |
| Least connections | Variable request duration |
| Least response time | p99 matters; isolates slow instances |
| IP hash / source affinity | Session-state-in-instance |
| Consistent hash | Key → instance; cache stickiness; minimal rebalance on scale |
| Weighted | Heterogeneous fleets |

**L4 (TCP)** = fast, app-blind (NLB, HAProxy TCP). **L7 (HTTP)** = header/path routing, retries, response inspection (ALB, Nginx, Envoy). L7 wins for HTTP services.

Failure modes: cascading (slow instance → others pile up); health check too lenient → dead-traffic, too strict → false reject; sticky imbalance when one customer is 90% of load.

## Sharding (PT2)

| Strategy | Pros | Cons |
|---|---|---|
| Range | Predictable, efficient range queries | Hotspot at newest shard |
| Hash mod N | Even distribution | Re-shard = move everything |
| Consistent hash | Adding shard = move 1/N keys | Slightly less even |
| Directory-based | Flexible mapping | Lookup is itself the bottleneck |
| Geographic | Locality | Cross-region queries painful |

**Shard-key choice IS the design.** Properties of a good key: high cardinality, even distribution, locality (related rows co-located), stable over time. Bad keys: `status`, `country`, `created_date` (hotspots). Good keys: `user_id`, `tenant_id`, `order_id`.

Failure modes: **hot partition (A8)** — 99% traffic to 1% of keys; detect via per-key QPS, fix via sub-sharding or hot-key replication. **Cross-shard queries** scatter-gather → denormalise. **Re-sharding pain** — consistent hash → 1/N moves vs all. **Distributed TX across shards** — expensive; avoid.

## Replication (PT3)

| Topology | When |
|---|---|
| Leader-follower | Simple; reads scale; writes don't |
| Multi-leader | Writes scale; conflict resolution needed |
| Leaderless (Dynamo) | All nodes accept writes; quorum reads |

Sync (strong, slow, blocks on lagging replica) vs async (fast, may lose recent writes on failover) vs semi-sync (compromise). See `tradeoff-framework.md`.

Failover modes: automatic (fast, risk split-brain) vs manual (slow, safer) vs quorum-based (witness third node breaks ties). **Split-brain** is the canonical failure — fence with quorum.

## Caching layers (PT4)

```
Client → CDN/Edge → API Gateway → Reverse Proxy → App → App Cache → Distributed Cache → DB
```

| Layer | Hit latency | Storage |
|---|---|---|
| Client cache | 0 | KB–MB |
| CDN | 5–50 ms | TB at edge |
| Reverse proxy (Varnish) | <1 ms | GB in memory |
| In-process (Caffeine/Guava) | µs | MB–GB |
| Distributed (Redis/Memcached) | 1–5 ms | GB–TB |
| DB | 5–50 ms | TB–PB |

Patterns: cache-aside (default) · write-through · write-back (write-behind) · refresh-ahead. See `tradeoff-framework.md` for picking.

Failure modes: **stampede** (many concurrent misses on cold key) → lock-around-fill, refresh-ahead, jittered TTL. **Hot key** → replicate with versioned suffix. **Stale read after write** → versioning or read-from-source for the writer.

## Message queues (PT5)

| Tool | Type | When |
|---|---|---|
| **Kafka** | Distributed log | High throughput, event sourcing, replay |
| RabbitMQ | Traditional MQ (AMQP) | Complex routing, work queues |
| AWS SQS | Hosted queue | Simple managed |
| Redis Streams | Lightweight log | Small scale |
| NATS | Pub/sub + JetStream | Cloud-native, low latency |

Patterns: work queue (one task, one consumer) · pub/sub (1→N) · partitioned topic (ordered per key) · **dead letter queue (DLQ)** for poison messages.

Failure modes: **lost messages** (fire-and-forget) → `acks=all` or outbox (PT9). **Duplicates** are normal → consumer must be idempotent (PT6). **Order** guaranteed only per partition/queue. **Backpressure** → bound queues; reject or signal when full. **DLQ flood** → alert on DLQ depth.

## Idempotency (PT6)

For any retried operation. Mechanism:

1. Client sends `Idempotency-Key: <uuid>` header.
2. Server checks the key against a store (TTL ≥ retry window, e.g. 24 h).
3. First call: execute, record result with key.
4. Duplicate same key + same body: return cached result.
5. Same key + **different body**: reject `422` (the client made an error).

Where it matters: external HTTP POSTs, webhook receivers, async consumers (PT5), payments. Naturally idempotent: set-state, upsert. Not idempotent: increment, append-list-row, send-email.

**Exactly-once is a lie (T9)** — idempotency is the working substitute.

## Rate limiting (PT7)

| Algorithm | When |
|---|---|
| Token bucket | Default; allows burst up to B |
| Leaky bucket | Smooths bursts |
| Fixed window | Simple; spike at boundary |
| Sliding window | No edge spike |
| Sliding log | Most accurate; memory-hungry |

Distributed: counter in Redis. **Race:** `INCR` then `EXPIRE` is non-atomic — first call survives, every subsequent racer can incrementally bypass. Use Redis Lua scripts (atomic) or `SET ... NX EX` patterns. See `kotlin-examples.md`.

## Circuit breaker + bulkhead (PT8)

**Circuit breaker** stops cascading failure:

```
CLOSED ─── error rate > threshold ──▶ OPEN
   ▲                                    │
   │                                    │ timeout
   │ test request OK                    ▼
HALF-OPEN ◀──────────────────── (probe allowed)
```

In OPEN, fail fast (no waiting). After timeout, allow a probe.

**Bulkhead** = separate thread pools per downstream:

```
paymentPool   = 20 threads
inventoryPool = 50 threads
searchPool    = 100 threads
```

Payment outage drains payment's 20, inventory + search keep working. Without bulkhead, one slow dep starves the others.

Pair with **retry + exponential backoff + jitter** (`wait = 2ⁿ s + rand(0..2ⁿ⁻¹ s)`, cap ~30 s, ~5 attempts) to avoid thundering herd. **Don't retry** 4xx, POST without idempotency key, or after the deadline.

## Outbox pattern (PT9)

Atomically change DB state + publish event without 2PC:

1. Single TX: update domain row + insert into `outbox` table.
2. Separate relay process polls `outbox` → publishes to Kafka.
3. Mark outbox row published (or delete).

Loss-resistant because the TX is atomic. Pair with idempotent consumer (PT6) since at-least-once is built in. See `kotlin-examples.md` for shape.

## Saga (PT10)

Cross-service workflow when distributed TX is too expensive. Sequential local transactions + **compensating actions** on failure (e.g. reserve inventory → charge payment → create shipment; if shipment fails, refund payment + release inventory).

Two flavours: **orchestration** (central coordinator drives steps; clearer at large scale) vs **choreography** (services react to events; simpler small, opaque large). Compensations are application-level rollbacks, not DB rollbacks. Every step must be idempotent.

## CDN / edge

Cache static + cacheable API responses at edge POPs (CloudFlare, Fastly, CloudFront) by URL. Control via `Cache-Control: max-age=N` + `ETag` for conditional GET. Failure modes: post-purge origin stampede; stale content (`stale-while-revalidate` softens it); accidental cache-bust by tracking query params.

## Reference systems vocabulary (H)

Each one should be in muscle memory — main bottleneck + one scaling trick:

| System | Teaches |
|---|---|
| URL shortener | Read-heavy KV, cache layering, ID generation |
| News feed (Twitter) | Fan-out write vs read, eventual consistency |
| Chat (WhatsApp, Slack) | WebSockets, persistence, offline delivery |
| Rate limiter | Token bucket, Redis patterns |
| File storage (Dropbox) | Chunking, dedup, metadata DB + blob |
| Search (autocomplete + full-text) | Trie, inverted index, denormalised projection |
| Distributed cache | Consistent hashing, replication, eviction |
| Notification system | Queues, idempotency, retry, DLQ |
| Ride-share matcher (Uber) | Geospatial index, low-latency dispatch |
| Payment system | Idempotency, strong consistency, audit, double-entry |

For each: know the high-level diagram, the main bottleneck, one or two scaling tricks. They're the vocabulary of system-design interviews and real architecture conversations.

## How to use this library

Patterns are vocabulary. Name them precisely — "cache-aside with 1 h TTL" beats "we'll add caching"; "Kafka topic with outbox" beats "we'll use events". Don't reach for a pattern without naming the problem it's solving.
