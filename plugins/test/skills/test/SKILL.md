---
name: test
description: "Entry point and router for the test-* family — testing discipline for any Kotlin/Spring (or language-agnostic) codebase. Owns three things the per-topic siblings don't: the cross-cutting testing principles that apply everywhere regardless of layer (test code is first-class, F.I.R.S.T., BUILD-OPERATE-CHECK, single concept per test, the deployment-seam floor under any shape, what NOT to test), the topic-routing logic (which `test-*` sibling actually applies to the question on the table — `test-strategy` for shape selection, `test-principles` for per-test discipline, `test-unit` / `test-integration` / `test-acceptance` / `test-contract` / `test-architecture` for layer-specific tooling), and the family-level anti-patterns (coverage-as-goal, one-shape-org-wide, pyramid-over-anaemic-domain, `@SpringBootTest`-for-everything, mock-the-world unit tests, characterising tests deleted after refactor, retry-until-pass for flakes, snapshot-everything). Use whenever the user mentions testing, tests, a test suite, test pyramid / diamond / inverted pyramid / honeycomb / trophy, TDD, BDD, F.I.R.S.T., 'how do I test X', 'should this be unit or integration', a flaky test, a slow CI suite, a brittle test, a test that breaks on every refactor, a test that mocks the world, Testcontainers, slice tests, Spring `@WebMvcTest` / `@DataJpaTest` / `@SpringBootTest`, MockMvc, MockK / Mockito, AssertJ / Kotest, ArchUnit, Spring Modulith, Pact / Spring Cloud Contract, Pitest / mutation testing, 'we should rewrite the suite', or any question that touches the testing discipline of a codebase. Routes to the right sibling for deep treatment; owns the cross-cutting rules that all siblings inherit."
risk: safe
source: "House synthesis on top of R. Martin Clean Code Ch.9, V. Khorikov Unit Testing: Principles Practices and Patterns, Mike Cohn's pyramid, Ham Vocke / Martin Fowler practical pyramid, Spotify's honeycomb, Kent C. Dodds's Testing Trophy"
date_added: "2026-05-12"
---

# Test — Entry Point for the Testing Skill Family

This skill is the **router**: it sees the question, names the layer / decision / artefact, and points to the sibling that owns it. It also owns the **cross-cutting rules that apply everywhere** — the discipline that doesn't change whether you're writing a unit test of a value object or an acceptance test of a use case.

> "There is no universal 'right way to test'. There is the way that matches *this* codebase, at *this* layer, for *this* behaviour. The test family answers the *which*; the per-layer skills answer the *how*." — house ethos

## Use this skill when

