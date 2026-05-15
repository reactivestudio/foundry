---
name: solid
description: "Design or review class/module structure via SRP/OCP/LSP/ISP/DIP. NOT for component principles."
---

# SOLID

Five rules for arranging functions and data into modules so the system tolerates change. SOLID sits above naming, below architectural boundaries.

Each `resources/<principle>.md` focuses on **what baseline knowledge of SOLID gets wrong** — Martin's sharper formulations, named smells, architectural-scale framing. Open the relevant resource when working on a principle.

## When to use

- Designing a new class or module — picking responsibilities and dependencies.
- Reviewing structure in PRs — which class talks to which, which is allowed to import what.
- Refactoring after structural pain: merge hotspots, shotgun edits, hidden coupling.
- Deciding whether to introduce an interface, split a class, or invert a dependency.

## Principles

- **SRP** — [srp](resources/srp.md): actor framing (not "one reason to change"); accidental duplication; Facade.
- **OCP** — [ocp](resources/ocp.md): directional control + information hiding; what "closed" really means.
- **LSP** — [lsp](resources/lsp.md): behavioral substitutability; `instanceof` as the smell; architectural pollution.
- **ISP** — [isp](resources/isp.md): segregate by client role, not by aesthetic; scales beyond OO.
- **DIP** — [dip](resources/dip.md): four practices; crossing the curve; stability ≠ abstractness.

## Procedure

1. **Identify the actor.** Who requests changes to this module? Two actors in one file → SRP says split. ([srp](resources/srp.md))
2. **Sort volatile vs. stable.** Frameworks, DB, UI = volatile. Business policy and core entities = stable. Mark each before drawing arrows.
3. **Point dependencies toward stability.** Domain never imports infra by name; if it does, introduce an abstraction the domain owns. ([dip](resources/dip.md), [ocp](resources/ocp.md))
4. **Keep contracts narrow and honest.** No `instanceof`/`is` to use an abstraction (LSP); no methods the client doesn't call (ISP). ([lsp](resources/lsp.md), [isp](resources/isp.md))

## Quick red flags

- **SRP** — one file gets PRs from teams in different domains; a private helper is called by methods that answer to different stakeholders.
- **OCP** — adding a new output channel forces edits to domain classes; use-case code imports a web framework or ORM directly.
- **LSP** — callers need `instanceof`/`is` to use the abstraction; a subtype tightens preconditions or weakens postconditions.
- **ISP** — a class no-ops or throws on half its interface's methods; a heavy dependency is pulled in to use one corner of it.
- **DIP** — a use-case class names a concrete ORM/HTTP/framework type; `new ConcreteThing()` appears outside the composition root.

## When NOT to use

- One-off scripts, prototypes, throwaway experiments — structural cost outweighs benefit.
- Component-level cohesion/coupling (REP, CCP, CRP, ADP, SDP, SAP) — separate principles for grouping classes into deployable components; SOLID is the level below.
- Architectural boundaries (Clean Architecture's circles, ports & adapters) — SOLID is the lever that lets those boundaries hold, not a substitute for them.

## Source

Adapted from R. C. Martin, *Clean Architecture: A Craftsman's Guide to Software Structure and Design* (2017), Part III, chapters 7–11.
