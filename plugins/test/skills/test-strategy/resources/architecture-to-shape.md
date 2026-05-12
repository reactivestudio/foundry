# Architecture → Shape: The Selection Algorithm

The shape of the test suite is **downstream** of the architecture of the business logic. Pick the architecture deliberately; the shape follows.

This file is the mapping. For each architectural style — what the code looks like, which Khorikov quadrants dominate, which shape earns its place, what changes if you refactor.

> "There is no universal 'right' shape. There is the shape that matches *this* code. Change the code and the shape changes with it." — house ethos

## Khorikov's four quadrants — recap

From Vladimir Khorikov, *Unit Testing: Principles, Practices and Patterns* (Manning, 2020), code lives on two axes:

- **Complexity / domain significance** — how much decision density, how many invariants, how many branches per line.
- **Number of collaborators** — how many external dependencies (other classes, services, ports).

The four quadrants:

|  | **Few collaborators** | **Many collaborators** |
|---|---|---|
| **High complexity** | **Domain Model & Algorithms** — unit-test, highest ROI | **Overcomplicated** — refactor; don't test as-is |
| **Low complexity** | **Trivial** — don't test; getters / data bags | **Controllers** — integration-test |

The shape of a codebase is the **distribution of code across these quadrants**. The shape of the test suite should mirror it:

- Lots of Domain Model & Algorithms → pyramid.
- Lots of Controllers → diamond.
- Lots of Trivial → those lines aren't tested at all.
- Lots of Overcomplicated → fix the code; until then, integration tests are the only meaningful coverage.

**Khorikov's most undertaught insight**: what you **don't** test is half the strategy. A 95%-covered codebase where the 95% is Trivial code and the 5% gap is the Overcomplicated god service has near-zero confidence. A 70%-covered codebase where the 70% is Domain Model has very high confidence. Coverage is not the signal; **distribution** is.

---

## Architectural style → quadrant distribution → shape

### Transaction Script

**The code**: business logic in procedural scripts (Java/Kotlin methods, often calling SQL / stored procedures directly). Each "transaction" is one method that does the full thing — read inputs, query DB, compute, write back. Entities are usually plain data classes or even raw `Map<String, Any?>`. Logic often partly lives in SQL.

Patterns. *Fowler, PoEAA Ch. 9*. Common in: reporting tools, ETL pipelines, accounting systems, billing scripts, integration glue, "import this CSV into Postgres" jobs.

**Quadrant distribution**:
- A lot of code in **Controllers** (procedural orchestration, many DB / external collaborators).
- A non-trivial chunk in **Overcomplicated** (the script grew, decisions piled up).
- Some in **Trivial** (data classes).
- Almost nothing in **Domain Model & Algorithms** — there is no domain model.

**Earned shape**: **Diamond, pulled toward Inverted in extreme cases.**
- Few unit tests — there's almost nothing pure to unit-test. Most decision logic is interlocked with IO / SQL.
- Integration tests dominate — script + real DB. This is where the logic actually executes correctly.
- Acceptance / end-to-end for the whole flow. Often the most readable specification.
- *If* a piece of pure computation is extractable (a formula, a date-arithmetic helper), unit-test it; that's a hint to extract toward Domain Model.

**Anti-pattern at this architecture**: classic pyramid with many unit tests of the Java wrapper around `jdbcTemplate.query(...)`. They test that mocking `JdbcTemplate` works — not that the script is correct.

**What changes with refactor**: if you extract pure pricing / scheduling / parsing helpers from the script, those become Domain Model & Algorithms — pyramid for *those modules*. The script orchestration stays diamond.

---

### Active Record

**The code**: entities = rows. The entity class has both the data (fields) *and* the persistence behaviour (`save()`, `find()`, etc., or annotations that wire it). Business behaviour sometimes lives on the entity, sometimes in a service. Often coupled to ORM (JPA, Hibernate).

*Fowler, PoEAA Ch. 10*. Common in: Rails-style codebases ported to Java, simple CRUD services, projects where the ORM annotations dominate.

**Quadrant distribution**:
- Most code in **Controllers** (service-over-entity orchestration with many DB / framework collaborators).
- Some in **Trivial** (data fields, getters/setters, simple converters).
- Some in **Domain Model** if behaviour creeps onto entities — but often entangled with persistence concerns (lifecycle, lazy loading), which makes pure unit-testing impossible without an `EntityManager`.

