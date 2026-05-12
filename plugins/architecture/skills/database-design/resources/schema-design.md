# Schema Design

JPA entities, IDs, timestamps, relationships, embedded VOs, JSONB, multi-tenancy. Kotlin + Spring Data JPA + PostgreSQL.

---

## 1. JPA entity ≠ domain entity

If your domain has invariants (e.g. `Order` must have at least one item), keep the JPA entity and the domain entity **separate** in any non-trivial bounded context.

```kotlin
// Domain entity — pure Kotlin, no Spring/JPA, enforces invariants
class Order(
    val id: OrderId,
    val customerId: CustomerId,
    private val items: MutableList<OrderLine>,
    var status: OrderStatus,
) {
    init { require(items.isNotEmpty()) { "empty order" } }
    fun submit() { check(status == OrderStatus.PENDING); status = OrderStatus.SUBMITTED }
    // ...
}

// JPA entity — persistence shape, no invariants
@Entity
@Table(name = "orders")
class OrderJpaEntity(
    @Id val id: UUID,
    @Column(name = "customer_id", nullable = false) val customerId: UUID,
    @Column(nullable = false) var status: String,
    @OneToMany(mappedBy = "order", cascade = [CascadeType.ALL], orphanRemoval = true)
    val items: MutableList<OrderLineJpaEntity>,
    @Column(name = "created_at", nullable = false, updatable = false) val createdAt: Instant,
    @Version val version: Long = 0,
) {
    override fun equals(other: Any?) = other is OrderJpaEntity && other.id == id
    override fun hashCode() = id.hashCode()
}
```

The infrastructure layer maps between them. See `architecture-patterns` for the Onion layout.

For simple CRUD without invariants, one entity (JPA) is fine. **Just never use `data class` for the JPA one.**

---

## 2. Primary keys

### Default: UUID v7

```kotlin
@Id val id: UUID = UUID.randomUUID()  // v4 — random
```

UUID v4 is the safe default for distributed systems and external IDs. It's not sortable, but the index is fine for non-sequential reads.

**UUID v7** (time-ordered) is the better default in 2025+ if your driver supports it — sortable, index-friendly, and still globally unique. Many Postgres extensions (`uuid_generate_v7()`) and Java 21+ libraries (`UUIDv7`) now offer it.

```kotlin
// With a library that provides v7 generation
@Id val id: UUID = UuidCreator.getTimeOrderedEpoch()  // v7
```

### When UUID is the wrong default

- **Internal-only entities with no external surface.** A `BIGINT IDENTITY` is smaller (8 bytes vs 16) and the natural index is hot.
- **Join tables / very high write rate.** UUID v4 random writes scatter across the B-tree; v7 fixes this. If you can't get v7, sequences win.

### Never expose internal sequences as public IDs

Sequences leak business volume ("we got order #543 today"). For public APIs, UUID. For internal-only, sequences are fine.

### Composite keys

Rare in modern designs; the maintenance pain rarely pays for itself. Synthesise a single PK and add a unique index on the natural key:

```kotlin
@Entity
class Membership(
    @Id val id: UUID = UUID.randomUUID(),
    @Column(name = "user_id", nullable = false) val userId: UUID,
    @Column(name = "team_id", nullable = false) val teamId: UUID,
)
// Migration: UNIQUE (user_id, team_id)
```

---

## 3. `BaseEntity` / `BaseAggregateRoot`

Centralise id-based equality and audit timestamps. Avoid copy-pasting `equals`/`hashCode` in every JPA entity.

```kotlin
@MappedSuperclass
@EntityListeners(AuditingEntityListener::class)
abstract class BaseEntity<ID : Any>(
    @Id open val id: ID,
) {
    @Column(name = "created_at", nullable = false, updatable = false)
    @CreatedDate
    open var createdAt: Instant = Instant.MIN

    @Column(name = "updated_at", nullable = false)
    @LastModifiedDate
    open var updatedAt: Instant = Instant.MIN

    override fun equals(other: Any?): Boolean =
        other is BaseEntity<*> && other.javaClass == javaClass && other.id == id

    override fun hashCode(): Int = id.hashCode()
}
```

Enable auditing once at startup:

```kotlin
@Configuration
@EnableJpaAuditing
class JpaAuditingConfig
```

---

## 4. Timestamps

For **every** persistent row:

