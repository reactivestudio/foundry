---
name: grasp-patterns
description: "GRASP (General Responsibility Assignment Software Patterns) for Kotlin/Spring Boot — nine patterns for deciding which class should own which responsibility: Information Expert, Creator, Controller, Low Coupling, High Cohesion, Polymorphism, Pure Fabrication, Indirection, Protected Variations. The bridge between analysis and design — when SOLID asks 'is this class well-shaped?', GRASP asks 'should this method even live on this class?'. Use this skill whenever the user introduces a new class, refactors a service that reaches into entities to compute things ('feature envy'), spots scattered `new` calls that point at a missing Creator, fattens a controller with logic that belongs elsewhere, picks between event-based and direct calls, wraps a third-party vendor SDK to protect downstream code, or asks 'who should own this?'. Trigger especially for refactoring an anaemic domain into behaviour-rich classes, choosing between putting a method on the entity vs the service, deciding when to introduce an event vs a direct call, naming why a Util/Helper/Manager class is wrong, planning where a third-party vendor seam should sit, or audits before merge."
risk: safe
source: "custom — GRASP for Kotlin/Spring"
date_added: "2026-05-12"
---

# GRASP Patterns (Kotlin / Spring Edition)

Nine patterns for **assigning responsibilities** to classes — the bridge from analysis to design. SOLID validates a class's shape; GoF names a recurring shape; GRASP decides *which class gets which method* in the first place.

GRASP predates DDD by a decade and maps cleanly onto it. Think of GRASP as the "physics" of OO design (universal); DDD provides the "vocabulary" for a specific domain (project-local).

This skill is the canonical reference for GRASP applied through Kotlin idioms and Spring conventions. Sister skills cover the other foundational vocabularies:

- `solid-principles` — class-level shape rules (one reason to change, open/closed, substitutable, segregated, inverted)
- `gof-patterns` — pattern catalogue (Strategy, Decorator, Adapter, …) and what Kotlin subsumes

Together: GRASP picks the owner → SOLID validates the shape → GoF names the pattern that emerges.

## Use this skill when

- A new class needs introducing — pick the owner before writing code
- A service "feature-envies" an entity (reaches in to compute things) — Information Expert refactor
- Scattered `new SomeClass(...)` calls across the codebase — missing Creator
- A controller fattens with business logic — push to the right Use-Case Controller
- Choosing between direct call and domain event for a side effect — Low Coupling vs cohesion trade-off
- A `Util`/`Helper`/`Manager` class accumulates — High Cohesion violation; replace with focused Pure Fabrication(s)
- Wrapping a vendor SDK — Indirection + Protected Variations design conversation
- Same `when (type)` pattern appears across three files — Polymorphism refactor
- Onboarding a teammate who needs the vocabulary for design conversations

## Do not use this skill when

- The class shape is already correct and you're checking SRP/OCP/ISP/DIP — use `solid-principles`
- You're translating a Java-flavoured pattern (Singleton, Builder, Visitor) into idiomatic Kotlin — use `gof-patterns`
- The frame is specifically a bounded-context aggregate with transactional invariants — use `ddd-tactical-patterns` (DDD's aggregate root is parallel to GRASP's Information Expert with extra context discipline)
- You're choosing the module layout (Onion / Clean / Hexagonal / Modulith) — use `architecture-patterns`
- You're writing routine CRUD with no design problem — these patterns are tools, not gates

## Selective Reading Rule

Six resource files. Read the one matching your task — don't load the lot.