**Earned shape**: **Diamond.**
- Slice tests (`@DataJpaTest` + Testcontainers Postgres) carry the bulk — they exercise the entity's persistence behaviour realistically.
- Unit tests on the entity for pure invariants where possible (factory rules, value-object constraints).
- Acceptance via `@SpringBootTest` for whole flows.

**Anti-pattern at this architecture**: heavy unit-testing of the entity with mocked `EntityManager` / mocked repository. You test the mock, not the behaviour.

**Khorikov's specific warning**: Active Record makes the Domain Model quadrant nearly impossible to reach because behaviour can't be separated from persistence. The natural shape is Controllers-dominant → Diamond.

**What changes with refactor**: Active Record → Domain Model migration means separating the persistence concern (JPA entity / mapper) from the behaviour-rich aggregate. The aggregate then becomes pure → unit-testable → pyramid earns its place for the new domain.

---

### Anaemic Domain Model (Layered MVC default)

**The code**: entities are data bags (fields + getters/setters, no behaviour). All logic lives in services that orchestrate the data bags + repositories + other services. Spring `@Service` + JPA `@Entity` + `@Repository` is the canonical anti-pattern. Often called "Anemic Domain Anti-pattern" (Fowler).

Common in: most enterprise Java/Kotlin services that haven't deliberately adopted DDD or Clean Architecture.

**Quadrant distribution**:
- Most code in **Controllers** — services orchestrating many collaborators with light decision density per method.
- A lot in **Trivial** — data bag classes, getter/setter chains.
- The few rules that *are* complex are usually buried in services (becoming **Overcomplicated** as the service grows).
- Almost nothing in **Domain Model & Algorithms** — the entities have no behaviour.

**Earned shape**: **Diamond, leaning sometimes toward Inverted.**
- Unit tests of anaemic entities check that the getter returns the field. Hollow.
- Unit tests of services need a wall of mocks (every repository, every collaborator). The test becomes mock setup; the assertions are weak.
- Integration / slice tests with real DB carry the signal.
- Acceptance tests through application services are valuable — they exercise the orchestration.

**Anti-pattern at this architecture**: forcing pyramid by writing service unit tests with 8+ mocks. The result is a brittle, low-signal test that breaks on every refactor of the service internals.

**Khorikov's specific warning**: anaemic services with many collaborators sit squarely in the **Controllers** quadrant — they earn integration tests, not unit tests. Trying to unit-test them is the most common waste of test effort in enterprise Java.

**What changes with refactor**: anaemic → behaviour-rich migration moves the rules from services into aggregates. The new aggregates become Domain Model & Algorithms — pyramid for those. The services thin out and become true orchestrators — kept as integration / slice. The shape *should* shift from diamond toward pyramid as the refactor progresses.

---

### Domain Model (DDD-tactical, behaviour-rich aggregates)

**The code**: aggregates with private constructors and factory methods, methods that *do* the business operation and emit domain events, value objects encoding invariants, repositories as interfaces in the domain layer with impls in infra, application services orchestrating but holding no rules themselves.

*Evans, Vernon, Khorikov chapter "Functional Architecture"*. Common in: services deliberately designed with DDD, hexagonal / clean architecture, services where the core has been deliberately decoupled from framework.

**Quadrant distribution**:
- A large chunk in **Domain Model & Algorithms** — aggregates, value objects, domain services, specifications.
- A small chunk in **Controllers** — application services that orchestrate (few rules of their own).
- Small **Trivial** — DTOs, mapper boilerplate.
- Small **Overcomplicated** — if discipline is held.

**Earned shape**: **Pyramid.**
- Many fast unit tests on aggregates, value objects, domain services. Tests read as executable specifications of business rules.
- Slice tests for repository implementations (JPA / Mongo) verifying the mapper translates Domain ↔ row correctly.
- A few `@WebMvcTest` for HTTP serialisation / validation.
- Few `@SpringBootTest` — only true cross-layer smoke / acceptance.
- Architecture tests (ArchUnit / Modulith) to enforce the boundaries that make this shape sustainable.

**Khorikov's specific endorsement**: this is the architecture his book uses as the *positive* example. The unit-tests-of-domain layer is highest-ROI, fastest, most stable. Refactors of the application layer don't break domain tests. Refactors of the domain layer break exactly the tests that pin the rule that changed.

