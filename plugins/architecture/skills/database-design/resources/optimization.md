# Query Optimization (JPA / Hibernate / PostgreSQL)

EXPLAIN ANALYZE, N+1, JOIN FETCH, EntityGraph, @BatchSize, keyset pagination, batch inserts, HikariCP sizing.

---

## 1. The investigation order

When a query is slow, work in this order:

1. **Measure.** Get the actual query (Hibernate `show_sql` or proxy datasource).
2. **`EXPLAIN ANALYZE`** the query against production-like data.
3. **Look for the bottleneck** in the plan (Seq Scan over a huge table, expensive sort, nested loop with many rows).
4. **Fix the schema or index first** — application-level workarounds for missing indexes are bad investments.
5. **Then optimise JPA fetch.**
6. **Last:** drop to native SQL / jOOQ if JPA can't express the query well.

Don't skip steps. Most "slow JPA" is "missing index plus N+1".

---

## 2. EXPLAIN ANALYZE — quick read

```sql
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT * FROM orders WHERE customer_id = '...' ORDER BY created_at DESC LIMIT 20;
```

What to look at:

| Operator | What it means | Red flag? |
|---|---|---|
| `Seq Scan` | Reading the whole table | On large table = need index |
| `Index Scan` | Using an index | Good |
| `Index Only Scan` | Index covers everything | Best |
| `Bitmap Heap Scan` | Index + heap fetch for many rows | OK; check selectivity |
| `Nested Loop` | For each outer row, scan inner | Bad if outer has many rows |
| `Hash Join` / `Merge Join` | Building hash / sorting then merging | Usually fine |
| `Sort` | In-memory or disk sort | "external merge Disk" = needs more `work_mem` or an ORDER BY index |
| `Filter: ...` | Filter applied after scan | Means index didn't filter; consider partial/expression index |

**The two key numbers**: `actual time` (per-iteration), `rows`. If estimated rows ≫ actual rows or vice versa, statistics are stale — run `ANALYZE` on the table.

