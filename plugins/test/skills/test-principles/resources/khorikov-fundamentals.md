# Khorikov Fundamentals — Four Quadrants and Four Pillars

From Vladimir Khorikov, *Unit Testing: Principles, Practices and Patterns* (Manning, 2020). The model that complements Martin's *how* with the missing *what* and *whether*:

- **Four quadrants** — *which code* deserves tests, at what layer.
- **Four pillars** — *which tests* deserve to exist (and which look like coverage but provide negative value).

> "What you don't test is half the strategy." — Khorikov-paraphrase
>
> "A test exists for one reason: to give you the confidence to change the code. A test that doesn't give you that confidence — because it tests mocks, or because it breaks on every refactor — is paying for nothing." — house ethos

These two models layer on top of the Martin rules. Martin says how to write each test well; Khorikov says which to write at all and which to throw out.

---

## Part 1 — The four quadrants

Khorikov classifies code on two axes:

- **Complexity / domain significance** — how much decision density, how many invariants, how many branches per line.
- **Number of collaborators** — how many external dependencies (classes, services, ports).

The four quadrants:

```
                          high complexity / decision density
                                        ▲
                                        │
                                        │
   ┌────────────────────────────────────┼────────────────────────────────────┐
   │                                    │                                    │
   │   Overcomplicated                  │   Domain Model & Algorithms        │
   │   ─ many collaborators             │   ─ few collaborators              │
   │   ─ high complexity                │   ─ high complexity                │
   │   ─ refactor first;                │   ─ HIGHEST-ROI UNIT TESTS         │
   │     don't test as-is               │     here                           │
   │                                    │                                    │
   ├────────────────────────────────────┼────────────────────────────────────┤
   │                                    │                                    │
   │   Controllers                      │   Trivial                          │
   │   ─ many collaborators             │   ─ few collaborators              │
   │   ─ low complexity                 │   ─ low complexity                 │
   │   ─ integration tests              │   ─ DON'T TEST                     │
   │     are highest-ROI here           │     (getters, plain data)          │
   │                                    │                                    │
   └────────────────────────────────────┴────────────────────────────────────┘
                                        │
                                        │
                                        ▼
                          low complexity (few decisions)
                                        ◄────── few collaborators

                                        ◄────── many collaborators ──────►
```

### Quadrant 1: Trivial code (few collaborators + low complexity)

**Examples**: getters, setters, plain data classes, simple converters, one-line delegations.

**Test ROI**: near zero. The code has no decisions to break; the compiler guarantees field assignment / type correctness.

**Action**: **don't test directly**. Pass through to higher layers where the trivial code is *used* — if the use is correct, the trivial code is correct.

**Misconception**: "If I don't test it, my coverage drops." Yes — and that's fine. Coverage is a *symptom*, not the goal. A 70%-covered codebase where the 70% is high-value tests beats a 95%-covered codebase where the 25% extra is trivial.

---

### Quadrant 2: Domain Model & Algorithms (few collaborators + high complexity)

**Examples**: aggregates with behaviour, value objects, domain services, specifications, pricing algorithms, scheduling logic, parsing.

**Test ROI**: **highest in the codebase**. Each unit test is fast, surgical, and pins down one business rule. Refactoring inside the domain is safe because the rules are pinned.

**Action**: **unit-test densely**. Aim for one test per business rule (happy path + invariant violation). Pair with property-based tests for invariants over a class of inputs.

**Why this quadrant matters**: this is where pyramid-shaped suites earn their place. A codebase rich in this quadrant *deserves* a classic pyramid. The shape of the codebase determines the shape of the test suite.

---

### Quadrant 3: Controllers (many collaborators + low complexity)

**Examples**: application services that orchestrate the domain + ports (`OrderApplicationService.submit(...)`), Spring `@RestController` methods (route + validate + delegate), event listeners with light routing logic.

**Test ROI**: **integration > unit**. Unit tests of controllers require mocking every collaborator — the test becomes 80% mock setup, low decision density verified.

**Action**: **integration-test through the controller's natural seam**: HTTP request → service → real DB / stubbed external HTTP → assert on observable side effect. The whole orchestration runs realistically.

**The most common waste in enterprise Java**: writing pyramid-shaped unit tests for Controllers-quadrant code. Six mocked collaborators, one assertion that the mock was called. Khorikov's specific warning: this kind of test scores low on **all four pillars** (see below). It looks like coverage; it provides negative value.

---

### Quadrant 4: Overcomplicated (many collaborators + high complexity)

**Examples**: god services that do six things, methods with 14 collaborators and 200 lines, services that mix transactional, async, and external HTTP concerns.

**Test ROI**: **negative until refactored**. Tests of overcomplicated code are themselves overcomplicated — 30 mocks, conditional setup, the test brittle to every change in the production code. They impede refactoring instead of enabling it.

**Action**: **refactor first.** Extract pure logic into Domain Model & Algorithms (quadrant 2) — test those. Extract orchestration into thin Controllers (quadrant 3) — integration-test those. Iterate until the original god service is gone.

