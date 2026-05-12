# ORM and JPA Strategy

Spring Data JPA / JDBC / QueryDSL / jOOQ / raw JDBC — when each wins. Open Session In View. Entity-vs-DTO boundary. Spring Data Mongo / Elasticsearch.

---

## 1. The escalator

In a Spring/Kotlin codebase you have a ladder of data access tools. Use the lowest rung that solves the problem.

```
                          More control / more code
                                    ▲
                                    │
   ┌────────────────────────────────┴────────────────────────────────┐
   │ Raw JDBC (NamedParameterJdbcTemplate)                            │
   ├──────────────────────────────────────────────────────────────────┤
   │ jOOQ — typed SQL DSL, every Postgres feature                     │
   ├──────────────────────────────────────────────────────────────────┤
   │ Spring Data JDBC — minimal ORM, no proxies, no lazy magic        │
   ├──────────────────────────────────────────────────────────────────┤
   │ Spring Data JPA + QueryDSL — typed criteria over JPA             │
   ├──────────────────────────────────────────────────────────────────┤
   │ Spring Data JPA — Hibernate, full ORM, lazy/eager, dirty check   │
   └──────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
                          Less code / more magic
```

Default: **Spring Data JPA**. Drop down when JPA hurts more than it helps.

---

## 2. Spring Data JPA (Hibernate) — when it shines

- CRUD-heavy domains with clear aggregates.
- Lots of `findByX`, `findByXAndY` repository methods.
- Dirty tracking + cascade rules are useful (parent + composed children).
- You want the Repository abstraction for testing.

```kotlin
interface OrderRepository : JpaRepository<OrderJpaEntity, UUID> {
    fun findByCustomerIdOrderByCreatedAtDesc(customerId: UUID, page: Pageable): Page<OrderJpaEntity>
    fun findByStatusIn(statuses: List<String>): List<OrderJpaEntity>
}

@Service
@Transactional
class OrderService(private val orders: OrderRepository) {
    fun cancel(id: UUID) {
        val order = orders.findById(id).orElseThrow { NotFoundException("Order", id) }
        order.status = "CANCELLED"  // dirty check writes on commit
    }
}
```

### When JPA hurts

- Complex multi-table reporting queries (left lateral joins, window functions, CTEs).
- Bulk operations (you have to know about `@Modifying`, `clearAutomatically`, 1st-level cache).
- Polymorphic queries across inheritance — performance is unpredictable.
- Native Postgres features (LISTEN/NOTIFY, advisory locks, partitioning DDL).

Symptoms: you're fighting Hibernate annotations to get the SQL you want; you're calling `entityManager.createNativeQuery` more than once a week.

---

## 3. QueryDSL — typed criteria over JPA

For dynamic queries that change based on filters, plain JPA repository methods explode combinatorially. QueryDSL gives you type-safe composition:

```kotlin
// build.gradle.kts uses kapt to generate Q-classes
@Service
class OrderSearchService(private val em: EntityManager) {
    private val query = JPAQueryFactory(em)
    private val o = QOrderJpaEntity.orderJpaEntity

    fun search(filter: OrderFilter): List<OrderJpaEntity> {
        val predicate = BooleanBuilder().apply {
            filter.customerId?.let { and(o.customerId.eq(it)) }
            filter.status?.let { and(o.status.eq(it.name)) }
            filter.minTotal?.let { and(o.totalMinor.goe(it.amountMinor)) }
            filter.createdAfter?.let { and(o.createdAt.goe(it)) }
        }
        return query.selectFrom(o).where(predicate).orderBy(o.createdAt.desc()).fetch()
    }
}
```

Use QueryDSL when:
- A repository would need 8+ `findByXxxAnd...Or...` methods.
- Filter combinations are user-driven (search UI, admin panels).
- You want compile-time safety on the column names.

---

## 4. Spring Data JDBC — the middle ground

Spring Data JDBC is a lighter ORM:
- No proxies, no lazy loading, no Open Session In View.
- Aggregates load fully or not at all.
- Closer to the SQL; fewer surprises.

```kotlin
@Table("orders")
data class OrderRecord(
    @Id val id: UUID,
    val customerId: UUID,
    val status: String,
    val createdAt: Instant,
    @MappedCollection(idColumn = "order_id") val items: Set<OrderLineRecord>,
)

interface OrderJdbcRepository : CrudRepository<OrderRecord, UUID>
```

`data class` is fine here — there's no Hibernate proxy game.

Use Spring Data JDBC when:
- The aggregate is small and clearly bounded.
- Lazy loading would only cause N+1 confusion.
- You want a Repository abstraction without the JPA complexity.

Don't mix JDBC and JPA in the same module without a strong reason.

---

## 5. jOOQ — typed SQL DSL

When you need every Postgres feature (CTEs, window functions, `INSERT … ON CONFLICT`, JSON path expressions) and you want it typed:

```kotlin
val ranked = dsl
    .select(
        ORDERS.ID, ORDERS.CUSTOMER_ID, ORDERS.TOTAL_MINOR,
        rowNumber().over(partitionBy(ORDERS.CUSTOMER_ID).orderBy(ORDERS.CREATED_AT.desc())).`as`("rn"),
    )
    .from(ORDERS)
    .where(ORDERS.CREATED_AT.gt(since))
    .asTable("ranked")

dsl.selectFrom(ranked).where(field("rn", Int::class.java).eq(1)).fetch()
```

