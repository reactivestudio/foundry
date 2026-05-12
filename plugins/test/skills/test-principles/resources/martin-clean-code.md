# R. Martin, *Clean Code* Ch. 9 — Unit-Test Rules

The classical per-test discipline. Language-agnostic; the examples are Kotlin/JVM-ish for concreteness but the rules transfer to Python pytest, Go `testing`, Jest / Vitest, RSpec, anywhere.

> "Test code is just as important as production code. It is not a second-class citizen. It requires thought, design, and care. It must be kept as clean as production code." — Martin
>
> "If you let the tests rot, then your code will rot too." — Martin

## How to read this file

Each rule has:
- **Principle** — the one-sentence rule.
- **Bad / Good** — minimal examples.
- **Why** — the failure mode the rule prevents.
- **Exception** — when the rule legitimately bends.

The rules follow Martin's chapter order — which doubles as the order a test reader's eye moves through the suite: first the discipline that produces the tests (TDD), then the cleanliness that keeps them maintainable, then the structural patterns (BUILD-OPERATE-CHECK, DSL), then the per-test rules (one concept), then the suite-level F.I.R.S.T.

---

## Rule 1: The Three Laws of TDD

**Principle**: The TDD micro-cycle is three rules locked together:
1. You may not write production code until you have written a failing unit test.
2. You may not write more of a unit test than is sufficient to fail — and *not compiling* is failing.
3. You may not write more production code than is sufficient to pass the currently failing test.

The cycle is ~30 seconds long. The product is **dozens of tests per day, hundreds per month, thousands per year** — coverage produced *by construction* rather than chased afterwards.

**Why**: TDD couples specification and implementation in time. Code written *to pass a test* is *testable code* — small seams, narrow signatures, fewer side effects. Code written first and tested second tends to be untestable code with a thin layer of after-the-fact assertions.

**Exception**: Exploratory spikes. When the problem shape itself is unknown, write the spike, learn, throw it away, then write the tests first for the production version. **Don't graduate spike code to production without characterisation tests in front of it.** See `tdd-discipline.md` for the full exception map.

---

## Rule 2: Test Code Is First-Class

**Principle**: Test code is held to the **same standards of clarity, naming, structure, and design as production code**. Dirty tests are not an asset — they are a liability that grows until the team discards the entire suite.

**Bad** (sloppy fixture, generic names, swarm of low-level details):
```kotlin
@Test
fun testIt() {
    val c = Customer(UUID.randomUUID(), "x", LocalDate.now(), null, null, false)
    val o = Order(UUID.randomUUID(), c.id, OrderStatus.DRAFT, mutableListOf(), null, null)
    val r = svc.submit(o, listOf(OrderLine(UUID.randomUUID(), "sku-1", 1, BigDecimal("1.00"))))
    assertEquals(2, r.status.ordinal)
    assertTrue(r.id != null)
}
```

**Good** (named helpers, intent-revealing assertions):
```kotlin
@Test
fun `submitting a draft order with one line is accepted`() {
    val customer = givenCustomer()
    val outcome = submitOrderFor(customer, lines = listOf(orderLine()))

    assertThat(outcome).isSubmittedSuccessfully()
}
```

**Why**: Tests must change as production code evolves. If tests are dirty, every production change requires fighting through them — and the fight eventually loses. The team that discarded their tests didn't start by saying "let's stop testing"; they started by saying "let's not worry about test quality" — and the second decision implied the first.

**Heuristic**: if your senior reviewer reads the test and asks "what is this asserting?", the test isn't clean — regardless of whether it passes.

---

## Rule 3: Tests Enable the -ilities

**Principle**: It is unit tests — not architecture, not naming, not patterns — that keep production code **flexible**, **maintainable**, and **reusable**. The mechanism is simple: tests remove the *fear of change*. Code you can change without fear becomes the code you can clean up; code you can't, rots.

**Why**: Without tests, every change is a possible bug. With tests, change is verified by the suite — so improving structure becomes a near-free side effect of every feature. Tests are not *the goal*; they are the substrate that lets the other goals (clean architecture, naming, decomposition) compound over time.

---

## Rule 4: Readability Is the One Thing — for Tests, Even More So

**Principle**: "What makes a clean test? Three things. Readability, readability, and readability." Tests are read more than production code — once to write, then on every failure, every onboarding, every audit. Optimise mercilessly for the reader.

