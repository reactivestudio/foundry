---
name: test-principles
description: "Per-test discipline — the language-agnostic principles that make any test, at any layer, in any stack, read well and pull its weight. Owns: R. Martin's *Clean Code* Ch.9 rules (Three Laws of TDD, F.I.R.S.T. — Fast / Independent / Repeatable / Self-Validating / Timely, BUILD-OPERATE-CHECK / Given-When-Then, Domain-Specific Testing Language, dual standard, one assert vs single concept), Vladimir Khorikov's *Unit Testing: Principles, Practices and Patterns* fundamentals (the four quadrants — Trivial / Controllers / Domain Model & Algorithms / Overcomplicated — and the four pillars of a good test — protection-against-regressions / resistance-to-refactoring / fast-feedback / maintainability), and TDD discipline (when to apply, when to bend, characterisation tests for legacy code, the rules vs the spirit). Use this skill whenever the user writes a new test, refactors a test method, reviews a PR with a test that takes three reads to understand, splits one mega-test into single-concept tests, builds a test DSL, fixes a flaky / slow / interdependent test, decides whether multi-assert is one concept or many, audits a suite for F.I.R.S.T. violations, names a test that currently says `test1()` / `shouldWork()`, untangles BUILD-OPERATE-CHECK that's been smashed into one wall of mechanics, asks 'is this test worth keeping?' (Khorikov's four pillars answer that), translates a Martin-Ch.9 Java example into idiomatic Kotlin / Spring, refuses to write a test that mocks the world, debates 'should we TDD this?', or hardens a test that depends on `Thread.sleep` / `Instant.now()` / shared static state. This skill is **language-agnostic foundation**; for layer-specific tooling (Kotlin idioms, Spring slices, Testcontainers, ArchUnit) see test-unit / test-integration / test-acceptance / test-contract / test-architecture; for shape selection (pyramid vs diamond) see test-strategy."
risk: safe
source: "Adapted from R. Martin, *Clean Code* (2008) Ch.9 'Unit Tests', and Vladimir Khorikov, *Unit Testing: Principles, Practices and Patterns* (Manning, 2020), with house extensions"
date_added: "2026-05-12"
---

# Test Principles — Per-Test Discipline (Language-Agnostic)

This skill is the **foundation**: what makes a *single* test, at *any* layer, worth keeping. The strategic decisions (pyramid vs diamond, which behaviour goes where) live in `test-strategy`. The tooling decisions (MockK, AssertJ, Testcontainers, slices) live in the layer-specific skills. **This** skill is the discipline that applies to every test in the suite regardless of layer or language.

> "A test is the *executable specification* of a behaviour and the *safety net* that lets the production code change without fear. Both jobs depend on the test being readable, fast, deterministic, and pulling its weight." — house ethos

A suite where every individual test follows these principles compounds: refactoring is cheap, failures are diagnostic, and the test suite is the most trustworthy documentation of the system. A suite where they don't compounds the opposite way: tests rot, the team stops trusting CI, and within a year someone proposes "we should just rewrite the suite". Both outcomes are downstream of how individual tests are written.

## Use this skill when

- Writing a new unit test — *before* the first `@Test` / `it(...)` line.
- Refactoring a test method that takes ten lines of setup to express one assertion.
- Reviewing a PR and you see a test you have to read three times to understand the *intent*.
- A test in CI fails only on Mondays, only in parallel runs, or only on someone else's laptop — the **F.I.R.S.T.** violations are written on the symptom.
- Deciding whether to split a test: *one assert* or *one concept*?
- A test method has three sections separated by blank lines — likely three tests pretending to be one.
- The same fixture-building scaffolding appears in 20 tests — time to extract a testing DSL.
- A test inspects a log line, sleeps for "enough" milliseconds, or reads a file from disk — **self-validating** and **repeatable** are at risk.
- A test mutates a static field, depends on JVM time zone, or relies on `H2` masquerading as Postgres — **repeatable** is broken.
- Auditing a test suite before a refactor — the suite must be trustworthy *before* you start moving code around.
- Asking *"is this test worth keeping?"* — Khorikov's four pillars (regression protection, refactor resistance, fast feedback, maintainability) answer it.
- Debating whether to apply TDD to a specific feature — this skill names when the cycle pays and when it doesn't.

## Do not use this skill when

