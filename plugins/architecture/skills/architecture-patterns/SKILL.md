---
name: architecture-patterns
description: "Picking the layout pattern for a Kotlin/Spring Boot service or module — Layered (MVC), Onion, Clean Architecture, with DDD as an overlay on top of Onion/Clean. Defines module boundaries, package structure, dependency direction, and the architectural fitness test that enforces them in CI (ArchUnit, Spring Modulith `ApplicationModuleTest`). Use when designing a new service / module from scratch and picking the layout, refactoring a Layered codebase toward Onion when the domain has grown, migrating from anaemic controllers/services to a domain-centric structure, or establishing module-layout standards for a team. Use AFTER `architecture` has decided that architectural investment is warranted; BEFORE `architecture-decision-records` captures the choice; the per-pattern code idioms inside a chosen layout (aggregates, value objects, repositories) belong to `ddd-tactical-patterns`."
risk: safe
source: custom
---

# Architecture Patterns

> "The layout pattern decides the dependency direction. Once it's wrong, every future change pays interest."

This skill picks **one of four layout patterns** for a Spring Boot service. It doesn't decide whether the service is worth architecting (`architecture`), doesn't capture the decision (`architecture-decision-records`), doesn't audit an existing one (`architect-review`), and doesn't write code inside a chosen layout (`ddd-tactical-patterns`).

Hexagonal (Ports & Adapters) is intentionally **omitted** — Clean and Onion already cover the same dependency-inversion goal with less ceremony for the Spring stack. If a problem genuinely pushes toward ports/adapters vocabulary, model it as Clean Architecture.

## Use this skill when
- Designing a new Spring Boot service or module from scratch and picking the layout shape.
- Refactoring a Layered/MVC codebase toward Onion/Clean as the domain grows real invariants.
- Migrating anaemic controller-service-repository code to a domain-centric structure.
- Establishing module-layout standards for a team or codebase.
- Deciding whether to overlay DDD discipline on top of an Onion or Clean structure.
- Adding architectural fitness tests (ArchUnit, Spring Modulith `ApplicationModuleTest`) to enforce the chosen layout in CI.

## Do not use this skill when
- The task is **deciding whether** architectural investment is justified at all → `architecture`.
- The task is **writing the ADR** that records the chosen pattern → `architecture-decision-records`.
- The task is **auditing an existing layout** for compliance or smells → `architect-review`.
- The task is **DDD code-level patterns** inside one bounded context (aggregates, value objects, repositories, domain events) → `ddd-tactical-patterns`. This skill picks the layout; that one shapes the code inside it.
- The task is **microservices decomposition** (when to split a monolith into services) → `microservices-patterns-deep` (cross-service operational concerns) or `ddd-strategic-design` (where the bounded-context lines go).
- A small local refactor with no cross-component impact — picking a layout pattern overfits a single-file change.

## The four patterns at a glance

| Pattern | One-line shape | Best fit | Cost | When it stops scaling |
|---|---|---|---|---|
| **Layered (MVC)** | Controller → Service → Repository, top-down dependencies. | Simple CRUD, small team (≤ 3), short horizon, minimal domain invariants. | Almost zero. The default Spring scaffold gives you this for free. | When business logic spreads across services and the same rule appears in 3+ places — that's the moment to move to Onion. |
| **Onion** | Domain core (no framework); ports outward; adapters at the rim depend inward. | Rich domain with real invariants; multi-month/year horizon; team can hold "domain has no framework imports" in their heads. | Moderate. Setup ceremony, but Spring autoconfig keeps it manageable. | When you need formal use-case orchestration with cross-cutting policy enforcement — that's Clean. |
| **Clean Architecture** | Onion + explicit Use-Case / Interactor layer + named ports for each crossing. | Large domain, multiple input adapters (HTTP + CLI + scheduler + message handler), strict reusability across entry points. | High. Most ceremonious; pays back when use-cases are reused across input channels. | When the domain itself needs strategic decomposition into bounded contexts — that's where DDD overlay enters. |
| **DDD (overlay)** | Not a layout — a vocabulary that overlays Onion or Clean. Bounded contexts as modules, aggregates as transactional roots, domain events as cross-context glue. | Domain has real rules domain experts can articulate; team is large enough to align on ubiquitous language; the domain genuinely differentiates the business. | High plus learning curve. | When the team starts splitting bounded contexts into separate services — that's `microservices-patterns-deep` territory. |

## The decision in one sentence

Pick **Layered** unless the domain has invariants that escape into services. Then pick **Onion**. Add **Clean's** explicit use-case layer only when multiple input adapters reuse the same domain operations. Add **DDD overlay** when the domain is rich enough that domain experts and engineers need a shared vocabulary.

## Pattern selection process

1. **Surface the domain shape.** Is logic mostly "load X, mutate field Y, save"? Or are there rules like "an order cannot be submitted empty" that must hold across every path? CRUD → Layered. Real invariants → Onion-or-better.
2. **Surface the team and horizon.** Solo dev shipping in 6 weeks vs. 10-person team for a 3-year product. Layered fits the first; Onion+ fits the second.
3. **Surface the input adapters.** One HTTP API → Onion is enough. HTTP + CLI + scheduler + message bus all calling the same operations → Clean's use-case layer earns its keep.
4. **Decide DDD overlay separately.** DDD is orthogonal to Layered/Onion/Clean — it answers "how do we slice the domain into modules" not "how do layers depend on each other." Layered + DDD is uncommon but not wrong; Onion + DDD is the canonical pairing.
5. **Define the dependency direction explicitly.** Layered = outer-to-inner with a hard "no looping back" rule. Onion/Clean = arrows always point inward toward the domain core.
6. **Add the fitness test.** Without enforcement in CI, the layout decays in months. ArchUnit for package rules; Spring Modulith `ApplicationModuleTest` for module boundaries.

