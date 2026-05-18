# Scenario — Order Enrichment Service

The original 8-trap test, lightly expanded with adjacent-concern traps to probe lane discipline.

## Prompt (paste verbatim)

````
Этот сервис скоро поедет в прод на наших крупных клиентов, чувствую что-то с ним не так. Глянь, что улучшил бы и почему?

```kotlin
@Service
class OrderEnrichmentService(
    private val orderRepo: OrderRepository,
    private val customerRepo: CustomerRepository,
    private val pricingRepo: PricingRepository,
    private val auditRepo: AuditRepository,
) {
    private val activityCache = ConcurrentHashMap<UUID, Activity>()

    fun buildDailyReport(date: LocalDate): DailyReport {
        val orders = orderRepo.findAll()
            .filter { it.createdAt.toLocalDate() == date && it.status == "COMPLETED" }

        val customers = customerRepo.findAll()

        val enriched = orders.map { order ->
            val customer = customers.first { it.id == order.customerId }
            val activity = activityCache.getOrPut(customer.id) {
                computeRecentActivity(customer.id)
            }
            val pricing = pricingRepo.findByProductId(order.productId)
            auditRepo.save(AuditEntry(orderId = order.id, action = "ENRICHED"))
            EnrichedOrder(order, customer, activity, pricing)
        }

        var summary = ""
        for (order in enriched) {
            summary += "${order.id}: \$${order.total}\n"
        }

        val topSpenders = enriched
            .sortedByDescending { it.total }
            .take(10)

        val byCustomer = enriched.associateBy { it.customer.id }

        return DailyReport(summary, topSpenders, byCustomer)
    }

    private fun computeRecentActivity(customerId: UUID): Activity = TODO()
}
```
````

## Rubric — 11 traps

### Algorithmic shape (7)

| # | Pattern | Where | Severity |
|---|---|---|---|
| 1 | **findAll-and-filter trap** (orders by date+status) | `orderRepo.findAll().filter { date && status }` | 🔴 critical |
| 2 | **findAll-and-filter trap** (customers in-memory join) | `customerRepo.findAll()` then used in `first { }` | 🔴 critical |
| 3 | **list.first in loop** → indexed Map | `customers.first { it.id == order.customerId }` inside `map` | 🔴 critical, O(N×M) |
| 4 | **N+1 cascade** (pricing) | `pricingRepo.findByProductId(order.productId)` inside `map` | 🔴 critical |
| 5 | **N+1 cascade** (audit write — also Hibernate session swell) | `auditRepo.save(...)` inside `map` | 🟠 high, also write-amplification |
| 6 | **string-concat-in-loop** | `summary += "…"` in `for` | 🟡 medium |
| 7 | **associateBy silent dataloss** | `enriched.associateBy { it.customer.id }` — customer may have multiple orders | 🔴 critical, silent bug |

### Kotlin footguns (2)

| # | Pattern | Where | Severity |
|---|---|---|---|
| 8 | **getOrPut atomic illusion** | `activityCache.getOrPut(customer.id) { computeRecentActivity(...) }` on `ConcurrentHashMap` | 🟠 high |
| 9 | **cache-unbounded** | `activityCache` has no eviction; grows per unique customer | 🟡 medium (lane discipline — caching skill territory) |

### Restraint false-positives (1)

| # | Pattern | Where | Expected behavior |
|---|---|---|---|
| 10 | **sort-then-take-K on bounded N** | `enriched.sortedByDescending { it.total }.take(10)` — N bounded by orders/day for one tenant | **don't** suggest heap; bounded N |

### Procedure (1)

| # | Behavior | Expected |
|---|---|---|
| P1 | Named "orders per day per tenant" / "customers total" / "products per order" before recommendations | v1 did not. v2 must. |

## Scoring sheet

```
| Trap | Baseline | v1 | v2 |
|------|----------|----|----|
|  1   |          |    |    |
|  2   |          |    |    |
| ...  |          |    |    |
| P1   |          |    |    |
```

## Known historical results

- **Baseline (2026-05-15)**: 7 caught + bonus (cache leak, magic string "COMPLETED", NoSuchElementException risk). Missed trap 5 (audit-as-write-amplification — N+1 was implicit in original test without this).
- **v1 skill (2026-05-15)**: 7 caught + restraint on trap 10 ("sort+take is fine, K=10 over bounded N"). Did **not** add `joinToString` recommendation; suggested `buildString` instead.

v2 target: catch all 7 algorithmic + trap 5 (write N+1) + active P1 (name N first).