**Until refactor possible** (legacy / time pressure): **characterisation tests at integration level**. Pin the observable behaviour at the system boundary; refactor under those tests; replace them with quadrant-2 and quadrant-3 tests as the refactor unfolds.

---

## How to identify a quadrant for a piece of code

Two questions:

1. **Count collaborators** — how many fields are injected? How many other classes does this class call? More than ~3 → "many".
2. **Count decisions** — `if` / `when` / `switch` / loops with conditions / `require`s / business invariants. More than ~5 → "high complexity".

| Decisions | Collaborators | Quadrant |
|---|---|---|
| Few | Few | Trivial |
| Many | Few | Domain Model & Algorithms |
| Few | Many | Controllers |
| Many | Many | Overcomplicated |

The threshold values are heuristics, not laws — apply judgement. A class with two collaborators and five decisions is in the Domain Model quadrant; a class with three collaborators and six decisions is borderline (and probably wants to be split).

---

## Part 2 — The four pillars of a good test

Each test has value along four axes. They are **tradeoffs**, not all-or-nothing.

### Pillar 1: Protection against regressions

**Question**: when a real bug is introduced into the production code, does this test catch it?

**Maximised by**:
- Testing **observable behaviour**, not implementation details.
- Asserting on **outputs** (return values, state changes, emitted events) rather than method calls.
- Exercising more production code per test (a slice test covers more lines than a unit test).
- Testing at the **right level of abstraction** for the bug class — JSONB queries need integration tests; pricing rules need unit tests.

**Reduced by**:
- Mocking the system-under-test's collaborators heavily — the mock returns whatever you tell it, regardless of real behaviour.
- Asserting only on internal state (`verify { mock.called(...) }`).
- Tests with no real assertion (`assertTrue(true)`).

**Tradeoff**: maximising protection often pushes tests toward integration (slower, slower feedback). The four pillars together force the explicit tradeoff.

---

### Pillar 2: Resistance to refactoring

**Question**: when production code is refactored *but behaviour doesn't change*, does this test still pass?

**Maximised by**:
- Testing **behaviour**, not method-call signatures.
- Using **black-box** seams (HTTP request, command, event).
- Avoiding `verify { mock.method(specificArgs) }` — that asserts implementation, not behaviour.
- Avoiding tests of private methods (via reflection or visibility hacks).

**Reduced by**:
- Over-mocking — tests break when you rename a method, change argument order, or extract a helper.
- Tests that assert on private fields.
- Snapshot tests that capture incidental output (whitespace, ordering of unsorted fields).

**Why this is the most-ignored pillar**: tests that break on every refactor *erode trust*. A team that has been bitten by 50 broken tests during one refactor stops refactoring — which is the opposite of what the test suite is for.

---

### Pillar 3: Fast feedback

**Question**: does this test run quickly enough to run on every save?

**Maximised by**:
- Pure unit tests with no Spring / DB / IO.
- Test slicing (only the layer under test loads).
- Testcontainers with `withReuse(true)`.
- Tiered test tasks (`unitTest` < 30s, `integrationTest` separately).

**Reduced by**:
- `@SpringBootTest` everywhere.
- `H2` substituted for Postgres (fast, but breaks Repeatable).
- Real network calls.
- Pre-test data seeding that runs once per test method instead of per class.

**Tradeoff**: fast feedback often trades against protection-against-regressions — the fastest tests are unit tests, but a unit test of a Controllers-quadrant function provides little protection. The pyramid recovers fast feedback at the cost of pushing some protection to a slower tier.

---

### Pillar 4: Maintainability

**Question**: as the codebase evolves, how cheap is keeping this test working?

**Maximised by**:
- Short test bodies (3-6 lines).
- Domain-language DSL for fixtures and assertions.
- Builder factories with named defaults (`anOrder(status = SUBMITTED)`).
- Black-box seams that don't change when implementation does.
- Cleanly named tests (the name *is* the documentation).

**Reduced by**:
- Long, cryptic setup blocks.
- Tests that lean on shared mutable state.
- Snapshot tests with manual review on every diff.
- Cascading test failures (one production change breaks 30 tests).

---

## The pillar diagram — every test trades two against the other two

You cannot maximise all four simultaneously. Every test is a point in a 4-dimensional space, optimising a *combination*.

| Test type | Protection | Refactor-resistance | Fast feedback | Maintainability |
|---|---|---|---|---|
| Pure unit test of domain method | High | High | High | High |
| `@DataJpaTest` of repository | High | High | Med | Med |
| `@SpringBootTest` end-to-end | Very high | High | Low | Low |
| Unit test of service with 8 mocks | **Low** | **Low** | High | **Low** |
| Snapshot test of full HTML output | Med | Low | High | Low |
| Property-based test of value object | High | High | High | Med |

