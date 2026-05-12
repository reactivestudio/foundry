# What to Test Where — Per-Shape Layer Allocation

Once the **shape** is picked (see `architecture-to-shape.md`), this file answers: **for each behaviour, which layer of the suite tests it?** And — equally important — **what does NOT get tested at all?**

> "The most valuable list isn't 'what to test'. It's 'what NOT to test at this layer'." — Khorikov-paraphrase

This is the day-to-day reference. Print it. Pin it. When someone asks "should we add a unit test for X or an integration test?", read the relevant per-shape section and answer with the matrix.

## The cross-shape constants — these are always true regardless of shape

Some test-allocation rules don't depend on shape. They're floor / ceiling rules.

### Floor: what *every* shape needs

Regardless of architecture, these must exist somewhere in the suite:

- **DB-specific behaviour** — Postgres JSONB queries, partial indexes, locking, MVCC, Flyway migrations. Testcontainers + slice or integration. *Never* an in-memory DB substitute pretending to be Postgres.
- **JPA / ORM mapping** — that the entity maps to / from rows correctly. `@DataJpaTest` + Testcontainers. Catches lazy-loading bugs, cascade quirks, sequence wiring.
- **Kafka / RabbitMQ serdes + partition / routing key** — real broker container + produce-and-consume round trip.
- **Spring Security** — at least one slice / integration test per authentication path (JWT, OAuth, mTLS) and per critical authorisation rule.
- **Transactional event listeners + outbox** — the commit-time semantics are the most common production surprise. A real-DB integration test per critical event flow.
- **Retry / idempotency / circuit-breaker** — Resilience4j config, retry policy, dead-letter behaviour. Integration with a fault-injecting stub.
- **Bean wiring / context loads at all** — at least one `@SpringBootTest` that boots the full app. Catches misconfigured profiles, missing `@Configuration`, circular dependencies.

These are the **deployment-seam tests**. Skipping them is how production "surprises" happen.

### Ceiling: what *no* shape should waste tests on

Regardless of architecture, these are wasted effort:

- **Getters / setters / data class equality** — generated code. Nothing to break that the compiler doesn't already check.
- **Annotations on data classes / DTOs** — `@Serializable`, `@JsonProperty`. Either the library works or it doesn't; one integration / slice test covers it.
- **`toString()` output** — unless `toString` is part of a logging contract that a downstream parser depends on (rare; then it's a contract test, not a unit test).
- **Framework correctness** — that Spring's `@Transactional` rolls back on exception, that JPA flushes on commit. Trust the framework; test *your* code.
- **Trivial pass-through methods** — `fun submit(cmd) = handler.submit(cmd)` (single delegation). Test the handler; the delegation is one-line.
- **Private methods directly** — tests of private logic via reflection. Refactor: the private method either belongs in another class (with its own tests) or its behaviour shows up through the public method (test that).
- **Code in the Trivial quadrant or the Overcomplicated quadrant** — see Khorikov. Trivial = no value to test. Overcomplicated = refactor first; tests of god classes are 80% mock setup.

These are the **Khorikov "do not test" zones**. Free yourself from the obligation; redirect the effort to behaviours that *matter*.

---

## Pyramid — per-layer allocation

For: Domain Model, algorithms, hexagonal core.

### Unit layer (~70-80%)

**Test here**:
- Aggregate behaviour — every domain method. Happy path + invariant violation. Assert on state + emitted events.
- Value objects — invariants on construction (positive + negative cases).
- Domain services — pure functions composing aggregates.
- Specifications — boundary and non-boundary cases.
- Pure algorithms (pricing, scheduling, parsing, matching).
- Pure-function utilities (date arithmetic, currency conversion).

**Don't test here**:
- DB / IO interactions (move to integration).
- Spring configuration (move to integration / acceptance).
- Anything requiring `EntityManager` / `Repository` implementation.
- Anaemic services with many collaborators (if you have these, see Diamond — your shape is wrong-fit).

### Slice / integration layer (~15-25%)

**Test here**:
- Repository implementations — `@DataJpaTest` + Testcontainers. JPA mapping, custom queries, cascade behaviour.
- Controllers — `@WebMvcTest`. HTTP validation, ProblemDetail mapping, security filter behaviour.
- JSON / serialisation — `@JsonTest` for custom serialisers, `@JsonView` rules.
- Outbound HTTP — `@RestClientTest` with `MockRestServiceServer`.
- Kafka consumers / producers — single-broker Testcontainer test.
- Event listeners with `@TransactionalEventListener` — `@SpringBootTest`-narrow to verify commit-time semantics.

**Don't test here**:
- Domain rules (already covered at unit).
- Full multi-layer flows (move to acceptance).

### Acceptance layer (~5%)

**Test here**:
- End-to-end happy paths through application services: HTTP / event in → DB / event out.
- Critical user journeys that span 3+ layers.
- Bean wiring smoke (one test that boots the full context).

**Don't test here**:
- Per-rule variations — already covered at unit / slice.
- Error-path matrices — covered at slice.

### What does *not* get tested in a Pyramid

- Anaemic getters / setters (there are few; ignore them).
- Pure DI plumbing.
- `toString()`, `hashCode()`, `equals()` — already covered by the compiler for data classes.

---

## Diamond — per-layer allocation

For: Anaemic Domain, Active Record, Layered MVC default, CRUD-over-JPA.

### Unit layer (~20-30%)

**Test here**:
- Pure value objects — invariants on construction.
- Pure-function utilities (`Money` arithmetic, date math, validators).
- Domain helpers (specifications, simple algorithms) where they exist.
- Application-service unit tests **only** when they are pure orchestration with ≤ 2 collaborators and the assertion is meaningful.

**Don't test here**:
- Anaemic entities — there's no behaviour to test (the unit test is `entity.x = 1; entity.x shouldBe 1` — hollow).
- Services with 4+ collaborators — the test becomes 80% mock setup. Move to integration.

### Slice / integration layer (~50-70%)

**The centre of gravity.** This is where most signal lives.

**Test here**:
- `@DataJpaTest` + Testcontainers Postgres for every repository — query correctness, indexes, JSONB, cascades.
- `@WebMvcTest` per controller — HTTP validation, error responses, security.
- `@RestClientTest` per outbound HTTP client.
- Kafka producer / consumer tests with real container.
- Application service tests in slice or `@SpringBootTest`-narrow with real DB + mocked external HTTP. These are where business rules over data actually run.
- Search / projection tests with real Elasticsearch / Clickhouse.
- `@TransactionalEventListener` + outbox commit-time tests.

**Don't test here**:
- Whole user journeys — move to acceptance.
- Pure value-object rules — covered at unit.

### Acceptance layer (~5-15%)

**Test here**:
- Critical user journeys end-to-end.
- Bean wiring smoke.
- Cross-module flows.

**Don't test here**:
- Per-rule variations.
- Slice-level concerns already covered.

### What does *not* get tested in a Diamond

- Anaemic entity unit tests — hollow.
- Service unit tests with > 3 mocked collaborators — paid attention to mocks, not behaviour.
- Code in the Overcomplicated quadrant — refactor first.

---

## Inverted Pyramid — per-layer allocation

For: legacy systems that can't be refactored *yet*, thin coordination services where e2e *is* the business value. **Rare as a chosen shape.**

### Unit layer (~10-20%)

**Test here**:
- The few extractable pure helpers.
- Value objects.
- Migration code (DB scripts, data-fixup logic) where extractable.

**Don't test here**:
- Anything that requires the legacy environment to make sense.

### Integration layer (~20-30%)

**Test here**:
- Per-component slice tests where the slice is *possible* — many legacy components don't slice cleanly.
- Adapter tests.

### E2E layer (~50-70%)

**Test here**:
- Critical user journeys.
- Coordination flows.
- Regression scenarios captured as characterisation tests during legacy hardening.

**Don't test here**:
- Anything reachable by slice / unit; redirect those.

### What does *not* get tested in an Inverted Pyramid

- Per-line behaviour. Coverage is necessarily incomplete; aim for **critical-path** coverage, not line coverage.

### Mandatory escape plan

An inverted pyramid is **never** the long-term target. Every quarter:
- Identify one piece of logic to extract from e2e into a slice / unit test.
- Migrate the test, delete the e2e.
- Repeat until the shape is diamond or pyramid.

---

## Honeycomb — per-layer allocation

For: glue / gateway / API aggregator / event-routing microservices.

### Unit layer (~10-20%)

**Test here**:
- The rare pure transformation (request → DTO mapping with non-trivial logic).
- Request validation rules.
- Auth-related pure logic.

**Don't test here**:
- Routing logic — that's integrated-service-level.
- Transformations that are 1-line `dto.copy(...)` — trivial.

### Integrated-service layer (~70-80%) — the bulk

**Test here**:
- Start the service + real DB + real queue (or fast in-memory equivalents); stub external HTTP via WireMock or Pact stub server.
- Drive a request / event through the whole service.
- Assert on side effects: DB rows, queue messages, downstream HTTP calls (verified via WireMock).
- Per critical flow: happy path + key error paths (timeout, downstream 500, idempotent retry).

**Don't test here**:
- Per-line rules — for a glue service, the value is the wiring.

### E2E layer (~5-15%)

**Test here**:
- One or two true end-to-end flows including real downstream partners (gated CI tier).

**Or, in place of e2e**:
- Contract tests (see `test-contract`) with each partner. Often beats brittle e2e for cross-service compatibility.

### What does *not* get tested in a Honeycomb

- In-process business rules (there aren't any).
- The downstream services' behaviour (those have their own suites).

---

## Testing Trophy — per-layer allocation (frontend)

For: React / Vue / Svelte / Angular component-heavy frontends.

### Static layer (~10%)

**Test here**:
- TypeScript strict mode catches a huge class of bugs.
- ESLint / Stylelint catches code-style and obvious bugs.
- Type tests for generic-heavy library code.

### Unit layer (~30%)

**Test here**:
- Pure helpers — formatters, parsers, validators, sorting / filtering logic.
- Reducers / state-management pure logic.
- Selectors / memoised derivations.
- Pure routing logic where applicable.

**Don't test here**:
- Component rendering in isolation with heavy mocking (move to integration).

### Component / integration layer (~40%) — the bulk

**Test here**:
- Mount the component (and its real children) with `@testing-library/react` / `@testing-library/vue` etc.
- Drive interactions as a user would — click, type, navigate.
- Assert on what the user sees / what accessibility tools see.
- Use MSW (Mock Service Worker) to intercept fetch / GraphQL at the network layer, not the React hook layer.

### E2E layer (~20%)

**Test here**:
- Happy paths through the entire app — Playwright / Cypress.
- Critical user journeys (signup, checkout, primary feature flow).
- Cross-browser smoke (Chrome + WebKit + Firefox).

**Don't test here**:
- Per-component variations — covered at component layer.

### What does *not* get tested in a Trophy

- Component implementation details (state shape, hook call order). Behaviour, not internals.
- CSS pixel-perfect comparisons (visual regression tools handle this separately).
- Third-party library internals.

---

## Per-shape quick-allocation matrices

### Pyramid

| Behaviour | Layer |
|---|---|
| Aggregate state transition (happy path + invariant) | Unit |
| Value object invariant | Unit |
| Domain service composition | Unit |
| Pricing / algorithm | Unit |
| Repository query against Postgres | `@DataJpaTest` |
| Controller HTTP / validation | `@WebMvcTest` |
| Outbound HTTP client | `@RestClientTest` |
| Full user journey | Acceptance (narrow `@SpringBootTest`) |
| Anaemic getter/setter | NOT TESTED |
| Spring framework correctness | NOT TESTED |

### Diamond

| Behaviour | Layer |
|---|---|
| Value object invariant | Unit |
| Money arithmetic | Unit |
| Repository query | `@DataJpaTest` + Testcontainers |
| Controller HTTP | `@WebMvcTest` |
| Service over real DB | `@SpringBootTest`-narrow with real DB |
| External HTTP | `@RestClientTest` + WireMock |
| Whole user journey | Acceptance |
| Anaemic entity field | NOT TESTED |
| Service with 6+ mocked collaborators | NOT TESTED (refactor or move to integration) |
| Toy delegating methods | NOT TESTED |

### Honeycomb

| Behaviour | Layer |
|---|---|
| Pure transformation | Unit (rare) |
| Routing + DB + queue + stub external | Integrated-service |
| Cross-service compatibility | Contract |
| Critical e2e flow | E2E |
| In-process business rule (doesn't exist) | NOT TESTED |

### Testing Trophy (frontend)

| Behaviour | Layer |
|---|---|
| TypeScript type | Static |
| Pure reducer / selector | Unit |
| Component behaviour as user sees it | Component / Integration |
| Critical user flow across pages | E2E |
| Component implementation detail | NOT TESTED |
| Library internals | NOT TESTED |

---

## The "what to NOT test" patterns (cross-shape)

These deserve a permanent home in PR-review:

- **Test of one-line delegation** — `fun submit(cmd) = handler.submit(cmd)`. Test `handler`; the delegation is enforced by the compiler.
- **Test that mocks 80% of what it's testing** — the seam is too coarse. Either find a higher-level seam or extract a pure function.
- **Test that asserts `verify { mock.method(...) }` and nothing else** — testing that the function calls the mock. Behaviour ≠ method call.
- **Test of generated code** — data class `equals`, `hashCode`, `copy`; Lombok / record getters; Jackson default serialisation.
- **Test of trivial constructor / property** — `Order(id=...).id shouldBe ...` — tautology.
- **Test "for coverage"** — written purely to make the metric green. Delete; it's noise.
- **Test of framework correctness** — that `@Cacheable` caches, that `@Transactional` rolls back. Trust the framework.
- **Test that depends on `Thread.sleep`** — flaky by construction. Either inject a deterministic seam or use Awaitility + a real condition.
- **Test that asserts on private state via reflection** — the state isn't public; assert on observable behaviour.
- **Test of `toString()` for non-contract logging** — not behaviour.

If you're writing one of these, the test is **owed an explanation in the PR**. Most often, the right answer is "delete".

---

## When the shape is mixed (multi-module / CQRS / hexagonal)

Per-module allocation. Apply the matching shape's matrix to each module. Document the choice in an ADR. Re-evaluate when the module's architecture shifts.

A modular monolith's overall suite shape is the *weighted union* of its per-module shapes — and that's fine. The repo doesn't need a single uniform shape; the **modules** do.

---

## A reading checklist for your existing suite

For an existing project, run this against the test suite:

1. **Count** by layer (grep for slice annotations). Match against your stated shape.
2. **Sample 10 random unit tests**. For each, ask "what bug would this catch?". If the answer is "nothing real" — it's in the Trivial quadrant; the test is wasted.
3. **Sample 10 random unit tests of services**. Count the mocks per test. If most are > 3 — those tests are paying for mock setup, not behaviour. Convert to integration.
4. **Sample 5 random integration tests**. Each should cover a true deployment seam (DB / queue / HTTP / security). If not — convert to a slice or unit.
5. **Check the floor**: do you have JSONB / partial-index / Tx-listener / Kafka serde / Spring Security integration tests? If not, the floor is missing regardless of shape.

The output of this checklist is **the audit** that motivates the refactor toward the right shape.