## Anti-patterns

| Anti-pattern | Signal | Fix |
|---|---|---|
| **Pattern shopping** | Adopting Clean Architecture "because it sounds clean" without a problem that demands it. | Start with the simpler pattern (Layered → Onion → Clean). Promote only when the simpler one visibly hurts. |
| **Hexagonal as default** | Every new service gets ports + adapters even when there's one HTTP entry and one DB. | Use Onion or Clean; Hexagonal's vocabulary doesn't earn its keep in single-adapter services. |
| **Layered with leaking domain logic** | Services contain `if/else` chains over entity state; the same rule appears in 4 services. | Time to move to Onion — the rules want to live in domain objects, not in services. |
| **Onion with `@Entity` on the domain** | JPA annotations sprinkled on supposedly-pure domain classes; domain tests need a database. | Move JPA mapping to a persistence-layer entity; map between persistence and domain. Yes, it's more code. Yes, it's worth it. |
| **Use-case layer without reuse** | Clean Architecture's Use-Case layer wraps one method that only one controller ever calls. | If there's no reuse across input adapters, the use-case layer is ceremony. Collapse to Onion. |
| **DDD on a CRUD app** | Bounded contexts, aggregates, repositories, value objects — for a 3-table internal tool. | DDD is a tax that pays off when invariants exist. Don't force it on systems without them. |
| **Layer-skipping** | Controllers calling repositories directly, bypassing the service layer (or domain layer). | Either the skipped layer is useless (delete it and own the simpler shape) or the skip is a bug (fix it). Half-honoured layers are the worst kind. |
| **No fitness test in CI** | Layout enforced only by code review; small violations accumulate over months. | Add ArchUnit or Spring Modulith verifier from day one. Hand-enforcement always loses to attrition. |
| **Pattern mixed within one module** | Half-Onion / half-Layered — different files follow different rules. | Pick one per module. Mixing creates two mental models that drift in opposite directions. |

## Spring/Kotlin stack mapping

| Concern | Default |
|---|---|
| Layered structure | Standard Spring scaffold: `controller` / `service` / `repository` packages. |
| Onion structure | Domain in its own module / package with **zero Spring imports**. Adapters in `infrastructure` / `persistence` / `web` packages depending inward. |
| Clean structure | Add a `usecase` / `application` package between domain and adapters; each use-case is a small `@Service`-annotated class. |
| Module isolation | Spring Modulith `@ApplicationModule` per bounded context; `ApplicationModuleTest` for enforcement. |
| Architectural fitness test | ArchUnit (`com.tngtech.archunit`) for package-dependency rules; Spring Modulith verifier for module graph. Run in CI as part of `./gradlew check`. |
| Cross-cutting concerns | AOP / Spring interceptors at the adapter rim. Never in the domain core. |
| Domain events | In Onion/Clean: domain emits events; adapter publishes via `ApplicationEventPublisher` or Modulith. See `cqrs-implementation` for projection patterns. |

## Selective reading rule

| File | When to read |
|---|---|
| `resources/implementation-playbook.md` | Detailed per-pattern layouts, full Kotlin/Spring code samples, per-pattern pitfalls, ArchUnit rule examples, Modulith verifier setup. |

## Related skills

| Skill | This not that |
|---|---|
| `architecture` | Decides *whether* architectural investment is warranted. This skill picks the *layout* once that decision is made. |
| `architecture-decision-records` | Captures the chosen pattern as an ADR. This skill makes the choice; that one records it. |
| `architect-review` | Audits an existing layout for compliance and smells. This skill picks the layout; that one critiques it. |
| `ddd-tactical-patterns` | DDD code-level patterns *inside* a chosen layout — aggregates, value objects, repositories, domain events. This skill picks the box shape; that one fills the boxes. |
| `ddd-strategic-design` | Bounded contexts as the *domain* slicing — orthogonal to layout. Pair with this skill when applying DDD overlay. |
| `microservices-patterns-deep` | Cross-service operational concerns once the team decides to split contexts into separate services. |
| `system-design-fundamentals` | System-scale design (capacity, reference architectures) — operates above the layout-pattern decision. |
| `testing-strategy-kotlin-spring` | The slicing of tests follows the architectural layout (`@WebMvcTest`, `@DataJpaTest`, etc.). |

## Limitations
- Hexagonal / Ports-and-Adapters is intentionally not enumerated as a fifth pattern; model it as Clean Architecture if that vocabulary fits the team.
- The choice of pattern is downstream of the system's dominant quality attributes (evolvability vs. simplicity vs. performance). If those are unclear, resolve them first via `architecture` or `system-design-fundamentals`.
- Layout patterns are *long-lived* decisions — closer to a one-way door. Use `architecture-decision-records` to capture the choice with a revisit trigger ("if we add a second input adapter, reconsider Clean").