jOOQ generates code from the DB schema. Migrations run first, then code generation, then compile.

Use jOOQ when JPA can't express the query without `createNativeQuery`. Reports, analytics, admin queries.

---

## 6. Raw JDBC — last resort, sometimes correct

For things that genuinely don't need an ORM:

- Bulk inserts where you control the SQL (10K rows in one `COPY` is faster than any ORM).
- Postgres-specific features ORMs don't model (`LISTEN/NOTIFY`, advisory locks, `LATERAL`).
- Hot-path queries where every microsecond matters.

```kotlin
@Repository
class OrderBulkInsertRepository(private val template: NamedParameterJdbcTemplate) {
    fun bulkInsert(orders: List<NewOrder>) {
        val params = orders.map { o ->
            MapSqlParameterSource()
                .addValue("id", o.id)
                .addValue("customerId", o.customerId)
                .addValue("totalMinor", o.totalMinor)
        }.toTypedArray()
        template.batchUpdate("INSERT INTO orders (id, customer_id, total_minor) VALUES (:id, :customerId, :totalMinor)", params)
    }
}
```

Don't sprinkle raw JDBC across the codebase. Concentrate it in adapters; the rest of the app talks to a clean repository interface.

---

## 7. Mixing tools — the rule

You can use JPA for the writes and jOOQ for the reads. Common, productive pattern:

- JPA owns the write side (aggregates, dirty tracking, cascade).
- jOOQ owns the analytical reads (joins across 5 tables, window functions, aggregations).

**Don't share entities across them.** jOOQ reads project to flat data classes (DTOs / view records), not JPA entities. Mixing first-level caches across the two leads to stale data.

---

## 8. Open Session In View — turn it off

Spring Boot defaults `spring.jpa.open-in-view=true`. It keeps the Hibernate session open through the view (controller) layer so lazy loads don't blow up.

**This is a footgun.** It hides N+1 problems (each lazy load is a separate query during JSON serialization), holds DB connections open longer, and silently couples the persistence layer to the HTTP layer.

```yaml
spring:
  jpa:
    open-in-view: false
```

Then **transaction boundary = service layer**, and any entity returned from a service must have its required associations loaded inside the transaction (via `JOIN FETCH` or `EntityGraph`). Lazy loads outside the transaction fail loudly — which is what you want.

---

## 9. Entity vs DTO boundary

Don't return JPA entities from REST controllers. Three reasons:

1. **Coupling** — every column rename breaks the public API.
2. **Lazy traps** — Jackson serialization triggers lazy loads outside the transaction.
3. **Over-exposure** — internal fields (password hashes, internal flags) leak.

Use explicit DTOs at the boundary:

```kotlin
data class OrderResponse(
    val id: UUID,
    val customerId: UUID,
    val status: String,
    val total: Money,
    val createdAt: Instant,
)

fun OrderJpaEntity.toResponse() = OrderResponse(
    id = id, customerId = customerId, status = status,
    total = Money(totalMinor, currency), createdAt = createdAt,
)
```

For complex projections, use **JPA interface projections** or **Spring Data class projections**:

```kotlin
interface OrderSummaryView {
    fun getId(): UUID
    fun getCustomerId(): UUID
    fun getStatus(): String
    fun getTotalMinor(): Long
}

interface OrderRepository : JpaRepository<OrderJpaEntity, UUID> {
    fun findAllProjectedBy(): List<OrderSummaryView>
}
```

Hibernate generates a query that selects only those columns. Less data over the wire, no entity baggage.

---

## 10. Spring Data MongoDB

Conceptually similar to JPA but document-oriented:

```kotlin
@Document(collection = "user_preferences")
data class UserPreferencesDocument(
    @Id val userId: String,
    val theme: String,
    val notifications: NotificationSettings,
    val customFields: Map<String, Any> = emptyMap(),
)

interface UserPreferencesRepository : MongoRepository<UserPreferencesDocument, String>
```

`data class` is fine here — no Hibernate proxy.

Mongo + JPA in the same module: separate `@Configuration` for each, with `@EnableMongoRepositories(basePackages = …)` and `@EnableJpaRepositories(basePackages = …)` scoped to different packages.

---

## 11. Spring Data Elasticsearch

Different paradigm — index documents, not rows. Queries are JSON or a fluent Criteria API:

```kotlin
@Document(indexName = "orders")
data class OrderSearchDoc(
    @Id val id: String,
    @Field(type = FieldType.Keyword) val customerId: String,
    @Field(type = FieldType.Text, analyzer = "standard") val notes: String,
    @Field(type = FieldType.Date) val createdAt: Instant,
)

interface OrderSearchRepository : ElasticsearchRepository<OrderSearchDoc, String>
```

Don't treat ES as a primary store. ES is for **search**, fed from the primary store via projections (see `cqrs-implementation/resources/read-side-patterns.md`).

---

## 12. Decision quick reference

| Workload | Use |
|---|---|
| CRUD + clear aggregates | Spring Data JPA |
| Aggregate without lazy / proxies | Spring Data JDBC |
| Dynamic filtered search over JPA entities | QueryDSL |
| Complex SQL with CTE / window / lateral | jOOQ |
| Bulk operations, `COPY`, advisory locks | Raw JDBC |
| Document storage with flexible schema | Spring Data Mongo |
| Search / fuzzy / faceted | Spring Data Elasticsearch (as projection target) |

Pick consciously per module. Don't dogmatically apply one to everything.
