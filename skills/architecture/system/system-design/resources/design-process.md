# The 7-Phase Process

How to move from "we need a new system" to "here's a design we can build." Each phase produces a concrete artefact; the *story* across phases is the deliverable, the diagram is the artefact (P5).

## P1 — Clarify

Make the problem precise. Two parts:

**Functional** (what the system does, in 1–3 sentences). Who are the users? Volume per type. What's explicitly **out of scope** — naming non-goals up front prevents scope creep that no design can absorb.

**Non-functional** — force concrete numbers on every row. Designing without NFRs is theatre (T1, T2):

| NFR | Question | Numbers, not adjectives |
|---|---|---|
| Latency | p50 / p99 / p99.9 — for which operations? | "p99 ≤ 200 ms", not "fast" |
| Throughput | reads/s + writes/s, average + peak | "10 K writes/s peak" |
| Durability | tolerance for last-N-minute loss | "must persist before ACK" / "5 min OK" |
| Consistency | strong / RYW / eventual — per operation (T5) | "linearizable for payments" |
| Availability | uptime SLO | "99.9%" = ~9 h/yr down |
| Geography | single-region / multi / global edge | "global edge for reads; primary in us-east" |
| Cost ceiling | $/month budget | drives many decisions |
| Compliance | PII / PCI / HIPAA / GDPR | constrains architecture |
| Time-to-launch | weeks vs years | rules out novel infra |

Output: 1-paragraph problem statement + NFR table with numbers.

## P2 — Estimate

Compute QPS, storage, bandwidth, memory, instances. Method + numbers live in [capacity-estimation](capacity-estimation.md). Estimation prevents over-engineering: numbers rule out 100 architectures in 30 seconds (P3).

Worked example — URL shortener:

```
100 M new URLs/month, 1 B redirects/month, ~100 B per URL, retain forever.

Writes:    100 M / 30 / 86400 ≈ 40/s avg     → peak ~200/s
Reads:     1 B  / 30 / 86400 ≈ 400/s avg     → peak ~2 000/s
R/W ratio: 10:1                              → read-heavy, cache helps
Storage:   100 M × 100 B × 12 × 5 = 600 GB   → fits one DB instance
Bandwidth: 1 KB resp × 400/s ≈ 0.4 MB/s     → trivial
```

These numbers immediately rule out sharding, multi-region, fancy ID generators. *One* Postgres + cache solves it. Without arithmetic you might have built 12 services (P4 — start simple).

## P3 — High-level

5–7 boxes max. More = you've leaked into P4. Pieces to consider:

- **Clients** (web, mobile, API consumers)
- **Edge** (CDN, load balancer, API gateway)
- **Services** (the boxes)
- **Data stores** (primary, cache, search index)
- **Async fabric** (message broker, event bus)
- **External integrations** (payment, email, auth)

URL shortener at high level:

```
Browser → CDN → LB → App (stateless, N)
                       ↓
                     Redis (cache-aside)
                       ↓ miss
                     Postgres (source of truth)
                       ↓ events
                     Kafka → Clickhouse (analytics projection)
```

That's it. Cache-aside Redis, source-of-truth Postgres, analytics via async Kafka projection. No premature complexity.

## P4 — Component

For each box, one paragraph:

- **Responsibility** — one sentence.
- **API** — what comes in, what goes out.
- **Dependencies** — which boxes it talks to.
- **Failure mode** — what happens when this is down. A box without a stated failure mode is decoration.

Example — "App service" for URL shortener:

> POST `/shorten`: generate code, store mapping, return short URL. GET `/:code`: look up code, 302 redirect. GET `/:code/analytics` (auth): aggregated click data.
>
> Depends on: Postgres (writes), Redis (cache), Kafka (analytics events).
>
> Failure modes: Postgres down → 503. Redis down → degrade to direct Postgres reads (slower, still works). Kafka down → fire-and-forget, no user-facing impact, analytics lag.

The degraded-paths matter as much as the happy path.

## P5 — Detail

Now drill down. What lands in this phase:

| Detail | URL-shortener example |
|---|---|
| Data model | `urls(code PK, original_url, created_at, created_by, clicks_count)` |
| ID generation | Base62 7-char random + collision check, or Snowflake/ULID |
| Cache key / value / TTL | `code → original_url`, TTL 1 h |
| API contract | OpenAPI / proto definitions |
| Critical algorithm | Pseudo-code for code generation + redirect |
| Transactional boundaries | What commits where; what's idempotent |
| Event schemas | `UrlCreated { code, url, createdAt }`, `UrlVisited { code, ip, ua, at }` |

ID choice is itself a thesis-locked decision: predictable codes leak business info; UUIDs are too long; auto-increment is a write bottleneck. 62⁷ ≈ 3.5 T codes — at 100 M total, collision probability per insert is ~10⁻⁵, so retry-on-conflict is fine.

## P6 — Bottlenecks

For each box ask: CPU bound? Memory bound? I/O bound? Network bound? Lock bound? Then name a threshold.

URL shortener bottleneck audit:

| Component | Risk | Threshold |
|---|---|---|
| App service | None at 2 K req/s | stateless, scales horizontally |
| Redis | Memory: 100 M × 100 B = 10 GB | fits one node; cluster at 10× |
| Postgres writes | 200/s peak | trivial |
| Postgres reads | 200/s cold (90% cache hit) | trivial |
| Kafka | 400 events/s | one partition handles 10× |
| ID generation | Single counter = bottleneck | use random + collision check |

Easy-to-miss ones: N+1 inside a "single API call"; cache stampede on cold key; connection pool exhaustion *before* CPU; external-service timeout chain; hot partition.

## P7 — Scale

For each bottleneck, name the migration *path*. Don't pre-build:

| Component | 10× current | 100× current |
|---|---|---|
| App | Add instances | Multi-region |
| Redis | Bigger node | Cluster + per-region replicas |
| Postgres reads | Read replicas | Shard by code prefix |
| Postgres writes | Vertical scale | Shard |
| Kafka | More partitions | Multi-cluster |

The biggest P7 mistake: designing for 100× when you have 1× (A2). Identify the path, don't commit to building it.

## Communicating the design

A design doc / ADR / interview answer follows the same order — Phases 1 → 7. The story carries; the diagram is the artefact (P5). Iteration is the job: bottleneck discoveries in P6 routinely send you back to P3 (P2). That's not failure, that's the process.

## Honesty about unknowns

"I don't know writes/sec" is correct; making up a number is the failure mode (P6). Capture unknowns as questions, not as decoration in the design.