**Bad**:
```kotlin
@Test
fun testGetPageHieratchyAsXml() {
    crawler.addPage(root, PathParser.parse("PageOne"))
    crawler.addPage(root, PathParser.parse("PageOne.ChildOne"))
    crawler.addPage(root, PathParser.parse("PageTwo"))

    request.setResource("root")
    request.addInput("type", "pages")
    val responder = SerializedPageResponder()
    val response = responder.makeResponse(FitNesseContext(root), request) as SimpleResponse
    val xml = response.content

    assertEquals("text/xml", response.contentType)
    assertSubString("<name>PageOne</name>", xml)
    assertSubString("<name>PageTwo</name>", xml)
    assertSubString("<name>ChildOne</name>", xml)
}
```

**Good** (Martin's Listing 9-2 — same test, helpers extracted):
```kotlin
@Test
fun `page hierarchy XML lists every page`() {
    makePages("PageOne", "PageOne.ChildOne", "PageTwo")

    submitRequest(resource = "root", arg = "type:pages")

    assertResponseIsXML()
    assertResponseContains(
        "<name>PageOne</name>", "<name>PageTwo</name>", "<name>ChildOne</name>",
    )
}
```

**Why**: A reader who has to mentally execute ten lines of construction before the assertion has spent their attention budget *before* the point of the test. A hard-to-read test won't lead to a fast diagnosis. The whole point of a test is to **make failures cheap to investigate**.

---

## Rule 5: BUILD-OPERATE-CHECK (Given-When-Then)

**Principle**: Every test has three sections, in this order:
1. **BUILD** (Given) — set up the test data / world.
2. **OPERATE** (When) — perform the action under test.
3. **CHECK** (Then) — assert the observable outcome.

Blank lines between sections; helpers named in those vocabularies (`given...`, `make...`, `when...`, `then...`, `assert...`).

**Bad** (sections interleaved):
```kotlin
@Test
fun rendersXml() {
    val page = WikiPage("PageOne")
    crawler.addPage(root, PathParser.parse("PageOne"))
    val response = responder.makeResponse(ctx, request) as SimpleResponse
    crawler.addPage(root, PathParser.parse("PageTwo"))
    assertEquals("text/xml", response.contentType)
    val r2 = responder.makeResponse(ctx, request) as SimpleResponse
    assertSubString("<name>PageOne</name>", r2.content)
}
```

**Good**:
```kotlin
@Test
fun `xml response lists every requested page`() {
    // Given
    makePages("PageOne", "PageTwo")

    // When
    submitRequest(resource = "root", arg = "type:pages")

    // Then
    assertResponseIsXML()
    assertResponseContains("<name>PageOne</name>", "<name>PageTwo</name>")
}
```

**Why**: Tests are sentences. *Given* sets the subject, *When* states the verb, *Then* names the predicate. A test that doesn't fit this grammar is either testing the wrong thing or testing several things.

**Exception**: A test that is **purely about construction** (e.g., constructor invariant violations) may collapse to Given + Then — the `When` is the constructor call. That's fine; the three-section structure is a default, not a fence.

---

## Rule 6: Build a Domain-Specific Testing Language

**Principle**: Tests should speak the *domain*, not the *framework*. Rather than using production APIs directly in tests, build helper functions that express the test's intent at the domain level — `makePages("PageOne")` over `crawler.addPage(root, PathParser.parse("PageOne"))`. The DSL **emerges** from refactoring duplicated test code; **it is not designed up front.**

**Three layers of DSL**:
1. **Fixture builders** — `givenCustomer()`, `orderLine()`. Construct domain objects with sensible defaults overridable by named arguments.
2. **Workflow helpers** — `submitOrderFor(customer, lines)`. Wrap a use case so the test reads as a single sentence.
3. **Custom assertions** — `assertThat(order).isInSubmittedState()`. Encode domain meaning in the assertion.

**Why**: A test written against the testing DSL is more *robust*: when the production API changes (constructor adds a parameter, repository method renames), one helper updates and all tests follow. A test written against the raw API breaks once per affected test.

**Exception**: Building DSL up front, before duplication exists, is **premature** and almost always shapes it wrong. Wait for the third copy-paste — that's when the right primitive becomes obvious.

---

## Rule 7: The Dual Standard

**Principle**: Test code can be **less efficient than production code** — string concatenation in tight loops, allocating fresh fixtures per test, copying lists. Test code must **not** be **less clean**. The dual standard is about *efficiency*, not *cleanliness*.

**Acceptable in tests, unacceptable in production**:
- String concatenation in a loop instead of `StringBuilder`.
- Fresh `BigDecimal` / `LocalDateTime` per test instead of caching.
- Reflection where production would require a refactor.
- Allocating new collections per test method.

**Unacceptable in either**:
- Cryptic names.
- Long methods, deep nesting, mixed levels of abstraction.
- Copy-paste of more than three lines.
- Hidden mutation of shared static state.
- Commented-out code, dead test methods.
- Asserting nothing.

**Why**: Tests run in a test environment — different CPU/memory budgets. But the *readers* are the same humans. Cleanliness is for readers; efficiency is for runners. The two needs are independent.

---

## Rule 8: One Assert per Test — the Guideline

**Principle**: Each test has one and only one `assert` (or assertion chain). The advantage: each test reaches one quick, unambiguous conclusion.

**The catch**: when followed dogmatically, the rule creates duplication. Martin himself admits the cost can outweigh the benefit. **See Rule 9 for the deeper formulation.**

---

## Rule 9: Single Concept per Test — the Real Rule

**Principle**: A test should exercise **one concept**. Multiple concepts → multiple tests. The number of assertions is a *consequence*: if the concept needs three assertions to describe it, three is fine; if you reach for a fourth, the test is probably doing too much.

**Bad** (three concepts smashed together — Martin's `testAddMonths`):
```kotlin
@Test
fun testAddMonths() {
    val d1 = SerialDate.createInstance(31, 5, 2004)
    val d2 = SerialDate.addMonths(1, d1)
    assertEquals(30, d2.dayOfMonth)
    assertEquals(6, d2.month)

    val d3 = SerialDate.addMonths(2, d1)               // ← second concept
    assertEquals(31, d3.dayOfMonth)
    assertEquals(7, d3.month)

    val d4 = SerialDate.addMonths(1, SerialDate.addMonths(1, d1))  // ← third concept
    assertEquals(30, d4.dayOfMonth)
    assertEquals(7, d4.month)
}
```

**Good** (each concept its own test, named after the rule):
```kotlin
@Test
fun `adding one month to May 31 clamps to June 30`() {
    val date = SerialDate.of(31, 5, 2004).plusMonths(1)
    assertThat(date).isEqualTo(SerialDate.of(30, 6, 2004))
}

@Test
fun `adding two months to May 31 lands on the 31st of July`() {
    val date = SerialDate.of(31, 5, 2004).plusMonths(2)
    assertThat(date).isEqualTo(SerialDate.of(31, 7, 2004))
}

@Test
fun `incrementing one month twice from May 31 stays clamped`() {
    val date = SerialDate.of(31, 5, 2004).plusMonths(1).plusMonths(1)
    assertThat(date).isEqualTo(SerialDate.of(30, 7, 2004))
}
```

**When multiple asserts are OK** — when they all describe the *same* concept:
```kotlin
@Test
fun `the SubmitOrder response carries the new id, status, and total`() {
    val response = orders.submit(givenDraftOrder(total = "99.00"))

    assertSoftly {
        assertThat(response.id).isNotNull()
        assertThat(response.status).isEqualTo("SUBMITTED")
        assertThat(response.total).isEqualByComparingTo(BigDecimal("99.00"))
    }
}
```

The test fails as a single concept; the assertions name *what* "correctly" means.

**Why**: A test is a *named claim*. If the name describes one claim but the body checks three, the claim is wrong. Splitting one-concept-per-test gives every behaviour its own pinpoint.

**Exception**: A *symmetric* set of single-concept tests is a `@ParameterizedTest` — one method, many cases. That's "one concept, many examples", not "multiple concepts in one method".

---

## Rule 10: F.I.R.S.T. — Fast

**Target**: Single unit test < 50 ms. Full unit suite < 30 s locally.

**Why**: A 5-minute suite runs once per commit (if you're lucky). A 5-second suite runs **every save**.

**Exception**: Slice / Testcontainer tests legitimately take longer. The fix is **tiering** — fast `test` task (unit, < 30s) and a separate `integrationTest` task (slower, gated). The unit tier must stay fast.

---

## Rule 11: F.I.R.S.T. — Independent

**Target**: Tests pass in any order, in parallel, with one disabled.

**Why**: When tests depend on each other, a single failure cascades — diagnosis becomes "which broke first?" instead of "what broke?". Parallel execution becomes impossible. The suite turns into a fragile sequence.

**Heuristic**: random-order test runs (e.g., `MethodOrderer.Random`) periodically in CI. If randomisation breaks the suite, hidden dependencies exist — find and fix.

---

## Rule 12: F.I.R.S.T. — Repeatable

**Target**: Runs identically on laptop, CI, and a train without Wi-Fi.

**Common violations**:
- Network calls to real services.
- `LocalDate.now()` / `Instant.now()` — non-deterministic time.
- Default `Locale` / time zone — JVM-dependent.
- Random seeds left to `System.nanoTime()`.
- Tests that "usually pass" — flaky tests are *not* repeatable.
- H2 pretending to be Postgres.

**Fix**:
- Inject `Clock` and `Random`; in tests, `Clock.fixed(...)` and seeded `Random`.
- WireMock / stub for external HTTP.
- Testcontainers over local databases.
- Pin JVM `-Duser.timezone=UTC -Duser.language=en` in test config.

---

## Rule 13: F.I.R.S.T. — Self-Validating

**Target**: Boolean output. No log inspection. No manual diff. No "looks right to me".

**Bad**:
```kotlin
@Test
fun rendersReport() {
    val report = renderer.render(order)
    println(report)                    // ← human will inspect
    // (no assertion)
}
```

**Good**:
```kotlin
@Test
fun `report contains the order id and total`() {
    val report = renderer.render(order)

    assertThat(report).contains("Order #${order.id}", "Total: $99.00")
}
```

**Why**: A test requiring human inspection is a *demo*, not a test. It runs but doesn't verify. The suite containing it cannot fail automatically — which means it cannot block a regression in CI.

**Exception**: Approval / snapshot tests — the expected output is captured to a file, compared on every run; the diff is the assertion. Inspection only on diff.

---

## Rule 14: F.I.R.S.T. — Timely

**Target**: Tests written **just before** the production code that makes them pass.

**Why**: When tests are written after production code, two things happen — both bad:
1. The production code turns out hard to test (no seams). You hack around it instead of fixing it.
2. You miss cases you wouldn't have thought of without the test-first prompt.

**Exception**: Characterisation tests for legacy code — write the test to capture *current* behaviour, *then* refactor under it. See `tdd-discipline.md`.

---

## Rule 15: Tests as Documentation

**Principle**: A well-written test suite is the most accurate documentation of the system's behaviour. Test names, structure, and assertions together tell the next reader what the code does and what it does not do.

**Bad**:
```kotlin
@Test fun test1() { ... }
@Test fun testEdgeCase() { ... }
```

**Good**:
```kotlin
@Test fun `submitting a draft order with empty lines is rejected`() { ... }
@Test fun `submitting an order copies the customer's billing address`() { ... }
@Test fun `submitting twice with the same idempotency key returns the original order`() { ... }
```

A new joiner reading just the test method names should be able to **list the behavioural contract of the class**. If they can't, the names are doing the wrong job.

---

## Summary table — rules at a glance

| # | Rule | One-line test |
|---|---|---|
| 1 | Three Laws of TDD | Test failed (or didn't compile) before any production line was written. |
| 2 | Test code is first-class | Reviewer would sign off on the test the same way they sign off on prod code. |
| 3 | Tests enable the -ilities | The team refactors freely; tests are the safety net, not the obstacle. |
| 4 | Readability above all | A new reader gets the test's *intent* in one pass. |
| 5 | BUILD-OPERATE-CHECK | Three blank-line-separated sections, in order, named in the right vocabulary. |
| 6 | Domain-Specific Testing Language | The test reads as the domain, not the framework. |
| 7 | Dual standard | Test code may be less efficient; it may not be less clean. |
| 8 | One assert per test (guideline) | Assert count is *minimised*, not capped at 1. |
| 9 | Single concept per test | Each test is one named claim; one claim per name. |
| 10 | Fast | The full unit suite runs in seconds, not minutes. |
| 11 | Independent | The suite passes in any order, in parallel, with any subset enabled. |
| 12 | Repeatable | The suite passes the same way on a laptop, on CI, and on a train. |
| 13 | Self-validating | A failing test is red; a passing test is green; no human inspection of logs. |
| 14 | Timely | The production code's seams were chosen by the test that came before it. |
| 15 | Tests as documentation | The list of test names *is* the behavioural contract of the class. |