- Picking *what layer* to test at (controller slice vs service vs integration) — use `test-strategy`. That skill picks the *level*; this skill makes each test at every level read well.
- Picking *what shape* the suite should be (pyramid vs diamond) — also `test-strategy`.
- Looking up a Kotlin idiom (`assertSoftly`, MockK DSL, backtick names) — use `test-unit` (or the layer-specific skill).
- Configuring Spring slice annotations / Testcontainers / `@MockkBean` — use `test-integration` / `test-acceptance`.
- Designing the production code being tested — use `clean-code-functions`, `clean-code-naming`, `clean-code-error-handling`. Clean tests can't rescue badly designed production code; they can only call it.
- Architecture-level test concerns (module fitness, ArchUnit rules, Modulith) — use `test-architecture`.

## Selective Reading Rule

Read the file that matches the question you're answering.

| File | Description | When to read |
|---|---|---|
| `resources/martin-clean-code.md` | Martin Ch.9 rules deepened — Three Laws of TDD, Tests Enable the -ilities, Readability, BUILD-OPERATE-CHECK, Domain-Specific Testing Language, Dual Standard, One Assert vs Single Concept, F.I.R.S.T. expanded with examples. Read first. | Writing or reviewing any test; foundation for everything else. |
| `resources/khorikov-fundamentals.md` | Khorikov's four quadrants (Trivial / Controllers / Domain Model & Algorithms / Overcomplicated) and four pillars of a good test (protection against regressions / resistance to refactoring / fast feedback / maintainability). The "should this test even exist?" filter. | When the question is "is this test worth keeping?" or "should this code be tested at all?". |
| `resources/tdd-discipline.md` | TDD as a default vs as a religion — when the three laws apply, when characterisation comes first, when a spike legitimately skips it, how to apply TDD to legacy code, the "tests force good design" hypothesis. | When the question is "should we TDD this?" / "how do I write the test if the production code doesn't exist yet?" / "we have a legacy class with no tests — what now?". |

## The seven core principles — applies to every test

These principles are non-negotiable. They predate Kotlin, predate Spring, and apply equally to a Python unit test, a Go integration test, and a React component test.

1. **Test code is first-class.** Same standards of clarity, naming, and structure as production code. Slightly different rules around micro-efficiency — *not* around cleanliness. If you wouldn't ship that code, you shouldn't ship that test.

2. **Three Laws of TDD.** *(i)* No production code until a failing unit test exists. *(ii)* Only as much test as needed to fail — *not compiling* counts as failing. *(iii)* Only as much production code as needed to pass. The cycle is seconds long; the product is exhaustive coverage produced *by construction*, not chased afterwards. The laws are the default; `resources/tdd-discipline.md` covers when to bend.

3. **Readability above all.** What makes a test clean is clarity, simplicity, and density of expression — *more* so than in production code. A test is a worked example for the next reader; if reading it doesn't immediately tell them what the behaviour is, the test failed before it ever ran.

4. **BUILD-OPERATE-CHECK (Given-When-Then).** Every test has three sections, in this order, separated by blank lines. *Build* the world → *operate* on it → *check* the outcome. Helpers named in those vocabularies (`given...`, `submit...`, `assert...`). The pattern is so reliable that a test missing one of the three is almost certainly broken.

5. **Domain-Specific Testing DSL.** Tests should speak the *domain*, not the framework. `submitOrder(customer, lines)` over `orderService.submit(SubmitOrderCommand(customer.id, lines.map { ... }, clock.instant()))`. The DSL is **not designed up front** — it *emerges* through refactoring duplicated test code.

6. **Single Concept per Test.** "One assert per test" is a guideline that often pays off but isn't a law. The deeper rule: a test method should exercise **one concept**, with **as few assertions as needed to describe that concept**. Multiple concepts → multiple tests (or `@Nested` / parameterised tests).

7. **F.I.R.S.T.** Tests are **F**ast (else they don't run), **I**ndependent (else one failure cascades), **R**epeatable (else they aren't trustworthy), **S**elf-validating (boolean output, not log inspection), **T**imely (written before or with the production code, not afterwards). Non-negotiable.

## Khorikov's four pillars — the filter for "is this test valuable?"

Khorikov adds a second dimension to the Martin discipline: **which tests deserve to exist at all**. Each test has a value along four axes:

1. **Protection against regressions** — does this test catch real bugs when they're introduced? A test with no protection is dead code with a green tick.
2. **Resistance to refactoring** — does the test break when *implementation* changes but *behaviour* doesn't? A test with low resistance breaks every legitimate refactor and erodes trust in the suite.
3. **Fast feedback** — does the test run quickly enough to be run on every save? Slow tests run rarely; rare tests catch less.
4. **Maintainability** — is the test cheap to keep working as the codebase evolves?

These are *tradeoffs*, not all-true / all-false. A pure unit test of a domain method scores high on all four. A heavy `@SpringBootTest` scores high on protection-against-regressions but low on fast-feedback and (often) maintainability. An over-mocked service test scores high on fast-feedback but low on protection (it tests the mocks).

