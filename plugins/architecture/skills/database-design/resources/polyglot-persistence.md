# Polyglot Persistence

When PostgreSQL / MongoDB / Elasticsearch / Clickhouse. Decision tree, cost of each store, cross-store consistency strategies.

---

## 1. Default position: PostgreSQL only

Until proven otherwise, PostgreSQL is the right answer for **everything**. It handles:

- Transactional writes with ACID
- Complex joins
- JSONB for semi-structured data
- Full-text search (good enough for ~10K-100K rows)
- Time-series (good enough for moderate volume with BRIN + partitioning)
- Materialised views for read denormalisation

**Reach for additional stores only when Postgres has a real, demonstrated limitation.** Every additional store = new failure mode, new backup story, new monitoring, new operational cost.

---

## 2. The decision tree

```
Workload to support?
│
├── Transactional writes, aggregates, ACID
│   → PostgreSQL (default, always)
│
├── Full-text search, fuzzy matching, faceted filters
│   ├── < 10K rows AND simple ranking
│   │   → PostgreSQL full-text + pg_trgm
│   └── More than that, OR need synonyms / multilingual / scoring
│       → Elasticsearch (projection target)
│
├── Document with variable schema, sparse fields, large payload blobs
│   ├── Schema mostly stable, fields mostly populated
│   │   → PostgreSQL JSONB
│   └── Schema genuinely varies per document, payloads >100KB
│       → MongoDB
│
├── Analytical queries: aggregations over 10M+ rows, time-series rollups
│   ├── < 10M rows, query latency tolerable in seconds
│   │   → PostgreSQL with proper indexes, BRIN, partitioning
│   └── 10M+, or sub-second analytics on huge data
│       → Clickhouse
│
├── Hot cache, counters, leaderboards, ephemeral state
│   → Redis
│
└── Anything else
    → PostgreSQL
```

---

## 3. PostgreSQL — strengths and limits

**Strengths:**
- ACID transactions
- Strong typing (every column has a type)
- Rich indexing (B-tree, GIN, GiST, BRIN — see `indexing.md`)
- JSONB for sparse / variable fields
- Materialised views for denormalised reads
- `LISTEN/NOTIFY` for in-DB pub/sub (small-scale events)
- pg_trgm for fuzzy text (good enough for autocomplete)
- Native partitioning (declarative since v10)

**Real limits:**
- Single primary writer. Read replicas scale reads, not writes.
- Vacuum overhead on very high update churn (think: per-second status updates on millions of rows).
- Full-text search doesn't compete with ES on multilingual, synonyms, scoring relevance.
- Analytical scans over 100M+ rows hurt — designed for OLTP, not OLAP.

**Sharding** in Postgres is operational pain. If you really need horizontal write scaling, you're either restructuring or migrating to something that handles it natively (Citus, CockroachDB). Usually you don't actually need it — you need indexes.

---

## 4. MongoDB — narrow use case

Use MongoDB when:
- Document shape genuinely varies per record and isn't a small JSONB column.
- Documents are large (10s-100s of KB) and you store/retrieve them whole.
- Schema-on-read makes sense (the consumer interprets the structure).

**Don't use MongoDB when:**
- You're going to join it against other collections (Mongo joins are weak).
- You need ACID across multiple documents (multi-document transactions exist but are operationally limited).
- You're using it as a "JSONB column with extra steps" — that's what JSONB is for.

Real Mongo use cases in a JVM/Spring shop:
- **Vendor integration payloads** — raw API responses you keep for debug / replay.
- **Audit log of complex objects** — versioned snapshots of large structs.
- **User-generated content** — articles, posts where the body schema varies.

For most other "we have JSON" cases, Postgres JSONB is the better answer.

---

## 5. Elasticsearch — search, not storage

ES is a **search engine that happens to store data**. Treat it that way.

**Use ES for:**
- Full-text search (tokenisation, stemming, synonyms, multilingual)
- Faceted filters (`type=order AND status=shipped AND amount > 100 GROUP BY category`)
- Fuzzy / typo-tolerant matching
- Geo queries (geohash, geo_bounding_box)
- Time-series log search (think: ELK / OpenSearch logs)

**Don't use ES as:**
- Source of truth. ES indexes are derived; you must be able to rebuild them.
- Transactional store. No ACID. Refreshes are async.
- Primary CRUD store. Use Postgres; project to ES for search.

Typical pattern: Postgres `orders` table is the source of truth; a Spring Modulith event listener projects to an ES `orders` index for search queries. See `cqrs-implementation/resources/read-side-patterns.md`.

```kotlin
@Component
class OrderSearchProjection(private val es: OrderSearchRepository) {
    @ApplicationModuleListener
    fun on(event: OrderPlaced) {
        es.save(OrderSearchDoc.fromEvent(event))
    }
}
```

Operational notes:
- ES clusters are operationally non-trivial. Memory tuning, shard sizing, GC tuning.
- Mapping migrations require reindexing — plan it.
- The free / OSS license story is messy; pick OpenSearch (Apache 2.0) for new projects unless you have Elastic enterprise needs.

---

## 6. Clickhouse — analytics, not OLTP

Clickhouse is **columnar, append-mostly, analytical**. It eats aggregations for breakfast.

