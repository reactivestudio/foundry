# Migrations (Flyway, zero-downtime)

Flyway conventions, expand-contract patterns, CONCURRENTLY indexes, backfills, table rename via view.

---

## 1. Flyway basics

Flyway is the migration tool. Standard layout:

```
src/main/resources/
└── db/migration/                    (or app/src/main/resources/migrations/ per project)
    ├── V1__create_users_table.sql
    ├── V2__add_email_to_users.sql
    ├── V3__create_orders_table.sql
    └── R__update_search_view.sql    (repeatable, runs whenever its checksum changes)
```

Naming convention:

| Prefix | What | When it runs |
|---|---|---|
| `V<n>__` | Versioned migration | Once, in order; checksum locked after first run |
| `R__` | Repeatable migration | Whenever its file content changes (good for views, stored procs) |
| `U<n>__` | Undo migration | Manual; Flyway Teams only; rarely used in practice |

`validateMigrationNaming = true` in `flyway` config catches typos at build time. Set it.

Spring Boot configuration:

```yaml
spring:
  flyway:
    enabled: true
    locations: classpath:db/migration
    validate-migration-naming: true
    baseline-on-migrate: false      # safer; explicit baseline only when migrating an existing DB
```

---

## 2. The Golden Rule: every migration must be zero-downtime-capable

Zero-downtime means: old app version is running, new app version is being rolled out, and the migration is being applied. **Old version cannot break and new version cannot break.**

This rules out:
- Renaming columns in one step
- Adding `NOT NULL` columns without a default
- Dropping columns that old code still reads
- Changing column types (PG often requires rewriting the table — locks it)

The pattern is **expand-contract**: split a "breaking" change into two or three deploys.

---

## 3. Adding a column — the canonical expand-contract

### Adding a nullable column

Safe in one step:

```sql
-- V42__add_phone_to_users.sql
ALTER TABLE users ADD COLUMN phone VARCHAR(32);
```

PG marks the column nullable; existing rows get `NULL`; no rewrite, no lock issue. Both old and new app versions are fine.

### Adding a NOT NULL column

Three steps:

**Deploy 1: add as nullable, with a backfill**

```sql
-- V42__add_phone_to_users_step1.sql
ALTER TABLE users ADD COLUMN phone VARCHAR(32);

-- Backfill in chunks to avoid long locks
DO $$
DECLARE
    batch_size INT := 1000;
    affected INT;
BEGIN
    LOOP
        UPDATE users SET phone = 'unknown'
        WHERE id IN (SELECT id FROM users WHERE phone IS NULL LIMIT batch_size);
        GET DIAGNOSTICS affected = ROW_COUNT;
        EXIT WHEN affected = 0;
        COMMIT;          -- only in PG12+ procedural blocks
    END LOOP;
END $$;
```

For very large tables, backfill in the application instead (cron job or a one-off batch service) — gives you better control over rate.

**Deploy 2: app writes the column (new code)**

App is now writing real values, not relying on the default.

**Deploy 3: add the NOT NULL constraint**

```sql
-- V43__make_phone_not_null.sql
-- Verify no NULLs remain
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM users WHERE phone IS NULL) THEN
        RAISE EXCEPTION 'phone has NULL values; backfill incomplete';
    END IF;
END $$;

-- This step does take a brief AccessExclusiveLock
ALTER TABLE users ALTER COLUMN phone SET NOT NULL;
```

For huge tables, PG 12+ supports `ALTER TABLE ... ADD CONSTRAINT ... NOT VALID` followed by `VALIDATE CONSTRAINT` — locks are briefer.

### Adding NOT NULL with a default in one step (PG 11+)

PG 11 introduced "fast" defaults that don't rewrite the table:

```sql
ALTER TABLE users ADD COLUMN role VARCHAR(20) NOT NULL DEFAULT 'USER';
```

Safe **for new defaults** (literal, immutable). PG records the default in metadata; existing rows materialise on next update. Use this when:
- The default is appropriate for every existing row.
- The default is a literal (not a function call like `now()`).

