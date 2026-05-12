---
name: test-acceptance
description: "Layer-specific discipline for use-case / application-service-level tests — the layer between per-slice integration and full-stack end-to-end. Owns: the house definition of 'acceptance test' (one use case exercised end-to-end through the application service boundary, infrastructure either replaced by in-memory adapters or booted narrowly via `@SpringBootTest` with real DB + stubbed external HTTP), the two acceptance-test seams (in-memory-adapter style vs narrow-`@SpringBootTest` style) and when each fits, the outside-in TDD pattern (failing acceptance test drives inner unit tests; inner unit tests drive production code; acceptance test goes green from the inside out), the in-memory `OrderRepository` / `RecordingEventPublisher` / stubbed outbound HTTP pattern, Spring Modulith `@ApplicationModuleTest` for per-bounded-context use-case tests, Testcontainers + `@ServiceConnection` for the narrow-`@SpringBootTest` variant, `@MockkBean` for stubbing external HTTP at the use-case boundary, WireMock for stubbing the external world end-to-end, Awaitility for async use-case flows, Spring Modulith `PublishedEvents` for asserting event flow, `@TransactionalEventListener` + outbox at the acceptance level, when (and rarely) Gherkin / Cucumber pays vs plain JUnit with backtick names, acceptance criteria from a user story translated into executable specs, BDD `Given / When / Then` at the use-case level. Use this skill when designing a use-case-level test, writing a test for a user story's acceptance criteria, deciding between in-memory adapters and a real Testcontainers DB for a use case test, picking whether to use Gherkin / Cucumber (usually no on JVM), refactoring a `@SpringBootTest` that is really testing one use case toward a narrower acceptance test, adding an outside-in TDD test that drives the next implementation slice, or testing a cross-aggregate orchestration / saga happy path. For per-rule unit-level tests see test-unit; for per-slice / per-adapter tests see test-integration; for cross-service contracts see test-contract; for true full-real-environment e2e (which this skill does NOT cover) see test-strategy → inverted-pyramid section."
risk: safe
source: "Synthesised from existing DDD test patterns (clean-code-unit-tests/ddd-tests.md §8, §11), Spring `@SpringBootTest` patterns (clean-code-unit-tests/spring-boot-tests.md §4, §7, testing-strategy-kotlin-spring/spring-boot-testing.md), test-strategy / what-test-where.md acceptance-layer definitions, plus house practice on use-case-level testing"
date_added: "2026-05-12"
---

# Test Acceptance — Use-Case-Level Discipline

This skill owns the **layer between integration and end-to-end** — the use-case / application-service tier. An acceptance test exercises **one use case** end-to-end through the application service boundary. The use case is the unit; the world below the application service is either replaced by **in-memory adapters** (in-memory repository, recording event publisher, stubbed HTTP) or booted **narrowly** via `@SpringBootTest` with a real DB + stubbed external HTTP. This is the bridge between fine-grained unit tests and full-stack e2e — the layer that verifies *the whole orchestrated use case* without paying full e2e cost.

> "An acceptance test is the one place in the suite that asks 'does this *use case* behave correctly end-to-end?' — not 'does this rule hold?' (unit), not 'does this adapter map correctly?' (integration), not 'does the whole environment work?' (e2e). One use case. The application service is the entry. The infrastructure is either fake or narrow. That's the seam." — house ethos

Many readers will arrive here unsure what "acceptance test" even means — the term overlaps with "feature test", "use-case test", "story test", "BDD test". This skill picks a **house definition** and is opinionated about scope. For shape selection (does this concern even belong at the acceptance tier?) see `test-strategy`. For per-test discipline (F.I.R.S.T., BUILD-OPERATE-CHECK, DSL, naming) see `test-principles`. For unit-tier content see `test-unit`. For slice / adapter content see `test-integration`.

## Use this skill when