| Column | Type | Purpose |
|---|---|---|
| `created_at` | `TIMESTAMPTZ NOT NULL` | When created. Immutable after insert. |
| `updated_at` | `TIMESTAMPTZ NOT NULL` | Last modified. Bumped on every UPDATE. |
| `deleted_at` | `TIMESTAMPTZ NULL` (optional) | Soft delete marker. |

**Always `TIMESTAMPTZ`, never `TIMESTAMP`.** `TIMESTAMP` is naive (no offset); you'll regret it when the server moves to UTC or a daylight saving transition hits.

```kotlin
@Column(name = "created_at", nullable = false, updatable = false)
@CreatedDate
val createdAt: Instant = Instant.MIN
```

Hibernate populates via auditing listeners. Don't set them manually.

---

## 5. Soft delete — read the warnings

Adding `deleted_at` looks easy. It comes with painful constraints:

- **Every query has to remember the filter.** Forget once, expose a tombstoned record.
- **Unique constraints break.** `UNIQUE (email)` now lets you have a deleted `alice@x.com` plus a live `alice@x.com`. Use `UNIQUE (email) WHERE deleted_at IS NULL` (partial index).
- **Foreign keys break.** If you allow FK to a soft-deleted parent, the parent is "alive" by FK rules but "dead" by application rules.
- **Storage grows unbounded.** You need a separate archival policy.

Alternatives often beat soft delete:
- **Audit log table.** Move-on-delete: copy the row to `orders_history`, then real delete.
- **Status enum.** `OrderStatus.ARCHIVED` is honest — it's not gone, it's archived, and code that filters by status is more readable.

Reach for soft delete only when the use case really is "we need to undo arbitrary deletes for some window".

---

## 6. Relationships

### `@ManyToOne` — the workhorse

```kotlin
@Entity
class OrderLineJpaEntity(
    @Id val id: UUID,
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "order_id", nullable = false)
    val order: OrderJpaEntity,
    @Column(nullable = false) val productId: UUID,
    @Column(nullable = false) val quantity: Int,
)
```

`fetch = LAZY` — **always**. Eager fetch is one of the top sources of N+1. See `optimization.md` for proper fetch strategies.

### `@OneToMany` — needs `mappedBy`

```kotlin
@OneToMany(mappedBy = "order", cascade = [CascadeType.ALL], orphanRemoval = true)
val items: MutableList<OrderLineJpaEntity> = mutableListOf()
```

Without `mappedBy`, Hibernate creates a join table you didn't ask for. The `mappedBy` references the field name on the **owning** side (`order` in `OrderLineJpaEntity`).

`orphanRemoval = true` deletes child rows when removed from the collection. Use only if children are truly owned by the parent (composition, not association).

### `@ManyToMany`

Almost always wrong. The join row carries metadata (created_at, role, attributes) — make it a real entity:

```kotlin
@Entity
class TeamMembership(
    @Id val id: UUID,
    @ManyToOne(fetch = FetchType.LAZY) val user: UserJpaEntity,
    @ManyToOne(fetch = FetchType.LAZY) val team: TeamJpaEntity,
    @Column(nullable = false) val role: String,
    @Column(name = "joined_at", nullable = false) val joinedAt: Instant,
)
```

Better than a phantom join table you can't put a column on.

### `@OneToOne`

Rare in well-designed schemas. Usually it's:
- An `@Embedded` value object (no separate identity)
- A subtype that should be modelled differently (inheritance, polymorphism)
- A relationship that's really `@ManyToOne` from one side

If you genuinely have 1:1 — use it, with `@MapsId` for shared PK:

```kotlin
@Entity
class UserProfile(
    @Id val userId: UUID,
    @MapsId @OneToOne(fetch = FetchType.LAZY) @JoinColumn(name = "user_id")
    val user: UserJpaEntity,
    val avatarUrl: String,
)
```

---

## 7. Foreign key `ON DELETE`

| Action | Use when |
|---|---|
| `CASCADE` | Children are conceptually part of the parent (order → order_lines). Delete parent, delete children. |
| `SET NULL` | Children should outlive the parent but lose the link (post → category — recategorise). |
| `RESTRICT` (default in PG) | Parent has dependents; delete should fail. Forces the application to clean up first. |
| `NO ACTION` | Same as RESTRICT but checked at commit; rarely useful. |

Note: Hibernate's `orphanRemoval` and `cascade = [CascadeType.REMOVE]` operate at the **JPA layer**. The DB-level `ON DELETE` operates at the **schema layer**. Pick one and be explicit; don't have both fighting.