**The most expensive mistake**: tests with **high fast-feedback** (unit, fast) but **low protection** (they test mocks) and **low refactor-resistance** (they break on any refactor). These tests *feel* like coverage but provide negative value. See `resources/khorikov-fundamentals.md` for how to spot them.

## F.I.R.S.T. — quick targets

| Letter | Target | Action when violated |
|---|---|---|
| **Fast** | A unit test < 50 ms; the unit suite < 30 s locally | Profile slow ones; split tiers — unit < integration < e2e |
| **Independent** | Tests pass in any order, in parallel, with one disabled | No `static` mutable state; no shared file paths; truncate or rollback the DB between tests |
| **Repeatable** | Runs identically on laptop, CI, and a train without Wi-Fi | Pin time (`Clock`), seed randomness, freeze the time zone, Testcontainers over local DBs, WireMock over real HTTP |
| **Self-validating** | One green/red bit per assertion — no human log reading | Real assertions (AssertJ / Kotest matchers); **never** `println` / `System.out` / `logger.info` for verification |
| **Timely** | Test written before / with the production code, not after | Three Laws of TDD, even if loosely applied; characterisation test before any refactor |

## BUILD-OPERATE-CHECK — the canonical layout

Every test reads in three sections, in this order, with blank lines between them. The vocabulary you name the helpers in (`given...`, `make...`, `when...`, `submit...`, `then...`, `assert...`) makes the structure jump off the page.

```kotlin
@Test
fun `submitting an order with empty lines is rejected`() {
    // Given (BUILD)
    val customer = givenCustomer(name = "Ada")
    val order = Order.draft(customer.id)

    // When (OPERATE)
    val outcome = order.submit(lines = emptyList())

    // Then (CHECK)
    assertThat(outcome).isInstanceOf(Outcome.Rejected::class.java)
    assertThat(order.status).isEqualTo(OrderStatus.DRAFT)
}
```

The vocabulary doesn't need explicit `// Given / When / Then` comments if the helpers name themselves — but the **blank-line separation** is non-negotiable. The reader's eye uses it.

## Smell → fix quick reference (cross-stack)

| Smell | Fix |
|---|---|
| Test method > 20 lines | Extract Given/When/Then helpers; the test should read as 3-6 lines. |
| Test name is `test1()` / `testFoo()` / `shouldWork()` | Rename to a sentence: `\`rejects negative quantities\`` / `it('rejects negative quantities')`. |
| `// arrange / // act / // assert` comments naming the sections | The comments are the section names — extract them into named helpers; delete the comments. |
| Cryptic positional fixture (`Customer(UUID.randomUUID(), "Ada", ..., null, null, false)`) | Builder helper with named defaults: `givenCustomer(name = "Ada")`. |
| The same 8-line Given block in many tests | Extract a `@BeforeEach` *or* a builder — `@BeforeEach` if every test needs it, builder if only most do. |
| Test that sleeps (`Thread.sleep(200)`) | Inject a `Clock` (or equivalent); advance time deterministically. |
| Test that depends on test order | One of the tests is leaking state; fix the leak, not the order. |
| Test asserts log content (not part of a contract) | Either: assert on the *behaviour* the log reflects, or use a log-capture extension for *intentional* log contract tests. |
| 4+ asserts that exercise 3+ concepts | Split into per-concept tests, or group symmetric ones under parameterised test. |
| `try { ... ; fail() } catch (e: SomeException) { ... }` | Use the library: `assertThrows<SomeException> { ... }` / `assertThatThrownBy { ... }` / `expect.toThrow`. |
| Mock setup so deep that the test mostly verifies mocks | The collaborator is the wrong seam; test through a higher-level entry point or refactor production code. |
| One test that "covers" 6 method paths via a giant `when` block | Each branch is a concept; one test per branch, or parameterised. |
| Test uses `LocalDate.now()` / `Instant.now()` directly | Inject `Clock`; in test, `Clock.fixed(...)` or mutable test clock. |
| Test that "passes but the log looks wrong" | It didn't pass — convert the log inspection into a real assertion. |

## Test-writing anti-patterns

