# Capacity Estimation (Back-of-Envelope)

Numbers every backend engineer should have in their head. Without them, "we'll handle the load" is a vibe, not a design (A7). With them, 30 seconds of arithmetic rules out 100 architectures.

## Numbers to memorise

### Time (C1)

| Period | Seconds |
|---|---|
| 1 day | 86 400 (~10⁵) |
| 1 month (30 d) | 2.6 M |
| 1 year | 31.5 M |

**Conversion:** `X / month / 2.6 M = X / second` average. **Peak factor: ×3–5** for human-traffic systems (Black Friday, app store launch features).

Sanity rules:

- 100 M / month ≈ 40/s avg → 200/s peak
- 1 B / month ≈ 400/s avg → 2 000/s peak
- 10 B / month ≈ 4 000/s avg → 20 000/s peak

### Data sizes (units)

```
1 KB = 10³   |   1 GB = 10⁹    |   1 TB = 10¹²   |   1 PB = 10¹⁵
```

Common row/item sizes (back-of-envelope):

| Item | Size |
|---|---|
| UUID binary / string | 16 B / 36 B |
| Timestamp binary / ISO | 8 B / 24 B |
| Short URL row | 100–200 B |
| User profile / tweet | 1–2 KB / 300–500 B |
| Email / thumbnail | 10–100 KB |
| Full photo / 30 s video | 1–5 MB / 10–100 MB |

### Latency hierarchy (C2 — Jeff Dean updated)

| Operation | Latency | Vs L1 |
|---|---|---|
| L1 cache reference | 0.5 ns | 1× |
| Main memory reference | 100 ns | 200× |
| SSD random read | 100 µs | 200 K× |
| HDD seek | 10 ms | 20 M× |
| Same-DC round-trip | 0.5 ms | 1 M× |
| Cross-continent RTT | 150 ms | 300 M× |

**Implication (C5):** a network call is ~1000× slower than a memory access. A sync chain of 5 services accrues ≥5× the per-hop budget; you don't get to ignore the ladder.

### Throughput per node (C3)

| Component | Rough ceiling |
|---|---|
| Postgres writes (tuned) | 10–50 K/s |
| Postgres reads | 50–100 K/s |
| Redis single instance | 100 K ops/s (1 M w/ pipelining) |
| Kafka per partition | 10–100 MB/s |
| Elasticsearch indexing | 1–10 K docs/s per node |
| ES search | 100–1 000 QPS per node |
| Clickhouse inserts (batched) | 100 K – 1 M rows/s per node |
| Single JVM service | 5–20 K req/s per instance |
| L7 LB (Nginx/HAProxy) | 50–200 K req/s |
| 1 Gbps link | ~125 MB/s |
| 10 Gbps link | ~1.25 GB/s |

These vary 10× with workload. Use as sanity checks, not promises.

## Estimation method

For any system, in order:

```
1. DAU / MAU                  → user count
2. Actions per user per day   → operations/day
3. ÷ 86 400                   → operations/s average
4. × 3–5                      → operations/s peak
5. Bytes per operation        → bandwidth + storage
6. Reads vs writes ratio      → cache strategy, replica need
7. Retention                  → total storage
```

### Worked example — News feed

**Given:** 100 M DAU, 5 feed loads/day, 50 posts × 500 B each.

```
Reads/day   = 100 M × 5 = 500 M
Reads/s avg = ≈ 5 800/s     | peak ≈ 30 K/s
Bytes/load  = 50 × 500 = 25 KB
Bandwidth   = 30 K × 25 KB ≈ 750 MB/s ≈ 6 Gbps
Writes/day  = 200 M (2/user)  | peak ≈ 12 K/s
```

Reveals: **cache the feed** (90% hit → 3 K/s DB hits); **6 Gbps** at peak demands CDN/edge; **12 K writes/s** fits one Postgres + Kafka fan-out.

### Worked example — Chat (WhatsApp-scale)

**Given:** 1 B DAU, 50 messages sent + 100 received per user/day, 200 B/message, 7-day retention.

```
Sent/day        = 1 B × 50 = 50 B
Sent/s          ≈ 580 K/s    | peak ≈ 2.5 M/s
Storage/day     = 50 B × 200 B = 10 TB
Storage 7 days  = 70 TB
```

Reveals: **no single Postgres**, must shard; **70 TB** for one week → 7+ shards minimum; **2.5 M w/s peak** → Kafka + sharded store, multi-DC. Architecture decisions are *completely different* from the URL shortener — by orders of magnitude. That's the value of arithmetic.

## Storage estimation

```
Total disk = rows × row size × replication × indexing-overhead
```

| Multiplier | Typical |
|---|---|
| Row size | data + PK + timestamps + ~30 B per-row overhead |
| Replication | 2–3× (primary + 1–2 replicas) |
| Indexing | 1.5–3× the table (every index copies indexed cols) |
| WAL / journal | +20–30% on write-heavy |

So a 100 GB **raw** dataset = **300–600 GB on disk** after indexing + replication (C4). Add backups (×2–4) and cold-tier copies. Don't forget the ×3–5 disk multiplier when sizing storage tier.

## Memory estimation

```
Working set = hot keys × avg value size
```

URL shortener: 100 M codes × 100 B = 10 GB raw, but only ~20% are hot in 24 h → 2 GB working set fits one Redis node. Estimate object overhead **up** by ~2× (headers, padding, hash-map slots are real).

## Instance count

Stateless service:

```
Instances = peak QPS / (QPS per instance × utilisation target)
```

If a service handles 5 K req/s at p99 = 100 ms and you target 50% util:

```
For 30 K peak: 30 K / (5 K × 0.5) = 12 instances
```

Then enforce HA floor (≥3 across AZs). Result: `max(12, 3) = 12`.

## Bandwidth

```
QPS × bytes/response × ~1.5 (HTTP/2 + TLS overhead) = bandwidth
```

30 K × 25 KB × 1.5 ≈ 1 GB/s ≈ 8 Gbps per region. Cloud charges for egress; matters for cost.

## Little's Law (T7)

```
Concurrency = throughput × latency
```

10 K req/s at 50 ms latency ⇒ 500 in-flight requests. Sets thread/connection-pool sizes. Pool too small = queueing; pool too large = thrash + GC pressure.

## Common traps

| Trap | Reality |
|---|---|
| Designing for average | Peak is 3–10× avg; design for peak |
| Forgetting replication + indexing | 3–5× raw is the real disk |
| Single-machine maths on sharded reality | One node handles 1/N + coordination overhead (not 1/N flat) |
| Linear scaling | Network/lock contention breaks linearity past ~10× |
| Ignoring growth | 100%/yr ⇒ 1024× in 10 years |
| User-perceived latency = server latency | Add network, serialise, GC, cold cache, cross-AZ — 100s of ms |

## 30-second interview reflex

Ask DAU + ops/user → compute QPS, storage, bandwidth (formulae above) → map to throughput table → name which boxes need sharding / replicas. 30 seconds, on paper, before drawing (I2). Without arithmetic, you're showing the interviewer you haven't internalised hardware costs.
