---
name: test-strategy
description: "Test-suite shape selection — pyramid / diamond / inverted pyramid / honeycomb / testing trophy — and the algorithm that picks the right one based on the business-logic architecture (Transaction Script / Active Record / Anemic Domain / Domain Model / UI-heavy frontend). Synthesised on top of Khorikov's four quadrants (Trivial / Controllers / Domain Model & Algorithms / Overcomplicated) from *Unit Testing: Principles, Practices and Patterns* — what each shape costs, what each shape misses, which layer carries the centre of gravity, and what tests are wasted effort under each shape. Use when starting a new service / module and the test plan is blank, refactoring a suite that feels slow / brittle / low-signal, splitting a monolith and each piece may need a different shape, joining a project where the suite is upside-down (e.g. all `@SpringBootTest`) and you need to justify the corrective move, picking what to test at the use-case / integration / unit layer, deciding what NOT to test (Khorikov's most undertaught insight), reviewing whether existing test allocation matches the architectural style, designing the test plan for a CQRS / event-sourced / hexagonal service, picking a shape for a frontend (React / Vue) module separately from the backend, or settling a team disagreement about \"should we have more unit or more integration\". This skill picks the *shape* and *layer allocation*; the per-layer content (what to write, with which tools) lives in test-unit / test-integration / test-acceptance / test-contract / test-architecture; the per-test discipline (F.I.R.S.T., readability, DSL) lives in test-principles."
risk: safe
source: "Synthesised from Khorikov, *Unit Testing: Principles, Practices and Patterns* (Manning, 2020), Mike Cohn's pyramid, Ham Vocke / Martin Fowler practical pyramid, Spotify's honeycomb, Kent C. Dodds's Testing Trophy, plus house experience"
date_added: "2026-05-12"
---

# Test Strategy — Shape and Layer Allocation

The single biggest leverage point in a test suite is **shape**: how many tests live at the unit layer vs the integration layer vs above. Picking the wrong shape costs years — a `@SpringBootTest`-heavy "pyramid" inverted into a brittle CI cycle, or a pyramid of unit tests over an anaemic domain model that catches nothing. The right shape is **not** a default; it follows from the **architecture of the business logic** under test.

> The pyramid was right *for the codebases Mike Cohn was looking at in 2009*. A modern Spring service that does CRUD-over-Postgres with anaemic JPA entities is a different beast. Same with a React app, same with a Transaction Script in stored procedures. Pick the shape the architecture earns, not the shape the conference talks default to.

This skill is the **front-of-funnel decision**: given what the system *is*, what shape should its test suite be, and where should the centre of gravity sit? The per-layer details (how to write a clean `@DataJpaTest`, what belongs in `test-unit` vs `test-integration`) live in the layer-specific skills.

## Use this skill when

- Starting a new service / module and the test plan is blank.
- Joining a project whose suite is **upside-down** (all `@SpringBootTest` and brittle, or all unit tests and missing real integration bugs).
- Refactoring a suite that **feels** wrong — slow, brittle, low-signal — and you need a framework to name *what* is wrong.
- Splitting a monolith — each carved-out piece may legitimately need a *different* shape.
- Designing the test plan for a **CQRS / event-sourced / hexagonal** service where the write side and read side have different shapes.
- Picking a shape for a **frontend module** separately from the backend (the trophy/honeycomb usually beats the pyramid for UI).
- Deciding what to **NOT** test — Khorikov's most undertaught insight: code in the *trivial* quadrant and the *overcomplicated* quadrant has near-zero test ROI; the latter must be refactored, not tested.
- Settling a team disagreement: *"should we add more unit or more integration tests?"* — the architectural style answers it.
- Reviewing whether existing test allocation matches the codebase shape (often it doesn't, because the codebase shifted but the test allocation didn't follow).

## Do not use this skill when

- You're writing or refactoring **an individual test** — its content is `test-principles` (per-test discipline: F.I.R.S.T., readability, DSL) and the relevant layer skill (`test-unit`, `test-integration`, …) for tooling.
- You already have the right shape and just need to add the next test in an existing layer — go straight to that layer skill.
- The question is about **TDD vs after-the-fact testing discipline** — that's `test-principles`.
- The question is **purely tooling** ("how do I write `@DataJpaTest` with Testcontainers?") — that's `test-integration`.

## Selective Reading Rule

Read the file that matches the decision you're making.

