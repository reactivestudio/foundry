---
name: test-unit
description: "The unit layer of a Kotlin/Spring suite — pure-JVM tests with no Spring context, no DB, no network. What gets unit-tested (domain aggregates, value objects, pure algorithms, domain services, specifications, anti-corruption-layer translation), what does not (anaemic entities, framework correctness, anything Khorikov puts in the Trivial / Controllers / Overcomplicated quadrants), and the tooling discipline that keeps these tests fast and information-dense (JUnit 5 + AssertJ + MockK as the house default; Kotest where property-based / data-driven / spec-style earns its place). Use when writing a new unit test for a domain method, refactoring a unit test that mostly programs mocks, picking unit vs integration for a piece of code (Khorikov quadrants answer it), deciding sociable vs solitary unit tests, deciding mocks vs fakes vs in-memory adapters, applying Khorikov's *output-based / state-based / communication-based* classification to pick the test style with the highest pillar score, naming a Kotlin unit test (backtick sentence style), structuring fixtures (`anOrder` / `a/an` factories with `copy()`), grouping with `@Nested`, parameterising with `@ParameterizedTest` or Kotest `withData`, asserting with AssertJ chains or Kotest matchers, freezing time via injected `Clock`, testing coroutines with `runTest` and virtual time, picking when (rarely) a Spring annotation is still a unit test (`@JsonTest` for pure serializer rules; pure `data class` `@ConfigurationProperties` validation), or when the test you're about to write actually belongs at a sibling layer. For shape / pyramid-vs-diamond selection see test-strategy; for per-test F.I.R.S.T. / readability / DSL discipline see test-principles; for slice tests (`@WebMvcTest`, `@DataJpaTest`) + Testcontainers see test-integration; for use-case-level orchestration see test-acceptance; for cross-service Pact-style contracts see test-contract; for ArchUnit / Modulith / Pitest fitness see test-architecture. Use this skill whenever the user writes a new unit test, refactors a unit test, picks unit vs integration for a piece of code, reviews a unit test in a PR, or audits the unit layer of an existing suite."
risk: safe
source: "Adapted from R. Martin *Clean Code* Ch.9, V. Khorikov *Unit Testing: Principles, Practices and Patterns* (Manning, 2020), plus Kotlin/Spring house experience"
date_added: "2026-05-12"
---

# Test Unit — Pure-JVM Tests, the Pyramid Base

This skill owns the **unit layer**: pure-JVM tests that exercise one piece of behaviour with no Spring context, no DB, no network. The cheapest, fastest, most diagnostic tests in the suite — when they're written against code that earns them.

> *A unit test is a small, fast, deterministic check on a piece of code that has somewhere worth checking. Unit-testing code that has nothing worth checking is busywork; unit-testing code that has too much worth checking (god services, controllers wiring six ports) tests the mocks, not the rule. The whole skill is knowing which code is in the first set and writing for it ruthlessly.*

The unit layer is the base of the pyramid in a Domain-Model service, and a thinner slice (but still a real layer) in Diamond / Honeycomb services. The strategy lives in `test-strategy`; the per-test discipline lives in `test-principles`; *this* skill owns the **content** of those tests in a Kotlin / Spring codebase.

## Use this skill when

- Writing a new unit test for a domain aggregate, value object, domain service, specification, ACL, or pure algorithm.
- Refactoring a unit test that mostly programs `every { … } returns …` and `verify { … }` — the seam is probably wrong.
- Picking unit vs integration for a piece of code — Khorikov's quadrants answer it (Domain Model & Algorithms → unit; Controllers → integration; Trivial → don't test; Overcomplicated → refactor first).
- Deciding **sociable vs solitary** unit tests — when to use the real collaborator (sociable) and when to substitute (solitary).
- Deciding **mocks vs fakes vs in-memory adapters** — mocks for output / communication checks; fakes for stateful collaborators the test exercises across multiple calls.
- Reaching for **Khorikov's output-based / state-based / communication-based** classification to pick the highest-pillar test style.
- Naming a Kotlin unit test (backtick sentence style); structuring fixtures (`a/an` factories with named defaults + `copy()`); grouping with `@Nested`.
- Parameterising with `@ParameterizedTest` or Kotest `withData`; asserting with AssertJ chains, `assertSoftly`, or Kotest matchers.
- Freezing time with an injected `Clock` (or `MutableClock`); testing coroutines with `runTest` and virtual time.
- Deciding the rare case when a Spring annotation is still a *unit-flavoured* test (`@JsonTest` for a single Jackson serializer; pure `@ConfigurationProperties` `init { require(...) }`).
- Auditing the unit layer of an existing suite — what's pulling its weight, what's testing the mocks.

