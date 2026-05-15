---
name: solid
description: "Design or review class/module structure via SRP/OCP/LSP/ISP/DIP. NOT for component principles."
---

# SOLID

Five rules for arranging functions and data into classes so the system tolerates change. SOLID sits above naming, below architectural boundaries. The unifying question: *which changes do you want to be cheap, and which are you willing to make expensive?*

## When to use

- Designing a new class or module — picking responsibilities and dependencies.
- Reviewing structure in PRs — which class talks to which, which is allowed to import what.
- Refactoring after structural pain: merge hotspots, shotgun edits, hidden coupling.
- Deciding whether to introduce an interface, split a class, or invert a dependency.

## Principles at a glance

| Principle | Idea | More |
|---|---|---|
| **SRP** | One module → one **actor** (stakeholder group). Not "does one thing." | [srp](resources/srp.md) |
| **OCP** | Extend behavior without modifying the artifact. | [ocp](resources/ocp.md) |
| **LSP** | Implementations must be **behaviorally** substitutable, not just signature-compatible. | [lsp](resources/lsp.md) |
| **ISP** | Clients shouldn't depend on methods they don't use. Holds for modules and services too. | [isp](resources/isp.md) |
| **DIP** | Source-code deps point to **stable abstractions**, never volatile concretes. | [dip](resources/dip.md) |

When working on a specific principle, **open its `resources/<principle>.md`**. The body here is the index; the resources are the depth.

## Procedure

1. **Identify the actor.** Who requests changes to this module? Two actors in one file → SRP says split. ([srp](resources/srp.md))
2. **Sort volatile vs. stable.** Frameworks, DB, UI = volatile. Business policy and core entities = stable. Mark each before drawing arrows.
3. **Point dependencies toward stability.** Domain never imports infra by name; if it does, introduce an abstraction the domain owns. ([dip](resources/dip.md), [ocp](resources/ocp.md))
4. **Keep contracts narrow and honest.** No `instanceof`/`is` to use an abstraction (LSP); no methods the client doesn't call (ISP). ([lsp](resources/lsp.md), [isp](resources/isp.md))

## Quick red flags

First-pass smell check. Open the matching resource for the full picture and remedies.

- **SRP** — one file gets PRs from teams in different domains; a private helper is called by methods that answer to different stakeholders; "I'm scared to change X because Y might break, and Y is owned by another team."
- **OCP** — adding a new output channel forces edits to domain classes; a DB schema change propagates up into use cases; use-case code `import`s from a web framework or ORM directly.
- **LSP** — an override throws `UnsupportedOperationException`; callers branch on type name to use the abstraction; a subtype tightens preconditions or weakens postconditions vs. its parent.
- **ISP** — a class no-ops or throws on half its interface's methods; a test double stubs methods the SUT never calls; a heavy dependency is pulled in to use one corner of it.
- **DIP** — a use-case class names a concrete ORM/HTTP/framework type; `new ConcreteThing()` appears outside the composition root; the domain test can't run without infrastructure.

## When NOT to use

- One-off scripts, prototypes, throwaway experiments — structural cost outweighs benefit.
- Component-level cohesion/coupling (REP, CCP, CRP, ADP, SDP, SAP) — separate principles for grouping classes into deployable components; SOLID is the level below.
- Architectural boundaries (Clean Architecture's circles, ports & adapters) — SOLID is the lever that lets those boundaries hold, not a substitute for them.

## Source

Adapted from R. C. Martin, *Clean Architecture: A Craftsman's Guide to Software Structure and Design* (2017), Part III, chapters 7–11.