- Designing a use-case-level test — the entry is the application service, the test asserts on the *outcome of the use case*, not on per-rule state.
- Writing a test that maps directly to a **user story's acceptance criteria** — "Given a draft order with at least one line, when the customer submits it, then it is moved to SUBMITTED and OrderSubmitted is published."
- Deciding between **in-memory adapters** and a **real Testcontainers DB** for a use-case test — both are valid; the criteria are below.
- Refactoring a `@SpringBootTest` that's actually testing one use case toward a **narrower acceptance test** (in-memory adapters or `@ApplicationModuleTest`).
- Testing a **cross-aggregate orchestration** — a use case that touches `Order` + `Inventory` + `Customer` and publishes events. The orchestration is the application service; that's exactly the acceptance seam.
- Testing an **event flow** at the use-case level — HTTP in → application service → event published → projection updated. Spring Modulith `PublishedEvents`, Awaitility for the projection.
- Testing **idempotency / retry / saga happy paths** — the orchestration is what idempotency is *about*; the acceptance tier is where it pays.
- Picking whether to use **Gherkin / Cucumber** vs plain JUnit — almost always plain JUnit wins on the JVM; this skill explains when Cucumber legitimately pays.
- Driving an **outside-in TDD** flow — the acceptance test fails first, then drives the per-rule unit tests, then the implementation, and finally the acceptance test goes green.
- Writing the **one or two `@SpringBootTest` tests per service** that smoke the full wiring (the acceptance test that doubles as a bootstrap check).

## Do not use this skill when

- Picking the *shape* — should this concern be tested at unit, integration, or acceptance? That's `test-strategy`.
- Writing or reviewing the *content* of a single test (BUILD-OPERATE-CHECK, naming, DSL, F.I.R.S.T.) — that's `test-principles`. This skill assumes the principles are applied; it adds the acceptance-layer specifics on top.
- Writing a pure unit test of a domain rule (no Spring, no Testcontainers, < 50 ms) — that's `test-unit`. Each rule deserves its own unit test; the acceptance test asserts on the *use-case outcome*, not the per-rule state.
- Writing a slice / adapter test (`@DataJpaTest`, `@WebMvcTest`, `@RestClientTest`) — that's `test-integration`.
- Writing a consumer-driven contract test (Pact, Spring Cloud Contract) — that's `test-contract`.
- Writing ArchUnit / Modulith fitness tests — that's `test-architecture`.
- Writing a **true full-real-environment e2e** (the test that hits real downstream partners, real Kafka, real OAuth provider) — that's an inverted-pyramid concern (rarely a chosen shape; see `test-strategy → inverted-pyramid section`). This skill stops *one step short of full e2e* — at the use case, with externals stubbed.

## Selective Reading Rule

Read the file that matches the question you're answering.

| File | Description | When to read |
|---|---|---|
| `resources/general.md` | Language-agnostic acceptance-test discipline — the house definition, hexagonal framing, in-memory-adapter pattern, RecordingEventPublisher, stubbed outbound HTTP, acceptance-criteria-to-tests, the outside-in TDD flow in detail, Gherkin / Cucumber pros and cons, vocabulary disambiguation, BDD `Given / When / Then` at the use-case level. | First read — frames everything below. Applies to Python, Go, Node use-case tests too. |
| `resources/kotlin.md` | Kotlin-specific acceptance-test patterns — in-memory repository implementations, recording event publishers, fixture factories rich enough to seed the in-memory store, AssertJ custom assertions on lists of emitted events, building a small use-case-level test DSL (`givenSubmittedOrder`, `whenCancellingOrder`, `thenEvents`), `runTest` for coroutine use cases, Kotest `BehaviorSpec` if the team picks it, cucumber-jvm / cucumber-kotlin notes (brief). | When picking Kotlin-side tooling for an acceptance test. |
| `resources/spring.md` | Spring tooling for acceptance tests in depth — `@SpringBootTest` reserved for acceptance / smoke, `@SpringBootTest(MOCK)` + MockMvc through HTTP boundary, `@SpringBootTest(RANDOM_PORT)` + WebTestClient, `@ApplicationModuleTest` (Spring Modulith) per bounded context, Testcontainers + `@ServiceConnection` for the real-DB variant, `@MockkBean` for stubbing external HTTP, WireMock for stubbing the external world, Awaitility for async, Modulith `PublishedEvents`, `@TransactionalEventListener` + outbox at the acceptance level, `TestRestTemplate` vs `WebTestClient`, profiles + `@TestPropertySource`, and a concrete "OrderSubmitted" acceptance test from HTTP POST to event published to projection updated. | The bulk of this skill. Read whenever you write a Spring-flavoured acceptance test. |

