---
name: solid
description: "Designing modules/classes or reviewing dependencies — SRP/OCP/LSP/ISP/DIP. NOT for component principles."
---

# SOLID

Five rules for arranging functions and data into classes so the system tolerates change. SOLID sits above naming, below architectural boundaries. The unifying question: *which changes do you want to be cheap, and which are you willing to make expensive?*

## When to use

- Designing a new class or module — picking responsibilities and dependencies.
- Reviewing structure in PRs — which class talks to which, which is allowed to import what.
- Refactoring after structural pain: merge hotspots, shotgun edits, hidden coupling.
- Deciding whether to introduce an interface, split a class, or invert a dependency.

## Principles at a glance

| Principle | Core idea (Martin's framing) | Deep-dive |
|---|---|---|
| **SRP** — Single Responsibility | A module is responsible to one and only one **actor** (group of stakeholders). Not "does one thing." | [resources/srp.md](resources/srp.md) |
| **OCP** — Open-Closed | Behavior extends without modifying the artifact. The "most fundamental reason" for architecture. | [resources/ocp.md](resources/ocp.md) |
| **LSP** — Liskov Substitution | Implementations of a contract must be **behaviorally** interchangeable, not just signature-compatible. | [resources/lsp.md](resources/lsp.md) |
| **ISP** — Interface Segregation | Clients should not depend on methods they don't use. Holds for modules and services, not just OO. | [resources/isp.md](resources/isp.md) |
| **DIP** — Dependency Inversion | Source-code dependencies point to **stable abstractions**, never volatile concretes. | [resources/dip.md](resources/dip.md) |

The order is narratively load-bearing: SRP separates by actor → OCP arranges those pieces by direction of dependency → LSP keeps the substitutability OCP relies on → ISP keeps interfaces narrow so OCP/DIP can work → DIP picks where dependencies point.

## Procedure

1. **Identify the actors.** For the module under design, who requests changes — which stakeholders or roles? If two answers point to two different humans, SRP says split. Open `resources/srp.md` when the boundary isn't obvious.
2. **Find the volatile/stable axis.** UI, DB, framework concretes — volatile. Business policy and core entities — stable. Note which is which before drawing dependency arrows.
3. **Point dependencies toward stability.** Apply DIP: domain code never imports framework or infra classes by name. If it does, introduce an abstraction the domain owns. Open `resources/dip.md` when unsure where a new boundary belongs.
4. **Keep contracts honest.** Any subtype or interface implementer must be a drop-in for the abstraction. If callers need `instanceof`/`is`, the contract is broken. Open `resources/lsp.md` to spot subtler violations.
5. **Trim interfaces to client roles.** No client should see methods it doesn't call (ISP); no extension should require editing existing code (OCP). Apply both at the boundary just drawn.

When working on a specific principle, **read its `resources/<principle>.md` file**. The body here is the index; the resources are the depth.

## Quick red flags

First-pass smell check. Open the matching resource for the full picture and remedies.

- **SRP** — one file gets PRs from teams in different domains; a private helper is called by methods that answer to different stakeholders; "I'm scared to change X because Y might break, and Y is owned by another team."
- **OCP** — adding a new output channel forces edits to domain classes; a DB schema change propagates up into use cases; use-case code `import`s from a web framework or ORM directly.
- **LSP** — an override throws `UnsupportedOperationException`; callers branch on type name to use the abstraction; a subtype tightens preconditions or weakens postconditions vs. its parent.
- **ISP** — a class no-ops or throws on half its interface's methods; a test double stubs methods the SUT never calls; a heavy dependency is pulled in to use one corner of it.
- **DIP** — a use-case class names a concrete ORM/HTTP/framework type; `new ConcreteThing()` appears outside the composition root; the domain test can't run without infrastructure.

## When NOT to use

- One-off scripts, prototypes, throwaway experiments — structural cost outweighs benefit.
- Generated code — regeneration overwrites manual structure.
- A module a single person owns end-to-end with no anticipated reuse.
- Component-level cohesion/coupling (REP, CCP, CRP, ADP, SDP, SAP) — separate principles for grouping classes into deployable components; SOLID is the level below.
- Architectural boundaries (Clean Architecture's circles, ports & adapters) — SOLID is the lever that lets those boundaries hold, not a substitute for them.

## Source

Adapted from R. C. Martin, *Clean Architecture: A Craftsman's Guide to Software Structure and Design* (2017), Part III, chapters 7–11.
