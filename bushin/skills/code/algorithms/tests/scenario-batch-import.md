# Scenario — Batch Customer Import

Spring Data heavy. Probes the area where Claude baseline is weakest: JPA session lifecycle, `@Transactional` semantics, bulk write patterns.

## Prompt (paste verbatim)

````
Ревью импортного сервиса перед раскаткой. Что бы поправил?

```kotlin
@Service
@Transactional
class CustomerImportService(
    private val customerRepo: CustomerRepository,
    private val auditRepo: AuditRepository,
    private val taxRepo: TaxRepository,
    private val emailValidator: EmailValidator,
) {
    fun importCustomers(records: List<CustomerCsvRow>): ImportReport {
        val report = ImportReport()

        for (row in records) {
            val existing = customerRepo.findById(row.externalId).orElse(null)

            if (existing == null) {
                val tax = taxRepo.findByCountry(row.country)
                val customer = Customer(
                    externalId = row.externalId,
                    name = row.name,
                    email = row.email,
                    country = row.country,
                    taxRate = tax?.rate,
                    createdAt = Instant.now(),
                )

                if (emailValidator.isValid(customer.email)) {
                    customerRepo.save(customer)
                    auditRepo.save(AuditEntry("CREATED", customer.id, Instant.now()))
                    report.created++
                } else {
                    report.invalid++
                }
            } else {
                existing.name = row.name
                existing.email = row.email
                customerRepo.save(existing)
                auditRepo.save(AuditEntry("UPDATED", existing.id, Instant.now()))
                report.updated++
            }
        }

        val all = customerRepo.findAll()
        val byCountry = all.groupBy { it.country }
        val largestCountry = byCountry.maxByOrNull { it.value.size }

        report.totalCustomers = all.size
        report.largestCountry = largestCountry?.key
        report.summary =
            "Imported ${report.created}+${report.updated}, " +
            "${report.invalid} invalid, largest country: ${largestCountry?.key}"

        return report
    }

    @Transactional(readOnly = false)
    fun listAllWithRecentActivity(pageable: Pageable): Page<CustomerSummary> {
        val customers = customerRepo.findAll(pageable)
        return customers.map { c ->
            val recent = auditRepo.findByCustomerIdOrderByTimestampDesc(c.id)
                .take(5)
            CustomerSummary(c, recent.lastOrNull()?.action, recent.size)
        }
    }
}
```
````

## Rubric — 14 traps

### Algorithmic shape (8)

| # | Pattern | Where | Severity |
|---|---|---|---|
| 1 | **N+1 cascade** (existence check) | `customerRepo.findById(row.externalId)` in `for` over `records` | 🔴 critical |
| 2 | **N+1 cascade** (tax lookup) | `taxRepo.findByCountry(row.country)` in loop — tax table is small, load once | 🔴 critical |
| 3 | **Hibernate session swell** | `customerRepo.save(customer)` + `auditRepo.save(...)` in loop, no `flush()` + `clear()` — 1st-level cache grows unbounded → OOM at large N | 🔴 critical, Spring-specific |
| 4 | **findAll-and-filter trap** (summary read) | `customerRepo.findAll()` loaded just to count + groupBy | 🔴 critical |
| 5 | **in-memory aggregate** (groupBy + max) | `all.groupBy { it.country }.maxByOrNull { it.value.size }` — should be `SELECT country, COUNT(*) FROM ... GROUP BY country ORDER BY COUNT(*) DESC LIMIT 1` | 🟠 high |
| 6 | **bulk-fetch missed** | `findById` in loop → `findAllByExternalIdIn(externalIds)` once, build a Map | 🟠 high (fix for #1) |
| 7 | **N+1 cascade** (recent audit per customer) | `auditRepo.findByCustomerIdOrderByTimestampDesc(c.id).take(5)` per row in page | 🔴 critical |
| 8 | **sort-then-take-K** misused | `findByCustomerIdOrderByTimestampDesc(...).take(5)` — DB returns all rows ordered, then `take(5)` in JVM. Should use `Pageable.ofSize(5)` or `Top5By...` Spring Data method. | 🟠 high |

### Spring/JPA semantic (4)

| # | Pattern | Where | Severity |
|---|---|---|---|
| 9 | **`@Transactional` scope misuse** | `@Transactional` wraps the entire `importCustomers`. One failure rolls back the whole batch; long-running tx holds locks. Should chunk: process N records per tx, or use `REQUIRES_NEW` per chunk. | 🔴 critical |
| 10 | **`@Transactional(readOnly = false)` on a read method** | `listAllWithRecentActivity` — only reads, but `readOnly = false` triggers Hibernate dirty-checking on every entity. Should be `readOnly = true`. | 🟠 high |
| 11 | **dirty-update via mutation** | `existing.name = row.name; existing.email = row.email` then `customerRepo.save(existing)` — works via dirty-checking but the explicit `save()` is redundant inside `@Transactional`. Stylistic but suggests author confusion about JPA persistence model. | 🟡 medium |
| 12 | **Pageable + per-page N+1** | `customerRepo.findAll(pageable).map { ... auditRepo.findBy(c.id) }` — page-sized N+1 on top of the page query. Should pre-fetch audits for the page's customer IDs in one batch. | 🔴 critical |

### Restraint false-positives (2)

| # | Pattern | Where | Expected behavior |
|---|---|---|---|
| 13 | **clear if/else over Optional** | `customerRepo.findById(...).orElse(null)` then `if (existing == null)` — idiomatic Kotlin/JPA. **Don't** suggest `.map { update(it) }.orElseGet { create() }` chain. | leave |
| 14 | **plain for over `forEach`** | `for (row in records)` — clear and debuggable. **Don't** suggest `.forEach { }` or `.also { }` chain. | leave |

### Procedure (1)

| # | Behavior | Expected |
|---|---|---|
| P1 | Asked "how big is `records`?" / "what's the largest plausible batch?" before recommending fixes | v2 must |

## Scoring sheet

```
| Trap | Baseline | v1 | v2 |
|------|----------|----|----|
|  1   |          |    |    |
|  2   |          |    |    |
| ...  |          |    |    |
| P1   |          |    |    |
```

## Predicted baseline behavior

Likely catches:
- 1, 4, 5 (general N+1 / findAll patterns)
- 7, 12 (page-N+1, often caught)
- 9 (long transaction, sometimes)
- Probably 3 (session swell) — depends on Spring experience cued in training

Likely misses:
- 6 (bulk-fetch named alternative) — usually just "use a batch" without naming
- 10 (readOnly = false on reads) — subtle
- 8 (`.take(5)` after DB order) — subtle
- 13, 14 (restraint) — may over-engineer Optional / forEach
- P1 (asking about N) — no

This scenario discriminates well on Spring/JPA semantics — the area where the new `spring.md` resource should add the most value.