Pre-PG 11 codebases need the three-step pattern.

---

## 4. Removing a column

Two steps:

**Deploy 1: stop using the column in code**

App no longer reads or writes the column. Deploy and let it bake — at least one full release cycle. Verify with logs / queries that the column is truly unused.

**Deploy 2: drop the column**

```sql
-- V50__drop_legacy_status_from_orders.sql
ALTER TABLE orders DROP COLUMN legacy_status;
```

Quick lock; safe.

**Don't drop the column in the same release that stopped using it.** If the deploy rolls back, old code is reading a column that's gone.

---

## 5. Renaming a column — the most painful case

Four steps. Yes, four.

**Deploy 1: add the new column**

```sql
ALTER TABLE orders ADD COLUMN customer_uuid UUID;
-- Backfill from old column
UPDATE orders SET customer_uuid = customer_id_uuid_format_conversion(customer_id);
```

Or use a generated column if PG12+ and the conversion is simple:

```sql
ALTER TABLE orders ADD COLUMN customer_uuid UUID GENERATED ALWAYS AS (customer_id::uuid) STORED;
```

**Deploy 2: app writes both columns (dual-write)**

```kotlin
@Entity
class OrderJpaEntity(
    @Column(name = "customer_id") val customerIdLegacy: String,
    @Column(name = "customer_uuid") val customerUuid: UUID,
)
```

Both columns are kept in sync by the app. Old code reads the old column, new code can read either.

**Deploy 3: app reads new column only**

App reads `customer_uuid` everywhere. Old column is still being written for safety.

**Deploy 4: stop writing and drop old column**

```sql
ALTER TABLE orders DROP COLUMN customer_id;
ALTER TABLE orders ALTER COLUMN customer_uuid SET NOT NULL;
```

This is why renames are expensive. Plan ahead, name columns right the first time.

---

## 6. Renaming a table

Postgres rename is fast (metadata-only) but breaks everything that references the old name. Approach:

**Option A: rename + view alias**

```sql
ALTER TABLE orders RENAME TO orders_new;
CREATE VIEW orders AS SELECT * FROM orders_new;
```

Old code reads via the view; new code uses the new name. Eventually drop the view.

Caveats: views are not always updatable; this works for simple cases.

**Option B: dual-table during transition** — more involved; build a trigger on the old name that writes to both, then cut over.

Most of the time, **leave the table named as-is**. Renames in production are rarely worth the effort.

---

## 7. Changing a column type

PG sometimes rewrites the table on `ALTER TABLE ... ALTER COLUMN ... TYPE ...`. This locks the table for the duration of the rewrite — minutes to hours on big tables.

Safe-ish type changes (no rewrite):

- `VARCHAR(n)` → `VARCHAR(m)` where `m >= n` (just extending length)
- `VARCHAR` → `TEXT`

Unsafe (rewrite required):

- `TEXT` → `VARCHAR(n)` (validation needs to check every row)
- `INT` → `BIGINT` (size changes)
- Any numeric precision change

For unsafe cases, use the expand-contract pattern with a new column.

---

## 8. Adding an index — `CREATE INDEX CONCURRENTLY`

`CREATE INDEX` (without `CONCURRENTLY`) takes an `ACCESS EXCLUSIVE` lock — blocks all reads and writes on the table. **Never** in production.

The catch: `CREATE INDEX CONCURRENTLY` cannot run inside a transaction. Flyway runs each migration in a transaction by default. Two options:

**Option A: Flyway-specific transaction control (Flyway 9.5+)**

```sql
-- V60__add_index_orders_customer.sql
-- This statement runs outside a transaction (Flyway 9.5+)
CREATE INDEX CONCURRENTLY ix_orders_customer ON orders (customer_id);
```

