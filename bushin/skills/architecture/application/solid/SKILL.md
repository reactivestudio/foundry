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

1. **Same level?** Distance from I/O determines level (UI ≪ use case ≪ domain). Things at different levels don't share an interface even if their surfaces look similar — a UI feature is not a new instance of an export strategy. ([ocp](resources/ocp.md))
2. **Identify the actor.** Who requests changes to this module? Two actors in one file → SRP says split. ([srp](resources/srp.md))
3. **Sort volatile vs. stable.** Frameworks, DB, UI = volatile. Business policy and core entities = stable. Mark each before drawing arrows.
4. **Point dependencies toward stability.** Domain never imports infra by name; if it does, introduce an abstraction the domain owns. ([dip](resources/dip.md), [ocp](resources/ocp.md))
5. **Keep contracts narrow and honest.** No `instanceof`/`is` to use an abstraction (LSP); no methods the client doesn't call (ISP). ([lsp](resources/lsp.md), [isp](resources/isp.md))

## Restraint defaults

Most SOLID damage is caused by **eager application**, not omission. Default answers when tempted:

- **Add an interface?** No, until either (a) a real boundary is crossed (process, deployment, framework edge) or (b) a second implementation actually exists. One stable impl behind one client = anemic abstraction. ([dip](resources/dip.md))
- **Extract a helper?** No, until two callers in *different actors'* code want the same thing. "Looks the same" ≠ "is the same" — that's accidental duplication. ([srp](resources/srp.md))
- **Split a class?** No, until a second actor *actually* requests competing changes. Speculative SRP is worse than a cohesive monolith. ([srp](resources/srp.md))
- **Introduce a layer / strategy hierarchy?** No, until you're absorbing a specific named change vector. OCP closes against **named** change, not "future flexibility". ([ocp](resources/ocp.md))

Each speculative split / interface / layer taxes every future read: one more file to open, one more redirect, one more name to keep consistent, one more mock to set up in every test. Default is **no**. Wait for evidence — a real second case, a real second actor, a real boundary.

## Review output

When reviewing existing code, produce three sections — the second is the discriminator that separates careful SOLID review from naive SOLID review:

1. **Findings** — actual violations. Each: principle, cited code, mechanics (not "looks bad"), risk if left.
2. **Non-findings** — things that *look* like violations but aren't, with reasoning. Always check at least these candidates:
   - Class with N methods serving one actor → not SRP, don't split.
   - Single-impl interface in a stable, in-process context → may be anemic, may not need to exist.
   - Same-looking code paths under one actor → honest duplication, don't DRY.
   - Two output forms / two consumers → may be different levels, don't unify.
3. **Refactor sketch** — for real findings only. Show source-code dependency direction after the change.

A review that lists only findings encourages naive splits, anemic interfaces, and DRY-ing of accidental duplication. The non-findings section is what prevents the review from making the code worse.

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