**Use Clickhouse for:**
- Dashboards that aggregate over 10M-1B rows in sub-second
- Time-series rollups (per-minute / per-hour / per-day stats)
- Event analytics, funnel analysis, cohort queries
- Logs you want to query (not just store)

**Don't use Clickhouse for:**
- Single-row CRUD. Postgres point reads at ~50µs; Clickhouse at ~50ms. Wrong shape.
- Workloads needing UPDATE / DELETE. Clickhouse supports them but they're operationally heavy (mutations rewrite parts).
- Strong consistency. Clickhouse is eventually consistent for replicated tables.

Typical pattern:
1. Aggregate emits domain events.
2. A projection sinks events into Clickhouse, batched (every 1-5 seconds) — `INSERT ... VALUES` of 1000+ rows per batch.
3. Dashboards query Clickhouse directly.

Schema design for Clickhouse is fundamentally different — `MergeTree` engine with a sort key chosen for query patterns. That's worth a separate skill if you go deep.

For typical Spring app integration:

```yaml
clickhouse:
  url: jdbc:clickhouse://clickhouse:8123/analytics
  username: app
  password: ${CLICKHOUSE_PASSWORD}
```

```kotlin
@Configuration
class ClickhouseConfig {
    @Bean("clickhouseDataSource")
    fun clickhouseDataSource(props: ClickhouseProperties): DataSource = HikariDataSource(...)

    @Bean("clickhouseJdbcTemplate")
    fun clickhouseJdbcTemplate(@Qualifier("clickhouseDataSource") ds: DataSource) =
        NamedParameterJdbcTemplate(ds)
}
```

No JPA — use `NamedParameterJdbcTemplate` or jOOQ. JPA / Hibernate + Clickhouse is not a productive combination.

---

## 7. Redis — cache, not store

Redis is in your stack when you need:
- Cache for expensive computations (`@Cacheable` backed by Spring + RedisTemplate).
- Distributed rate limiting (Bucket4j + Redis).
- Counters that are too hot for Postgres (per-second click counts).
- Pub/sub for small-scale fan-out.
- Distributed locks (with care — Redlock is contentious).

**Never** put your source of truth in Redis. It's volatile by design.

---

## 8. The pitfall: "use everything"

Every store you add brings:

| Cost | Reality |
|---|---|
| **Operational complexity** | Different backup story, different monitoring, different upgrade path |
| **Observability surface** | New metrics endpoints, new dashboards, new alerts |
| **Developer cognitive load** | "Where does this data live? When does it sync? What's the lag?" |
| **Failure modes** | Each store can be down independently |
| **Cross-store consistency** | Eventual; design for lag and reconcile |

**Add a store only when the pain of not having it outweighs all of the above.**

Bad reason: "Mongo is good for X." Good reason: "We tried Postgres JSONB, profiled, and the queries we actually run scan 90% of the column — that's a Mongo workload."

---

## 9. Cross-store consistency

When you have data in two stores (Postgres + ES, Postgres + Clickhouse), consistency is eventual.

Strategies:

| Strategy | How | Trade-off |
|---|---|---|
| **Outbox + projection** | Aggregate emits event in same TX as save. Projection listener writes to other store. | Standard pattern. Spring Modulith provides outbox. Lag = projection time. |
| **CDC (Debezium)** | Stream Postgres WAL → Kafka → secondary stores. | No app-level event publication needed. Operational complexity high. |
| **Periodic sync** | Cron job that diffs and syncs. | Simplest. Worst freshness. OK for daily reports. |
| **Synchronous dual-write** | App writes to both stores in the same request. | Bad. Half-write on failure = inconsistent. Don't do this. |

For most cases: **outbox + projection** via Spring Modulith events. Already in your toolbox.

For very large data volumes or polyglot data warehouses: **CDC**. Different operational shape; investigate when you have the need.

**Never** "synchronous dual-write" — it's the second-most-common cause of cross-store inconsistency (the first being "we forgot to update store B").

---

## 10. Concrete decisions for assista-platform-style stack

| Workload | Store | Why |
|---|---|---|
| `Order` aggregate writes, transactional state | **PostgreSQL** | ACID, joins to customer, single source of truth |
| `Order` search by customer + status + date range + free-text notes | **Elasticsearch** | Full-text + facets; can't get it from PG at scale |
| `Order` analytics — daily revenue, avg order value, percentiles | **Clickhouse** | Aggregations over millions, sub-second |
| `User` profile preferences (variable shape) | **PostgreSQL JSONB** | Schema mostly known; one column suffices |
| `Vendor integration payloads` (raw API responses, kept for debug) | **MongoDB** | Truly variable schema per vendor; we want to keep blobs |
| `Auth session cache`, rate limiting tokens | **Redis** | Volatile, hot, short TTL |

Each store has a clear job. The skill is knowing **what NOT to put in each**.

---

## 11. Architecture checklist before adding a new store

- [ ] Defined the **query** the new store is for (one sentence, concrete)
- [ ] Tried it in PostgreSQL first, profiled, found the actual limit
- [ ] Decided who maintains the new store (team capacity)
- [ ] Designed the projection / sync mechanism (outbox? CDC? batch?)
- [ ] Planned how to rebuild the secondary store from scratch
- [ ] Set up monitoring for projection lag
- [ ] Captured the decision in an ADR
- [ ] Set a sunset date to revisit ("if usage doesn't justify in 6 months, remove")
