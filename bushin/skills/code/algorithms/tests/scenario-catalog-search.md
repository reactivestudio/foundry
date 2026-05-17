# Scenario — Catalog Search Service

20 planted traps across all 5 skill axes. The hardest test in the suite.

## Prompt (paste verbatim)

````
Делаем code review этого сервиса перед merge. Что улучшил бы?

```kotlin
@Service
class CatalogSearchService(
    private val productRepo: ProductRepository,
    private val inventoryRepo: InventoryRepository,
    private val reviewRepo: ReviewRepository,
    private val priceRepo: PriceRepository,
) {
    private val popularityCounters = HashMap<UUID, Int>()
    private val similarityCache = ConcurrentHashMap<UUID, List<UUID>>()
    private val resultCache = ConcurrentHashMap<SearchKey, SearchResponse>()

    data class SearchKey(
        var queryNormalized: String,
        val categoryId: UUID?,
        val tenantId: UUID,
    )

    fun search(req: SearchRequest): SearchResponse {
        val cacheKey = SearchKey(
            req.query?.lowercase()?.trim() ?: "",
            req.categoryId,
            req.tenantId,
        )
        resultCache[cacheKey]?.let { return it }

        val matching = productRepo.findAll().filter { p ->
            p.tenantId == req.tenantId &&
            (req.categoryId == null || p.categoryId == req.categoryId) &&
            (req.minPrice == null || p.basePrice >= req.minPrice) &&
            (req.query == null || p.name.contains(req.query, ignoreCase = true))
        }

        val page = matching
            .sortedByDescending { it.popularity }
            .drop(req.page * req.size)
            .take(req.size)

        val enriched = page.map { product ->
            val inventory = inventoryRepo.findByProductId(product.id)
            val reviews = reviewRepo.findByProductId(product.id)
            val price = priceRepo.findByProductIdAndTenantId(product.id, req.tenantId)
            EnrichedProduct(
                product = product,
                inventory = inventory,
                rating = if (reviews.isEmpty()) 0.0 else reviews.sumOf { it.rating } / reviews.size,
                price = price,
            )
        }

        val highlights = enriched
            .sortedByDescending { it.rating }
            .take(3)

        val related = enriched.associate { e ->
            val others = productRepo.findAll().filter { other ->
                other.id != e.product.id && other.tagIds.any { it in e.product.tagIds }
            }
            e.product.id to others.map { it.id }
        }

        for (e in enriched) {
            if (popularityCounters.containsKey(e.product.id)) {
                popularityCounters[e.product.id] = popularityCounters[e.product.id]!! + 1
            } else {
                popularityCounters[e.product.id] = 1
            }
        }

        for (e in enriched) {
            similarityCache.getOrPut(e.product.id) { computeSimilarity(e.product.id) }
        }

        var auditLog = "Search tenant=${req.tenantId}: "
        for (e in enriched) {
            auditLog += "${e.product.id}(r=${e.rating}) "
        }

        val mostPopularIds = popularityCounters.entries
            .sortedByDescending { it.value }
            .take(20)
            .map { it.key }

        val popularDetails = productRepo.findAll().filter { it.id in mostPopularIds }

        val byCategory = enriched.associateBy { it.product.categoryId }

        val activeTagIds = enriched.asSequence()
            .flatMap { it.product.tagIds }
            .toSet()

        val response = SearchResponse(
            items = page,
            enriched = enriched,
            highlights = highlights,
            related = related,
            popular = popularDetails,
            byCategory = byCategory,
            activeTagIds = activeTagIds,
            auditLog = auditLog,
        )
        resultCache[cacheKey] = response
        return response
    }

    private fun computeSimilarity(productId: UUID): List<UUID> = TODO()
}
```
````

## Rubric — 20 traps

### Algorithmic shape (12)

