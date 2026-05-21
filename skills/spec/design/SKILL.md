---
name: spec-design
description: "Design-stage rules: system-design.md + application-design.md schemas (C4, ports/adapters, contracts). NOT for refinement or decomposition."
---

# spec-design

Knowledge for the design stage: turn approved `requirements.md` into two artifacts — `system-design.md` (system-level view: contexts, containers, integrations) and `application-design.md` (application-level view: modules, ports/adapters, contracts, data model). Used by the `architect` agent.

## When to use

- Writing or reviewing `system-design.md` / `application-design.md` during design stage.
- Deciding what belongs in system-level vs application-level design.
- Picking architectural patterns (hexagonal, ports/adapters, CQRS, event-driven) consistent with `.spec/standards/architecture.md`.

## Two artifacts, two scopes

| File | Scope | Audience |
|---|---|---|
| `system-design.md` | C4 levels 1–2: external systems, services, data stores, message buses, deployment topology | tech leads / cross-team reviewers |
| `application-design.md` | C4 level 3 inside the affected service(s): modules, ports, adapters, key contracts, data model | implementation team, code-reviewer |

Keep them **separate** — system-level decisions outlive feature work; application-level changes per change.

## `system-design.md` schema

```
# System design: <title>

## Context
<1–3 paragraphs: who uses this, what business outcome, what existing capability it extends>

## Affected systems
- Service / container / external dep | role in this change | direction of data flow

## Integration view (C4 container)
<inline mermaid or textual diagram showing services + flows specific to this change>

## Key decisions
- D1: <decision> — alternatives: <list> — chosen because: <one sentence>
- D2: …

## Risks & mitigations
- Risk: <what could go wrong> — Mitigation: <plan>

## Compliance with standards
- standards/architecture.md §<…> — followed | exception <reason>

## Open questions for decomposition / implementation
- Q1: <topic> (assignee: teamlead | code-implementor)
```

## `application-design.md` schema

```
# Application design: <title>

## Affected modules
- module / package | role | new | modified | unchanged

## Domain model (sketch)
<entities, value objects, aggregates — names + 1-line responsibility; full DDD only if scope demands>

## Ports (interfaces)
- Port: <name>  Input: <type>  Output: <type>  Owner: <module>

## Adapters
- Adapter: <name>  Implements: <port>  Tech: <db/http/queue/etc.>  External dep: <yes/no>

## Contracts
- HTTP: <method> <path> | request schema | response schema | status codes
- Event: <topic / subject> | payload schema | producer | consumer
- gRPC / GraphQL: <if applicable>

## Data model changes
- table / collection / index | DDL sketch | migration class

## Cross-cutting concerns
- auth: <how this surface is protected>
- observability: <metrics / logs / traces added>
- error handling: <strategy>

## Open questions for decomposition
- Q1: …
```

## Decision quality bar (when to mark `review`)

Every Key decision must have:
1. **Alternative options listed** — at least 2 (incl. "do nothing" where relevant).
2. **Trade-off statement** — one sentence on why chosen vs. alternatives.
3. **Reference to a standard** (where applicable) — `standards/<file>.md §<section>`.
4. **Affected port/adapter cited** — link to where in application-design.md it lands.

If you can't satisfy these, the decision is half-baked — surface as Open question instead.

## Patterns vocabulary (suggested)

- **Hexagonal / ports & adapters** — primary/secondary ports, adapter dependency direction inward.
- **Layered (controller / service / repository)** — for CRUD-heavy services on Spring Boot, but make layer boundaries explicit.
- **CQRS** — only when read/write models genuinely diverge.
- **Event-driven** — publish events on aggregate state changes; specify schema, ordering guarantees, idempotency strategy.
- **DDD aggregates** — when the requirements explicitly model business invariants spanning multiple entities.

Reference `.spec/standards/architecture.md` for project-specific defaults. If the project uses different defaults (e.g. "no DDD here"), respect them — surface only if the change can't fit and explain why.

## When NOT to use

- Refining requirements → `spec-refinement` skill.
- Breaking design into tasks → `spec-decomposition` skill.
- Writing the code → `code-implementor` agent.
- Project-wide architectural conventions → `.spec/standards/architecture.md` (long-lived, edited directly, no lifecycle).

## Anti-patterns

- **One big "design.md" file.** Split. System-level decisions should survive past this change; conflating with application-level forces re-review.
- **Designing in code.** Don't write class skeletons in design.md. Class layout is implementation's call. Show contracts + boundaries, not bodies.
- **Skipping alternatives.** "We use X" without "instead of Y because Z" is a decree, not a decision. Surface as Open question if alternatives weren't considered yet.
- **Reproducing requirements verbatim.** Design references requirements (`FR3` cited where served); doesn't repeat them.
- **No contract examples.** Contracts must include schemas — pseudo-OpenAPI / pseudo-AsyncAPI is fine; pure prose is not.