Production rule: prefer DB-level `ON DELETE CASCADE` over JPA cascade for composition relationships — it's correct even when something writes to the DB outside JPA.

---

## 8. Embedded value objects

Tagged primitives and small VOs map cleanly via `@Embedded`:

```kotlin
@Embeddable
data class Money(
    @Column(name = "amount_minor", nullable = false) val amountMinor: Long,
    @Column(name = "currency", nullable = false, length = 3) val currency: String,
)

@Entity
class InvoiceJpaEntity(
    @Id val id: UUID,
    @Embedded
    @AttributeOverrides(
        AttributeOverride(name = "amountMinor", column = Column(name = "total_amount_minor")),
        AttributeOverride(name = "currency", column = Column(name = "total_currency")),
    )
    val total: Money,
)
```

Two columns in the table; one VO in the entity. Equality by value (works because `@Embeddable` + `data class` is fine — only **`@Entity`** must not be a `data class`).

`@JvmInline value class` doesn't currently map as a JPA field — convert at the adapter boundary, or use `@Embeddable` for VOs that need to persist.

---

## 9. JSONB — yes, but with discipline

PostgreSQL JSONB is genuinely useful for:
- Schema-flexible payloads (user preferences, integration configs)
- Audit / event payloads where the structure varies per event type
- Sparse attributes (most rows don't have most fields)

It is **not** a free pass to skip schema design. JSONB columns should be:

```kotlin
@Entity
class UserPreferences(
    @Id val userId: UUID,
    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "preferences", columnDefinition = "jsonb", nullable = false)
    val preferences: Map<String, Any>,
)
```

Rules:

- **Index the fields you query** with GIN on the path (`USING GIN ((preferences->'theme'))` or generic GIN with `jsonb_path_ops`).
- **Validate the JSON shape** in the application (Kotlinx Serialization, Jackson with a typed class) — don't trust JSONB to enforce structure.
- **If you query a field on every row, promote it to a real column.** JSONB is for "sometimes" attributes.

---

## 10. Multi-tenancy

Three strategies, in order of complexity:

| Strategy | How | When |
|---|---|---|
| **Shared schema, tenant_id column** | Every table has `tenant_id`, every query filters by it | Default. Easiest ops, OK for hundreds of tenants. |
| **Schema per tenant** | Each tenant gets its own Postgres schema; same DB | Per-tenant customisation needed; mid-scale (10s of tenants) |
| **Database per tenant** | Each tenant gets its own DB instance | Compliance / data residency requirements |

For shared schema:

- Add `tenant_id UUID NOT NULL` to every tenant-scoped table.
- Index it as the first column of most composite indexes (you'll filter by it on every query).
- Use **Postgres Row-Level Security** (RLS) as a backstop: a policy filters by `current_setting('app.tenant_id')`. App still adds the filter; RLS catches missed cases.

```sql
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY orders_tenant_isolation ON orders
    USING (tenant_id = current_setting('app.tenant_id')::uuid);
```

Set the GUC in the app per request:

```kotlin
@Component
class TenantConnectionInterceptor : HandlerInterceptor {
    override fun preHandle(req: HttpServletRequest, res: HttpServletResponse, handler: Any): Boolean {
        val tenantId = resolveTenant(req)
        jdbcTemplate.execute("SET LOCAL app.tenant_id = '$tenantId'")
        return true
    }
}
```

---

## 11. Schema design checklist

Before merging a new schema:

- [ ] PK type chosen consciously (UUID v4 / v7 / sequence) — rationale captured
- [ ] All tables have `created_at TIMESTAMPTZ NOT NULL`, `updated_at TIMESTAMPTZ NOT NULL`
- [ ] All FKs have `ON DELETE` action set explicitly
- [ ] No `@OneToMany` without `mappedBy`
- [ ] No `data class` for `@Entity`
- [ ] Every column is `NOT NULL` unless the absence has business meaning
- [ ] String columns have explicit length (`VARCHAR(n)`) where it represents a real bound
- [ ] Indexes for every column used in `WHERE`, `JOIN`, `ORDER BY` of expected queries
- [ ] Multi-tenant tables have `tenant_id` indexed as first column of compound indexes
- [ ] Migration is expand-contract-safe (see `migrations.md`)
- [ ] No JSONB column that's queried on every row (promote to column)
