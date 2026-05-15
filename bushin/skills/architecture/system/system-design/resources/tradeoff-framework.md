# Trade-off Framework

Every design decision is a trade-off (T8). Name it explicitly or it's not a design — it's a guess. This file: the canonical pairs, what they mean concretely, how to choose, and the false choices people commonly confuse with them.

## CAP (T3)

> A distributed system can guarantee at most **two of**: Consistency, Availability, Partition tolerance.

Network partitions are inevitable, so the real choice is **CP or AP during a partition**. Without a partition, you get all three.

| Choice | What gives | Examples |
|---|---|---|
| **CP** | Reject requests during partition to keep data consistent | Spanner, etcd, ZooKeeper, CockroachDB, MongoDB (majority writes) |
| **AP** | Serve possibly-stale data during partition | DynamoDB (default), Cassandra, Riak, Redis active-active |
| **CA** | Assumes no partitions — single-machine only | Single Postgres |

Misconception: CAP isn't "pick 2 of 3 at all times" — it's "what do you sacrifice **when** a partition happens." Most of the time, nothing is being sacrificed.

## PACELC (T4)

PACELC refines CAP: **if Partition, A or C; Else, Latency or Consistency.** Even with no partition, sync replication adds RTT (slow), async risks stale reads (fast). The honest design question isn't "CP or AP" but "in steady state, do I pay latency for consistency, or accept staleness for speed?"

## Consistency models (T5)

"Consistency" isn't a single thing.

| Model | Guarantee | Cost |
|---|---|---|
| Linearizable | All ops appear instantaneous + globally ordered | Slowest; consensus required |
| Sequential | Same order on all nodes | Faster; some nodes lag |
| Causal | If A→B happens-before, all observers see A before B | Reasonable for chat/collab |
| Read-your-writes | Client sees its own writes immediately | Cheap; common UX expectation |
| Monotonic reads | Don't go back to older version once you see N | Needs routing affinity |
| Eventual | All replicas eventually converge | Cheapest; widely deployed |

**Per-operation** classification is the modern stance (F1): "writes to this aggregate are linearizable; reads of this projection are eventually consistent up to ~1 s lag." Not "the system is consistent."

Quick map:
- Payments (per account) → linearizable.
- Tweet/Instagram feed → eventual (+ read-your-writes for the author).
- Inventory counter → strong on write, eventual on display.

## Latency vs throughput (T6, T7)

Different axes. Optimising one often hurts the other.

| Concept | Definition | Tactics |
|---|---|---|
| Latency | Time per request | Reduce queueing, reduce I/O, parallelise |
| Throughput | Requests handled per unit time | Batch, async, queue |

Concrete: a service handling 100 ms-each one-at-a-time delivers 100 ms p99 at 10 req/s. Add batching with 50 ms wait → ~150 ms p99 (worse) but 100+ req/s (much better — overhead amortised).

User-facing API: **latency wins**. Analytical pipeline: **throughput wins**. Pick the axis.

**Little's Law (T7):** `concurrency = throughput × latency`. 10 K req/s at 50 ms ⇒ 500 in-flight ⇒ pool size 500. Sets thread/connection sizing.

## Sync vs async (T10)

When does call A need to wait for call B?

| Choice | When | Trade |
|---|---|---|
| Sync | Caller needs result for correctness | Simple, natural backpressure, failure visible |
| Async (event) | Side effect only | Lower latency, harder error handling, eventual consistency |

Rule: **sync only what correctness requires; everything else async.** F4 — per-call classification, not blanket policy.

