# Indexing Strategy (PostgreSQL)

Index types, composite ordering, partial / expression / covering indexes, CONCURRENTLY, maintenance.

---

## 1. Index types reference

PostgreSQL ships with five generally-useful index types. Pick by data shape and query pattern.

| Type | Sortable | Good for | Notes |
|---|---|---|---|
| **B-tree** | yes | `=`, `<`, `>`, `BETWEEN`, `IN`, `IS NULL`, `LIKE 'prefix%'`, `ORDER BY` | Default. ~90% of indexes. |
| **GIN** | no | JSONB (`@>`, `?`), arrays, full-text (`tsvector`) | Inverted index. Slower writes. |
| **GiST** | no | Geometric types, range types (`tstzrange`, `int4range`), `&&` overlap | Used for exclusion constraints. |
| **BRIN** | no | Huge tables with **physical ordering** (append-only time-series) | Tiny on disk; coarse-grained. |
| **Hash** | no | Equality only on huge values | Rare; B-tree usually beats it. |

You'll use B-tree for almost everything, GIN for JSONB and full-text, GiST for ranges, BRIN for append-only time-series, and basically never Hash.

---

## 2. When to add an index

The honest answer: when `EXPLAIN ANALYZE` shows a `Seq Scan` you don't want, AND the column has enough cardinality for an index to help (selectivity matters — more on this below).

Add indexes for:

- Columns in `WHERE` clauses with high selectivity (matching <10% of rows)
- Columns in `JOIN ... ON` conditions
- Columns in `ORDER BY` (especially with `LIMIT`)
- Foreign key columns (also helps DELETE on the parent — without it, FK delete does a Seq Scan of the child)
- Unique constraints (Postgres creates the index for you)

**Don't** add indexes for:

- Boolean columns with skewed distribution (90% of rows true, 10% false — index doesn't help most queries; consider a partial index instead)
- Columns rarely queried (every index slows writes)
- Tables that are write-heavy and rarely read in this pattern
- Already-covered query patterns (a composite `(a, b)` index covers queries on `a`, you don't also need a standalone index on `a`)

---

## 3. Composite indexes — column order matters

For an index on `(a, b, c)`:

- Queries can use the index if they filter on `a`, `(a, b)`, or `(a, b, c)`.
- Queries that filter only on `b` or `c` **cannot** use this index.

Rules of thumb:

1. **Equality columns first**, range columns last.
   - `WHERE tenant_id = X AND created_at > T` → index `(tenant_id, created_at)`, not the other way.
2. **Most selective first** (if all are equality).
   - `(tenant_id, status)` if you have 1000 tenants and 3 statuses.
3. **Match `ORDER BY`** when possible — lets the index serve the ordering without a sort step.
4. **Match `WHERE` and `ORDER BY` together** for top-N queries:
   - `WHERE customer_id = X ORDER BY created_at DESC LIMIT 20` → index `(customer_id, created_at DESC)`.

### Example: multi-tenant table

```sql
-- Table
CREATE TABLE orders (
    id UUID PRIMARY KEY,
    tenant_id UUID NOT NULL,
    customer_id UUID NOT NULL,
    status VARCHAR(20) NOT NULL,
    total_minor BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    -- ...
);

-- For "list orders for tenant by customer, newest first"
CREATE INDEX ix_orders_tenant_customer_created
    ON orders (tenant_id, customer_id, created_at DESC);

-- For "list orders for tenant with status filter"
CREATE INDEX ix_orders_tenant_status_created
    ON orders (tenant_id, status, created_at DESC);
```

Two compound indexes covering two query patterns. Resist the urge to make one giant `(tenant_id, customer_id, status, created_at)` index — it's larger and not faster than the smaller, query-matched ones.

---

## 4. Partial indexes — index a slice

When most rows have a common value, a partial index is much smaller and faster than a full one:

```sql
-- 95% of orders are not in special status
-- Index only the interesting 5%
CREATE INDEX ix_orders_pending_attention
    ON orders (created_at)
    WHERE status IN ('PAYMENT_PENDING', 'NEEDS_REVIEW');
```

Also useful for **soft delete** unique constraints:

```sql
-- Allow re-using an email after the user is soft-deleted
CREATE UNIQUE INDEX ux_users_email_active
    ON users (email)
    WHERE deleted_at IS NULL;
```

---

## 5. Expression indexes — index a computed value

When you query a transformed value, index the expression:

```sql
-- Case-insensitive email lookup
CREATE UNIQUE INDEX ux_users_email_lower
    ON users (LOWER(email));

-- Then query as:
SELECT * FROM users WHERE LOWER(email) = LOWER('Alice@Example.com');
```

For JSONB paths:

```sql
CREATE INDEX ix_users_pref_theme
    ON user_preferences ((preferences->>'theme'));
```

---

## 6. Covering indexes — `INCLUDE`

If a query can be answered entirely from the index (no need to fetch the row), you get an **index-only scan**. Postgres supports this with `INCLUDE`:

```sql
CREATE INDEX ix_orders_lookup
    ON orders (customer_id, status)
    INCLUDE (total_minor, created_at);
```

Now `SELECT customer_id, status, total_minor, created_at FROM orders WHERE customer_id = ? AND status = ?` can be answered from the index alone. Faster, fewer page reads.

Trade-off: bigger index. Only worth it when the query is hot and the included columns are small.

---

## 7. GIN for JSONB and full-text

### JSONB

Two flavours of GIN for JSONB:

```sql
-- Default: index everything, all operators (slower, bigger)
CREATE INDEX ix_users_prefs ON user_preferences USING GIN (preferences);

-- jsonb_path_ops: smaller, faster, but only @> containment
CREATE INDEX ix_users_prefs_pathops ON user_preferences USING GIN (preferences jsonb_path_ops);
```

Use `jsonb_path_ops` unless you need the other operators (`?`, `?|`, `?&`). Half the size, twice the speed for `@>` queries.

For a specific JSONB path that's hot, an expression index is even better:

```sql
CREATE INDEX ix_users_theme ON user_preferences ((preferences->>'theme'));
```

### Full-text

```sql
CREATE INDEX ix_articles_content ON articles
    USING GIN (to_tsvector('english', content));
```

Or store the `tsvector` in a generated column for query simplicity:

```sql
ALTER TABLE articles ADD COLUMN search_vector tsvector
    GENERATED ALWAYS AS (to_tsvector('english', title || ' ' || content)) STORED;
CREATE INDEX ix_articles_search ON articles USING GIN (search_vector);
```

---

## 8. BRIN for huge append-only tables

Block Range Indexes store min/max per "range of pages". Tiny on disk, useful when data is **physically ordered** (typical for append-only logs, time-series).

```sql
-- Events table inserted in time order, never updated
CREATE INDEX ix_events_occurred_brin ON events USING BRIN (occurred_at);
```

A 100GB table might have a BRIN of a few hundred MB versus tens of GB for B-tree. The query is less precise but still beats `Seq Scan` enormously.

Don't use BRIN if rows aren't physically ordered (e.g. random UUID PK without clustering on time).

---

## 9. CONCURRENTLY — never block writes

`CREATE INDEX` takes an `ACCESS EXCLUSIVE` lock that blocks all reads and writes on the table. For any table receiving production traffic, **never** create an index without `CONCURRENTLY`:

```sql
CREATE INDEX CONCURRENTLY ix_orders_customer ON orders (customer_id);
```

- Cannot run inside a transaction (Flyway: see `migrations.md` for how to handle).
- Takes longer (multiple table scans).
- Can fail; if it fails, leaves an invalid index — drop and retry.

Same for drops:

```sql
DROP INDEX CONCURRENTLY ix_orders_customer;
```

And rebuilds:

```sql
REINDEX INDEX CONCURRENTLY ix_orders_customer;
```

---

## 10. Index bloat and maintenance

Every UPDATE/DELETE leaves dead tuples; vacuum cleans them, but index pages can fragment over time.

Symptoms:
- Index is much larger than the data it covers
- `EXPLAIN ANALYZE` shows fewer rows per heap fetch than expected

Diagnosis:

```sql
SELECT
    schemaname, relname AS table, indexrelname AS index,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
ORDER BY pg_relation_size(indexrelid) DESC
LIMIT 20;
```

Fix:

```sql
REINDEX INDEX CONCURRENTLY ix_orders_customer;
```

Or for a whole table:

```sql
REINDEX TABLE CONCURRENTLY orders;
```

Run during low-traffic windows. The `pg_repack` extension is the heavier hammer if you have severe bloat.

---

## 11. Unused indexes

Every index has a write cost. Indexes you don't use are pure tax.

```sql
SELECT
    s.schemaname, s.relname AS table, s.indexrelname AS index,
    pg_size_pretty(pg_relation_size(s.indexrelid)) AS index_size,
    s.idx_scan AS scans
FROM pg_stat_user_indexes s
JOIN pg_index i ON s.indexrelid = i.indexrelid
WHERE NOT i.indisunique AND NOT i.indisprimary
  AND s.idx_scan < 50              -- arbitrary low-use cutoff
ORDER BY pg_relation_size(s.indexrelid) DESC;
```

Indexes with `idx_scan = 0` after a stable production window are candidates for removal. Drop with `CONCURRENTLY`. Keep an audit trail of dropped indexes — if a future workload needs one, you'll want to know.

---

## 12. Selectivity check before adding

Before creating an index, check the cardinality:

```sql
-- Is the column selective enough?
SELECT
    count(DISTINCT status) AS distinct_statuses,
    count(*) AS total_rows
FROM orders;
-- If distinct_statuses is 3 and total_rows is 10M, status alone is bad index material.
```

Rule: if the most common value matches more than ~20% of rows, the index won't be used for queries matching that value. Composite or partial indexes can help.

---

## 13. Indexing checklist

Before merging an index migration:

- [ ] `EXPLAIN ANALYZE` of the actual query shows the index would be used
- [ ] Column has enough selectivity (or use partial / composite)
- [ ] Column order in composite indexes matches query pattern
- [ ] `CONCURRENTLY` for any table with production writes
- [ ] No redundant index (e.g. standalone `(a)` when you already have `(a, b)`)
- [ ] Index name follows convention (`ix_<table>_<columns>`, `ux_` for unique)
- [ ] If JSONB: chose between `jsonb_ops` (default) and `jsonb_path_ops` consciously
- [ ] Documented in a comment why the index exists (the query it serves)