## Do not use this skill when

- Picking the **shape** of the suite (pyramid vs diamond vs honeycomb vs trophy) — that's `test-strategy`. This skill is invoked after the shape says "this code earns unit tests".
- Working on the **per-test discipline** (F.I.R.S.T., readability, DSL emergence, single concept, dual standard) — that's `test-principles`. Read it before you start writing tests in earnest.
- Writing a **slice test** (`@WebMvcTest`, `@DataJpaTest`, `@JsonTest` for more than a single serializer, `@RestClientTest`) or anything with Testcontainers — that's `test-integration`. The moment the test needs ANY Spring bean wiring beyond a single isolated annotation, leave this skill.
- Writing **use-case-level** tests through application services with in-memory adapters and a recording publisher — that's `test-acceptance`.
- Writing **consumer-driven contract** tests (Pact, Spring Cloud Contract) — that's `test-contract`.
- Writing **fitness functions** (ArchUnit, Modulith) or mutation tests (Pitest) — that's `test-architecture`.

## Selective Reading Rule

Read the file that matches the decision you're making. Don't read all three.

| File | Description | When to read |
|---|---|---|
| `resources/general.md` | Language-agnostic unit-test discipline — what counts as a unit, sociable vs solitary, mocks vs fakes vs stubs vs dummies, Khorikov's output-based / state-based / communication-based classification, when NOT to write a unit test (the four quadrants applied), property-based framing, cross-language anti-patterns. | First read — the vocabulary and mental model that the tooling sits on top of. |
| `resources/kotlin.md` | The Kotlin tooling stack — JUnit 5 + AssertJ + MockK as default, Kotest as a specialist tool. Backtick names, `a/an` factories, `copy()` for derived fixtures, extension-function DSLs, `@Nested`, `assertSoftly` / `assertAll`, `@ParameterizedTest` and Kotest `withData`, `assertThrows<T>` / `assertThatThrownBy` / `shouldThrow`, `Result<T>` / sealed `Outcome`, `runTest` + virtual time, MockK suspend support, `Clock` injection. | When you're writing or reviewing a Kotlin unit test and need the idiom. |
| `resources/spring.md` | The Spring-at-the-unit-layer edge cases — overwhelmingly "go to test-integration". The two narrow exceptions (`@JsonTest` for a *single* Jackson serializer; `data class` `@ConfigurationProperties` validation tested without Spring). The rule: any Spring bean wiring → not a unit test. | When tempted to put a Spring-touching test in this layer; this file usually says "wrong layer, go to test-integration". |

## What counts as a unit test

The word "unit" has been argued about for twenty years. The pragmatic position in this codebase:

- **Sociable unit test** — the unit under test uses its *real* collaborators, including other domain classes (aggregates, value objects, pure services). The "unit" is the *behaviour*, not the *class*. This is the **default** for domain tests — `Order.submit(...)` uses real `OrderLine`, real `Money`, real `OrderStatus`. Test doubles only appear for collaborators that escape the JVM (clocks, randomness, time-aware services, infrastructure ports).
- **Solitary unit test** — the unit under test is isolated by substituting *all* of its collaborators with doubles. Useful for application services / domain services that orchestrate other components — exactly **one** real class, everything else doubled. Use sparingly; over-isolation drifts toward "testing the mocks".

The **Khorikov axis** — output-based / state-based / communication-based — is the more useful classification:

| Style | What it asserts on | Pillar profile | When it fits |
|---|---|---|---|
| **Output-based** | The function's return value, given the input. No state mutation, no side effects. | Strongest on every pillar — high protection, high refactor-resistance, fast, maintainable. The gold standard. | Pure functions, value objects, specifications, calculation methods, pure aggregate transitions returning a new state. |
| **State-based** | The system's state *after* the operation. Mutation is observed via a query. | Strong, but more coupled to internals than output-based. | Mutable aggregates (`order.submit()` then read `order.status`), stateful in-memory fakes. |
| **Communication-based** | The calls the unit made to its collaborators. Asserted via mock `verify { … }`. | Weakest — couples the test to the implementation's call pattern. Easy to over-specify. | When the call *is* the contract — publishing an event, recording an audit log entry. Otherwise prefer output-based or state-based. |

**Rule of thumb**: if you can rephrase the test as output-based, do so. If you can't, state-based. Communication-based last, and only when the call is the actual contract being checked.

## The default unit test shape

BUILD-OPERATE-CHECK with blank-line separators (full discipline in `test-principles`). At the unit layer this looks like:

