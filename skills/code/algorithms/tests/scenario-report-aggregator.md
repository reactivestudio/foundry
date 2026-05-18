# Scenario — Financial Report Aggregator

Aggregation-heavy. Mix of groupBy / top-K / cartesian-over-time-series / cross-tenant comparison. Tests algorithmic-shape reasoning on time-series-ish data.

## Prompt (paste verbatim)

````
Сервис генерации месячных отчётов. Перед раскаткой нужно code review. На что обратить внимание?

```kotlin
@Service
class FinancialReportService(
    private val transactionRepo: TransactionRepository,
    private val accountRepo: AccountRepository,
    private val currencyRateRepo: CurrencyRateRepository,
    private val tenantRepo: TenantRepository,
    private val reportRepo: ReportRepository,
) {
    private val rateCache = HashMap<String, BigDecimal>()
    private val tenantNameCache = ConcurrentHashMap<UUID, String>()

    fun generateMonthlyReport(month: YearMonth, tenantId: UUID): MonthlyReport {
        val all = transactionRepo.findAll()
        val txns = all.filter {
            it.tenantId == tenantId && YearMonth.from(it.timestamp) == month
        }

        val byAccount = txns
            .groupBy { it.accountId }
            .mapValues { (_, g) -> g.sumOf { it.amount } }

        val top5 = byAccount.entries
            .sortedByDescending { it.value }
            .take(5)
            .map { (id, sum) ->
                val account = accountRepo.findById(id).orElseThrow()
                AccountTotal(account, sum)
            }

        val byCurrency = mutableMapOf<String, BigDecimal>()
        for (txn in txns) {
            val rate = rateCache.getOrPut(txn.currency) {
                currencyRateRepo.findLatestRate(txn.currency).rate
            }
            byCurrency[txn.currency] =
                (byCurrency[txn.currency] ?: BigDecimal.ZERO) + (txn.amount * rate)
        }

        val thisTenant = tenantRepo.findById(tenantId).orElseThrow()
        val peers = tenantRepo.findAll()
            .filter { it.id != tenantId && it.region == thisTenant.region }
        val peerSummaries = peers.map { peer ->
            val peerTotal = all
                .filter { it.tenantId == peer.id && YearMonth.from(it.timestamp) == month }
                .sumOf { it.amount }
            PeerSummary(peer.id, getTenantName(peer.id), peerTotal)
        }

        val suspicious = mutableListOf<Pair<UUID, UUID>>()
        for (a in txns) {
            for (b in txns) {
                if (a.id != b.id && a.accountId == b.accountId &&
                    Duration.between(a.timestamp, b.timestamp).abs() < Duration.ofMinutes(1)
                ) {
                    suspicious.add(a.id to b.id)
                }
            }
        }

        var text = "Monthly report for ${thisTenant.name} - $month\n"
        text += "Total transactions: ${txns.size}\n"
        for (t in top5) text += "  ${t.account.name}: ${t.amount}\n"

        val report = MonthlyReport(
            tenantId = tenantId, month = month, text = text,
            top5 = top5, byCurrency = byCurrency,
            peerComparison = peerSummaries, suspiciousPairs = suspicious,
        )
        reportRepo.save(report)
        return report
    }

    private fun getTenantName(id: UUID): String =
        tenantNameCache.getOrPut(id) { tenantRepo.findById(id).orElseThrow().name }
}
```
````

## Rubric — 13 traps + 2 false positives

### Algorithmic shape (10)

