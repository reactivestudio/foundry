# Read-Side Patterns

Queries, projection handlers, target stores (Postgres view / ES / Clickhouse), state tracking, rebuild, read-your-writes consistency. Kotlin/Spring Boot.

---

## 1. Query shape

A query is a **request for data**, expressed as immutable data. Queries are flat — no aggregates, no domain logic.

```kotlin
sealed interface OrderQuery<R> {
    data class ById(val id: OrderId) : OrderQuery<OrderDetailView?>
    data class ByCustomer(
        val customerId: CustomerId,
        val status: OrderStatus? = null,
        val page: PageRequest,
    ) : OrderQuery<Page<OrderListItem>>
    data class Search(
        val text: String,
        val filters: SearchFilters,
        val page: PageRequest,
    ) : OrderQuery<Page<OrderSearchHit>>
    data class DailyStats(val from: LocalDate, val to: LocalDate) : OrderQuery<List<DailyStatRow>>
}
```

Each variant carries the parameters it needs and declares its return type. The return types are **flat data classes** designed for the query — not aggregates.

```kotlin
// Designed for the detail page — single record, full info
data class OrderDetailView(
    val id: OrderId,
    val customerId: CustomerId,
    val customerName: String,        // denormalised from Customer
    val customerEmail: String,       // denormalised
    val status: OrderStatus,
    val items: List<OrderItemView>,
    val total: Money,
    val placedAt: Instant,
    val shippedAt: Instant?,
)

// Designed for the list page — minimal fields
data class OrderListItem(
    val id: OrderId,
    val status: OrderStatus,
    val total: Money,
    val itemCount: Int,
    val placedAt: Instant,
)

// Designed for search — includes search-engine specifics
data class OrderSearchHit(
    val id: OrderId,
    val customerName: String,
    val total: Money,
    val highlight: String?,          // ES highlight snippet
    val score: Float,                // ES relevance score
)

// Designed for analytics — pre-aggregated
data class DailyStatRow(
    val date: LocalDate,
    val orderCount: Long,
    val revenue: Money,
    val avgOrderValue: Money,
)
```

Four return shapes for one aggregate. Each optimised for its query. This is the point of CQRS.

---

## 2. Query handler

Same pattern as command handlers: one `@Service` per query class, or grouped when cohesive.

```kotlin
@Service
class OrderDetailQueryHandler(
    private val views: OrderDetailViewRepository,
) {
    fun handle(query: OrderQuery.ById): OrderDetailView? = views.findById(query.id.value).orElse(null)
}

@Service
class OrderSearchQueryHandler(
    private val es: ElasticsearchOperations,
) {
    fun handle(query: OrderQuery.Search): Page<OrderSearchHit> {
        val criteria = Criteria("status").matches(query.filters.status?.name)
            .and("placedAt").greaterThanEqual(query.filters.from)
            .and(Criteria.or().queryString(query.text).boost(2.0f))

        val nativeQuery = NativeQueryBuilder()
            .withQuery(criteria)
            .withPageable(query.page)
            .withHighlightQuery(HighlightQuery(…))
            .build()

        val hits = es.search(nativeQuery, OrderSearchDoc::class.java)
        return hits.map { it.toView() }.toPage(query.page)
    }
}

@Service
class OrderStatsQueryHandler(
    @Qualifier("clickhouseJdbcTemplate") private val ch: JdbcTemplate,
) {
    fun handle(query: OrderQuery.DailyStats): List<DailyStatRow> = ch.query(
        """
        SELECT day, count() AS order_count, sum(total_minor) AS revenue_minor, currency
        FROM order_daily
        WHERE day BETWEEN ? AND ?
        GROUP BY day, currency
        ORDER BY day
        """,
        DailyStatRowMapper(),
        query.from, query.to,
    )
}
```

Each handler talks to **its own store** via its own repository / template. They don't know about each other; they don't share a model.

---

## 3. Projection handler — the bridge

A projection handler:
1. Listens to a domain event.
2. Updates one or more read models.

