# Trade-off Framework

Every system design decision is a trade-off. This file: the canonical trade-off pairs, what they mean concretely, how to choose.

---

## 1. CAP theorem

> A distributed system can guarantee at most **two of**: Consistency, Availability, Partition tolerance.

Network partitions are **inevitable** in distributed systems. So the real choice is **CP or AP** during a partition.

| Choice | What it means | Examples |
|---|---|---|
| **CP** — Consistency + Partition tolerance | When partition occurs, reject requests to keep data consistent. Sacrifice availability. | Spanner, ZooKeeper, etcd, CockroachDB, MongoDB (strong) |
| **AP** — Availability + Partition tolerance | When partition occurs, serve requests with possibly stale data. Sacrifice consistency. | DynamoDB (default), Cassandra, Riak, Redis (active-active) |
| **CA** | Theoretically: assumes no partitions. Only in single-machine systems. | Single Postgres |

**Misconception:** CAP isn't about choosing 2 of 3 always. It's about what you sacrifice **when a partition happens**. Most of the time, no partition is happening, and you get all 3.

---

## 2. PACELC — the refinement

PACELC: if Partition, choose A or C; **Else**, choose Latency or Consistency.

Even without a partition, you trade. Most databases offer "strong consistency" only via consensus (slow) or "low latency" only via async replication (eventually consistent).

| System | Partition behaviour | Normal behaviour |
|---|---|---|
| Cassandra | AP (default) | EL (low latency, eventually consistent) |
| MongoDB | CP (with majority writes) | EC (sync replication is slow) |
| Postgres + sync replicas | CP | EC (sync is slower than async) |
| DynamoDB strong reads | CP | EC |
| DynamoDB eventual reads | AP | EL |

The honest question is **not** "CP or AP" but "in steady state, do I pay latency for consistency, or accept staleness for speed?"

---

## 3. Consistency models

The "C" of CAP is not a single thing.

| Model | Guarantee | Cost |
|---|---|---|
| **Strict / Linearizable** | All operations appear instantaneous and globally ordered | Slowest; needs consensus |
| **Sequential** | All operations in some order, same on all nodes | Faster; some nodes lag |
| **Causal** | If A happened-before B, all see A before B | Reasonable for chat/collaboration |
| **Read-your-writes** | A client sees its own writes immediately | Cheap to add; common UX expectation |
| **Monotonic reads** | Once you see version N, you don't go back to N-1 | Routing affinity needed |
| **Eventual** | All replicas eventually converge | Cheapest; widely deployed |

For a payment system: **linearizable** (per account).
For a tweet feed: **eventual** (with read-your-writes).
For an inventory counter: **strong on writes**, eventually consistent on display is fine.

**Per-operation consistency** is the modern approach: not "the system is consistent" but "writes to this aggregate are linearizable; reads of this projection are eventually consistent up to 1s lag."

---

## 4. Latency vs throughput

These are **different** axes. Optimising one often hurts the other.

| Concept | Definition | Optimisation tactic |
|---|---|---|
| **Latency** (response time) | Time from request sent to response received | Reduce queueing, reduce I/O, reduce serialisation work, parallelise |
| **Throughput** (req/s) | Total requests handled per unit time | Batch operations, async processing, queue requests |

### Concrete example

A service that handles requests one at a time, each taking 100ms:
- **Latency**: 100ms p99
- **Throughput**: 10 req/s per worker

Adding batching: requests wait up to 50ms to be combined with others:
- **Latency**: ~150ms p99 (worse)
- **Throughput**: 100+ req/s (much better, due to amortised overhead)

For an OLTP API (user-facing), **latency wins**. For an analytical pipeline, **throughput wins**. Don't optimise blindly.

### Little's Law

```
Concurrency = Throughput × Latency
```

If you want 10K req/s at 50ms latency, you need 500 concurrent requests in flight. That sets thread pool / connection pool sizes.

---

## 5. Push vs pull

Two ways for data to reach a consumer.

| Pattern | How | Pros | Cons |
|---|---|---|---|
| **Push** | Producer notifies consumer (webhook, WebSocket, Kafka push, Server-Sent Events) | Low latency, no polling cost | Consumer must be available; backpressure trickier |
| **Pull** | Consumer asks producer for new data (polling, Kafka consumer, REST) | Consumer controls pace; simpler error handling | Latency = poll interval; overhead even when no data |

**Hybrid:** long-polling, where pull blocks until new data — combines simplicity of pull with latency of push. Used in chat systems before WebSockets.

For chat: push. For batch sync: pull. For low-frequency notifications: webhook (push). For event-driven microservices: usually push (Kafka with consumer groups).

---

## 6. Cache vs source-of-truth

Caching is the most common "fast" optimisation. Trade-off: **staleness**.

| Strategy | Read path | Write path |
|---|---|---|
| **Cache-aside** | Try cache → miss → read source → fill cache | Write source → invalidate cache |
| **Write-through** | Cache always populated by writes | Write cache + source synchronously |
| **Write-behind** (write-back) | Cache populated by writes; async flush to source | Write cache; async flush |
| **Refresh-ahead** | Read cache; if entry about to expire, async refresh | Write source → cache updated async |

**Cache invalidation** is the famous hard problem:

- TTL — simple, can be stale. Pick based on staleness tolerance (1s? 1h?).
- Event-driven — invalidate on `OrderUpdated` event. Tighter staleness; more plumbing.
- Versioned — key includes version; old versions naturally evicted (LRU).

**Cache stampede**: many concurrent misses on a hot cold key all hit source. Mitigate with:
- Locking around cache fills
- Pre-warming (refresh-ahead)
- Probabilistic early expiration

---

## 7. Synchronous vs asynchronous

When does call A need to wait for call B?

| Choice | When | Pros / Cons |
|---|---|---|
| **Synchronous (block)** | Caller needs B's result to proceed; correctness depends on B | Simple; backpressure natural; failure visible |
| **Asynchronous (fire and forget / event)** | Side effect only, caller doesn't need result | Lower latency; harder error handling; eventual consistency |

**Rule:** make synchronous only what's strictly required for correctness. Everything else: async via event.

Common mistake: SMS sent synchronously inside `placeOrder`. Causes:
- 200ms added latency every order
- SMS provider down → order fails (wrong!)
- One slow customer holds up the order pool

Fix: emit `OrderPlaced`, async listener sends SMS. Order succeeds; SMS retries on its own.

---

## 8. Idempotent vs at-least-once vs exactly-once

Distributed systems guarantees on message/operation delivery.

| Guarantee | What it means | Cost |
|---|---|---|
| **At-most-once** | Operation runs ≤ 1 time. May not run if failure. | Cheap but data loss |
| **At-least-once** | Operation runs ≥ 1 time. May run multiple times on failure/retry. | Cheap but duplicates |
| **Exactly-once** | Operation runs exactly 1 time. | Expensive; requires idempotency or 2PC |

**Idempotency** is the practical answer: make at-least-once safe by ensuring duplicate calls have the same effect.

- Implement via idempotency key (see `cqrs-implementation/resources/write-side-patterns.md` §6).
- Database upserts (`INSERT ... ON CONFLICT DO UPDATE`) instead of blind inserts.
- Natural idempotency (setting a state, not incrementing a counter).

**Exactly-once is usually a lie** in distributed systems. Kafka claims exactly-once for some pipelines via transactional producer + idempotent consumer; under the hood it's at-least-once + dedup. Cheaper than 2PC.

---

## 9. Sync vs async replication

| Mode | What | Trade-off |
|---|---|---|
| **Sync** | Write returns after N replicas ACK | Stronger consistency, slower writes, write blocked on slow replica |
| **Async** | Write returns after primary ACK; replicas catch up | Faster, can lose data if primary dies before sync |
| **Semi-sync** | Primary + ≥1 replica ACK before return | Balance |

Postgres default = async streaming replication. Critical financial systems usually run synchronous to a same-DC replica.

Trade-off concretely:
- **Sync replication adds RTT**. Same-DC: +0.5ms. Cross-region: +50-200ms.
- **Async risks data loss** if primary fails between commit and replication.

---

## 10. Shared-nothing vs shared-everything

| Architecture | Examples |
|---|---|
| **Shared-nothing** | Each node owns disjoint partition; coordination minimal | Cassandra, DynamoDB, sharded MySQL |
| **Shared-disk** | Compute nodes share storage layer | Aurora, Snowflake |
| **Shared-memory** | Threads in one process | Single-machine systems |

Shared-nothing scales out, but cross-partition queries are expensive (scatter-gather). Shared-disk scales out compute easily but disk layer becomes the bottleneck.

---

## 11. Monolith vs microservices

Already covered in `architecture` Example 3. The trade-off:

| Aspect | Monolith | Microservices |
|---|---|---|
| Initial dev velocity | High | Low |
| Operational complexity | Low | High |
| Independent deployment | No | Yes |
| Team independence | Limited | Real |
| Cross-cutting refactor | Easy | Hard |
| Performance (in-process call vs network) | Fast | 100-1000× slower per call |
| Debugging | One process | Distributed tracing required |

Most teams **don't** need microservices. Start with a modular monolith (e.g., Spring Modulith). Split only when:
- Team independence demands it (Conway's law in reverse)
- Independent scaling per component is real (not theoretical)
- Different stacks/languages per component genuinely benefit

Reaching for microservices without these conditions buys you the costs without the benefits.

---

## 12. Choice patterns I see misjudged

| False choice | Real choice |
|---|---|
| "Strong consistency or eventual" | Per-operation: which ones need strong, which can be eventual |
| "Cache or no cache" | What TTL / invalidation strategy |
| "SQL or NoSQL" | Workload shape (transactional vs analytical vs document vs search) |
| "Sync or async" | Per-call: which need result to proceed |
| "Monolith or microservices" | Number of teams, deployment independence needs |
| "Push or pull" | Latency tolerance, consumer control |
| "Build or buy" | Total cost of ownership; team focus |

---

## 13. Communication trade-offs

In design discussions, **call out the trade-off explicitly**. Not "we use Postgres" but "we use Postgres because we need strong consistency on writes; we accept that scaling writes past 10K/s will require sharding work in 18 months."

Naming the trade-off:
- Forces the team to acknowledge it
- Becomes the trigger for re-evaluation later
- Makes the design defensible vs second-guessing

Capture in ADR (`architecture-decision-records`).