## What is an acceptance test — the house definition

> An **acceptance test** is one test that exercises **one use case** end-to-end through the **application service boundary**, with infrastructure either replaced by **in-memory adapters** or booted **narrowly** via `@SpringBootTest` (real DB via Testcontainers, external HTTP stubbed via `@MockkBean` / WireMock). It asserts on the **observable outcome of the use case**: state changes, events published, HTTP responses returned. It does NOT assert on per-rule mechanics (that's unit) and does NOT include real external dependencies (that's e2e).

The **unit of the test is the use case**, not a class or a layer. A use case is the unit of business value — "submit an order", "confirm a reservation", "settle an invoice". The application service is the entry; the domain is the engine; the adapters are scaffolding the test puts in place.

Equivalently: the acceptance test answers the question *"does this story behave correctly when wired together?"* — not *"does this rule hold?"* (which is unit) and not *"does this adapter map correctly?"* (which is integration).

**Where it sits in the pyramid**:

```
                e2e (real external partners)         ← outside this skill
              ─────────────────────────────────
                acceptance (this skill)              ← use-case end-to-end,
                                                       in-memory or narrow
              ─────────────────────────────────
                integration / slice                  ← per-adapter; test-integration
              ─────────────────────────────────
                unit                                 ← per-rule; test-unit
```

For a domain-rich service of moderate complexity, you typically have **5-15 acceptance tests** (one per critical use case). For a glue / honeycomb service, the count is higher — acceptance becomes the centre of gravity. See `test-strategy` for the shape decision.

## Two acceptance-test seams: in-memory adapters vs narrow `@SpringBootTest`

There are two legitimate ways to write an acceptance test. Both have their place. Pick by what's actually being verified.

### Seam A — in-memory adapters

The application service is wired to **in-memory implementations of its ports**: `InMemoryOrderRepository`, `RecordingEventPublisher`, `StubInventoryClient`. No Spring. The test runs in milliseconds. The Given populates the in-memory store; the When invokes the application service; the Then asserts on the in-memory store + the recorded events.

**Use this seam when**:
- The use case's value is the **orchestration of domain logic** — multiple aggregates, events, transitions. The infrastructure is incidental.
- You want **fast feedback** on a use case during outside-in TDD.
- You want the test to be **deterministic** — no Testcontainers, no boot time, no flake surface.

### Seam B — narrow `@SpringBootTest` (real DB + stubbed external HTTP)

The application context boots — but narrowly (via `@ApplicationModuleTest` if Spring Modulith is in use, otherwise `@SpringBootTest` with explicit `classes = [...]` or a focused configuration). The DB is real via Testcontainers + `@ServiceConnection`. External HTTP is stubbed via `@MockkBean` or WireMock. Tests run in seconds (not milliseconds), but they cover the **real wiring**.

**Use this seam when**:
- The use case's value involves **non-trivial persistence** — JSONB queries, complex JPA mappings, outbox writes, transactional event listeners.
- You want to test the **commit-time semantics** — `@TransactionalEventListener(AFTER_COMMIT)`, outbox-poll-publish, projection update on commit.
- You want one test that doubles as the **bootstrap smoke** for the bounded context.

### Picking between them

| Question | If yes → | If no → |
|---|---|---|
| Does the use case involve non-trivial SQL / JSONB / locking? | Seam B | Seam A |
| Does the use case rely on `@TransactionalEventListener(AFTER_COMMIT)` or outbox? | Seam B | Seam A |
| Is the orchestration the centre of the test (events, multi-aggregate)? | Either; default Seam A for speed | — |
| Are you driving outside-in TDD in the inner loop? | Seam A | Seam B (later, once shape is stable) |
| Do you already have ≥10 acceptance tests and CI is slow? | Seam A by default; reserve Seam B for the 1-2 cases that need real wiring | — |