| File | What it contains | When to read |
|---|---|---|
| `resources/theory.md` | Nine patterns: definition, the question each answers, language-agnostic example, when it applies | First contact with GRASP, refreshing a pattern, explaining to a teammate |
| `resources/kotlin.md` | Idiomatic Kotlin per pattern — sealed for Polymorphism, function types for Strategy-like Indirection, `companion fun create()` for Creator, extension functions for Indirection | Designing or refactoring Kotlin code; you know the pattern, you want the idiom |
| `resources/spring-boot.md` | Spring conventions per pattern — `@RestController` IS Controller, `ApplicationEventPublisher` enables Low Coupling and Indirection, repository interface is Indirection + Protected Variations, `@Profile` swaps protect from change | Designing a Spring service, deciding between direct invocation and an event, choosing where the wrapping seam belongs |
| `resources/bad-practices.md` | Catalogue of GRASP violations: anaemic domain (Information Expert violated), god service that orchestrates and computes (Pure Fabrication misused), fat controller (Controller misapplied), `Util/Helper/Manager` (High Cohesion violated), scattered `new` (Creator missed), direct vendor SDK calls (Protected Variations missed) | Code review; pre-merge audit; you suspect the wrong class owns a responsibility |
| `resources/best-practices.md` | Heuristics for assignment, decision rules ("who has the data → who owns the behaviour"), when each pattern earns its cost, GRASP × DDD mapping, PR-review checklist | Planning a refactor; framing a design discussion; running a structured review |
| `resources/cross-references.md` | Bridges to SOLID / GoF / DDD / architecture: GRASP Polymorphism ↔ SOLID OCP ↔ GoF Strategy/State; GRASP Indirection ↔ GoF Adapter/Proxy/Facade; GRASP Information Expert ↔ DDD Aggregate root | Mapping a GRASP question to a SOLID validation or GoF named pattern; preparing for a design conversation that crosses vocabularies |

## Quick reference

| Pattern | Question it answers |
|---|---|
| **Information Expert** | Who has the data needed for this operation? They own the operation. |
| **Creator** | Who should call `new A()` / construct instances of A? |
| **Controller** | Who handles this system event from the UI / API / event bus? |
| **Low Coupling** | Of these placements, which creates the fewest new dependencies? (meta) |
| **High Cohesion** | Do all methods on this class serve the same purpose? (meta) |
| **Polymorphism** | How do we handle this differs-by-type variation? |
| **Pure Fabrication** | Where does this responsibility belong when no domain class fits? |
| **Indirection** | How do we keep A and B from knowing about each other directly? |
| **Protected Variations** | What's most likely to change next, and how do we shield other code from it? |

## Core meta-rules

1. **GRASP names the design conversation.** Once your team agrees that *"`OrderPricing` is the Information Expert for total"*, design discussions become precise. The names ARE the value.
2. **Information Expert is the workhorse.** Most "should this method live on the entity or the service?" questions resolve cleanly with Info Expert: the data location decides. The remaining cases are usually Pure Fabrication candidates.
3. **Low Coupling and High Cohesion are meta-criteria, not patterns.** They're the lenses through which you choose between alternatives. Every other GRASP pattern can be motivated by one of these two.
4. **Protected Variations is the most expensive pattern.** Every interface is a cost. Apply at boundaries where you have *good reason* to expect change (vendor SDKs, third-party providers, swappable infrastructure). Don't protect every variation — YAGNI applies here too.
5. **GRASP precedes DDD tactically.** Aggregate root ≈ Info Expert with bounded-context discipline. Domain Service ≈ Pure Fabrication. ACL ≈ Indirection + Protected Variations. If DDD vocabulary feels too heavy for a sub-context, GRASP is the lighter fallback.

## Related skills

- `solid-principles` — class shape rules; GRASP picks the owner, SOLID checks the result
- `gof-patterns` — pattern catalogue; many GRASP-driven refactors land on a named GoF pattern (Strategy, Decorator, Adapter, Facade)
- `clean-code-classes` — class-level Kotlin idioms (encapsulation, primary-constructor properties, weasel-suffix ban)
- `clean-code-objects-and-data` — Tell-Don't-Ask, anaemic-domain anti-pattern; the object-vs-data axis is where Info Expert lives
- `clean-code-naming` — Manager / Helper / Util are GRASP's High Cohesion violations made visible in the name
- `clean-code-boundaries` — Wrap-Don't-Pass + Anti-Corruption Layer = GRASP Indirection + Protected Variations at the vendor seam
- `ddd-tactical-patterns` — Aggregate / Repository / Domain Service vocabulary; parallel to GRASP, with bounded-context discipline added
- `architecture-patterns` — module layout where Indirection / Protected Variations operate at architectural scale

## Limitations

- GRASP is descriptive, not prescriptive. It gives you the names; it doesn't tell you *which* domain class is the Info Expert — that requires domain knowledge.
- The patterns overlap. A Pure Fabrication is often also an Indirection that provides Protected Variations — that's normal. Pick the most informative name for the conversation at hand.
- Low Coupling and High Cohesion can pull in opposite directions. Dropping a method onto an entity raises cohesion *there* and may raise coupling *elsewhere*. The art is balancing the two; there's no formula.