| File | Description | When to read |
|---|---|---|
| `resources/shapes.md` | The five canonical shapes — Pyramid, Diamond, Inverted Pyramid, Honeycomb, Testing Trophy. What each looks like, what it costs, what it misses, when it's right, when it's wrong. | First read — you need vocabulary before you can pick. |
| `resources/architecture-to-shape.md` | The selection algorithm — Khorikov's four quadrants applied to architectural styles (Transaction Script / Active Record / Anaemic Domain / Domain Model / CQRS / Hexagonal / Event-sourced / UI-heavy) and the shape each earns. | When you know the architecture and need to pick the shape. |
| `resources/what-test-where.md` | Per-shape layer-allocation matrix — for each shape, which behaviours go to which layer (and which behaviours are NOT tested at all). The most useful day-to-day reference. | When the shape is fixed and you're allocating a specific feature's tests across layers. |

## The four-step decision

Don't pick a shape by vibe. Pick it by the four questions below — answered against the **current** state of the codebase, not the *aspired* state.

1. **Where does the business logic live?**
   In the domain layer (behaviour-rich aggregates) → centre of gravity belongs at unit. In services orchestrating data bags → integration. In SQL / stored procedures → integration / DB-direct. In a React component tree → component-level.
2. **What collaborator density?** (Khorikov's collaborator axis)
   Few collaborators (pure functions, value objects, aggregates) → cheap to unit-test. Many collaborators (controllers, application services that wire 6 ports) → unit-testing the orchestration is mostly mock setup; integration is more informative.
3. **What complexity?** (Khorikov's complexity axis)
   High decision density / many branches / invariants → unit tests are highest-ROI. Trivial getters / setters / one-line delegations → tests are wasted effort *at any layer*.
4. **What's the deployment seam — what could break at runtime that unit tests will miss?**
   Postgres JSONB queries, Kafka partition keys, JPA cascade behaviour, async event handlers, retry/idempotency, Spring Security config, OAuth flows — these *must* have integration coverage regardless of shape; they are the floor under whatever shape you pick.

If you answer those four honestly, the shape falls out. The files in `resources/` make the mapping explicit.

## Khorikov's four quadrants — the underlying model

Khorikov classifies code on two axes — **complexity** (how much branching / invariants / decisions) and **collaborator count** (how many external dependencies). The four quadrants:

```
                    high complexity
                          ▲
                          │
   Overcomplicated  ─────┼─────  Domain Model
   (refactor — don't       │  & Algorithms
    test as-is)            │  (UNIT — highest ROI)
                          │
   ───────────────────────┼─────────────────────► many collaborators
                          │
   Trivial                 │  Controllers
   (don't test —           │  (INTEGRATION —
    getters, plain          │   unit-mocking is
    data classes)           │   mostly mock setup)
                          │
                          ▼
                    low complexity
```

The shape of a codebase = **the distribution of its code across these quadrants**. A pure Domain Model service has most code in the top-left → pyramid earns its place. A CRUD-over-JPA service has most code in the bottom-right → diamond, because the unit layer of that codebase tests Trivial code (low value) and the orchestration is Controllers (better tested as integration). A Transaction Script service has logic *inside* SQL / procs → diamond pulled toward integration / inverted, because the "business logic" isn't even in the JVM.

The shape is downstream of the architecture. **Change the architecture and the shape must change with it.** A refactor from anaemic JPA toward behaviour-rich aggregates *should* be accompanied by a shift in test allocation toward the unit layer. If it isn't, the new domain model is uncovered and the integration tests stay artificially high — both wasted.

## Quick shape lookup

| Architecture | Default shape | Centre of gravity | Read more |
|---|---|---|---|
| Domain Model (DDD-tactical, behaviour-rich aggregates, hexagonal ports) | **Pyramid** | Unit (domain) | `architecture-to-shape.md` §Domain Model |
| Anaemic Domain (data-bag entities + thick services) | **Diamond** | Integration (slice) | `architecture-to-shape.md` §Anaemic |
| Active Record (entity = row + behaviour mixed) | **Diamond** | Integration (slice + Testcontainers) | `architecture-to-shape.md` §Active Record |
| Transaction Script (logic in scripts, often partly in SQL / procs) | **Diamond → Inverted** | Integration / acceptance | `architecture-to-shape.md` §Transaction Script |
| CQRS (write side: aggregates, read side: projections) | **Two shapes** — pyramid on write, diamond on read | Mixed | `architecture-to-shape.md` §CQRS |
| Event-sourced | **Pyramid** for aggregate decisions + diamond for projection rebuild | Mixed | `architecture-to-shape.md` §Event-sourced |
| Frontend (React / Vue, UI-heavy) | **Testing Trophy** (Kent C. Dodds) — heavy on integration / component | Component / integration | `architecture-to-shape.md` §Frontend |
| Pure infrastructure / glue service (no business logic) | **Honeycomb** | Integration | `architecture-to-shape.md` §Glue |

## Common shape mistakes (catalogue)

- **Pyramid over anaemic domain.** Unit tests on data-bag entities check `getter()` returns the field passed to `setter()`. The actual decisions live in the service + DB. Diamond fits.
- **Inverted (mostly `@SpringBootTest`) by accident.** Started with one `@SpringBootTest`; every new test reused that base class because it worked. CI now takes 14 minutes. Audit and replace with slices / unit where possible.
- **Pyramid over Transaction Script.** Logic is in SQL / procs / orchestration scripts. Unit tests of the Java wrapper test the JDBC plumbing, not the business rule. Diamond / inverted.
- **No integration tests because "we have 95% unit coverage".** Coverage is per-line, not per-seam. Postgres-specific SQL, Kafka serdes, JPA cascade-delete behaviour, transactional event listeners — none are covered by unit tests. Integration is the floor, not negotiable.
- **Same shape for write side and read side of CQRS.** Wrong: the two sides have different code shapes (rich domain vs flat projection) and need different test allocations.
- **Frontend imitating the backend pyramid.** Component logic is mostly composition of library calls (React, Redux, Apollo); unit-testing components in isolation requires mocking the world. Testing Trophy / honeycomb fits — mount the component, render it, drive it as a user would.

## Anti-patterns at the strategy level

- **"More tests is always better."** No. Tests in the trivial quadrant (one-line getters, plain data classes) and in the overcomplicated quadrant (god services with 14 collaborators) are wasted effort — the former because there's nothing to break, the latter because the test ends up being 80% mock setup. Khorikov's insight: **what to NOT test is half the strategy.**
- **Picking shape by tool stock.** "We have JUnit + AssertJ + Testcontainers, so we should…" The tools don't pick the shape. The architecture does.
- **One shape across the org.** A monolithic codebase may legitimately host multiple shapes — domain modules on pyramid, glue services on honeycomb, read-side projections on diamond. Picking *one* shape org-wide forces some pieces into bad fits.
- **Refusing to change shape after a refactor.** When the architecture shifts (anaemic → behaviour-rich, CRUD → CQRS, monolith → modular), the *correct* shape shifts with it. Test allocation must follow; otherwise the new architecture is uncovered and the old shape is now noise.
- **Coverage as the steering signal.** Coverage measures *which lines ran during the suite*, not *whether the behaviour is pinned down*. Mutation testing (`test-architecture`) is the real signal for effectiveness; coverage is the symptom.

## Related skills

- `test-principles` — the per-test discipline (F.I.R.S.T., TDD laws, BUILD-OPERATE-CHECK, DSL, single concept, dual standard). Strategy picks the *shape*; principles make each test inside it read well. Pair them.
- `test-unit` — once strategy says "this code earns unit tests", how to write them (general, Kotlin idioms, Spring-light cases).
- `test-integration` — slice tests + Testcontainers + adapter tests. The bulk of a diamond / inverted shape lives here.
- `test-acceptance` — use-case-level tests through application services with in-memory adapters or narrow `@SpringBootTest`.
- `test-contract` — consumer-driven contracts where shape doesn't help (cross-service compatibility is its own concern).
- `test-architecture` — fitness functions (ArchUnit, Modulith) + mutation testing (Pitest); shape-independent quality gates.
- `architecture-patterns`, `ddd-tactical-patterns`, `cqrs-implementation` — *they* shape the codebase; *this* skill picks the test allocation that fits the shape they create.
- `methodology-karpathy-guidelines` — §4 verifiable success criteria; the shape is the criterion for "the suite is well-allocated".

## Limitations

- **The shape is a default, not a contract.** Inside a pyramid-shaped service, a complex integration concern (e.g. JSONB partial index behaviour) still earns its integration test. Inside a diamond-shaped service, an algorithm with rich invariants (e.g. pricing) still earns unit tests. The shape names the centre of gravity, not a quota.
- **Khorikov's quadrants are a model, not a ruler.** The thresholds (where "few collaborators" becomes "many", or "low complexity" becomes "high") are judgement calls. Use the quadrants to *frame* the decision; don't use them as a checklist.
- **The shape can change inside one project.** If you carve out a behaviour-rich module from an otherwise anaemic service, that module earns a pyramid even though the surrounding code is diamond. Don't fight that — it's correct.
- **Property-based and mutation testing are orthogonal to shape.** Property-based fits whichever layer hosts the invariant; mutation testing fits any layer where you want to verify the tests *actually* assert something. Neither moves the centre of gravity.
- **For a brand new project where the architecture isn't decided yet**, the test strategy is also undecided. Default to pyramid + integration floor; revise as the architecture earns it.