**Mixed pattern (common)**: most acceptance tests use Seam A; one or two per bounded context use Seam B for the wiring smoke + persistence-sensitive use cases. This is the right balance for a Pyramid- or Diamond-shaped service.

## The outside-in TDD pattern

Outside-in TDD makes the acceptance test the **driver** of the implementation. The cycle:

1. **Write the failing acceptance test.** It expresses the use case in the ubiquitous language: "Given a draft Order with one line, when the customer submits it, then OrderSubmitted is published and the order is SUBMITTED." It fails because nothing exists yet — or it fails because the application service exists but doesn't do the work.
2. **Step inward.** The acceptance test fails for a specific reason — usually `NotImplementedError` from a domain method, or a missing aggregate transition. Write a **unit test** that pins down that piece.
3. **Make the unit test pass.** Implement the domain method, the aggregate transition, the value object — whatever the unit test needs. Use TDD's three laws on the inner loop.
4. **Re-run the acceptance test.** It progresses to the next missing piece. Repeat steps 2-3 until the acceptance test goes green from the inside out.
5. **Refactor.** Acceptance test stays green; unit tests stay green; the inside is now clean.

The acceptance test is **slow to write the first time** (you build the use case piece by piece) but **fast to keep working** (the inner unit tests carry the per-rule coverage; the acceptance test only re-asserts on the use-case outcome). It is also the **most readable artefact** — a new joiner can read the acceptance test and understand what the use case *is*.

**Key shape**: outside-in TDD uses **Seam A (in-memory adapters)** for the acceptance test — Seam B's boot cost would defeat the inner-loop tempo.

For per-test TDD discipline (Three Laws, BUILD-OPERATE-CHECK, when to bend), see `test-principles`.

## What acceptance tests are FOR

- **Use-case happy paths.** "Customer submits an order with one line; the order is SUBMITTED, OrderSubmitted is published, and the API returns 201 with a Location header."
- **Critical user journeys.** A multi-step journey that traverses multiple application services / aggregates / events — captured as one acceptance test (or a short sequence) at the use-case level.
- **Cross-aggregate orchestrations.** "Customer cancels an order; the Order moves to CANCELLED, the Inventory reservation is released, and OrderCancelled + InventoryReleased are published." The orchestration is the application service; the test asserts on the multi-aggregate outcome.
- **Event-flow verification.** "Submitting an order publishes OrderSubmitted, which the OrderProjection consumes, which updates the read model." Awaitility + `PublishedEvents` or in-memory event log.
- **Idempotency / retry / saga happy paths.** "Submitting the same order twice with the same idempotency key returns the same response and does NOT publish OrderSubmitted twice." This is exactly the use-case-level question.
- **Security at the use-case level.** "An unauthenticated POST to /orders returns 401; an authenticated request with the wrong role returns 403; a request with the right role goes through." One acceptance test per critical authorisation path.
- **Bootstrap smoke (1-2 per service).** One `@SpringBootTest` that boots the full app — catches misconfigured profiles, missing `@Configuration`, circular dependencies. Doubles as the broadest acceptance test.

## What acceptance tests are NOT for