- **Writing tests after the fact for code that wasn't designed to be tested.** Untestable production code is a *design* defect. The cleanest test won't rescue it; refactor the production code (or accept lower coverage and document why).
- **Asserting nothing.** A test that runs the code and exits is a smoke test, not a unit test. It catches uncaught exceptions only.
- **Mock-the-world tests.** When the test mostly programs `every { … } returns …` and `verify { … }`, the production seam is too coarse. Either find a higher-fidelity test (integration with real infra) or refactor the seam.
- **Snapshot-everything tests.** Approval / snapshot testing is a strong tool for *stable serialised output* (JSON, HTML), but a terrible default — it captures whatever you committed, including the bugs. Use it where the output is the contract; not as a substitute for assertions.
- **Premature test-DSL design.** Do not invent a `TestKit` class on day one. The DSL *emerges* — round one, copy-paste; round two, extract; round three, name it.
- **Coverage as the goal.** 100% line coverage with concept-free assertions is worse than 70% with surgical, named tests. Coverage is a *symptom* of test discipline, not the goal.
- **Refactoring tests to "clean them" while disabling them temporarily.** A disabled test is a deleted test. Either keep it green through the refactor or delete it.
- **`@DirtiesContext` as a normal tool.** A giant flag that the test is leaking. Find the leak.
- **Same test fails for two reasons.** "It's flaky" is a *property of the test*, not of the system. Quarantine, root-cause, fix; **do not** retry-until-pass.
- **Testing private methods directly via reflection.** Either expose the value the test cares about as a domain method on the aggregate, or build a custom assertion. The private method's behaviour shows up through the public one.
- **Testing the framework, not the rule.** A test that ensures `@Entity` fields map correctly is a JPA test, not a domain test. Trust the framework; test your code.

## Tests as documentation

A well-written test suite is the most accurate documentation of the system's behaviour. Names, structure, and assertions together tell the next reader what the code does and what it does not do.

The list of test names *is* the behavioural contract of the class. A new joiner reading just the test method names should be able to **list the behavioural contract of the class**. If they can't, the names are doing the wrong job.

```kotlin
class OrderTest {
    @Test fun `a draft order has no submitted timestamp`() { ... }
    @Test fun `submitting a draft order sets the submitted timestamp`() { ... }
    @Test fun `submitting an already-submitted order is rejected`() { ... }
    @Test fun `cancelling an order moves it to CANCELLED`() { ... }
}
```

Read that list aloud as if reporting to the product owner. If the sentences make sense, the suite is documentation. If they don't, the names are doing the wrong job.

## Related skills

- `test-strategy` — picks the *shape* (pyramid / diamond / inverted / honeycomb / trophy) and *layer allocation* (what behaviour goes where). This skill makes each test inside the chosen shape read well.
- `test-unit` — Kotlin / Spring tooling at the unit layer (JUnit, AssertJ, MockK, Kotest, `runTest`, fixture factories).
- `test-integration` — Testcontainers, Spring slices, `@MockkBean`, transactional semantics.
- `test-acceptance` — application-service-level tests, in-memory adapters, use-case-level Gherkin / BDD.
- `test-contract` — consumer-driven contracts (Pact, Spring Cloud Contract).
- `test-architecture` — ArchUnit / Modulith / Pitest fitness functions and mutation testing.
- `clean-code` — the smell vocabulary for production code (Rigidity / Fragility / Train wreck / Primitive obsession / God class). Clean tests can't rescue badly-designed production code; this skill assumes the production code follows that discipline.
- `clean-code-functions`, `clean-code-naming`, `clean-code-error-handling` — production-code discipline that makes testing cheap in the first place.
- `methodology-verification` — after every test refactor, re-run the suite in the current session and check the output. "Should pass" is not evidence.
- `debugging-systematic` — when a test fails mysteriously, root-cause investigation rather than masking with retries.

## Limitations

- **Numbers are heuristics.** "< 50 ms per unit test" is a strong default; a slice test legitimately takes hundreds of ms. Apply F.I.R.S.T. *proportionally* — a slice test can be slower than a unit and still be Fast *for its tier*.
- **TDD is a default, not a religion.** The three laws are excellent guidance when behaviour is well-defined; for genuine exploratory spikes, write the spike, validate by hand, *then* write characterisation tests before the spike code is allowed to graduate to production.
- **Some code is structurally hard to unit-test.** Framework callbacks, JPA criteria builders, generated proto handlers, native interop. Where the framework owns the seam, accept a slice or an integration test; do not bend the production code into a shape solely to please a unit test.
- **"One concept per test" is a guideline, not a fence.** A workflow test that asserts on three observable outcomes of a *single* domain operation (the returned id, the published event, the state transition) can legitimately be one test with `assertSoftly`.
- **Property-based / fuzzed tests bend readability.** A property test (`forAll`) deliberately tests a *class* of inputs, not a single case — the *property* is the readable concept.
- **Team consistency wins over micro-optimum.** If the project uses Kotest matchers, conform; if it uses AssertJ, conform. A single test written against the grain harms readability more than any single rule helps it.
