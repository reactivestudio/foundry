# Capacity Estimation (Back-of-Envelope)

Numbers every backend engineer should have in their head. Turns vague design discussions into concrete bottleneck identification.

---

## 1. Numbers to memorise

### Time

| Unit | In seconds | In milliseconds |
|---|---|---|
| 1 day | 86,400 | 86.4M |
| 1 week | 604,800 | 604M |
| 1 month (30d) | 2.6M | 2.6B |
| 1 year | 31.5M | 31.5B |

**Conversion:** "X per month" / 2.6M = "X per second" average.
- 100M / month ≈ 40/s avg
- 1B / month ≈ 400/s avg
- 10B / month ≈ 4000/s avg

**Peak factor:** 3-5× average for human-traffic systems. So 1B/month ≈ ~2000/s peak.

### Data sizes

| Unit | Bytes |
|---|---|
| 1 KB | 10³ |
| 1 MB | 10⁶ |
| 1 GB | 10⁹ |
| 1 TB | 10¹² |
| 1 PB | 10¹⁵ |

### Common data sizes

| Item | Size |
|---|---|
| UUID (binary) | 16 bytes |
| UUID (string) | 36 bytes |
| ASCII char | 1 byte |
| UTF-8 char | 1-4 bytes |
| `Long` / `Int64` | 8 bytes |
| `Int32` | 4 bytes |
| Timestamp (Instant) | 8 bytes (binary) / 24 bytes (ISO string) |
| Short URL row | ~100-200 bytes |
| User profile | ~1-2 KB |
| Tweet / short post | ~300-500 bytes |
| Email | ~10-100 KB |
| HTTP request (header + small body) | ~1 KB |
| Small image (thumbnail) | ~10-100 KB |
| Photo (full) | ~1-5 MB |
| Short video (30s) | ~10-100 MB |
| Video (10 min HD) | ~500 MB - 1 GB |

### Latency numbers (Jeff Dean's classic, updated)

| Operation | Latency | Approx multiplier |
|---|---|---|
| L1 cache reference | 0.5 ns | 1× |
| Branch mispredict | 5 ns | 10× |
| L2 cache reference | 7 ns | 14× |
| Mutex lock/unlock | 25 ns | 50× |
| Main memory reference | 100 ns | 200× |
| Compress 1KB with Snappy | 10 µs | 20K× |
| Send 1KB over 1 Gbps network | 10 µs | 20K× |
| Read 1 MB sequentially from RAM | 50 µs | 100K× |
| SSD random read | 100 µs | 200K× |
| Read 1 MB sequentially from SSD | 1 ms | 2M× |
| Disk seek (HDD) | 10 ms | 20M× |
| Read 1 MB sequentially from HDD | 30 ms | 60M× |
| Round-trip within same datacenter | 0.5 ms | 1M× |
| Round-trip CA → Netherlands | 150 ms | 300M× |

**Implications:**
- A network call is **1000× slower** than a memory access. Don't chain microservices casually.
- A disk seek is **30× slower** than an SSD random read. Why we cache.
- Cross-continent latency is dominated by speed of light, can't be optimised.

### Throughput numbers

| Component | Throughput |
|---|---|
| Single Postgres instance, writes | ~10-50K writes/s (proper tuning) |
| Single Postgres instance, reads | ~50-100K reads/s |
| Redis (single instance) | ~100K ops/s, ~1M with pipelining |
| Memcached | ~100K-1M ops/s |
| Kafka per partition | ~10-100 MB/s |
| Kafka cluster (typical) | ~1-10 GB/s |
| Elasticsearch indexing | ~1-10K docs/s per node |
| Elasticsearch search | ~100-1000 QPS per node |
| Clickhouse inserts | ~100K-1M rows/s per node (batched) |
| Single JVM service | ~5-20K req/s per instance |
| Load balancer (HAProxy/Nginx) | ~50-200K req/s |
| Network — 1Gbps link | ~125 MB/s |
| Network — 10Gbps link | ~1.25 GB/s |
| HTTP/2 multiplexed | ~10K streams per connection |

These are rough. Specific workloads vary 10× either way. Use as **sanity check**, not promise.

---

## 2. The estimation method

For any system, work in this order:

```
1. DAU / MAU                   → user count
2. Actions per user per day    → operations/day total
3. /86400 (seconds in a day)   → operations/s average
4. ×3-5 (peak factor)          → operations/s peak
5. Bytes per operation         → bandwidth & storage
6. Reads vs writes ratio       → cache pattern, replica need
7. Retention                   → total storage
```

### Worked example 1 — News feed

**Given:** 100M DAU, average 5 feed loads/day, each load = 50 posts × ~500 bytes.

```
Reads/day     = 100M × 5 = 500M feed loads
Reads/s avg   = 500M / 86400 ≈ 5800/s
Reads/s peak  = ~30K/s
Bytes/load    = 50 × 500 = 25 KB
Bandwidth     = 30K/s × 25 KB = 750 MB/s = 6 Gbps

Posts/day     = 100M × 2 (writes per user) = 200M
Writes/s avg  = 2300/s
Writes/s peak = ~12K/s
```

Reveals:
- **Cache the feed** — 30K/s reads is hot but cacheable (90% hit rate → 3K/s DB hits)
- **6 Gbps bandwidth** at peak — multi-region delivery via CDN/edge
- **12K writes/s** — single Postgres can do it; multi-node Kafka for fan-out

### Worked example 2 — Chat (WhatsApp-like)

**Given:** 1B DAU, average 50 messages sent + 100 received per user/day, ~200 bytes/message, 7-day retention.