- **Per-rule domain logic.** "An Order with no lines cannot be submitted" is a *unit-level* invariant — see `test-unit`. The acceptance test will exercise the rule incidentally (through the use case) but does NOT assert on per-rule mechanics.
- **Per-adapter mapping.** "The JPA `OrderEntity` round-trips correctly through Postgres" is an *integration-level* concern — see `test-integration` (`@DataJpaTest`).
- **Per-controller HTTP wiring.** "POST /orders with an invalid body returns 422 with a ProblemDetail" is a *slice-level* concern — see `test-integration` (`@WebMvcTest`).
- **Cross-service contracts.** "Our `OrderSubmittedEvent` matches the consumer's expected schema" is a *contract* concern — see `test-contract`. Trying to verify cross-service compatibility through your own acceptance test produces a brittle suite that breaks on every counterpart deploy.
- **Full real-environment end-to-end.** "The deployed system in staging actually works against real Stripe / real SES / real OAuth" is an *e2e* concern — outside this skill. It's slow, flaky, and gated on environment availability. Use it sparingly (smoke-test tier in CI / nightly).
- **Per-rule error matrices.** "Posting with an empty customerId returns 422 with `field=customerId`; posting with a negative quantity returns 422 with `field=quantity`; ..." — these belong at slice level (`@WebMvcTest`). The acceptance test exercises the happy path + ONE representative error path per use case.

## Anti-patterns

- **Acceptance tests with mocked aggregates.** `every { order.submit(any()) } returns ...` inside an acceptance test. **Wrong unit.** The aggregate IS the engine the test exercises. Mock the *ports* (repository, event publisher, outbound HTTP); never the aggregate. If you find yourself doing this, you've confused the layer.
- **One mega-acceptance-test that asserts on everything.** Twenty-five assertions across five use cases, six event types, three error paths. **Split.** One acceptance test = one use case + one happy path + at most one canonical error path. Per-rule variations live in unit / slice.
- **Using `@SpringBootTest` for what should be a slice.** "I'm testing the controller's validation behaviour; I'll write a full `@SpringBootTest`." No — that's `@WebMvcTest`, `test-integration`. `@SpringBootTest` is reserved for **cross-slice** concerns; loading 300 beans to test one validation rule is a 50× speed penalty.
- **Gherkin-ing every test when plain JUnit reads better.** Cucumber adds tooling, vocabulary, and indirection. It pays *if and only if* business stakeholders actually read and edit the `.feature` files. If only developers read them, plain JUnit with backtick names is more readable, faster, and easier to refactor. See `resources/general.md` for the criteria.
- **Acceptance test reuses production `application.yml` unchanged.** External integrations enabled, retries on, async on — the test then either calls real services or is non-deterministic. Use `@ActiveProfiles("test")` + `application-test.yml` with externals stubbed and async controlled.
- **Acceptance test sleeps for a "long enough" duration.** `Thread.sleep(2000)` — flaky on slow CI, slow on dev. Use **Awaitility** + a real condition (the projection appeared, the event was published, the outbox row was processed).
- **No clear seam — in-memory adapters AND `@SpringBootTest` in the same test.** Pick one. If you find yourself with a hybrid, the test is fighting itself.
- **Acceptance test verifies nothing on the events.** The use case publishes an event; the test asserts only on the HTTP response. Half the value is missed — the **event is the contract** for the rest of the system. Assert on the recorded events / `PublishedEvents`.
- **Calling `Instant.now()` inside the application service.** The acceptance test is then non-deterministic. Inject `Clock`; the test supplies a fixed clock. (House rule — see `test-principles`.)
- **One acceptance test per `@Test` method but five `@BeforeEach` blocks layering state.** Each `@BeforeEach` is invisible setup; the reader has to scroll up to understand the Given. Prefer **explicit Given in the test body** via the use-case DSL.

## Related skills

