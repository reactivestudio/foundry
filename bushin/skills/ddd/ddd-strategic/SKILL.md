---
name: ddd-strategic
description: "Subdomains (Core/Supporting/Generic), bounded contexts, ubiquitous language. NOT for tactical DDD."
---

# DDD Strategic Design

Three decisions about where the lines fall: what to invest in (**subdomain classification**), where boundaries sit (**bounded contexts**), and what each boundary speaks (**ubiquitous language**). Strategic DDD sits above tactical patterns and below organizational strategy. Wrong lines, and the tactical code is well-built around the wrong shape.

[theory](resources/theory.md) deepens discovery, granularity, distillation (Core inside Core), and BC↔subdomain mapping. [practices](resources/practices.md) shows three bad/good pairs. Stack-specific boundary enforcement: [kotlin](resources/kotlin.md), [spring](resources/spring.md).

## When to use

- Carving subdomains out of an existing system before decomposition.
- Aligning teams with domain boundaries — one team per context is the goal.
- Building a per-context glossary with domain experts.
- Build-vs-buy-vs-integrate decisions — where to spend best engineers.
- Choosing which existing context owns a new capability — or whether a new context is justified.

## Subdomain types

- **Core** — what the company outperforms competitors on; complex, volatile. Built in-house with the best engineers; the moat.
- **Supporting** — necessary but not differentiating; company-specific, simple. Solid build, no gold-plating.
- **Generic** — solved problem, commodity. Buy / OSS / SaaS; custom code only at the seams.

Classification determines investment, not technology. **Inside a Core subdomain, recurse**: the *Core core* is the moat-within-the-moat (rules nobody else gets right); the rest is Generic mechanics (date math, basic vendor wrappers) and Supporting plumbing (audit logs, admin) that happen to live there. ([theory](resources/theory.md))

## Procedure

1. **Discover and classify subdomains.** Walk from public material → org chart → capabilities; for each, ask "would the company exist without this?" Each capability gets one of three labels and a one-sentence "why" tied to revenue or competitive advantage. ([theory](resources/theory.md))
2. **Design bounded contexts.** Default one BC per subdomain; one team owns each BC. A BC contains: one model, one ubiquitous language, one public contract. ([practices](resources/practices.md))
3. **Lock the ubiquitous language per BC.** Capture what business stakeholders (CRO/CFO/customers/domain experts) actually say for each capability — contrast against engineering vocabulary; gaps are UL signals. Then **inventory anti-terms**: every business noun that means different things across BCs (`Loan`, `Customer`, `Order`, `Employee`). Each entry: word → meaning per BC → healthy conflict (boundary surfaced) or harmful (semantic drift, needs rename).
4. **Set revisit triggers.** Classification is current-strategy, not permanent. Name the event that flips each entry: "promote to Core when it appears in the sales pitch", "downgrade to Generic when a vendor catches up".

## Restraint defaults

Most strategic-DDD damage is eager classification or eager splitting, not omission. Default answers when tempted:

- **Promote to Core?** No, until you can write the moat in one sentence tied to revenue or competitive advantage. "Everything is Core" means nothing is.
- **Add a new bounded context?** No, until the language has demonstrably diverged OR a second team needs a different release cadence. One subdomain spanning several BCs is rare and expensive.
- **Build (not buy) a Generic capability?** No. Auth, billing, search, notifications, identity, messaging — buy. The differentiation budget is finite; spend it on Core.
- **Unify "Customer" across contexts?** No. Different meanings in different contexts are healthy; they're how boundaries surface themselves. Document the anti-term, don't paper over it.
- **Run Event Storming or Domain Storytelling?** No, without at least one domain expert in the room. Output is fiction otherwise.

Each speculative context split, premature classification, or "build it ourselves" decision taxes every future change: another team to coordinate, another model to keep in sync, a piece of competitive advantage diluted. Wait for evidence — a real second team, real divergence, a real moat.

## Design output

When proposing strategic structure (forward design, not review of existing), produce these six artifacts in order. A response missing any of them is incomplete.