- The user says "tests", "testing", "test suite", "test pyramid" / "diamond" / "honeycomb" / "trophy" / "inverted pyramid", "TDD", "BDD", "F.I.R.S.T.", "characterisation tests".
- The user asks **"how do I test X"** and the right answer depends on which layer X belongs at — route to the right `test-*` sibling.
- The user asks **"should this be a unit test or an integration test"** — this is a `test-strategy` question.
- The user reports a **flaky / slow / brittle** test, or a CI suite that takes 15 minutes — diagnose with the cross-cutting rules; route to layer skill for tooling specifics.
- The user wants to **start a new service / module** and the test plan is blank — start at `test-strategy`, then layer skills.
- The user asks "what does Khorikov say about this?" — route to `test-principles`.
- The user mentions tools — MockK / Mockito / AssertJ / Kotest / Testcontainers / `@WebMvcTest` / `@DataJpaTest` / `@SpringBootTest` / WireMock / Pact / SCC / ArchUnit / Modulith / Pitest — route to the layer skill that owns that tool.
- The user asks **"is this test worth keeping?"** — route to `test-principles` (Khorikov's four pillars).
- The user asks **"what shape should our suite be?"** — route to `test-strategy`.
- The user wants to **audit / review** an existing suite — this skill provides the cross-cutting checks; route to layer skills for tooling audits.

## Do not use this skill when

- The user explicitly names a sibling skill — go directly to it (`test-unit`, `test-integration`, etc.).
- The user is asking about **production code design** (which makes code testable) — use `clean-code-functions`, `clean-code-naming`, `clean-code-error-handling`, `ddd-tactical-patterns`. Clean tests can't rescue badly-designed production code; this family assumes the production code follows that discipline.
- The user is asking about **verification of a completion claim** (e.g. "is this done?") — use `methodology-verification`.

## The decision tree — which sibling to read

```
What is the question?

├─ "What shape should our suite be?" / "Pyramid or diamond?"
│  / "Where does the centre of gravity belong?"          → test-strategy
│
├─ "How do I write a single test well?"
│  / "F.I.R.S.T. / BUILD-OPERATE-CHECK / DSL / TDD"
│  / "Is this test worth keeping?" (Khorikov)            → test-principles
│
├─ Layer-specific (the bulk of day-to-day questions):
│
│   ├─ Pure-JVM, no Spring, no DB — unit
│   │  Aggregates, value objects, algorithms             → test-unit
│   │
│   ├─ Spring slice + real infrastructure
│   │  `@DataJpaTest` + Testcontainers, `@WebMvcTest`,
│   │  `@RestClientTest`, transactional traps            → test-integration
│   │
│   ├─ Use case end-to-end through application service
│   │  Narrow `@SpringBootTest`, in-memory adapters,
│   │  `@ApplicationModuleTest`, outside-in TDD          → test-acceptance
│   │
│   ├─ Cross-service compatibility
│   │  Pact, Spring Cloud Contract, OpenAPI contracts    → test-contract
│   │
│   └─ Architecture fitness + mutation testing
│      ArchUnit, Spring Modulith verify(), Pitest        → test-architecture
│
└─ Multiple layers / unclear which → start at test-strategy, then descend.
```

## The cross-cutting rules — these apply at every layer

These rules are the **inheritance** of every test in the suite, regardless of which sibling owns the layer. If a test violates one of these, no amount of layer-specific tooling fixes it.

### Rule 1: Test code is first-class

Same standards of clarity, naming, structure, and design as production code. The cheat is in *efficiency* (test code can be less efficient — allocate fresh fixtures, copy lists, use reflection where production can't); never in *cleanliness*. Detailed treatment: `test-principles` → `martin-clean-code.md` §Rule 2 + §Rule 7 (Dual Standard).

### Rule 2: BUILD-OPERATE-CHECK (Given-When-Then) at every layer

Every test reads in three sections, in this order, with blank lines between them. Helpers named in those vocabularies (`given...`, `submit...`, `assert...`). Detailed treatment: `test-principles` → §BUILD-OPERATE-CHECK.

### Rule 3: F.I.R.S.T. proportionally per tier

| Letter | Unit tier | Slice / integration tier | Acceptance / e2e tier |
|---|---|---|---|
| **Fast** | < 50 ms | < 1 s | < 10 s |
| **Independent** | Always | Always | Always |
| **Repeatable** | Always (no time / locale / network) | Always (Testcontainers, no H2-as-Postgres) | Always (Testcontainers, WireMock for external) |
| **Self-Validating** | Always (AssertJ / Kotest, no `println`) | Always | Always |
| **Timely** | TDD by default | TDD where applicable (acceptance test drives slice + unit) | Outside-in TDD where applicable |

Detailed treatment: `test-principles` → §F.I.R.S.T.

### Rule 4: Single Concept per Test

A test exercises **one concept**. Multiple concepts → multiple tests (or parameterised). Multiple assertions are fine **if they all describe the same concept**; use `assertSoftly` / `assertAll` to collect failures. Detailed treatment: `test-principles` → §Single Concept.

### Rule 5: The deployment-seam floor — applies to every shape

Regardless of pyramid / diamond / inverted / honeycomb / trophy, these tests must exist *somewhere* in the suite:

- DB-specific behaviour (JSONB, partial indexes, locking, Flyway migrations).
- JPA / ORM mapping correctness.
- Kafka / RabbitMQ serdes + partition / routing key.
- Spring Security per authentication path.
- Transactional event listeners + outbox.
- Retry / idempotency / circuit-breaker.
- Bean wiring / full-context smoke.

Skipping the floor is how production "surprises" happen. Detailed treatment: `test-strategy` → `what-test-where.md` §Floor.

### Rule 6: The Khorikov filter — what NOT to test

Code in the **Trivial** quadrant (getters, plain data) — don't test directly. Code in the **Overcomplicated** quadrant (god services, many collaborators + high complexity) — refactor first; characterise at integration level until refactored. Code in the **Controllers** quadrant (orchestration with many collaborators, low decision density) — integration-test, not unit-test (unit-tests of Controllers code are mostly mock setup, low protection against regressions). Detailed treatment: `test-principles` → `khorikov-fundamentals.md`.

### Rule 7: Test names are documentation

The list of test method names *is* the behavioural contract of the class. Read aloud: each name should make sense to the product owner. `test1()` / `shouldWork()` / `testEdgeCase()` are not test names. Detailed treatment: `test-principles` → §Rule 15 (Tests as Documentation).

### Rule 8: Verification before completion

After every test refactor, **re-run the suite in the current session** and check the output. "Should pass" is not evidence. See `methodology-verification`.

## Family-level anti-patterns

Things that *cross* the per-layer concerns — usually signs the team is misunderstanding testing as a discipline:

- **Coverage-as-goal.** 100% line coverage with weak assertions is worse than 70% with surgical, named tests. Coverage is a *symptom*, not the target. Pair with mutation testing (`test-architecture` → Pitest) for the real signal.
- **One-shape-org-wide.** A monolith / modular monolith / multi-service estate may legitimately host multiple shapes (domain modules on pyramid, glue services on honeycomb, read-side projections on diamond). Forcing a uniform shape mangles some modules.
- **Pyramid-over-anaemic-domain.** Unit tests of data-bag entities check that getters return the field passed to setters. Hollow. Diamond fits anaemic / Active Record / CRUD-over-JPA.
- **`@SpringBootTest`-for-everything.** Each `@SpringBootTest` adds 3-10s of context boot; 200 of them = 30+ min CI. Slices over full boot wherever possible.
- **Mock-the-world unit tests.** 8 mocks per test = the test verifies the mock setup, not behaviour. Khorikov pillars score low; refactor seam or move to integration.
- **Characterising tests deleted after refactor.** The characterisation captures the *current* behaviour, the refactor preserves it; *don't delete the test*. Replace with proper TDD tests once the new structure is clean.
- **Retry-until-pass for flakes.** "It's flaky" is a *property of the test*, not the system. Quarantine, root-cause, fix. CI configured to retry hides bugs.
- **Snapshot-everything.** Approval/snapshot testing is for *stable serialised output* (JSON contracts, HTML rendering). As a default, it captures whatever you committed — including the bugs.
- **No integration tests because "we have 95% unit coverage".** Coverage is per-line; integration is per-seam. The two are orthogonal. The deployment-seam floor (Rule 5) is non-negotiable regardless of unit coverage.
- **TDD-as-religion.** Three Laws are the *default*, not a contract. Spikes, characterisation, framework callbacks each legitimately bend the cycle — but never as an excuse to skip testing.
- **TDD-as-theatre.** Writing the test, writing the obviously-passing production code, going green, moving on. Misses the design-feedback mechanism. The Khorikov pillars apply *during* the TDD cycle.

## How to navigate the family

| You want to … | Go to |
|---|---|
| Pick the shape for a new service / module / context | `test-strategy` |
| Audit whether the current shape matches the architecture | `test-strategy` → `architecture-to-shape.md` |
| Allocate a feature's tests across layers | `test-strategy` → `what-test-where.md` |
| Write a single test well (any layer, any language) | `test-principles` |
| Decide whether multi-assert is one concept or many | `test-principles` → §Single Concept |
| Decide whether to TDD this feature | `test-principles` → `tdd-discipline.md` |
| Apply the Khorikov "is this test worth keeping?" filter | `test-principles` → `khorikov-fundamentals.md` |
| Write a unit test of an aggregate / value object / algorithm | `test-unit` |
| Pick `@WebMvcTest` vs `@DataJpaTest` vs `@RestClientTest` | `test-integration` → `spring.md` |
| Set up Testcontainers + `@ServiceConnection` | `test-integration` → `spring.md` §Testcontainers |
| Debug a transactional test that "sometimes passes" | `test-integration` → `spring.md` §Transactional traps |
| Write a use-case-level acceptance test (in-memory or `@SpringBootTest` narrow) | `test-acceptance` |
| Set up consumer-driven contract tests (Pact or SCC) | `test-contract` |
| Verify cross-service compatibility without flaky e2e | `test-contract` |
| Add ArchUnit rules / Modulith verify / Pitest mutation testing | `test-architecture` |
| Establish architecture fitness functions for CI | `test-architecture` |

## Sibling map

| Sibling | What it owns | When to read |
|---|---|---|
| `test-strategy` | Shape selection (pyramid / diamond / inverted / honeycomb / trophy); Khorikov-based mapping from architecture style → shape; per-shape layer allocation matrix | Front-of-funnel decisions about the suite |
| `test-principles` | Martin Ch.9 rules; Khorikov four quadrants + four pillars; TDD discipline | Writing or reviewing a single test, at any layer |
| `test-unit` | Pure-JVM unit tests; JUnit 5 + AssertJ + MockK + Kotest; backtick names; fixture factories; `runTest` for coroutines; `Clock` injection | Writing a unit test of a domain method / value object / algorithm |
| `test-integration` | Spring slices; Testcontainers (Postgres / Mongo / ES / Kafka / Clickhouse / Redis); `@ServiceConnection`; `@MockkBean`; transactional traps; MockMvc; WireMock | Writing a slice test or an adapter test against real infra |
| `test-acceptance` | Use-case-level tests; in-memory adapters; narrow `@SpringBootTest`; `@ApplicationModuleTest`; outside-in TDD | Use-case end-to-end through the application service boundary |
| `test-contract` | Pact JVM; Spring Cloud Contract; OpenAPI contract testing; broker patterns; can-i-deploy | Cross-service compatibility, multiple teams, independent deployability |
| `test-architecture` | ArchUnit (layer / package rules); Spring Modulith `verify()` + `ApplicationModuleTest`; Pitest mutation testing; fitness functions | Architecture rules; test-effectiveness verification; preventing structural drift |

## Cross-skill bridges

- **`methodology`** wraps every coding task; testing is part of completion. `methodology-verification` is mandatory before claiming a test refactor is done.
- **`architecture-patterns` / `ddd-tactical-patterns`** shape the codebase that the test suite tests. Test-strategy is downstream of those.
- **`architecture-decision-records`** — pair every shape decision and every ArchUnit rule with an ADR. The fitness function and the decision live together.
- **`clean-code`** family — production-code discipline that makes testing cheap. Clean tests can't rescue messy production code; this family assumes the production code follows clean-code discipline.
- **`debugging-systematic`** — when a test fails mysteriously, phase-in to root-cause investigation rather than masking with retries.
- **`api-design-principles`** — what `test-contract` verifies the compatibility of.
- **`database-design`** — what `test-integration` exercises with real Postgres.
- **`cqrs-implementation`** — write side typically pyramid, read side typically diamond; cross-side acceptance tests verify the full flow.
- **`spring-boot-mastery`, `spring-bean`** — what slice / `@SpringBootTest` configurations exercise.

## Limitations of the family

- **Shapes are defaults, not contracts.** A pyramid-shaped service still earns integration tests for JSONB queries; a diamond-shaped service still earns unit tests for pricing algorithms. The shape names the centre of gravity, not a quota.
- **Khorikov's quadrants are heuristics.** The thresholds (where "few collaborators" becomes "many") are judgement calls. Use the quadrants to *frame* the decision; not as a checklist.
- **Per-module shape variation is normal.** Don't force one shape across a monolith / modular monolith.
- **Numbers are heuristic budgets.** "< 50 ms per unit test" is a strong default; a slice test legitimately takes hundreds of ms. Apply proportionally.
- **Frontend testing is largely out of scope** for the Kotlin/Spring slant of these skills. The Testing Trophy is mentioned in `test-strategy`; for deep frontend testing discipline, treat the family as inspiration and supplement with frontend-specific resources.

## Bootstrap reading order — if you're entirely new

1. `test-strategy` → `shapes.md` (vocabulary).
2. `test-strategy` → `architecture-to-shape.md` (pick your shape).
3. `test-principles` → `martin-clean-code.md` (per-test discipline).
4. `test-principles` → `khorikov-fundamentals.md` (filter).
5. Pick the layer you're working at, read its skill.

Roughly 2-3 hours total reading. After that, you have the vocabulary and the discipline to make every test pull its weight.