| Skill | Why |
|---|---|
| `test` | The router skill. Points here for acceptance-tier work. |
| `test-strategy` | Shape selection (pyramid / diamond / inverted / honeycomb / trophy). Tells you whether the concern even belongs at the acceptance tier and how many acceptance tests the shape earns. |
| `test-principles` | Per-test discipline — F.I.R.S.T. (proportionally for this tier — a Seam-B test taking 2-5 s is Fast *for this tier*), BUILD-OPERATE-CHECK, DSL, naming, Khorikov's four pillars. **Do not duplicate** that content here — point to it. |
| `test-unit` | Sibling, layer below. Per-rule pure unit tests with no Spring. The acceptance test drives them (outside-in TDD); the unit tests carry the per-rule coverage. |
| `test-integration` | Sibling, layer below. Per-adapter slice tests. The acceptance test trusts the adapters; the integration tests verify them. |
| `test-contract` | Sibling. Consumer-driven contracts (Pact, Spring Cloud Contract) — the right tool for cross-service compatibility. Acceptance tests stub external HTTP; contract tests pin the schema. |
| `test-architecture` | Sibling. ArchUnit / Modulith / Pitest fitness functions — fast unit-tier quality gates. |
| `ddd-tactical-patterns` | The application service is the entry point of the acceptance test; aggregates live below. The DDD patterns shape the production code the acceptance test exercises. |
| `cqrs-implementation` | Write side: acceptance test of the command handler. Read side: acceptance test of the projection rebuild path. The two often need different seams (Seam A for the write, Seam B for the read). |
| `architecture-patterns` | Hexagonal / clean architecture — in-memory adapters fit naturally into the ports-and-adapters style. The acceptance test reverses the dependency arrow: production uses ports; the test plugs in test-only adapters. |
| `api-design-principles` | The HTTP shape of the use case (ProblemDetail, idempotency keys, status codes) — acceptance tests verify the use case end-to-end through that contract. |
| `methodology-verification` | After every acceptance-test change, *re-run* the suite in the current session; "should pass" is not evidence. The acceptance test is the verifiable criterion for "the use case behaves correctly". |
| `methodology-karpathy-guidelines` | §4 verifiable success criteria — the acceptance test *is* the verifiable criterion for the use-case-level success. |
| `debugging-systematic` | When an acceptance test fails mysteriously (commit-time semantics, async timing, transactional rollback hiding a side effect), root-cause the seam — don't paper over with `@DirtiesContext` or `Thread.sleep`. |

## Limitations

- **Tier-relative F.I.R.S.T.** Seam A is fast (tens of ms — same as unit). Seam B is slower (seconds — `@SpringBootTest` boot + container). Both are *Fast for the acceptance tier*; the unit-tier < 50 ms target does not apply to Seam B. Apply F.I.R.S.T. proportionally.
- **The line between "narrow `@SpringBootTest`" and "integration slice" is fuzzy.** `@WebMvcTest(OrderController::class)` with the application service `@MockkBean`'d is a *slice* (integration); a narrow `@SpringBootTest` that loads the application service + repository against a real DB is *acceptance*. The deciding factor is the **unit of the test** — one HTTP-mapping concern is slice; one use-case end-to-end is acceptance.
- **Acceptance does NOT cover real-environment e2e.** This skill stops at "infrastructure narrow / stubbed". For "the deployed system actually works against real downstream partners", that's an e2e concern — outside this skill. The inverted-pyramid section of `test-strategy` covers when (rarely) that's the right centre of gravity.
- **Gherkin / Cucumber is not the recommendation.** Cucumber is *allowed*, and on JVM it works (cucumber-jvm, cucumber-kotlin), and where stakeholders actually read `.feature` files it earns its keep. But for dev-only teams, plain JUnit with backtick names reads better, refactors more easily, and has lower indirection. Default: plain JUnit. See `resources/general.md` for the criteria.
- **`@ApplicationModuleTest` (Spring Modulith) is the best Seam-B option** for modular monoliths — it loads one module's beans only. If you're not on Modulith, the alternative is `@SpringBootTest(classes = [SomeModuleConfig::class])`; older / non-modular projects use plain `@SpringBootTest` with explicit `@ContextConfiguration`.
- **The acceptance suite should be small.** A healthy Pyramid- or Diamond-shaped service has **5-15 acceptance tests**, not 50. If you have 50, you're testing per-rule variations at the wrong layer — push them down to unit / slice.
- **Property-based testing rarely fits the acceptance tier.** Properties belong at the unit layer where they're cheap; at the acceptance tier, the orchestration cost defeats input-space sweeps.
- **Acceptance tests of a glue / honeycomb service look different.** For a service that's mostly wiring, the acceptance tier IS the centre of gravity — Seam B is the default, in-memory adapters are rare, and the count is much higher. See `test-strategy → honeycomb` for that shape.
