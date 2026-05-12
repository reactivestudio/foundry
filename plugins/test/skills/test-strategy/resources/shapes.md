# Test-Suite Shapes — Vocabulary

Before you can pick a shape, you need to recognise one. Five canonical shapes — what each looks like, what it costs, what it misses, when it's right, when it's wrong.

> The shape is the *answer to "where does this suite spend its time and trust?"*. Suites with a clear shape ship faster and break less; suites without one have a quiet bug: every test pays the same attention, regardless of value.

The shapes are descriptive, not prescriptive. None is universally "better" — the right one is whichever matches the **architecture of the code under test** (see `architecture-to-shape.md`).

---

## 1. The Pyramid (Mike Cohn, 2009)

The original. Many fast unit tests at the base, fewer integration in the middle, very few end-to-end at the top.

```
       /\
      /e2\
     /----\
    /  in  \
   / -gra-  \
  / -tion-   \
 /------------\
/  unit  tests \
/----------------\
```

**Typical proportions**: 70–80% unit, 15–25% integration / slice, 5% e2e.

**Cost profile**: cheap. Most tests run in milliseconds, full suite in seconds; CI feedback in minutes.

**What it assumes**:
- Logic concentrates in code that is **cheap to test in isolation** — pure functions, behaviour-rich domain objects, algorithms with few collaborators.
- Integration concerns are limited and well-mapped (a known set of seams).
- The cost of an integration miss is bounded — usually a fast follow-up.

**What it misses (when wrong-fit)**:
- DB-specific behaviour (Postgres JSONB, locking, partial indexes) when most tests don't touch a real DB.
- Async event-driven side effects.
- Spring Security / OAuth flows that only manifest at full-boot.
- Anything where the *deployment seam* is non-trivial (JPA cascades, transaction propagation, Kafka serdes, retry/idempotency wiring).

**Right when**:
- Domain Model architecture (behaviour-rich aggregates, value objects, pure functions).
- Hexagonal / clean architecture where adapters are thin and the core is rich.
- Algorithm-heavy code (pricing, scheduling, search ranking).

**Wrong when**:
- Anaemic domain (data-bag entities + thick services). Unit-testing the data bags is hollow; the logic lives elsewhere.
- Transaction Script (logic in SQL / procs). Unit tests cover the Java wrapper, not the rule.
- Frontend (most tests run with React mounted; isolated component tests need world-mocking).

**Symptom of a wrong-fit pyramid**: unit tests pass; integration breaks frequently; bugs found in production are typically integration-layer (JSONB, transactions, security, async).

---

## 2. The Diamond (rhombus, sometimes called "Honeycomb-lite" or "Spotify-ish")

Fewer unit tests at the base, **lots of integration / slice tests in the middle**, few e2e at the top.

```
       /\
      /e2\
     /----\
    /      \
   /  inte  \
  /  -gra-   \
   \ -tion- /
    \      /
     \----/
      \un/
       \/
```

**Typical proportions**: 20–30% unit, 50–70% integration / slice, 5–15% e2e.

**Cost profile**: moderate. Slices and Testcontainers are slower than pure unit, but each test is **information-dense** — covers DB behaviour, JPA wiring, controller serialisation, security in one shot.

**What it assumes**:
- The unit layer has **little to assert** because logic is thin / spread (anaemic, CRUD-ish, orchestration-heavy).
- The integration layer is where the real risk lives and where the tests have the highest signal-to-noise.
- Testcontainers + slice annotations make integration tests fast enough to dominate the suite without breaking CI.

**What it misses (when wrong-fit)**:
- Per-rule fine-grained coverage when the rules live in domain logic — integration tests are too coarse to assert each invariant cheaply.
- Refactor safety in the domain — without unit tests pinning each rule, refactoring rich domain code is risky.

**Right when**:
- Anaemic domain / Active Record / Layered codebases — the entity is a data bag; tests of orchestration over real DB carry the real signal.
- CRUD services where most "logic" is "save it / fetch it / return it".
- Spring services where the value of each test = how realistically it exercises the framework.

**Wrong when**:
- Domain Model with rich behaviour — you're paying integration costs for tests that could be unit-fast and equally informative.
- Algorithm-heavy code — algorithms with high decision density per line are wasted on slice tests.

