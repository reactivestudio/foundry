# Regression test suite — `code/algorithms`

Each `scenario-*.md` is a self-contained code-review test:
- **Prompt** to paste into a fresh Claude Code session
- **Code** under review (Kotlin / Spring)
- **Named-trap rubric** — what's planted, where, what the expected catch looks like
- **Scoring sheet** — discriminators between baseline and skill

## How to run

For each scenario:

1. **Baseline run** — fresh Claude Code session, `foundry` plugin **disabled** (or run in a session where it isn't installed). Paste the **Prompt** block verbatim. Save the output.
2. **Skill run** — fresh session with `foundry` enabled. Paste the same prompt. Save the output.
3. **Score** each output against the rubric. Mark each trap as ✅ caught / ⚠️ partial / ❌ missed.
4. **Record** in `tests/results-iteration-<N>.md` with the date, version of skill under test (v1 / v2 / etc.), and per-trap scores.

## Named-pattern vocabulary (v2.0)

The skill uses these names in output. A catch that names the pattern is more verifiable than a paraphrase.

| Pattern | Signature |
|---|---|
| **findAll-and-filter trap** | `repo.findAll().filter { … }` — loads every row, filters in JVM |
| **cartesian repo dance** | `repo.findAll()` inside a loop — N table-scans per request |
| **N+1 cascade** | `repo.findByX(item.x)` inside a `for` / `map` — N round-trips |
| **bulk-fetch missed** | `forEach { repo.findById(it) }` — `findAllById(ids)` exists |
| **associateBy silent dataloss** | `xs.associateBy { it.f }` when `f` is not unique — last wins, others lost silently |
| **getOrPut atomic illusion** | `concurrentHashMap.getOrPut(k) { … }` — non-atomic; use `computeIfAbsent` |
| **containsKey-then-put** | `if (m.containsKey(k)) m[k] = … else m[k] = …` — verbose + racy; use `merge` / `compute` |
| **mutable-key cache phantom** | `data class Key(var x: …)` used as Map/Set key — mutation makes entry unreachable |
| **Hibernate session swell** | `repo.save()` in a loop with no `flush + clear` — session grows unbounded |
| **Pageable in-memory fallback** | `Pageable` + `Sort` over `@OneToMany` with `fetch = JOIN` — pagination falls back to in-memory |
| **lazy-init-on-serialize** | `@OneToMany(fetch = LAZY)` field accessed by Jackson outside transaction |
| **stream-doesnt-push** | `repo.findAll().stream().filter { … }` — `.stream()` is JVM-side, predicate not pushed |
| **audit-in-response leak** | service writes log/audit string into response DTO instead of `Logger` / `MDC` |
| **cache-key incomplete** | cached function result keyed by subset of params that affect result — wrong cache hit |
| **cache-unbounded** | `ConcurrentHashMap` / `HashMap` used as cache without TTL or `maximumSize` — slow OOM |
| **string-concat-in-loop** | `var s = ""; for (…) s += "…"` — O(N²) allocations |
| **sort-then-take-K** | `xs.sortedBy { … }.take(K)` when `K << xs.size` and `xs.size` is large — heap wins |
| **sequence-reflex (false positive)** | `.asSequence()` on ≤2-step chain over bounded N — overhead > savings; **remove** the wrap |
| **bounded-O(N²) acceptable (false positive)** | nested loop where N is provably small (≤ 100) — leave it, document the bound |

## Scoring template

```markdown
# Results — iteration N — <date>

Skill version: vX
Baseline: Claude <model> with no skill

| Scenario | Baseline catches | Skill catches | Exclusive skill catches | Tunnel-vision regressions |
|---|---|---|---|---|
| catalog-search | 11/20 | 17/20 | 7 | 0 |
| order-enrichment | … | … | … | … |
| … | … | … | … | … |

## Per-trap detail
… per-scenario, mark each rubric item ✅ / ⚠️ / ❌ for both runs …

## Notable observations
… qualitative notes …
```

## Success criterion (v2.0)

Per the plan: ship v2.0 when across all 5 scenarios:
- **Median advantage ≥ 3×** on exclusive skill catches
- **No scenario regresses** (skill never catches fewer than baseline)
- **Restraint false-positives** correctly handled in ≥ 3 of 5
- **Token budget** within projection (heavy usage ≤ 6500 tok)