Canonical mistake: SMS sent synchronously inside `placeOrder`. Result:
- +200 ms latency per order.
- SMS provider down → order **fails** (wrong outcome — order is correct, notification isn't).
- One slow customer holds up the pool.

Fix: emit `OrderPlaced`; async listener sends SMS. Order succeeds; SMS retries independently. See `kotlin-examples.md` for the refactor shape.

## Idempotency over exactly-once (T9)

| Guarantee | Meaning | Cost |
|---|---|---|
| At-most-once | Runs ≤ 1 time; may not run on failure | Cheap but data loss |
| At-least-once | Runs ≥ 1 time; may run multiple times | Cheap but duplicates |
| "Exactly-once" | Runs exactly 1 time | Expensive; usually a lie |

**Exactly-once delivery is a lie** in distributed systems. The practical answer: at-least-once + **idempotency** — make duplicate calls have the same effect.

Mechanics: idempotency key (UUID, not short string) stored alongside operation, TTL ≥ retry window. Same key + same body → return cached result. Same key + *different* body → reject `422`. Or use naturally-idempotent operations: set-state instead of increment, upsert instead of insert.

Kafka's "exactly-once" claim is at-least-once + dedup under the hood. Cheaper than 2PC but still that mechanism.

## Cache vs source-of-truth

The most common "fast" optimisation. Trade: **staleness**.

| Strategy | Read | Write |
|---|---|---|
| Cache-aside | Try cache → miss → read source → fill | Write source → invalidate cache |
| Write-through | Cache always populated by writes | Write cache + source synchronously |
| Write-behind | Cache populated by writes | Cache; async flush to source |
| Refresh-ahead | Read cache; async refresh near expiry | Source → cache async |

Default = **cache-aside** (PT4). Pick others only when their access shape clearly fits.

Invalidation is the famous hard problem:
- **TTL** — simple, allows staleness. Pick based on tolerance.
- **Event-driven** — invalidate on domain event. Tighter, more plumbing.
- **Versioned key** — include version; old versions LRU out.

**Cache stampede:** many concurrent misses on a hot cold key all hit source. Mitigate: lock-around-fill, refresh-ahead, probabilistic early expiration.

F2: the question isn't "cache or no cache" but "what TTL + invalidation strategy" — staleness budget is the variable.

## Sync vs async replication

| Mode | What | Trade |
|---|---|---|
| Sync | Write returns after N replicas ACK | Stronger consistency, slower writes |
| Async | Write returns after primary ACK | Faster; can lose data if primary dies pre-replication |
| Semi-sync | Primary + ≥1 replica ACK | Balance |

Postgres default = async streaming. Critical financial systems run sync to a same-DC replica. Concretely: sync adds RTT (+0.5 ms same-DC, +50–200 ms cross-region); async risks losing the last N transactions on failover.

## Monolith vs microservices (F5)

| Aspect | Monolith | Microservices |
|---|---|---|
| Initial velocity | High | Low |
| Operational complexity | Low | High |
| Independent deploy | No | Yes |
| Team independence | Limited | Real |
| Cross-cutting refactor | Easy | Hard |
| Per-call cost | In-process (ns) | Network (100–1000× slower) |
| Debugging | One process | Distributed tracing required |

Most teams **don't** need microservices (A1). Start with a modular monolith. Split only when (a) team independence demands it (Conway's-law pressure), (b) independent scaling per component is real, (c) different stacks per component genuinely help. Without these, you buy the costs without the benefits.

## Push vs pull

| Pattern | How | Pros | Cons |
|---|---|---|---|
| Push | Producer notifies (WebSocket, webhook, SSE) | Low latency | Consumer must be online; backpressure trickier |
| Pull | Consumer asks (polling, Kafka consumer, REST) | Consumer paces; simpler errors | Latency = poll interval |

Hybrid: long-polling — pull that blocks until data arrives.

Chat → push. Batch sync → pull. Low-frequency notifications → webhook (push).

## Shared-nothing vs shared-everything

| Architecture | Examples |
|---|---|
| Shared-nothing | Each node owns disjoint partition | Cassandra, DynamoDB, sharded MySQL |
| Shared-disk | Compute nodes share storage layer | Aurora, Snowflake |
| Shared-memory | Threads in one process | Single-machine |

Shared-nothing scales out but cross-partition queries are painful (scatter-gather). Shared-disk scales compute easily; disk becomes the bottleneck.

## False choices unmasked

| Looks like | Real choice |
|---|---|
| Strong vs eventual consistency | Per-operation classification (F1) |
| Cache or no cache | TTL + invalidation strategy / staleness budget (F2) |
| SQL or NoSQL | Workload shape: OLTP / OLAP / document / search / KV / time-series (F3) |
| Sync or async | Per-call: does the caller need the result for correctness (F4)? |
| Monolith or microservices | Team count, deploy independence, scaling-pressure asymmetry (F5) |
| Push or pull | Latency tolerance + consumer pacing |
| Build or buy | TCO + team focus |

## Communicating trade-offs

In discussion, **name the cost** as you choose. Not "we use Postgres" but "we use Postgres because we need linearizable writes; we accept that scaling writes past 10 K/s will require sharding work in ~18 months."

Naming the cost:
- Forces the team to acknowledge it.
- Becomes the trigger for re-evaluation later.
- Makes the design defensible vs second-guessing.
- Is the senior signal in design review and interview alike (I4).

Capture in an ADR. An undocumented trade-off becomes folklore within two quarters.
