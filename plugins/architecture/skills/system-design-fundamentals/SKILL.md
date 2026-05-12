---
name: system-design-fundamentals
description: "System design discipline for backend engineers — step-by-step design process from requirements to detailed design, back-of-envelope capacity estimation, trade-off frameworks (CAP, latency vs throughput, consistency models), and a pattern library (load balancing, sharding, replication, caching layers, queues). Use when designing a new system from scratch, evaluating an existing design, or preparing for / running a system design interview."
risk: safe
source: "custom — system design fundamentals for backend engineers"
date_added: "2026-05-12"
---

# System Design Fundamentals

The discipline of designing distributed systems from scratch. Not architecture *style* (Layered / Onion / Clean — see `architecture-patterns`), not architecture *decisions* (when CQRS, when Postgres — see `architecture`), but the **process of working from "we need a new system" to "here is a design we can build."**

> A system design is a sequence of decisions, each backed by a constraint. If you can't trace a decision to a non-functional requirement, the decision is decoration.

## Use this skill when

- Designing a new system / service / feature from scratch
- Evaluating someone else's design (in review or interview)
- Preparing for a system design interview (FAANG-style)
- Choosing between two architectural alternatives that look similar
- Estimating capacity for a launch ("can this handle Black Friday?")
- Communicating trade-offs to non-technical stakeholders

## Do not use this skill when

- The task is **picking the architecture overlay** (Onion/Clean/Layered/DDD) — use `architecture-patterns`
- The task is **picking a specific technology** (Postgres vs Mongo, REST vs gRPC) — use `architecture` decision trees
- The task is **implementation patterns** within a known architecture — use `cqrs-implementation`, `database-design`, etc.
- You're writing a CRUD controller. System design is for systems, not for endpoints.

## Selective Reading Rule

| File | Description | When to read |
|---|---|---|
| `resources/design-process.md` | Step-by-step: requirements → constraints → high-level → component → detail → bottlenecks → scale. The "how to think" of system design | Starting a new design; structuring an interview answer |
| `resources/capacity-estimation.md` | Back-of-envelope: QPS, storage, bandwidth, instances, cost. Numbers every engineer should know. Worked examples | Sizing a new system; sanity-checking an existing one |
| `resources/tradeoff-framework.md` | CAP, PACELC, consistency models, latency vs throughput, strong vs eventual, push vs pull, cache vs source-of-truth | Justifying decisions; recognising false choices |
| `resources/pattern-library.md` | Load balancing, sharding (range/hash/consistent-hash), replication (sync/async/leader-follower), caching layers, message queues, idempotency, rate limiting, fan-out | Looking up a pattern by problem |

## The 7 phases of system design

```
1. Clarify        — what are we actually building?
2. Estimate       — how much load, data, latency?
3. High-level     — boxes and arrows
4. Component      — what does each box do?
5. Detail         — data model, APIs, key algorithms
6. Bottlenecks    — where will this break first?
7. Scale          — how do we 10×?
```

Cycle: each later phase often forces you back. That's the job, not a flaw.

## Core principles

1. **Requirements drive architecture, not vice versa.** "We're using microservices" is not a requirement; "100K req/s at p99 ≤ 100ms" is.
2. **Non-functional requirements matter more than functional ones** in design discussions. *What* the system does is usually easy; *how well* it does it is hard.
3. **Capacity estimation prevents most bad decisions.** Numbers reveal absurdity before architecture commits to it.
4. **No silver bullets.** Every choice is a trade-off; the question is whether you've named the trade-off honestly.
5. **Start simple, identify the breaking point, then scale.** A single Postgres + load balancer handles more than most engineers assume. Don't pre-shard for a system that handles 100 req/s.
6. **Communicate the design as a story, not a diagram.** The diagram is the artefact; the story is the deliverable.
7. **Honesty about unknowns.** "I don't know how many writes/sec we'll have" is correct; making up a number is the failure.

## Reference architectures you should know cold

For backend interviews and real design work, have these in muscle memory:

| Reference | What it teaches |
|---|---|
| **URL shortener (TinyURL, bit.ly)** | Read-heavy KV store, cache layering, custom ID generation |
| **News feed (Twitter/X timeline)** | Fan-out (write vs read), heterogeneous user load, eventual consistency |
| **Chat system (WhatsApp, Slack)** | WebSockets, message persistence, push notifications, offline delivery |
| **Rate limiter** | Token bucket vs sliding window, distributed counters, Redis patterns |
| **File storage (Dropbox, Drive)** | Chunking, deduplication, metadata DB, blob storage |
| **Search (autocomplete + full-text)** | Trie, inverted index, ranking, denormalised projections |
| **Distributed cache (Redis cluster)** | Consistent hashing, replication, eviction |
| **Notification system** | Queues, idempotency, retry, dead-letter, priority |
| **Ride-sharing matcher (Uber)** | Geospatial indexing, low-latency dispatch, surge pricing |
| **Payment system** | Idempotency, strong consistency, audit, double-entry bookkeeping |

For each: know the high-level diagram, the main bottleneck, and one or two scaling tricks. They're the "vocabulary" of system design interviews and real-world architecture conversations.

## Quick capacity heuristics

| Question | Answer in your head |
|---|---|
| Bytes in 1 GB? | 1,073,741,824 ≈ 10⁹ |
| Seconds in a day? | 86,400 ≈ 10⁵ |
| 1 million records × 100 bytes = ? | 100 MB |
| 1 billion records × 1 KB = ? | 1 TB |
| Disk seek (HDD) / SSD random / RAM access | ~10ms / ~0.1ms / ~100ns |
| LAN round-trip / continent round-trip | ~0.5ms / ~150ms |
| Postgres point read (indexed) | ~50µs (warm), ~5ms (cold) |
| Redis GET | ~1ms over LAN |
| ES search across 10M docs | ~50-200ms |
| Single Postgres instance peak writes | ~10-50K writes/s (with proper config) |
| Kafka throughput per partition | ~10-100 MB/s |
| Single-server max concurrent TCP connections | ~64K (port limit, untuned) |

Memorise. They're the calibration for "will this work?" decisions.

## Anti-patterns

- **"We need microservices."** Stated as a requirement instead of an option. Microservices solve *organisational* problems (team autonomy, deploy independence), not technical ones. If you don't have those problems, you don't need them.
- **"Web scale" arguments.** Claiming a design needs to handle 10⁹ users when the real number is 10⁴. Right-size.
- **Strong consistency everywhere.** Pays more than you think. Most reads can tolerate seconds of staleness; identify those.
- **Single global database for everything.** Polyglot persistence (`database-design`) exists for a reason.
- **Adding caching without measuring.** Cache misses, invalidation, and warmup are real costs. Cache when you know the read pattern, not before.
- **Synchronous chains 5 services deep.** Each hop adds latency and a failure mode. Use async (events / queues) for non-critical paths.
- **No capacity numbers in the design.** Then it's a vibe, not a design.

## Related skills

- `architecture` — when to apply specific patterns (CQRS / polyglot / etc.)
- `architecture-patterns` — module/layer overlays (Onion / Clean / DDD)
- `ddd-strategic-design` + `ddd-context-mapping` — bounded contexts as the system-design unit at scale. This skill picks the *architectural boxes and arrows* (services, stores, queues) from non-functional requirements; `ddd-strategic-design` picks *which of those boxes are domain-owned subdomains* and how to classify them (Core / Supporting / Generic). Run strategic-DDD before system-design when the domain is rich; run system-design before strategic-DDD when scale/latency drives the shape
- `cqrs-implementation`, `database-design`, `api-design-principles` — the *how* once the system design is set
- `architecture-decision-records` — capture the design as ADRs

## Limitations

- This skill teaches the **discipline** — it can't substitute for domain-specific knowledge (e.g., what does a payment ledger actually need to enforce?). Pair with `ddd-strategic-design` for the domain.
- Numbers in `capacity-estimation.md` are 2025-ish ballpark. Hardware changes. Validate before relying on them.
- Stop and ask if **non-functional requirements** (latency, throughput, durability, consistency, availability) are not specified before designing. Designing without NFRs is theatre.
