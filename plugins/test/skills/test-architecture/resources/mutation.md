# Pitest — Mutation Testing

Mutation testing is the only objective measure of **test effectiveness** — the empirical answer to the question "if the production code were quietly broken, would my tests notice?" Coverage tells you which lines *ran*; mutation testing tells you which lines were actually *asserted on*.

> Coverage is necessary but insufficient. A test that calls a method and asserts nothing scores 100% line coverage and 0% mutation kill rate. The mutation result is the real signal.

Pitest is the standard mutation-testing tool on the JVM. It mutates your bytecode, reruns the tests, and reports which mutations were **killed** (test failed — good), **survived** (test passed despite the bug — bad), or had **no coverage** (line wasn't exercised).

## 1. What mutation testing is

Pitest takes your compiled production code and applies small, semantics-changing transformations (**mutations**) — flipping `>` to `<=`, removing a method call, returning `null` instead of the real value, returning `0` instead of the computed result. For each mutation:

1. Pitest compiles the mutated class into a temporary mutant.
2. Runs the test suite against the mutant.
3. Records whether any test failed (= **KILLED**) or all passed (= **SURVIVED**).

If a mutation **survives**, the production code can be changed in that way and *no test will notice*. That's a hole in the test suite — the test exists but its assertions are too weak to detect the bug.

The mutation kill rate (= killed / (killed + survived)) is the most honest single number for "how strong is this test suite, really?"

## 2. Setup — Gradle plugin

```kotlin
// build.gradle.kts
plugins {
    id("info.solidsoft.pitest") version "1.15.0"
}

pitest {
    junit5PluginVersion = "1.2.1"

    // Scope — most important config. Default scans everything; almost never what you want.
    targetClasses = listOf("pro.vlprojects.assista.platform.module.*.domain.*")
    targetTests = listOf("pro.vlprojects.assista.platform.module.*.domain.*Test")

    threads = 4
    outputFormats = listOf("HTML", "XML")

    // Gating
    mutationThreshold = 80        // build fails if < 80% mutations killed
    coverageThreshold = 80        // and if < 80% lines covered

    // Optional — exclude obvious noise
    excludedClasses = listOf(
        "*Configuration",
        "*Properties",
        "*Application",
    )
}
```

Run:

```bash
./gradlew pitest
```

Report lands in `build/reports/pitest/` — open `index.html` and drill into each surviving mutation.

## 3. Mutation operators

Pitest applies a configurable set of mutation operators. The defaults are well-chosen; the most relevant categories:

| Operator | What it does | Why it matters |
|---|---|---|
| `CONDITIONALS_BOUNDARY` | `>` → `>=`, `<` → `<=`, etc. | Catches off-by-one bugs. The single most useful operator. |
| `NEGATE_CONDITIONALS` | Flips `==` ↔ `!=`, `>` ↔ `<=`. | Catches inverted logic. |
| `MATH` | Swaps `+` ↔ `-`, `*` ↔ `/`, etc. | Catches calculation errors. |
| `INCREMENTS` | `i++` → `i--`, etc. | Catches loop / counter bugs. |
| `INVERT_NEGS` | `-x` → `x`. | Catches sign errors. |
| `RETURN_VALS` | Returns `0` / `null` / empty instead of computed value. | Catches "I didn't assert on the return value" mistakes. |
| `VOID_METHOD_CALLS` | Removes calls to void methods. | Catches "I forgot to verify the side effect happened". |
| `EMPTY_RETURNS` / `FALSE_RETURNS` / `TRUE_RETURNS` / `NULL_RETURNS` | Replaces return values with stub defaults. | Catches missing assertions. |

The default set (`STRONGER` group) is the right starting point. Don't tune the operator list until you've understood what the defaults are telling you.

## 4. Interpreting results — KILLED / SURVIVED / NO_COVERAGE

### KILLED

The test caught the mutation. Good. No action needed.

### SURVIVED

The mutation was applied; the test suite ran; **no test failed**. The production code was effectively changed and your tests didn't notice. This is the diagnostic gold of mutation testing.

### NO_COVERAGE

No test exercised the mutated line. Coverage gap — write a test that runs through that branch.

### TIMED_OUT

The mutation caused an infinite loop (e.g. mutating a loop-bound expression). Pitest's safety mechanism kicked in. Usually means the production code *does* have a loop that would diverge without the original condition. Counts as KILLED.

### NON_VIABLE / RUN_ERROR

The mutated class didn't compile / verify. Pitest ignores it.

## 5. The SURVIVED diagnosis cycle

A SURVIVED mutation is a diagnosis to be worked through. There are three common causes:

### Case 1 — Test exercised the line but didn't assert on the result

```kotlin
// Production
fun totalFor(lines: List<OrderLine>): Money =
    lines.sumOf { it.unitPrice * it.qty }  // mutation: returns Money.ZERO instead

// Test
@Test
fun `total is computed`() {
    val total = pricing.totalFor(lines)
    // no assertion on the value, just that it didn't throw
}
```

Pitest reports `SURVIVED: replaced return value with Money.ZERO at OrderPricing.totalFor:23`. The test ran the line but didn't check the result. **Fix: tighten the assertion.**

```kotlin
@Test
fun `total is sum of line prices`() {
    val total = pricing.totalFor(listOf(
        OrderLine(sku = "A", unitPrice = Money.eur(10), qty = 2),
        OrderLine(sku = "B", unitPrice = Money.eur(5), qty = 3),
    ))
    assertThat(total).isEqualTo(Money.eur(35))
}
```

### Case 2 — Equivalent mutant

```kotlin
// Production
fun discount(amount: Money): Money =
    if (amount > Money.eur(100)) amount * 0.1
    else Money.ZERO

// Pitest mutates: `>` → `>=`
// All tests pass — none of them use `Money.eur(100)` as the boundary input
```

The mutation changes the behaviour *only* at the boundary `Money.eur(100)`. If no test uses that exact value, both implementations are observationally identical for the inputs you have. Either:

- **Add a boundary test** — `amount = Money.eur(100)` and assert the expected behaviour (probably `Money.ZERO` under `>`, but `Money.eur(10)` under `>=` — pick the spec and pin it).
- **Accept it as an equivalent mutant** — rare on calculation code, more common on guard clauses.

### Case 3 — Code path is untested

Pitest shows the mutation as SURVIVED but the line *isn't* covered by any meaningful assertion because the test only exercises the other branch.

```kotlin
fun apply(cmd: Command): Outcome =
    when (cmd) {
        is Submit -> handleSubmit(cmd)
        is Cancel -> handleCancel(cmd)   // mutated: return Outcome.Rejected always
    }
```

Test only sends `Submit` → the `Cancel` branch's mutation survives. **Fix: add a test for the missing branch.**

## 6. Where Pitest pays — high-ROI targets

Mutation testing is **slow** — minutes to hours depending on scope. Spend the budget where it produces signal:

| Target | ROI | Why |
|---|---|---|
| Domain aggregates (`Order`, `Invoice`, `Booking`) | High | Dense decisions, many invariants, the place where bugs hurt most. |
| Value objects (`Money`, `Quantity`, `DateRange`) | High | Pure logic; mutation testing measures exactly what we care about. |
| Pricing / financial calculations | Very high | Off-by-one is money lost. |
| Scheduling, planning algorithms | High | Subtle correctness bugs. |
| State machines (workflow / order lifecycle) | High | Many transitions; mutation testing finds untested ones. |
| Complex parsing / serialization | Medium | If a "round-trip" property test is in place, mutation kill rate validates that. |

## 7. Where Pitest doesn't pay — skip these

| Target | Why to skip |
|---|---|
| `@RestController` classes | Mostly delegation; integration tests catch real issues; mutation testing here mostly mutates the framework call signatures. |
| `@Repository` interfaces / JPA repositories | Auto-generated by Spring Data; no code to mutate meaningfully. |
| DTOs / data classes | No decisions to mutate. |
| `@Configuration` / `@Component` wiring classes | No behaviour, only structure. |
| Adapters that delegate 1:1 to a port | Integration tests cover; mutation testing of the delegation is noise. |
| Generated code (proto, OpenAPI clients) | Don't mutate generated code. |

Exclude them via `excludedClasses`:

```kotlin
pitest {
    excludedClasses = listOf(
        "*Controller",
        "*Repository",
        "*Dto",
        "*Configuration",
        "*Properties",
        "*Application",
        "*Mapper",            // if mappers are 1:1
    )
}
```

## 8. Mutation threshold targets

| Threshold | Meaning |
|---|---|
| **0–40%** | The suite is mostly cosmetic. Bugs are not detected. |
| **40–60%** | Some assertions; many holes. Don't trust the suite for refactor safety. |
| **60–80%** | Decent. Most decisions are pinned. Worth ratcheting toward 80%. |
| **80%** | **Healthy production target.** Strong assertions on most decisions; remaining survivors are typically equivalent mutants or low-value boundary cases. |
| **80–95%** | Excellent. Reached by mature domain code with rich assertions. |
| **95–100%** | Overfitting. Tests start asserting implementation details to kill the last few mutants. Net negative. |

Set `mutationThreshold = 80` for domain modules. Don't set thresholds globally — set them per-module after you've seen the report.

## 9. CI integration — Pitest is slow

A full Pitest run on a non-trivial codebase takes minutes to hours. Don't run it on every commit. Two viable strategies:

### Strategy A — Nightly job

```yaml
# .github/workflows/mutation-testing.yml
on:
  schedule:
    - cron: '0 2 * * *'   # 02:00 UTC every night

jobs:
  pitest:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          java-version: '21'
          distribution: 'temurin'
      - run: ./gradlew pitest
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: pitest-report
          path: '**/build/reports/pitest/'
```

Threshold violations break the nightly job; the team fixes them the next day. Pairs well with mature suites where mutation kill rate is already > 80%.

### Strategy B — Per-PR on critical modules

For domain / pricing / financial modules where regression is expensive, run Pitest scoped to the changed module on every PR. The scoping makes it fast enough (< 5 minutes typically).

```yaml
jobs:
  mutation-test-critical:
    runs-on: ubuntu-latest
    steps:
      # ...
      - run: ./gradlew :module:pricing:pitest
```

Combine: nightly full run + per-PR critical-module run.

## 10. A worked example — diagnosing a SURVIVED mutation

Production:

```kotlin
class OrderPricing(private val taxRate: BigDecimal) {

    fun finalPrice(lines: List<OrderLine>, customerTier: CustomerTier): Money {
        val subtotal = lines.sumOf { it.unitPrice * it.qty }
        val discount = if (customerTier == CustomerTier.PREMIUM) subtotal * 0.1 else Money.ZERO
        val discounted = subtotal - discount
        return discounted + (discounted * taxRate)
    }
}
```

Test:

```kotlin
@Test
fun `premium customers get a 10% discount`() {
    val pricing = OrderPricing(taxRate = BigDecimal("0.20"))
    val price = pricing.finalPrice(
        lines = listOf(OrderLine(unitPrice = Money.eur(100), qty = 1)),
        customerTier = CustomerTier.PREMIUM,
    )
    assertThat(price).isPositive   // weak assertion
}
```

Pitest report:

```
SURVIVED  OrderPricing:5   Replaced multiplication with division (subtotal * 0.1)
SURVIVED  OrderPricing:5   Removed conditional (customerTier == PREMIUM)
SURVIVED  OrderPricing:6   Replaced subtraction with addition
SURVIVED  OrderPricing:7   Replaced multiplication with division (discounted * taxRate)
KILLED    OrderPricing:5   Returned Money.ZERO
```

Diagnosis: `assertThat(price).isPositive` is true for every mutation because every mutation produces *some* positive value. The test ran the code but didn't pin the calculation.

Fix:

```kotlin
@Test
fun `premium customer with 100 EUR line and 20% tax pays 108 EUR`() {
    val pricing = OrderPricing(taxRate = BigDecimal("0.20"))
    val price = pricing.finalPrice(
        lines = listOf(OrderLine(unitPrice = Money.eur(100), qty = 1)),
        customerTier = CustomerTier.PREMIUM,
    )
    // 100 - 10% discount = 90 ; 90 + 20% tax = 108
    assertThat(price).isEqualTo(Money.eur(108))
}

@Test
fun `non-premium customer with 100 EUR line and 20% tax pays 120 EUR`() {
    val pricing = OrderPricing(taxRate = BigDecimal("0.20"))
    val price = pricing.finalPrice(
        lines = listOf(OrderLine(unitPrice = Money.eur(100), qty = 1)),
        customerTier = CustomerTier.STANDARD,
    )
    assertThat(price).isEqualTo(Money.eur(120))
}
```

Re-run Pitest: all mutations on lines 5–7 are now KILLED. The mutation feedback drove the test from "ran the code" to "specified the calculation".

This is the value loop: SURVIVED is a diagnosis; tightening the assertion is the fix; re-running Pitest confirms the kill.

## 11. Pitest performance tips

- **Scope `targetClasses` tightly.** The single biggest performance lever. Don't mutate `*` — mutate the modules you actually care about.
- **Use `threads = N`** matching your CPU count. Pitest parallelises well.
- **Use the incremental analysis feature** (`enableDefaultIncrementalAnalysis = true`) for repeated local runs — Pitest skips unchanged classes.
- **Exclude generated code, configuration, DTOs** via `excludedClasses`.
- **Don't run Pitest with `@SpringBootTest` in scope.** Spring boot startup is repeated per mutation = catastrophe. Keep Pitest pointed at unit-testable domain code; `targetTests` should match plain-JUnit unit tests, not Spring-context tests.

## 12. Anti-patterns

- **Mutation threshold chased to 100%.** Drives test code that asserts implementation details just to kill equivalent mutants. The last 5–15% of mutants are typically equivalent; pursuing them is overfitting.
- **Pitest on the whole codebase.** Slow (hours), most of the surface is low-ROI (controllers, repos, DTOs). Scope deliberately.
- **Pitest running on every commit.** CI feedback turns to 30+ minutes. Schedule it nightly or on PRs that touch critical modules.
- **Treating SURVIVED as a coverage problem.** It's an *assertion* problem — the line ran; the test just didn't notice the mutation. Tighten the assertion, don't add more tests of the same shape.
- **Ignoring SURVIVED mutations because "the test is right, Pitest is wrong".** Sometimes true (equivalent mutant). More often the test really *is* weak and Pitest found it. Default to assuming Pitest is right; prove the equivalence before dismissing.
- **Mutating Spring-integrated tests.** `@SpringBootTest` per mutation = hours. Pitest is for plain-JUnit unit tests against domain code.
- **Setting `mutationThreshold` without first measuring.** A fresh codebase might be at 35%. Setting `mutationThreshold = 80` on day one fails the build and the team turns Pitest off. Measure first; set the threshold above the current baseline; ratchet upward.
- **Treating Pitest as a replacement for code review or static analysis.** It catches missing assertions; it doesn't catch bad design, missing abstractions, or unsafe APIs. Layer with the rest of the discipline.
- **Forgetting to exclude generated code.** Pitest mutates everything in `targetClasses` — generated mappers, proto-generated classes, OpenAPI clients. Noise.
