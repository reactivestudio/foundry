# Spring / JPA — Algorithmic-Shape Footguns

JPA hides complexity behind annotations and method names. The footguns below are *algorithmic-shape* bugs masquerading as ORM idioms. Each has a fixed signature, a verbatim fix, and a measurable scale on which it matters.

## Hibernate session swell

`repo.save()` (or any `entityManager.persist`) inside a loop accumulates entities in the first-level (session) cache. Every subsequent dirty-check scans every accumulated entity. At ~10K rows the session OOMs or the import slows to a crawl as dirty-checking goes quadratic.

```kotlin
// SMELL — single @Transactional method around a long batch
@Transactional
fun importAll(rows: List<Row>) {
    for (row in rows) {
        val entity = mapToEntity(row)
        repo.save(entity)
    }
}
```

Two fixes, depending on whether you want all-or-nothing:

```kotlin
// (a) Periodic flush + clear — keep one transaction, bounded session
@Transactional
fun importAll(rows: List<Row>) {
    rows.chunked(500).forEachIndexed { i, chunk ->
        chunk.forEach { repo.save(mapToEntity(it)) }
        entityManager.flush()
        entityManager.clear()   // free the session
    }
}

// (b) Per-chunk transactions — partial progress survives a failure
fun importAll(rows: List<Row>) {
    rows.chunked(500).forEach { chunk ->
        chunkService.processInNewTransaction(chunk)  // REQUIRES_NEW
    }
}
```

Trigger to recognise: any `for` / `forEach` containing a `repo.save` / `entityManager.persist` inside a `@Transactional` method with no `flush + clear`. **Default verdict: needs chunking; ask about expected batch size.**

## `@Transactional` scope on batches

A single `@Transactional` wrapping a long batch holds row/page locks for the entire duration, blocks other writers, and rolls back the whole thing on the last-record error. This is rarely what the author intended.

```kotlin
@Transactional                     // ⚠ entire batch is one transaction
fun importAll(rows: List<Row>): Int
```

Decide explicitly:
- **All-or-nothing required?** Keep `@Transactional`, document why.
- **Otherwise** — chunk into `REQUIRES_NEW` sub-transactions; failed chunks log + skip.

Trigger: `@Transactional` on a `for`-driven import / batch / migration method. **Ask: what's the desired failure semantic? then route to a fix.**

## `@Transactional(readOnly = true)` missing on reads

Without `readOnly = true`, Hibernate enables dirty-checking on every loaded entity at transaction commit. For a query returning N entities, that's N reflective scans for *no benefit* — the method only reads.

```kotlin
// SMELL
@Transactional   // implicit readOnly = false
fun listProducts(): List<Product> = repo.findAll()

// FIX
@Transactional(readOnly = true)
fun listProducts(): List<Product> = repo.findAll()
```

Effect at scale: 10-30% latency reduction on read-heavy endpoints, depending on entity size. Free win.

Trigger: any service method whose name starts with `find` / `get` / `list` / `count` / `read` and uses `@Transactional` without `readOnly`. Flag every one.

## `Pageable` in-memory fallback

`Pageable` with `Sort` over a `@OneToMany` field forces Hibernate to load **everything**, sort in JVM, then slice. Hibernate even logs a warning (`HHH000104: firstResult/maxResults specified with collection fetch; applying in memory`), but the warning is easy to miss.

```kotlin
// SMELL — joined collection + Pageable
@Query("SELECT o FROM Order o JOIN FETCH o.items WHERE o.tenant = :t")
fun findByTenant(t: UUID, pageable: Pageable): Page<Order>
```

Two fixes:

```kotlin
// (a) Two queries: page the parent, then JOIN FETCH the children for that page
val page = repo.findByTenant(t, pageable)
val withItems = repo.findAllByIdInWithItems(page.content.map { it.id })

// (b) @EntityGraph on a paginated method — fetches lazily per row but no fallback
@EntityGraph(attributePaths = ["items"])
fun findByTenant(t: UUID, pageable: Pageable): Page<Order>
```

Trigger: `Pageable` parameter on a `@Query` that uses `JOIN FETCH` over a `@OneToMany` / `@ManyToMany` collection. **Almost always wrong.**

## `findAll().stream()` doesn't push to DB

`.stream()` after `findAll()` is JVM-side. The predicate inside the stream is **not** translated to SQL — the repo already loaded every row.

```kotlin
// SMELL
val active = repo.findAll().stream()
    .filter { it.status == "ACTIVE" }
    .toList()
```