**What changes with refactor**: any move *away* from Domain Model toward anaemic / Active Record loses the pyramid. Migrate carefully — don't let the test pyramid degrade silently.

---

### CQRS (write side aggregates / read side projections)

**The code**: write side = commands → aggregates → events. Read side = events → projections (denormalised tables / search / analytics stores) → queries.

Common in: services with read/write asymmetry, event-sourced systems, services with polyglot projection stores (Elasticsearch for search, Clickhouse for analytics).

**Quadrant distribution**:
- **Write side**: heavy in **Domain Model & Algorithms** (aggregates, command handlers, event emission).
- **Read side**: heavy in **Controllers** (projection handlers orchestrating event → store → query).

**Earned shape**: **Two shapes — pyramid on write, diamond on read.**
- Write side: pyramid. Unit-test aggregates, value objects, command-handler validation. Slice for repository mapping.
- Read side: diamond. Slice / integration test projection handlers with real Postgres / ES / Clickhouse containers. Unit-test the rare pure transformation logic.
- Cross-side: a small set of acceptance tests verifying "command → aggregate → event → projection → query result" goes through correctly. These often live in `test-acceptance`.

**Anti-pattern**: forcing one shape across both sides. Either the write side under-uses unit tests (slow, low-resolution) or the read side gets pseudo-unit-tests on projection handlers with mocked stores (no real signal — projection bugs are SQL bugs, not Java bugs).

---

### Event-Sourced

**The code**: aggregates emit events; state is the event fold; replay reconstructs state; projection rebuild is a first-class operation.

**Quadrant distribution**:
- Heavy in **Domain Model & Algorithms** (event-emission rules, fold logic, invariants).
- Moderate in **Controllers** (projection updaters, replay coordinators).

**Earned shape**: **Pyramid for the write side (aggregates), with a special class of "given event stream, when next command, then expected events" tests at the unit level — Khorikov calls this the "output-based" test, the highest-quality unit test shape.** Plus diamond for the read side / projections.

**Specifically valuable test pattern**: the given-when-then over events:
```
Given: [OrderCreated, OrderItemAdded(2 widgets), OrderSubmitted]
When: cancel("customer request")
Then: emits [OrderCancelled(reason="customer request")]
```
This pattern reads as a business rule, runs in microseconds, and is the canonical Khorikov-style high-quality unit test.

**Anti-pattern**: testing the aggregate via in-memory store + repository mock. The event-sourced architecture *gives* you pure unit tests for free — using mocks is paying for what you already own.

---

### Frontend (React / Vue / Svelte component-heavy)

**The code**: component tree, state management (Redux / Zustand / Pinia / Vue store), data fetching (React Query / Apollo / SWR), routing.

**Quadrant distribution**:
- Most code in a frontend-specific quadrant — **composition over library calls**, with state and effects intertwined. This is roughly Controllers (many collaborators) but the collaborators are mostly libraries, not domain services.
- Pure logic (selectors, reducers, formatters, parsers) sit in Domain Model & Algorithms — but they are the minority of code.

**Earned shape**: **Testing Trophy** (Kent C. Dodds).
- Static (TypeScript + linter) is the foundation — catches a huge class of bugs cheaply.
- Component / integration tests dominate — mount with `@testing-library/react`, drive as a user would, assert on what the user sees.
- A few full e2e via Playwright / Cypress for the happiest paths.
- Pure-logic unit tests for reducers / selectors / pure helpers — small but valuable layer.

**Anti-pattern**: classic pyramid with Jest + heavy component mocking. You end up testing the mocks; component refactors break tests that aren't checking behaviour.

---

### Hexagonal / Ports-and-Adapters (a structural style, often combined with Domain Model)

**The code**: domain in the centre with no framework imports; ports (interfaces) declared in the domain layer; adapters (HTTP, JPA, Kafka, file system) implement the ports in the outer layer.

**Quadrant distribution**:
- Heavy **Domain Model & Algorithms** in the core.
- Adapters are mostly **Controllers** (orchestration over external collaborators).

**Earned shape**: **Pyramid on the core + Diamond on the adapter ring.**
- Domain core: pyramid. Pure unit tests, no Spring, no DB.
- Each adapter: slice-tested. `@DataJpaTest` for JPA adapter, `@RestClientTest` for HTTP adapter, real-Kafka-container test for Kafka adapter. Each adapter is independently verified.
- Application layer (use cases): tested with in-memory adapters (acceptance tests — see `test-acceptance`).
- Few `@SpringBootTest` for end-to-end.