| # | Pattern | Where | Severity |
|---|---|---|---|
| 1 | **findAll-and-filter trap** | `transactionRepo.findAll()` then filter by tenant + month — should be `findByTenantIdAndTimestampBetween` | 🔴 critical |
| 2 | **in-memory aggregate** | `txns.groupBy { it.accountId }.mapValues { sumOf }` — should be SQL `GROUP BY account_id, SUM(amount)` | 🟠 high (depends on txn count) |
| 3 | **N+1 cascade** (account lookup after top-5) | `accountRepo.findById(id).orElseThrow()` in `.map { }` | 🔴 critical |
| 4 | **bulk-fetch missed** (fix for #3) | top-5 ids known up front → `findAllById(top5Ids).associateBy { it.id }` | 🟠 high |
| 5 | **containsKey-then-put** | `byCurrency[k] = (byCurrency[k] ?: ZERO) + x` → `byCurrency.merge(k, x, BigDecimal::plus)` | 🟡 medium |
| 6 | **HashMap thread safety** | `rateCache = HashMap<...>` shared in singleton service, mutated under concurrent calls | 🔴 critical |
| 7 | **findAll-and-filter trap** (peers) | `tenantRepo.findAll().filter { region == ... }` — should be `findByRegion` | 🟠 high |
| 8 | **cartesian-with-filter** | for each peer, `all.filter { tenantId == peer.id && month }` — repeated O(N) scan per peer. Pre-group once: `all.groupBy { it.tenantId }` | 🔴 critical, O(P×T) |
| 9 | **N+1 cascade** (tenant names per peer) | `getTenantName(peer.id)` per peer — bulk pre-load peer names | 🟠 high |
| 10 | **cartesian txns × txns** | for-for over all txns to find ≤1-minute same-account pairs — O(N²). Fix: sort by timestamp + sliding window, O(N log N). | 🔴 critical, suspicious-pairs is the wrong shape |

### Kotlin / atomicity (2)

| # | Pattern | Where | Severity |
|---|---|---|---|
| 11 | **getOrPut atomic illusion** | `tenantNameCache.getOrPut(...) { tenantRepo.findById(...).orElseThrow().name }` on `ConcurrentHashMap` — non-atomic, can call `findById` twice for same id under concurrency | 🟠 high |
| 12 | **string-concat-in-loop** | `text +=` in `for (t in top5)` — bounded N=5, but still inelegant. **Note: K=5 makes this borderline-restraint**; baseline often catches, but the impact is negligible | 🟡 low (could legitimately argue either way) |

### Lane discipline / adjacent (1)

| # | Pattern | Where | Skill should… |
|---|---|---|---|
| 13 | **cache-unbounded** | `rateCache`, `tenantNameCache` — no eviction; grows over months × currencies × tenants | flag briefly, defer |

### Restraint false-positives (2)

| # | Pattern | Where | Expected behavior |
|---|---|---|---|
| 14 | **top-5 sort+take after groupBy** | `byAccount.entries.sortedByDescending.take(5)` — K=5, byAccount keyed by accounts per tenant per month (bounded). **Don't** suggest PriorityQueue. | leave |
| 15 | **groupBy + sumOf in JVM** | `txns.groupBy { it.accountId }.mapValues { sumOf }` is the right *operation*, only its locus is wrong (should be SQL). **Don't** suggest a manual fold or "more efficient" data structure. The single fix is push to SQL (trap 2). | leave the kotlin idiom |

### Procedure (1)

| # | Behavior | Expected |
|---|---|---|
| P1 | Asked "txns per tenant per month at peak?", "peers per region?", "accounts per tenant?" before recommending | v2 must ask at least one of these |

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
- 1, 7 (findAll + filter — obvious)
- 3 (N+1 in top-5 .map) — common pattern
- 6 (HashMap thread safety) — usually caught
- 10 (cartesian txns × txns) — O(N²) is visible
- 13 (cache leak) — common to mention

Likely misses or weak:
- 4, 9 (named bulk-fetch alternative — usually paraphrased)
- 5 (`merge` not as commonly suggested as the contains+put pattern)
- 8 (cartesian-with-filter on peers) — often missed; looks like one filter chain
- 11 (getOrPut on ConcurrentHashMap) — v1's exclusive win
- 14, 15 (restraint) — likely doesn't comment either way
- P1 (named N) — no

This scenario discriminates on **cartesian-with-filter** (trap 8) and **shape-correctness** (trap 10: O(N²) for time-window pairs is wrong even at modest N). Both are areas where Claude often misdiagnoses the shape.