`.stream()` looks performant but changes nothing about what was loaded. The fix is to move the predicate into the query:

```kotlin
val active = repo.findByStatus("ACTIVE")
// or for richer predicates:
val active = repo.findAll(Specification.where(StatusEquals("ACTIVE")))
```

Trigger: `.stream()` / `.asSequence()` immediately after `.findAll()`. The chain shape is a lie.

## `findById` in a loop → `findAllById`

The named-pattern version of the universal N+1.

```kotlin
// SMELL
val accounts = top5Ids.map { repo.findById(it).orElseThrow() }

// FIX — one round-trip
val byId = repo.findAllById(top5Ids).associateBy { it.id }
val accounts = top5Ids.map { byId[it] ?: error("missing $it") }
```

Trigger: `findById` inside any `for` / `map` / `flatMap` body. The fix is mechanical.

Same shape applies to `findByX` — if X is the natural key and the loop iterates over X-values, look for `findByXIn` or `findAllByXIn`.

## Top-N: use Spring Data's `findTopN` / `findFirstN`

`findAll().sortedByDescending { it.createdAt }.take(10)` is **two** wastes: (a) loads every row, (b) sorts in JVM.

```kotlin
// FIX — Spring Data derives the SQL with LIMIT
fun findTop10ByOrderByCreatedAtDesc(): List<Order>

// or with Pageable
fun findAll(PageRequest.of(0, 10, Sort.by(DESC, "createdAt")))
```

Trigger: `repo.findAll()` followed by `sortedBy { }` and `take(N)`. The DB can do all three in one indexed query.

## `Sort.by("createdAt")` silently slow without index

`Sort.by(DESC, "createdAt")` looks free. It's a sequential scan + sort if `created_at` isn't indexed. At 100K+ rows the cost dominates the query.

```kotlin
PageRequest.of(0, 20, Sort.by(DESC, "createdAt"))
```

There's no syntactic fix in code — the fix is **a DB index on `created_at`**. The skill's contribution: flag this at the call site so the index migration isn't forgotten.

Trigger: `Sort.by(...)` on a field used for routine ordering. Ask: is there an index?

## `LazyInitializationException` on DTO serialization

`@OneToMany(fetch = LAZY)` accessed by Jackson during response serialization throws `LazyInitializationException` — the transaction closed before serialization began.

Three idiomatic fixes:

```kotlin
// (a) Project to DTO inside the transaction
@Transactional(readOnly = true)
fun getOrderDto(id: UUID): OrderDto {
    val order = repo.findById(id).orElseThrow()
    return OrderDto(order.id, order.items.map { ItemDto(it.id, it.name) })
}

// (b) @EntityGraph on the read method
@EntityGraph(attributePaths = ["items"])
fun findById(id: UUID): Optional<Order>

// (c) Open Session In View — only for legacy reasons; avoid in new code
```

Trigger: response DTO containing a `List` or `Set` typed as a JPA collection (or a converter chain ending at `@OneToMany`-mapped data). Flag if no `@EntityGraph` / explicit projection / eager fetch.

## `Specifications + Pageable` count-query semantics

`findAll(spec, pageable)` issues *two* queries: the data page **and** a `COUNT(*)`. The count query can dominate for complex `Specification`s with multiple joins.

If the caller doesn't need a total count (infinite-scroll UI), use `Slice<T>` instead of `Page<T>` — no count query.

```kotlin
fun findBy(spec: Specification<X>, pageable: Pageable): Slice<X>
```

Trigger: `Page<T>` return type on an endpoint where the UI doesn't show "page X of Y" totals. Suggest `Slice`.

---

## Quick recognition heuristics

For any Spring/JPA review, walk this list against the code:

1. `@Transactional` on read methods → has `readOnly = true`? If not, flag.
2. `@Transactional` over a loop with `save` → has `flush + clear` or chunking? If not, flag.
3. `Pageable` over `JOIN FETCH` collection → flag (in-memory fallback).
4. `findAll(...).stream().filter` → flag (predicate not pushed).
5. `findById` in a loop → suggest `findAllById`.
6. `findAll(...).sortedBy.take(N)` → suggest `findTop(N)ByOrderBy...`.
7. `Sort.by("X")` → ask about index on X.
8. JPA collection in response DTO → flag lazy-init risk unless `@EntityGraph` or projection.
9. `Page<T>` on infinite-scroll UI → suggest `Slice<T>`.

Each heuristic is a sentence Claude can mechanically check. Use them as audits, not principles.