The row that should jump out: **unit test of service with 8 mocks** is high on fast-feedback only. It's a *negative-value* test — it looks like coverage but provides little protection (tests the mocks), little refactor-resistance (any service refactor breaks it), and bad maintainability (8 mocks to maintain). Khorikov's specific recommendation: **delete these or replace with integration tests**.

## The high-quality test — what scores well on all four

The **best** tests (Khorikov calls these "output-based" or "state-based" unit tests over Domain Model & Algorithms):
- Test pure functions or aggregates with no mocked collaborators.
- Assert on **outputs** (return value, state after the call, events emitted) — not on internal method calls.
- Use the production API as the seam, with no implementation-detail dependencies.
- Run in microseconds.

The canonical Khorikov-style high-value test, for an event-sourced aggregate:

```kotlin
@Test
fun `cancelling a submitted Order emits OrderCancelled with the reason`() {
    // Given (state-based or event-stream)
    val order = aSubmittedOrder()

    // When
    val cancelled = order.cancel(reason = "customer request", at = now)

    // Then — output: state + events
    assertThat(cancelled.status).isEqualTo(CANCELLED)
    assertThat(cancelled.pendingEvents()).containsExactly(
        OrderCancelled(cancelled.id, reason = "customer request", cancelledAt = now),
    )
}
```

This test scores high on all four pillars: real protection (a regression in `cancel()` breaks it), real refactor-resistance (the test doesn't care how `cancel()` works internally), fast feedback (no Spring, no DB), excellent maintainability (3-line body, names self-document).

## The low-quality test — what scores badly on all four

```kotlin
@Test
fun `submit calls the repository and the publisher`() {
    val orders = mockk<OrderRepository>()
    val publisher = mockk<EventPublisher>()
    val pricing = mockk<PricingService>()
    val tax = mockk<TaxService>()
    val notif = mockk<NotificationService>()
    val service = OrderService(orders, publisher, pricing, tax, notif)

    every { pricing.priceFor(any()) } returns Money("99.00")
    every { tax.taxFor(any()) } returns Money("9.90")
    every { orders.save(any()) } returns Unit
    every { publisher.publish(any()) } returns Unit

    service.submit(aSubmitOrderCommand())

    verify { orders.save(any()) }
    verify { publisher.publish(any()) }
}
```

**Score**:
- Protection: low — the test sets up the mocks; the assertions verify the mocks were called; no real behaviour is tested.
- Refactor-resistance: low — extract one helper, change one method signature, the test breaks.
- Fast feedback: high — runs in ms.
- Maintainability: low — five mock setups + service constructor + verify calls.

**Recommendation**: delete this test. Replace with an integration test (`@SpringBootTest` narrow with real DB + real publisher in test mode) that exercises the *behaviour* — submit a command, assert on DB state + published event. Higher protection, higher refactor-resistance, slightly slower — net win.

## How to apply Khorikov in practice

When writing a new test:

1. **Quadrant**: which quadrant is this code in?
2. **Layer**: pick the test layer the quadrant earns (Domain Model → unit; Controllers → integration; Trivial → don't test; Overcomplicated → refactor or characterise).
3. **Pillars**: as you write, sanity-check — does it score high on protection? high on refactor-resistance? Or am I writing a "calls the mock" test that looks like coverage?

When reviewing a PR with tests:

1. For each test, **estimate the quadrant** of the code under test. Mismatched (e.g. unit test of Controllers-quadrant code) → flag in review.
2. **Count mocks per test**. > 3 → "explain why" in the PR.
3. Look for `verify { mock.method(...) }` assertions with no behavioural counterpart — flag.
4. Look for tests where the assertion is *the same shape* as the production code's last line — that's tautology, not test.

When auditing an existing suite:

1. Sample 10 random tests. For each, name the bug it would catch. If the answer is "none real" — quadrant-mismatch or pillar-failure; candidate for deletion.
2. Count `@SpringBootTest` classes. If > 25% of total — protection-vs-feedback tradeoff is wrong; refactor to slices.
3. Run the suite with random order (`MethodOrderer.Random`). Tests that fail under randomisation violate Independent (Martin Rule 11) — fix or delete.

## Khorikov vs Martin — they're complementary

Martin: "every test you write should be clean, F.I.R.S.T., BUILD-OPERATE-CHECK, named as a sentence".

Khorikov: "and *which* tests should you write at all? The ones that score high on protection-against-regressions and resistance-to-refactoring. For code in the Domain Model quadrant. Not for code in the Trivial quadrant. Not for code in the Overcomplicated quadrant (refactor first). For Controllers quadrant — integration, not unit."

Together: write *the right tests*, written *the right way*. Either alone is half the picture.

## Summary

- **Four quadrants** classify code by complexity × collaborators. Pick the test *layer* per quadrant.
- **Four pillars** classify tests by value. Filter *which tests* to keep / write / delete.
- **The killer combination**: code in the Domain Model quadrant + a test that scores high on all four pillars. Aim for those wherever the architecture permits; the rest of the suite supports them.