```
Messages sent/day  = 1B × 50 = 50B
Messages sent/s    = 50B / 86400 ≈ 580K/s
Peak              = ~2.5M/s

Storage/day        = 50B × 200 bytes = 10 TB
Storage 7 days     = 70 TB
Annual             = 3.65 PB (if retention were a year)
```

Reveals:
- **No single Postgres**. Must shard.
- **70 TB** for a week — typical commodity disk is 10TB → 7+ shards minimum
- **2.5M writes/s peak** — Kafka + sharded store, multi-DC

Numbers immediately rule out "single big DB" designs.

### Worked example 3 — URL shortener (from design-process.md)

Already worked: 100M/month writes, 1B/month reads, 600GB over 5 years. Single Postgres fits.

The difference between Examples 2 and 3 is **3+ orders of magnitude**. Architecture decisions are completely different.

---

## 3. Memory estimation

### Working set for caches

```
Hot keys × Avg value size = Cache memory needed
```

For a URL shortener with 100M codes, ~100 bytes per entry: 10 GB raw. **But** only ~20% of codes are hot (visited in last 24h). So 2 GB working set → fits in one Redis node.

For a chat system with 1B users, ~100KB recent-conversation cache: 100 TB raw. Not cacheable in memory. Strategy: cache only **active** sessions (~1% × 100 TB = 1 TB) across a Redis cluster.

### JVM heap

Spring Boot app baseline: ~200-500 MB heap. Each cached object: object header (16 bytes) + fields. Pad significantly.

**Pitfall:** holding 1M `User` objects in memory ≠ 1M × 1KB = 1GB. It's usually 1M × 200 bytes overhead + 1M × 1KB fields + 1M × hash-map overhead → 1.5-2 GB. Estimate up.

---

## 4. Storage estimation

```
Total storage = rows × row size × replication factor × indexing overhead
```

| Multiplier | Typical |
|---|---|
| Row size | data + per-row PK + timestamps + per-row overhead (~30 bytes) |
| Replication factor | 2-3 (primary + 1-2 replicas) |
| Indexing overhead | 1.5-3× the table (every index adds copies of indexed columns) |
| WAL / journal | +20-30% on writes |

So a 100 GB raw dataset typically needs **300-600 GB** on disk after indexing + replication.

Don't forget:
- **Backups** — 2× to 4× depending on retention and frequency
- **Cold storage** — older data shipped to cheaper tier

### Time-series sizing

```
Series × points/series × bytes/point × retention
```

Example: 10K servers × 100 metrics each = 1M series. 1 point/15s = 5760/day. 16 bytes/point. Retain 90 days.

```
1M × 5760 × 16 × 90 = ~8 TB
```

Compresses ~10× in Prometheus / VictoriaMetrics → ~800 GB realistic.

---

## 5. Instance count estimation

For a stateless service:

```
Instances = Peak QPS / (QPS per instance × utilisation target)
```

If a Spring service handles 5K req/s at p99 = 100ms (1 core saturated, untuned), and you want 50% utilisation for headroom:

```
Need = 30K / (5K × 0.5) = 12 instances
```

Add HA: at least 3 across AZs even at low load. Total target = max(12, 3) = 12 instances.

For DBs: usually vertical-scale until forced to shard. "How many DB instances" comes after capacity-per-instance maths.

---

## 6. Bandwidth estimation

```
QPS × bytes/response × overhead = bandwidth
```

Overhead: HTTP/2 headers ~50 bytes/req, TLS ~50 bytes, padding to next packet boundary. 1.5× the payload is a fair multiplier.

Peak 30K QPS × 25KB × 1.5 = ~1 GB/s per region. That's 8 Gbps. Cloud providers charge for egress; this matters for cost.

---

## 7. Cost back-of-envelope

Cloud is roughly:
- **CPU-hour** (4 cores): $0.10-0.40/hr → ~$70-300/month per instance
- **Postgres-managed (4 cores, 32GB, 1TB SSD)**: ~$500-1500/month
- **S3 storage**: ~$0.02/GB/month → $200/TB/month
- **Egress bandwidth**: $0.05-0.10/GB → 1 TB/month = $50-100
- **Kafka managed (small)**: $500-2000/month
- **Redis managed (memory tier)**: $100-1000/month depending on size

Example: small SaaS with 12 app instances + Postgres primary + 1 replica + Redis + 1 TB egress/month:
- 12 instances × $150 = $1800
- Postgres × 2 = $2000
- Redis = $400
- Egress = $100
- **Total ≈ $4300/month** before observability/CI/etc.

Round up 2× for support costs (logs, monitoring, backups, oncall).

---

## 8. Common estimation traps

| Trap | Reality |
|---|---|
| Average ignoring peak | Peak is 3-10× avg; design for peak |
| Forgetting replication / indexing overhead | 3-5× the raw |
| Single-machine math when sharded reality | One node handles 1/N of work + coordination overhead |
| Linear scaling assumption | Network / lock contention break linearity past ~10× |
| Ignoring growth | 100% YoY growth = 1024× in 10 years |
| User-facing latency includes everything | Cold cache + cross-AZ + serialize/deserialize + GC = 100s of ms |

---

## 9. Quick reference for interviews

When asked "design X":
1. Ask: **DAU and operations per user**
2. Compute: **QPS = ops × DAU / 86400**, peak = 3-5×
3. Compute: **Storage = rows × bytes × replication × indexing**
4. Compute: **Bandwidth = QPS × bytes × 1.5**
5. Use the **throughput numbers** above to map components

A 30-second arithmetic-on-paper exercise that frames every subsequent decision.