Plus migration metadata to opt out of transactional execution (depends on Flyway config — check the version's docs).

**Option B: Repeatable migration without transaction**

Configure Flyway:

```yaml
spring:
  flyway:
    locations: classpath:db/migration
    init-sqls:
    # …
```

Use Flyway's `executeInTransaction = false` placeholder. In Spring Boot config this is per-callback; in standalone Flyway it's a CLI flag (`-mixed=true`).

Pragmatic alternative for projects without Flyway's mixed mode: keep a separate non-Flyway script ("operational migrations") run by ops with `psql`, with a Flyway no-op marker for tracking.

**Always** check after deploy that the index is `VALID`:

```sql
SELECT indexname, indexdef
FROM pg_indexes WHERE indexname = 'ix_orders_customer';

-- And confirm it's not in pg_index with indisvalid=false
SELECT i.relname AS index, idx.indisvalid
FROM pg_class i JOIN pg_index idx ON i.oid = idx.indexrelid
WHERE i.relname = 'ix_orders_customer';
```

If invalid, drop with `DROP INDEX CONCURRENTLY` and retry.

---

## 9. Backfill strategies

For backfilling a column or migrating data, two paths:

### SQL chunked backfill

Good for transformations expressible in SQL:

```sql
-- Repeatable in a loop, e.g. via cron or a one-off script
UPDATE orders SET tenant_id = '...' WHERE tenant_id IS NULL AND id IN (
    SELECT id FROM orders WHERE tenant_id IS NULL ORDER BY id LIMIT 5000
);
```

Run until 0 rows affected. Each batch is one transaction, so rollback impact is bounded.

### Application backfill

Better when the transformation needs application logic (parsing, calling another service):

```kotlin
@Service
class TenantBackfillJob(private val orders: OrderRepository) {
    @Scheduled(cron = "0 */5 * * * *")    // every 5 minutes, idempotent
    @Transactional
    fun run() {
        val batch = orders.findTopByTenantIdIsNull(PageRequest.of(0, 500))
        if (batch.isEmpty()) return
        batch.forEach { it.tenantId = resolveTenantFor(it.customerId) }
        // dirty checking saves on commit
    }
}
```

Or as a one-off command-line app launched explicitly. Either way: idempotent, restartable, observable (log progress).

---

## 10. The "blue-green" alternative for very risky changes

For changes that genuinely cannot be expand-contract'd (or where doing so is more complex than the alternative):

1. Create a new table with the new schema.
2. Backfill from the old table.
3. Keep them in sync with triggers or app dual-write.
4. Cut over the app.
5. Drop the old table.

Heavyweight but works for anything. Use as a last resort.

---

## 11. Testing migrations

Before deploying:

- **Run on a recent prod snapshot in staging.** Many migrations look fine on a fresh DB but lock for 30 minutes on prod data.
- **Time the migration.** If the staging snapshot is half the prod size and the migration takes 5 minutes, expect 10 in prod.
- **Verify rollback** — what's the recovery if the migration partially applies?
- **Run Flyway `info`** in CI to confirm checksums match what's in `flyway_schema_history`.

---

## 12. Repeatable migrations for views and procs

For view definitions, stored functions, materialised view refreshes — use `R__` migrations. They re-run whenever the file content changes.

```sql
-- R__order_summary_view.sql
CREATE OR REPLACE VIEW order_summary AS
SELECT o.id, o.customer_id, c.name AS customer_name, o.status, o.total_minor, o.created_at
FROM orders o JOIN customers c ON o.customer_id = c.id;
```

Edit the file, deploy, Flyway re-applies. Don't try to `V<n>__` a view that's going to change frequently.

For **materialised** views, the create is `V<n>__`; refresh is operational (a cron / scheduled job), not a migration.

---

## 13. Migration checklist

Before merging:

- [ ] Migration is zero-downtime (expand-contract if a breaking change)
- [ ] Versioned (`V<n>__`) name matches convention
- [ ] If a destructive operation, prior deploys stopped using the affected column/table
- [ ] Indexes use `CONCURRENTLY`
- [ ] Backfill chunked, not single huge UPDATE
- [ ] `ANALYZE <table>` after large data changes if planner stats matter
- [ ] Tested on a representative data volume
- [ ] Rollback path documented (or "irreversible — verify deploy carefully")
- [ ] No `DROP COLUMN` / `DROP TABLE` of objects still in use by older code in flight