```kotlin
@Component
class OrderDetailProjection(
    private val customers: CustomerReadRepository,
    private val views: OrderDetailViewRepository,
) {
    @ApplicationModuleListener
    fun on(event: OrderPlaced) {
        val customer = customers.findById(event.customerId.value)
            ?: throw IllegalStateException("customer ${event.customerId} not found at projection time")

        views.save(OrderDetailViewRow(
            id = event.orderId.value,
            customerId = event.customerId.value,
            customerName = customer.name,
            customerEmail = customer.email,
            status = "PLACED",
            total = event.total.amountMinor,
            currency = event.total.currency,
            placedAt = event.placedAt,
            shippedAt = null,
        ))
    }

    @ApplicationModuleListener
    fun on(event: OrderItemAdded) {
        val view = views.findById(event.orderId.value)
            ?: throw IllegalStateException("OrderDetailView ${event.orderId} missing")
        views.save(view.copy(total = view.total + event.quantity * event.unitPrice.amountMinor))
    }

    @ApplicationModuleListener
    fun on(event: OrderCancelled) {
        views.updateStatus(event.orderId.value, "CANCELLED")
    }
}
```

Rules:

- **Idempotent.** A projection handler must produce the same final state regardless of how many times it processes an event. Use upserts, not blind inserts.
- **Fast and small.** No business logic — just denormalise the event into the read schema.
- **No write back.** Read models are read-only. If a projection needs data it doesn't have, **denormalise the source event** to include it.
- **Bounded by the event payload.** If the projection needs to look up the customer's name, that lookup is fragile (customer may have been renamed since the event). Better: include the name in the event at emit time.

---

## 4. Choosing the projection target

| Target | When |
|---|---|
| **Postgres view / table** | Same store as write side. Simple denormalised reads, transactional consistency available if you really need it. |
| **Elasticsearch index** | Full-text search, faceted filters, fuzzy matching, autocomplete. Schema is JSON-ish. |
| **Clickhouse table** | Aggregations over millions of rows. Pre-rolled-up by day/hour/customer. Append-mostly. |
| **Redis structure** | Tight latency, single-key lookups, leaderboards, counters. Volatile. |

Don't multiplex stores per query without reason. Each new projection target = new deploy unit + new monitoring + new failure mode.

Example mapping for `Order`:

| Query | Projection target | Why |
|---|---|---|
| `OrderQuery.ById` (detail page) | Postgres `order_detail_view` table | Simple denormalised join; same DB |
| `OrderQuery.Search` (search by text) | ES `orders` index | Full-text + filters; Postgres can't compete here |
| `OrderQuery.DailyStats` (analytics) | Clickhouse `order_daily` table | Aggregations across 100M+ rows |
| `OrderQuery.ByCustomer` (customer's recent orders) | Postgres `order_detail_view` table with index on customer_id | Same projection serves two queries |

---

## 5. Projection state tracking

You need to know, for each projection, what's been applied. Reasons:

- **Rebuild from scratch** when projection schema changes.
- **Catch up** after downtime.
- **Read-your-writes** — caller waits until projection version ≥ command version.

Modulith's `event_publication` table tracks delivered events. For your own bookkeeping, store a per-projection cursor:

```sql
CREATE TABLE projection_state (
    projection_name VARCHAR(128) PRIMARY KEY,
    last_event_id   UUID         NOT NULL,
    last_event_at   TIMESTAMPTZ  NOT NULL,
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
```

Update inside the projection handler:

```kotlin
@ApplicationModuleListener
fun on(event: OrderPlaced) {
    views.save(...)
    state.advance(PROJECTION_NAME, event.eventId, event.occurredAt)
}
```

If the projection handler runs in the *same* transaction as the read-side write, the cursor and the projection update commit together. Use `@Transactional` on the listener method when the read store supports transactions (Postgres). For ES / Clickhouse, accept that the cursor and the projection can drift on failure — design idempotent handlers.

---

## 6. Rebuilding a projection

Triggers for rebuild:
- New field added to the read model.
- Bug discovered in a previous projection version.
- Adopting a new read store.

Mechanism (hand-rolled): a maintenance command that reads from the domain event log and re-runs the projection.

If you use Spring Modulith's `event_publication` as your event log, you have built-in replay:

```kotlin
@Component
class ProjectionRebuilder(
    private val publications: EventPublicationRegistry,
    private val resubmitter: IncompleteEventPublications,
) {
    fun rebuild(projection: String) {
        // 1. Clear the read store
        clearProjection(projection)

        // 2. Reset the cursor
        state.reset(projection)

        // 3. Resubmit all events (Modulith's API)
        resubmitter.resubmitIncompletePublications { publication ->
            publication.targetIdentifier.contains(projection)
        }
    }
}
```

If you're using Kafka with topic compaction, the equivalent is consume-from-earliest with a new consumer group.

**Pre-flight checklist** before a rebuild:
- Read-side traffic isolated (feature flag) or tolerates inconsistency for the rebuild window.
- Storage has room for the duplicate (rebuild may write into a new table/index and swap).
- Idempotency of the projection verified — running the rebuild twice produces the same result.

---

## 7. Read-your-writes consistency

The most common UX pain with CQRS: user posts a comment, then refreshes the list, comment isn't there yet — projection lag.

Three strategies:

### Strategy A: Honest 202 + polling

Command returns `202 Accepted` with `Location` of the read endpoint. Client polls until 200. Honest, simple, doesn't pretend the system is consistent.

### Strategy B: Version-aware reads

Command returns the version it produced. Client passes that version in the read; read waits up to N ms for the projection to catch up.

```kotlin
@GetMapping("/{id}")
fun get(
    @PathVariable id: UUID,
    @RequestHeader("X-Min-Version", required = false) minVersion: Long?,
): OrderDetailView {
    val deadline = System.currentTimeMillis() + 2000  // 2s max wait
    while (true) {
        if (minVersion != null && projectionLag(id) > minVersion) {
            Thread.sleep(50)
            if (System.currentTimeMillis() > deadline) {
                throw GatewayTimeoutException("projection lag")
            }
            continue
        }
        return query.handle(OrderQuery.ById(OrderId(id)))
            ?: throw NotFoundException("Order", id)
    }
}
```

Bounded wait. Works for short lags (< 1s typical). Don't busy-wait longer than you'd hold an HTTP connection.

### Strategy C: Optimistic UI

Frontend renders the expected post-command state locally (the comment appears immediately), reconciles with server when the projection catches up. Works only when the client knows enough to predict the projection result.

**Pick one consciously.** Mixing strategies leads to bugs that only show under load.

---

## 8. Handling projection failure

Projections will fail. Disk full, ES cluster down, Clickhouse rejecting writes. Plan for it.

| Failure mode | Action |
|---|---|
| Transient (network glitch) | Modulith retry from `event_publication` table |
| Persistent (downstream store down for hours) | Alarm. Halt projection. Resume when store back; replay from cursor. |
| Poison event (bug in projection handler) | Alarm. Park the bad event (dead-letter table). Fix code. Replay. |
| Schema mismatch (new event field, old projection) | Add new field to projection schema with default; redeploy projection first, then producers. |

Spring Boot Actuator metrics:

```kotlin
@Component
class ProjectionMetrics(registry: MeterRegistry) {
    val lag = Gauge.builder("projection.lag.seconds", this) { computeMaxLag() }.register(registry)
    val failed = Counter.builder("projection.events.failed").register(registry)
    val processed = Counter.builder("projection.events.processed").register(registry)
}
```

Alert on `projection.lag.seconds > 60` and `projection.events.failed > 0`.

---

## 9. Pagination — cursor for large reads

Offset pagination breaks down on large datasets and shifts under writes. Use cursor pagination on projections.

```kotlin
data class OrderListCursor(val placedAt: Instant, val id: OrderId)

@Service
class OrderListQueryHandler(private val views: OrderDetailViewRepository) {
    fun handle(query: OrderQuery.ByCustomer): CursorPage<OrderListItem> {
        val rows = views.findByCustomerIdOrderByPlacedAtDescIdDesc(
            customerId = query.customerId.value,
            cursor = query.page.cursor,
            limit = query.page.size + 1,
        )
        val hasMore = rows.size > query.page.size
        val items = rows.take(query.page.size).map { it.toListItem() }
        val nextCursor = if (hasMore) items.last().let {
            OrderListCursor(it.placedAt, it.id).encode()
        } else null
        return CursorPage(items, nextCursor)
    }
}
```

Cursor is opaque base64-encoded. Tie-breaker on ID prevents skipped rows when two records share the sort key.

---

## 10. Anti-patterns

- **Cross-store joins at query time.** "Read order from PG, join customer from MongoDB at runtime" — defeats the point of projecting. If the join is needed, project it.
- **Query handler hitting the write side.** If your `GetOrderByIdHandler` queries the `Order` aggregate, you don't have CQRS — you have CRUD with extra steps.
- **Synchronous projection inside the command transaction.** Couples both sides; one slow projection blocks all writes. Always async (after commit).
- **One projection per aggregate, mechanically.** Projections are designed per *query*, not per aggregate. Mix freely.
- **Trusting projection state in business decisions.** Stale by design. Decisions (e.g. "is this user allowed to do X") query the write side, not the read model.
- **Schema migrations without rebuild plan.** Every projection schema change needs a rebuild path. Plan it before deploying the change.
- **No monitoring of projection lag.** First time you find out about lag is in a P1 incident.