Tip: paste plans into [explain.depesz.com](https://explain.depesz.com) for visual analysis.

---

## 3. The N+1 problem — the classic JPA crime

```kotlin
// Symptom code
val orders = orderRepository.findAll()         // 1 query
orders.forEach { order ->
    println(order.customer.name)               // N queries — one lazy load per order
}
```

If you have 100 orders, you've issued 101 queries. You'll see this in `show_sql` as a wall of `SELECT customer ...`.

### Fix 1: `JOIN FETCH` (per-query, ad-hoc)

```kotlin
interface OrderRepository : JpaRepository<OrderJpaEntity, UUID> {
    @Query("SELECT o FROM OrderJpaEntity o JOIN FETCH o.customer WHERE o.status = :status")
    fun findByStatusWithCustomer(@Param("status") status: String): List<OrderJpaEntity>
}
```

Fetches order and customer in one SQL. Specific to this query method.

### Fix 2: `@EntityGraph` (declarative)

```kotlin
interface OrderRepository : JpaRepository<OrderJpaEntity, UUID> {
    @EntityGraph(attributePaths = ["customer", "items"])
    fun findByStatus(status: String): List<OrderJpaEntity>
}
```

Or dynamic via `NamedEntityGraph`:

```kotlin
@Entity
@NamedEntityGraph(
    name = "Order.withCustomerAndItems",
    attributeNodes = [NamedAttributeNode("customer"), NamedAttributeNode("items")],
)
class OrderJpaEntity(...)

interface OrderRepository : JpaRepository<OrderJpaEntity, UUID> {
    @EntityGraph("Order.withCustomerAndItems")
    fun findByCustomerId(customerId: UUID): List<OrderJpaEntity>
}
```

### Fix 3: `@BatchSize` (for collections you can't eagerly fetch in JOIN)

`JOIN FETCH` on multiple collections causes a cartesian product. For one-many + one-many, use `@BatchSize` instead:

```kotlin
@OneToMany(mappedBy = "order", fetch = FetchType.LAZY)
@BatchSize(size = 20)
val items: List<OrderLineJpaEntity> = mutableListOf()
```

Hibernate batches lazy loads: instead of N queries, it loads 20 collections per query, IN-list-style.

### Fix 4: Two queries are fine

If `JOIN FETCH` is awkward and `@BatchSize` is overkill, run two queries explicitly — load orders, then load items by order ID list. Cleaner than fighting JPA:

```kotlin
val orders = orderRepository.findByStatus(status)
val itemsByOrder = orderLineRepository.findByOrderIdIn(orders.map { it.id }).groupBy { it.orderId }
// hand-merge in service
```

---

## 4. The Cartesian product trap

`JOIN FETCH` on **two collections** at once produces a Cartesian product. With 10 items and 5 reviews per order, one row becomes 50 rows.

```kotlin
// BAD — Cartesian
@Query("SELECT o FROM OrderJpaEntity o JOIN FETCH o.items JOIN FETCH o.reviews WHERE o.id = :id")
```

Fix: fetch one collection in the query, the other via `@BatchSize` or a separate query.

```kotlin
@Query("SELECT o FROM OrderJpaEntity o JOIN FETCH o.items WHERE o.id = :id")
fun findByIdWithItems(@Param("id") id: UUID): OrderJpaEntity?
// reviews load lazily, batched with @BatchSize
```

---

## 5. Open Session In View — turn it off, then debug

If your app has `spring.jpa.open-in-view=true` (Spring Boot default), N+1 hides in the view layer — every lazy load during JSON serialization fires a query.

Turn it off:

```yaml
spring:
  jpa:
    open-in-view: false
```

Then any lazy load outside `@Transactional` throws `LazyInitializationException`. This is **good** — it surfaces the N+1 problems instead of silently issuing 100 queries per HTTP response.

Migration: turn it off in dev first, fix all the failures (use `JOIN FETCH` / `EntityGraph` / explicit DTOs), then deploy to prod.

---

## 6. Return DTOs, not entities, when you can

The cleanest way to avoid lazy / N+1 entirely: return projections.

```kotlin
interface OrderSummary {
    fun getId(): UUID
    fun getCustomerName(): String     // joined column
    fun getStatus(): String
    fun getTotalMinor(): Long
}

interface OrderRepository : JpaRepository<OrderJpaEntity, UUID> {
    @Query("""
        SELECT o.id AS id, c.name AS customerName, o.status AS status, o.totalMinor AS totalMinor
        FROM OrderJpaEntity o JOIN o.customer c
        WHERE o.tenantId = :tenantId
    """)
    fun summariesByTenant(@Param("tenantId") tenantId: UUID): List<OrderSummary>
}
```

Hibernate generates a query that selects only those columns. No entity, no lazy, no N+1, no overhead.

For complex projections: jOOQ or `NamedParameterJdbcTemplate` with a row mapper.

---

## 7. Pagination: offset vs keyset

### Offset — fine for small offsets

```kotlin
fun findByCustomer(customerId: UUID, page: Pageable): Page<OrderJpaEntity>
// → SELECT ... OFFSET 1000 LIMIT 20
```

Postgres has to scan + discard 1000 rows. Cheap when offset is small. **Bad** for deep paging — at offset 100,000 it's expensive.

### Keyset / cursor — scales to any depth

```kotlin
@Query("""
    SELECT o FROM OrderJpaEntity o
    WHERE o.customerId = :customerId
      AND (o.createdAt, o.id) < (:lastCreatedAt, :lastId)
    ORDER BY o.createdAt DESC, o.id DESC
""")
fun findByCustomerAfter(
    @Param("customerId") customerId: UUID,
    @Param("lastCreatedAt") lastCreatedAt: Instant,
    @Param("lastId") lastId: UUID,
    pageable: Pageable,
): List<OrderJpaEntity>
```

Index `(customer_id, created_at DESC, id DESC)` makes this O(log n + limit). Constant time regardless of how deep the user paged.

Use keyset for infinite-scroll APIs and large datasets. Offset is fine for admin tools where you'll never page past 50.

---

## 8. Batch inserts

JPA inserts row-by-row by default. For bulk operations, configure batching:

```yaml
spring:
  jpa:
    properties:
      hibernate:
        jdbc:
          batch_size: 50
        order_inserts: true
        order_updates: true
        batch_versioned_data: true
```

Then **`flush()` periodically** when inserting many rows:

```kotlin
@Service
@Transactional
class BulkOrderImport(private val em: EntityManager) {
    fun import(orders: List<NewOrder>) {
        orders.forEachIndexed { i, no ->
            em.persist(OrderJpaEntity.fromNew(no))
            if (i % 50 == 0) {
                em.flush()
                em.clear()  // critical — prevents 1st-level cache blowup
            }
        }
    }
}
```

For tens of thousands of rows, drop to raw JDBC and use `template.batchUpdate(...)` — see `orm-and-jpa.md` §6.

For tens of millions, drop further to Postgres `COPY`.

---

## 9. HikariCP pool sizing

Default Hikari pool: 10. Often wrong.

Classic formula:

```
pool_size = ((core_count * 2) + effective_spindle_count)
```

For a typical cloud VM with 4 cores and SSDs: ~10. For a 16-core machine with NVMe: ~32-40.

**It's not "more is better".** Beyond the optimal pool size, queries queue inside Postgres for CPU; you get less throughput and worse tail latency.

Configure:

```yaml
spring:
  datasource:
    hikari:
      maximum-pool-size: 20
      minimum-idle: 5
      connection-timeout: 3000      # 3s to acquire
      idle-timeout: 600000          # 10min
      max-lifetime: 1800000         # 30min — recycle before any infra timeout
      leak-detection-threshold: 60000  # 60s — log warnings on stuck connections
```

Watch `hikaricp_connections_active` vs `hikaricp_connections_max` in Prometheus. If active is consistently near max, pool is too small OR queries are too slow.

---

## 10. Common Hibernate pitfalls

- **`@Transactional` on the controller.** Wrong layer. Service layer owns the transaction.
- **`@Transactional` missing on a method that does multiple writes.** Each write commits independently; a failure halfway through is half-committed.
- **`save()` after mutation.** Inside a transaction, dirty checking handles it — explicit `save()` is redundant (and confusing — looks like the line matters).
- **Fetching parent entity to update one field.** Use `@Modifying @Query` or a partial DTO update:
  ```kotlin
  @Modifying
  @Query("UPDATE OrderJpaEntity o SET o.status = :status WHERE o.id = :id")
  fun updateStatus(@Param("id") id: UUID, @Param("status") status: String): Int
  ```
- **`@OneToOne` always eager.** Hibernate doesn't generate a lazy proxy for it correctly without bytecode enhancement. Either use `@MapsId` (shared PK) or switch to `@OneToMany` semantically.
- **Not knowing about `@DynamicUpdate`.** For wide tables with many columns, it generates UPDATE statements with only changed columns. Wins for tables with many rarely-updated columns.

---

## 11. Profiling tools

| Tool | What |
|---|---|
| **Hibernate `show_sql` / `format_sql`** | See generated SQL in app logs. Use only in dev — log volume is huge. |
| **`p6spy` / `datasource-proxy`** | Wrap the datasource; log every query with timings. Lighter than `show_sql`. |
| **Postgres `pg_stat_statements`** | Aggregated query stats from the DB side. Find the slowest queries by total time. |
| **EXPLAIN ANALYZE** | Per-query plan + actual costs. |
| **Spring Boot Actuator + Micrometer** | `hikaricp_*`, `spring.data.repository.invocations` metrics. |

For production diagnosis, `pg_stat_statements` is gold:

```sql
SELECT
    query, calls, total_exec_time, mean_exec_time, rows
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 20;
```

The top 20 queries by total time are where to spend optimisation effort.

---

## 12. Optimisation checklist

Before claiming a query is "fast enough":

- [ ] Profiled with `EXPLAIN ANALYZE` against representative data
- [ ] No `Seq Scan` on a table > 10K rows for indexed columns
- [ ] No N+1 — verified via `show_sql` or `pg_stat_statements`
- [ ] No `Cartesian product` from over-aggressive `JOIN FETCH`
- [ ] Pagination is keyset for any large dataset
- [ ] Returning DTO / projection, not full entity, where possible
- [ ] Connection pool isn't saturated under expected load
- [ ] `pg_stat_statements` shows reasonable `mean_exec_time` (<10ms for OLTP)