```kotlin
class OrderTest {

    @Test
    fun `submitting a draft Order with at least one line moves it to SUBMITTED and emits OrderSubmitted`() {
        val order = aDraftOrder(lines = listOf(orderLine()))

        val submitted = order.submit(submittedAt = "2024-01-15T10:00:00Z".toInstant())

        assertThat(submitted.status).isEqualTo(SUBMITTED)
        assertThat(submitted.pendingEvents()).containsExactly(
            OrderSubmitted(submitted.id, "2024-01-15T10:00:00Z".toInstant()),
        )
    }
}
```

Three sections, blank lines, ubiquitous-language name, `a/an` fixture, time as a parameter. No `mockk { }`, no Spring annotation, no `@BeforeEach` boilerplate. Reads in seven seconds.

## What unit tests are FOR (the catalogue)

These are the categories of code where unit tests have the highest ROI. Khorikov's *Domain Model & Algorithms* quadrant.

- **Aggregate behaviour** — every domain transition on an aggregate (`Order.submit`, `Reservation.confirm`, `Invoice.applyPayment`) is one or two unit tests: happy path + invariant violation. Asserts on the **new state** AND the **emitted domain events** (the event is the contract; assert it). See `resources/kotlin.md` and the related `ddd-tactical-patterns` for the production-side patterns.
- **Value object invariants** — every `data class` with `init { require(...) }` and every `@JvmInline value class` deserves at least one positive and one negative test. Cheapest tests in the suite; catch real bugs (a refactor that relaxes a `require` is exactly the kind of thing line-coverage misses).
- **Pure algorithms** — pricing, scheduling, ranking, parsing, encoding, conflict resolution. High decision density per line; unit tests are the only level where each branch is cheap to pin down. Property-based testing earns its place here.
- **Domain services** — stateless operations that span multiple aggregates (`TransferFundsService.transfer(from, to, amount, at)`). No infrastructure dependencies. Tested as pure functions.
- **Specifications** — query-only domain objects encoding a rule (`OrderEligibleForRefundSpec.isSatisfiedBy(order, now)`). Short, fast, exhaustive on the boundary.
- **Anti-corruption-layer translation** — the ACL converts a vendor's response type to the domain's outcome type (`StripeCharge` → `PaymentOutcome.Settled / .Rejected`). One test per outcome variant; SDK mocked at the SDK seam.
- **Pure helpers in the domain** — date arithmetic, string normalisation, code-table lookups. Trivial-but-useful.

## What unit tests are NOT for

These categories produce tests with high cost and low value. Khorikov's *Trivial*, *Controllers*, and *Overcomplicated* quadrants.

- **Anaemic data-bag entities** — `@Entity class OrderRecord(...)` with only getters/setters. The decisions live in the service + DB; the entity has nothing to assert. Don't unit-test it; the value is in `test-integration` slice tests.
- **Framework correctness** — that `@Entity` fields map correctly, that `@JsonProperty` names are honoured by Jackson, that Spring autowires the right bean. **Trust the framework.** Test your code. (The two narrow Spring exceptions live in `resources/spring.md`.)
- **Controllers / orchestrators wiring 6 ports** — Khorikov's *Controllers* quadrant. Unit-testing them requires programming six mocks; the test becomes the mock setup. Move to `test-integration` (`@WebMvcTest`) or `test-acceptance` (application service + in-memory adapters).
- **Anything that needs a real DB to be meaningful** — Postgres JSONB queries, JPA cascade behaviour, transactional semantics, optimistic locking. `test-integration` with Testcontainers.
- **Anything that needs real HTTP** — third-party API integration. Mock at the SDK boundary (an ACL test) OR use WireMock in `test-integration`.
- **Async / event-handler wiring** — that the listener got registered, that the queue routes the message. `test-integration`.
- **Overcomplicated god services** with 14 collaborators and 800 lines. The smell is the *production code*. Refactor first; test second.
- **Code in the Trivial quadrant** — one-line delegations, getter/setter pairs without invariants, plain DTOs without `init` validation. The test exists to silence a coverage tool; it has zero protection-against-regressions value.

## Anti-patterns at the unit layer