**Symptom of a wrong-fit diamond**: each test takes seconds; suite takes 5–15 minutes; refactoring inside the domain is scary because no fast-feedback safety net.

---

## 3. The Inverted Pyramid (the "anti-pyramid", "ice-cream cone", or "Mike Cohn's nightmare")

Lots of e2e at the top, fewer integration, almost no unit at the base.

```
/----------------\
\    e2e tests   /
 \--------------/
  \   integ-  /
   \  -ration/
    \---inte/
     \  un /
      \   /
       \ /
```

**Typical proportions**: 10–20% unit, 20–30% integration, 50–70% e2e.

**Cost profile**: **brutal**. Each e2e test is seconds-to-minutes; full suite is 20–60 minutes; CI gates everything. Flakiness compounds.

**When it appears in practice**: almost always **by accident**. The first test was an end-to-end smoke; every subsequent test reused the same base class because it worked; over six months the suite calcified.

**What it misses**:
- Every fine-grained rule. e2e tests test *that the system can run*, not *that each rule is correct*. Many rules either go untested or are tested incidentally.
- Fast feedback — the developer who waits 20 minutes for CI doesn't refactor between commits.
- Failure diagnosis — when an e2e test fails, the failing seam could be anywhere in 6 layers.

**Right when**:
- **Almost never as a chosen shape.** The only legitimate case: a thin orchestration service whose business value is *exactly* the integration (a Saga coordinator that calls 3 other services and that's it). And even then, contract tests + a few smoke e2e beats a pyramid of e2e.
- Legacy systems whose code is genuinely untestable below e2e and you can't refactor — accept the inverted shape **for now** and characterise.

**Wrong when**:
- Almost always. If you have an inverted pyramid by accident, **refactor toward diamond**. Pick three high-value e2e tests, demote the rest to slice / unit.

**Symptom**: CI is slow (>15 min); developers run "only my test" locally; flaky tests are normalised ("just rerun"); confidence in green builds is low.

---

## 4. The Honeycomb (Spotify, ~2018)

A middle-heavy shape with **few isolated unit tests, few full-system e2e, most tests at the "integrated service" level** — a service is run with its real DB and queues but external dependencies are stubbed.

```
   ┌──────────────────┐
   │    integrated    │
   │      tests       │
   │   (the bulk)     │
   └────┬─────────┬───┘
        │         │
   ┌────┴───┐ ┌──┴────┐
   │  unit  │ │  e2e  │
   └────────┘ └───────┘
```

**Typical proportions**: 10–20% unit, 70–80% integrated-service, 5–15% e2e (often replaced by contract tests).

**Cost profile**: moderate-to-high. Each integrated test starts the service and its DB; cheaper than e2e but pricier than slice.

**What it assumes**:
- The service has **very little internal logic worth unit-testing** — it's mostly glue, transformation, routing.
- The behaviour worth checking is "given a real DB / real queue, does the service do the right thing?".
- External integrations are tested via **contract tests** (Pact / SCC) separately, not via e2e through real partners.

**Right when**:
- Microservices that are mostly **glue / orchestration / API gateways / event routers** — the service per se has thin logic; its value is wiring.
- Services where the operational unit (service + DB) is the meaningful unit of confidence — testing pieces in isolation doesn't reflect production behaviour.

**Wrong when**:
- A service with substantial in-process logic (rules engines, pricing, domain model). The Honeycomb under-tests the rules and over-tests the wiring.
- Tight CI-budget environments — even Honeycomb tests are slow vs slice tests.

**Honeycomb vs Diamond**: the difference is mostly *scope of the integrated test*. Diamond = `@WebMvcTest` + Testcontainers ("a layer with the real DB"). Honeycomb = the whole service running, talking to its DB and stubbed externals ("the service in production-like wiring"). Honeycomb is heavier and broader; Diamond is lighter and per-layer.

---

## 5. The Testing Trophy (Kent C. Dodds, frontend)

A frontend-flavoured shape: **few static-type / lint checks, few unit tests, many integration / component tests, few e2e**.

```
            __
           /  \         e2e
          /----\
         /      \       integration
        /        \      (the bulk)
        \        /
         \______/
          /----\        unit
         /------\
        /  static\      typechecks / lint
       /----------\
```

**Typical proportions** (Dodds): 40% integration, 30% unit, 20% e2e, 10% static.

**Cost profile**: integration / component tests use `@testing-library/react` style — mount the real component tree, drive it as a user would, assert on what the user sees. Each test is sub-second but more expensive than a pure JS unit test.

**What it assumes**:
- A frontend component is mostly **composition** of library calls (React, Redux, Apollo, routing). Unit-testing it in isolation requires mocking the world; you end up testing the mocks.
- The thing worth checking is "does this component behave correctly *as the user sees it*?" — render, click, assert.
- Type system + linter catches a huge class of bugs cheaply; static is the foundation.

**Right when**:
- React / Vue / Svelte component-heavy frontends.
- Component libraries where the contract is *the rendered behaviour*, not internal state.

**Wrong when**:
- Backend services (the analogy doesn't transfer cleanly — backend "integration" means something heavier).
- Frontend with substantial domain logic in pure JS / TS (then a small classic pyramid on the domain modules + a trophy on the components is the real shape).

**Note**: The trophy is the dominant model for modern frontend testing. If you're testing a React component with Jest + heavy mocking, you're paying for unit-test discipline and getting integration-test value — at the worst price point. Switch to Testing Library / Playwright Component.

---

## Comparison at a glance

| Shape | Unit % | Integration % | E2E % | Speed | When to pick |
|---|---|---|---|---|---|
| **Pyramid** | 70–80 | 15–25 | <5 | Fast | Domain Model, algorithms, hexagonal core |
| **Diamond** | 20–30 | 50–70 | 5–15 | Moderate | Anaemic / Active Record / CRUD / Layered |
| **Inverted** | 10–20 | 20–30 | 50–70 | Slow | Almost never *by design*; refactor away |
| **Honeycomb** | 10–20 | 70–80 (full-service) | 5–15 | Moderate-high | Glue / gateway / event-routing microservice |
| **Trophy** | 30 | 40 (component) | 20 | Fast (FE-style) | Component-heavy frontend |

## Hybrid shapes — common and correct

Real codebases rarely fit one shape end-to-end:

- **CQRS** — write side often Pyramid (rich aggregates), read side often Diamond (projection rebuild over real DB).
- **Modular monolith** — domain modules Pyramid, glue / API gateway module Honeycomb.
- **Service with both a public API and a Kafka consumer** — the consumer side often Honeycomb (real Kafka container + stubbed downstream), API side Diamond (slice + Testcontainers Postgres).
- **Hexagonal service** — Pyramid for the domain core + Diamond for the adapters (each adapter slice-tested).

These hybrids are **correct**, not a sign of indecision. The unit of shape-choice is the **module / context / layer**, not necessarily the whole service.

## How to read your current shape (the diagnostic)

Don't trust intuition; measure.

```bash
# Approximate count by annotation
grep -r "@Test" src/test --include="*.kt" | grep -v "@SpringBootTest\|@WebMvcTest\|@DataJpaTest\|@JsonTest" | wc -l   # unit-ish
grep -rl "@WebMvcTest\|@DataJpaTest\|@JsonTest\|@JdbcTest\|@RestClientTest" src/test --include="*.kt" | wc -l            # slice
grep -rl "@SpringBootTest" src/test --include="*.kt" | wc -l                                                            # full
```

Compute the proportions; match against the table above; ask "is this the shape my architecture earns?". If the architecture is Domain Model but the suite is 80% `@SpringBootTest`, you have an inverted pyramid by accident — refactor toward pyramid.

For per-shape **layer-allocation** guidance (what behaviours belong at unit vs integration in each shape), see `what-test-where.md`. For the **selection algorithm** (which shape does *this* codebase earn), see `architecture-to-shape.md`.

## Summary table — shape at a glance

| Shape | Centre of gravity | Right for | Wrong for | Signature failure mode |
|---|---|---|---|---|
| Pyramid | Unit (domain) | Domain Model, algorithms | Anaemic, CRUD, frontend | Integration gaps; DB / async surprises in prod |
| Diamond | Integration | Anaemic, Active Record, CRUD | Rich domain | Refactor pain; slow unit feedback |
| Inverted | E2E | Almost never | Almost always | Brittleness; long CI; low confidence |
| Honeycomb | Integrated-service | Glue / gateway | Domain-rich | Misses rule-level bugs |
| Trophy | Component (FE) | React / Vue / Svelte | Backend | Doesn't transfer to backend |