**Why this is the gold standard**: each layer has a clean test seam. Refactoring the domain doesn't touch adapter tests. Swapping a JPA adapter for a different one (jOOQ, jdbi, native SQL) only re-runs that adapter's slice tests.

---

### Glue / Gateway / API Aggregator / Event-Routing Microservice

**The code**: receive HTTP / event → transform → forward to another service / topic. Almost no in-process business logic; the value is the wiring.

**Quadrant distribution**:
- Almost everything in **Controllers** (lots of collaborators, very little decision density).
- Almost nothing in Domain Model & Algorithms.

**Earned shape**: **Honeycomb.**
- Few unit tests (there's nothing to unit-test).
- Most tests are "service + real DB / real queue running, stubbed externals via WireMock / Pact stub server, drive a request through the whole service and assert on side effects".
- Contract tests for upstream and downstream dependencies (see `test-contract`).
- A handful of e2e for the happiest paths.

**Anti-pattern**: writing a classic pyramid for a gateway service. The unit tests test that you mocked `RestClient` correctly. You'd get 10× the signal with a Honeycomb shape and 1/3 the test count.

---

## Decision flowchart

Use the architecture you have, not the architecture you wish you had.

```
Is the codebase a frontend (React / Vue / Svelte / Angular)?
  → Testing Trophy (resources/shapes.md §Trophy)

Is most code pure orchestration / glue / routing — no in-process rules?
  → Honeycomb

Is logic in SQL / stored procedures / scripts (Transaction Script)?
  → Diamond (pulled toward Inverted for the heaviest scripts)

Are entities behaviour-rich aggregates with private constructors and methods that emit events?
  → Pyramid

Are entities data bags + thick services orchestrating them (anaemic / Layered MVC default)?
  → Diamond

Are entities JPA-driven with persistence concerns intertwined (Active Record)?
  → Diamond

Is this CQRS or event-sourced?
  → Hybrid: pyramid on write, diamond on read (CQRS); pyramid + event-stream tests (event-sourced)

Is this hexagonal / clean architecture with a rich domain core?
  → Pyramid for core + Diamond for each adapter
```

## Per-module shape (the realist's recipe)

In a real codebase, different modules will earn different shapes. **That is correct.** Don't pick one shape for the whole repo. Pick per-module.

A modular monolith might look like:
- `module-orders` (DDD, rich aggregates) → Pyramid.
- `module-billing` (heavy SQL scripts integrating with legacy invoicing) → Diamond.
- `module-api-gateway` (HTTP routing, request transformation) → Honeycomb.
- `module-events` (Kafka event routing, transform-and-forward) → Honeycomb.

Document the *per-module* shape choice in an ADR (`architecture-decision-records`). The reason: when the next refactor changes a module's architecture, the test allocation should change with it — and the ADR explains why.

## Heuristic: when the suite feels wrong

A wrong-fit shape usually announces itself:

| Symptom | Likely shape mismatch |
|---|---|
| Most unit tests don't catch real bugs; bugs found in production are in JSONB / Tx / async | Pyramid over anaemic domain — refactor toward diamond, or refactor the domain toward DDD |
| CI takes 15+ minutes; everything is `@SpringBootTest` | Inverted by accident — refactor toward diamond |
| Unit tests are 80% mock setup; service refactor breaks 12 unrelated tests | Pyramid over Controllers-heavy code — convert service unit tests to slice / integration |
| Refactoring inside the domain is scary; no fast-feedback safety net | Diamond over rich domain — add unit tests for the rules |
| Component refactor breaks 30 unit tests that mock the world | Pyramid on frontend — switch to Testing Trophy |

The fix is **never** to write more tests of the wrong kind. The fix is to recognise the architecture and pick the matching shape.

## See also

- `shapes.md` — vocabulary; what each shape looks like in detail.
- `what-test-where.md` — once the shape is fixed, what behaviour goes where.
- `architecture-patterns` — Layered / Onion / Clean / DDD-overlay; the architecture this skill is downstream of.
- `ddd-tactical-patterns` — how to refactor anaemic into behaviour-rich (which then earns a pyramid).
- `cqrs-implementation` — the CQRS shape this skill maps to two-shape allocation.