- **Mock-the-world.** When the test sets up six `every { } returns …` lines, the seam is wrong. Either move the test up one level (`test-acceptance` with in-memory adapters) or refactor the production code to a smaller seam.
- **Testing the mock.** A test whose body is `every { repo.findById(id) } returns order; assertThat(repo.findById(id)).isEqualTo(order)` asserts MockK works. MockK works. Delete the test.
- **Testing private methods via reflection.** The private method's behaviour shows up through the public one. If it doesn't, expose a new public method on the aggregate (often the right design move) and test that.
- **Communication-based tests where output-based would do.** `verify { repo.save(order) }` couples the test to *the call*. If `save` could be reordered, batched, or skipped (and the *outcome* is what matters), assert on the state, not on the call.
- **Sociable test that loads a real DB.** That's an integration test wearing a unit-test costume. If the test needs a real DB, accept the move to `test-integration`.
- **`runBlocking { delay(100) }` inside a coroutine unit test.** Real wait — slow, flaky. Use `runTest` + `advanceTimeBy`.
- **`Thread.sleep(...)` to "let the async thing finish".** The async thing should be deterministic in tests. Inject a `Clock` and / or a single-threaded executor.
- **Snapshot-everything for non-serialised types.** Snapshot tests fit serialised contracts (JSON, HTML). For domain objects, write actual assertions on the fields that matter.
- **Asserting on log output** instead of behaviour. Logs are observability, not contract. Convert to a real assertion on the observable outcome.
- **`@SpringBootTest` "because the IDE generated it"**. That's a full-context test masquerading as a unit. Delete and replace with a pure unit (or, if the test genuinely needs context, with the smallest slice in `test-integration`).
- **`OrderTest.testAllTransitions()`** walking through draft → submitted → cancelled in one method. Each transition is one concept. Split.

## Related skills

| Skill | Relationship |
|---|---|
| `test-strategy` | Picks the **shape** (pyramid / diamond / honeycomb) and what proportion of the suite belongs at the unit layer at all. This skill is invoked once strategy says "this code earns a unit test". |
| `test-principles` | The per-test discipline — F.I.R.S.T., BUILD-OPERATE-CHECK, readability, DSL emergence, single concept, dual standard. Foundation under everything in this skill. |
| `test-integration` | Slice tests (`@WebMvcTest`, `@DataJpaTest`) + Testcontainers + WireMock. Sibling layer. The moment the test needs Spring bean wiring beyond a single isolated case, leave this skill and go there. |
| `test-acceptance` | Use-case-level tests through application services with in-memory adapters / recording publisher. The other sibling to *this* layer. |
| `test-contract` | Consumer-driven contracts (Pact, Spring Cloud Contract) for cross-service compatibility. Shape-independent. |
| `test-architecture` | ArchUnit / Modulith fitness functions, Pitest mutation testing. Quality gates orthogonal to layer. |
| `ddd-tactical-patterns` | The production-code shapes (aggregates, value objects, specifications, domain services) that this skill's tests exercise. The patterns make unit-testing cheap; the tests pin down the patterns. |
| `clean-code-functions`, `clean-code-naming`, `clean-code-error-handling` | Production-code discipline that makes testing cheap in the first place. A unit test of a 200-line god method is suffering; the cure is in those skills, not in MockK. |
| `methodology-verification` | After every test refactor, re-run the suite in the current session and check output. "Should pass" is not evidence. |
| `methodology-karpathy-guidelines` | The always-on coding discipline — smallest change, no speculation, no premature abstraction. Applies to test code too: don't build a `TestKit` on day one; the DSL emerges. |
| `debugging-systematic` | When a unit test fails mysteriously (intermittent, only-on-CI, only-in-parallel), root-cause investigation rather than `@RepeatedTest(10)`. |

## Limitations

- **The boundary between unit and integration is judgement.** A test that exercises an aggregate and an in-memory repository is *clearly* unit. A test that exercises a thin Jackson serializer via `@JsonTest` is *almost* unit (covered in `resources/spring.md`). Where it's borderline, pick the cheaper layer and check that you're not lying to yourself ("Spring is auto-wiring something" → integration).
- **"Pure JVM, no Spring" is the rule, not a religion.** A pure `@ConfigurationProperties` `data class` whose validation is in `init { require(...) }` is testable as a pure unit (just call the constructor) even though it's a Spring-flavoured class — the test doesn't need Spring.
- **Mocks are sometimes the right tool.** Communication-based tests have lower pillar scores than output-based, but for collaborators whose role is *publishing* (event publisher, audit logger, metric recorder), the call *is* the contract.
- **Coverage at this layer is not the goal.** A small number of well-chosen aggregate / value-object / algorithm tests outperforms a large number of trivial tests of getters. See `test-architecture` for mutation testing if you want a real effectiveness signal.
- **The unit layer is necessary but not sufficient.** Even in a perfect pyramid, integration tests are the floor under the unit layer — DB-specific behaviour, JPA cascades, transactional semantics, Spring Security can't be covered here. That's `test-integration`'s job.
- **Property-based testing bends some readability rules** — a `forAll` test asserts a property over a class of inputs, not a single case. That's fine when the property *is* the readable concept (commutativity, associativity, monotonicity).
- **Team consistency wins over micro-optimum.** If the project uses Kotest matchers, conform; if AssertJ, conform. A single test written against the grain harms readability more than any single rule helps it.