| # | Pattern | Where | Severity |
|---|---|---|---|
| 1 | **findAll-and-filter trap** | `productRepo.findAll().filter { multi-predicate }` | 🔴 critical |
| 2 | **Pageable in-memory fallback** (sort + drop + take in JVM) | `matching.sortedByDescending.drop.take` | 🔴 critical |
| 3 | **N+1 cascade** (inventory) | `inventoryRepo.findByProductId(product.id)` in `map` | 🔴 critical |
| 4 | **N+1 cascade** (reviews) | `reviewRepo.findByProductId(product.id)` in `map` | 🔴 critical |
| 5 | **N+1 cascade** (price) | `priceRepo.findByProductIdAndTenantId(...)` in `map` | 🔴 critical |
| 6 | **cartesian repo dance** | `productRepo.findAll()` inside `enriched.associate { … }` — N table-scans per request | 🔴 critical, worst |
| 7 | **containsKey-then-put** | manual increment of `popularityCounters` | 🟠 high |
| 8 | **sort-then-take-K** on potentially huge map | `popularityCounters.entries.sortedByDescending.take(20)` | 🟡 conditional on counter size |
| 9 | **bulk-fetch missed** | `productRepo.findAll().filter { it.id in mostPopularIds }` should be `findAllById` | 🟠 high |
| 10 | **string-concat-in-loop** | `auditLog += "…"` | 🟡 medium |
| 11 | **getOrPut atomic illusion** | `similarityCache.getOrPut(...) { computeSimilarity(...) }` on `ConcurrentHashMap` | 🟠 high |
| 12 | **associateBy silent dataloss** | `enriched.associateBy { it.product.categoryId }` — category not unique | 🟠 high, silent bug |

### Restraint false-positives (3)

| # | Pattern | Where | Expected behavior |
|---|---|---|---|
| 13 | **sort-then-take-K on bounded N** | `enriched.sortedByDescending.take(3)` — N is page size | **don't** suggest heap; page size bounded |
| 14 | **sequence-reflex** | `enriched.asSequence().flatMap.toSet()` — 2-step chain, bounded N | actively **remove** the `.asSequence()` |
| 15 | **rating calc** | `if (reviews.isEmpty()) 0.0 else …` — clear, idiomatic | **don't** suggest `takeIf` / `getOrElse` |

### Kotlin footguns (2)

| # | Pattern | Where | Severity |
|---|---|---|---|
| 16 | **mutable-key cache phantom** | `data class SearchKey(var queryNormalized: …)` used as key of `ConcurrentHashMap<SearchKey, …>` | 🔴 critical |
| 17 | HashMap thread safety | `popularityCounters = HashMap` shared across concurrent service calls | 🔴 critical |

### Lane discipline / adjacent (3 off-scope)

| # | Pattern | Where | Skill should… |
|---|---|---|---|
| 18 | **cache-unbounded** | `resultCache`, `similarityCache`, `popularityCounters` all unbounded | flag briefly, defer to caching skill |
| 19 | **cache-key incomplete** | `SearchKey` lacks `page` and `size` — page 2 returns page 1's cached data | flag (this is correctness, not just memory) |
| 20 | **audit-in-response leak** | `auditLog` returned in `SearchResponse` | flag briefly, defer to API-design |

### Procedure (1 behavior)

| # | Behavior | Expected |
|---|---|---|
| P1 | Named the largest plausible N (catalog per tenant, page size, counter map growth) before recommendations | spec — both v1 tests this didn't fire; v2 must change this |

## Scoring sheet

```
| Trap | Baseline | v1 skill | v2 skill |
|------|----------|----------|----------|
|  1   |          |          |          |
|  2   |          |          |          |
| ...  |          |          |          |
| P1   |          |          |          |
```

Mark each: ✅ caught (named pattern preferred) / ⚠️ partial (caught but vague) / ❌ missed.

## Known historical results

- **Baseline (2026-05-15)**: 11 algo + 2 kotlin + 2 bonus = caught 15, including the cache-key-incomplete bonus and audit-in-response. Did **not** catch trap 11 (getOrPut atomicity).
- **v1 skill (2026-05-15)**: 10 algo + 3 kotlin + 1 bonus = caught 14, **exclusive catch on trap 11** (getOrPut). Missed the cache-key-incomplete bonus (tunnel-vision regression).

v2 target: catch all 11 baseline catches PLUS at least 4 of {sequence-reflex active removal, containsKey-then-put as its own named entry, cache-key incomplete, audit-in-response leak, named-N procedure, sort-then-take-K reasoning about counter map size}.