1. **Subdomain map** — table with columns `Capability | Type | Why (≤1 sentence tied to revenue or competitive advantage) | Revisit trigger (the event that flips the label)`. Every capability gets a row; absence of the *Why* column collapses to vibes-based classification.
2. **Distillation per Core entry** — for each capability classified Core in #1, identify the *Core core* (rules/data/signals nobody else gets right), the *Generic core* (solved mechanics it uses — date math, vendor data pulls, libraries), and the *Supporting core* (audit logs, admin tooling, configuration). Treating a Core BC as uniformly Core wastes best engineers on plumbing; treating it as uniformly Generic loses the moat to a library that almost-but-not-quite fits. ([theory](resources/theory.md) for the "what would a competitor copy us on if they saw the code" test.)
3. **Bounded context catalog** — per BC: `name | type | owner team | local model types (named in the BC's vocabulary, not generic 'User'/'Customer') | integration pattern with each neighbor`. Pattern names (Customer-Supplier, Conformist, ACL, OHS, Partnership, Shared Kernel, Separate Ways) — see `ddd-bounded-contexts` for mechanics.
4. **Anti-term inventory** — table with columns `word | meaning per BC | healthy conflict (boundary surfaced) or harmful (semantic drift, needs rename)`. At least one entry. Absence of anti-terms in a multi-BC system is itself suspicious — it usually means BCs haven't actually been distinguished.
5. **Considered-but-rejected** — ≥2 entries: "Considered X, rejected because Y." The design-time analog of `## Review output → Non-findings`. Cover at minimum: an alternative split, a build-vs-buy chosen against, and any stakeholder proposal pushed back on.
6. **Leave-alone list** — capabilities or modules that are stable, agreed-on, and must not be touched. Strategic DDD protects what works as explicitly as it restructures what doesn't.

A response that produces only #1 and #3 has classification and BC sketching without strategic discipline. The discriminators are #2 (distillation), #4 (anti-terms), #5 (considered-rejected), and #6 (leave-alone) — each is what distinguishes a strategic-DDD proposal from generic architecture advice.

## Review output

When reviewing existing strategic decisions (not designing new structure), produce three sections — the second is the discriminator that separates careful review from naive labeling:

1. **Findings** — actual classification or boundary violations, cited from code or org structure. Each: which thesis is broken, evidence (file, team, capability), risk if left.
2. **Non-findings** — looks like a violation, isn't. Always check at least:
   - Same entity name (`Customer`, `Order`, `User`) in two contexts → almost always healthy; rename to context-specific terms only if the meanings genuinely conflict.
   - One BC owning multiple subdomains → fine when starting; cost-justified split only when language genuinely diverges.
   - Same term meaning different things in two team docs → that's the boundary signal, not a bug.
   - One subdomain split across two BCs → sometimes legitimate (Core too big to own), often not. Default-suspicious.
3. **Boundary sketch** — for real findings only: which BC absorbs the capability, who owns it, what's in the public contract, which boundary pattern the pair uses (Partnership, Customer-Supplier, Conformist, Anti-Corruption Layer, Open-Host Service, Separate Ways, Shared Kernel — mechanics in `ddd-bounded-contexts`).

A review that lists only findings encourages premature splits and unnecessary renames. The non-findings section is what stops the review from making the architecture worse.

## Quick red flags

- Every capability labeled Core → no classification at all; the discipline IS the value.
- "We need a microservice for X" without a domain capability behind it → tech-driven boundary, not a context.
- A single class (`Customer`, `Order`) with cascading optional fields used by three teams → context violation; nullable-soup encodes "this means three different things".
- Two teams blocking each other in one codebase / module → the boundary is missing (or runs through the team).
- A company-wide glossary with one definition per term → no contexts have been drawn yet.
- A subdomain classified once with no revisit trigger → frozen strategy; the labels rot as the business shifts.
- Bounded contexts drawn by database tables (`UserContext`, `OrderContext`) → data-driven, not capability-driven.

## When NOT to use

- Fewer than ~5 engineers, one product, no domain experts available → one BC is right; strategic DDD is overhead.
- Pure CRUD / framework shell / no real domain logic → the exercise overfits trivial domains.
- Domain experts unavailable or strategy unclear → outputs collapse without these inputs; stop and surface to leadership.
- Already-stable, organization-agreed boundaries → strategic DDD shines on ambiguity, not on confirmation.

## Source

Adapted from V. Khononov, *Learning Domain-Driven Design* (O'Reilly, 2021), Part I — Strategic Design (chapters 1–3, with integration touchpoints from chapter 4).
