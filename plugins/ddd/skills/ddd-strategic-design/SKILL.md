---
name: ddd-strategic-design
description: "Strategic Domain-Driven Design — classifying subdomains (Core / Supporting / Generic), drawing bounded contexts, building ubiquitous language with domain experts, and aligning team ownership with domain boundaries. Use when carving a monolith into contexts, aligning teams to domain boundaries, building a glossary that domain experts and engineers can both speak, distinguishing what to build versus what to buy / outsource, or running a discovery workshop with stakeholders. Use BEFORE context mapping (ddd-context-mapping handles relationships between contexts once they exist) and BEFORE tactical patterns (ddd-tactical-patterns shapes code inside an already-defined context)."
risk: safe
source: custom
---

# DDD Strategic Design

> "The map is not the territory — but a wrong map costs more than no map at all."

Strategic DDD is the front-of-funnel decision about *where the lines go*. Get this wrong and tactical patterns (aggregates, repositories, events) are built around boundaries that fight the business. Get it right and the code reads like the domain experts speak.

## Use this skill when
- Carving a monolith into bounded contexts before / during decomposition.
- Aligning teams to domain boundaries (one team per context is the goal; deviations are debt).
- Building a ubiquitous language glossary with domain experts — and finding the *anti-terms* (words that mean different things in different contexts).
- Deciding what is **Core** (build, invest, differentiate), what is **Supporting** (build to fit, modest investment), and what is **Generic** (buy / use OSS, minimal investment).
- Running a domain discovery workshop (Event Storming, Domain Storytelling, Big Picture mapping).
- A new business capability is being added and you need to decide which existing context owns it (or whether to spin up a new one).

## Do not use this skill when
- The domain is already well-bounded and stable — strategic DDD shines on ambiguity, not on confirmation.
- You need integration patterns *between* contexts that already exist → `ddd-context-mapping`.
- You need tactical patterns *inside* one context (aggregates, value objects, repositories) → `ddd-tactical-patterns`.
- The task is purely infrastructure, UI shell, or pure CRUD with no real domain — strategic DDD overfits trivial domains.
- The team is < 5 engineers and there is one product — you probably need one bounded context, not five.

## The four-step process

1. **Discover** — talk to domain experts (or read their docs). Capture concepts, workflows, pain points. Output: candidate concept list, source quotes, painful seams. Tools: Event Storming, Domain Storytelling, business-capability mapping.
2. **Classify subdomains** — sort capabilities into Core / Supporting / Generic / Out-of-scope. This is a *strategic* call, not a technical one: it determines where to invest engineering attention.
3. **Draw bounded contexts** — group related capabilities under contexts. Each context has a single transactional boundary, a single team owner (ideally), and a single internal vocabulary.
4. **Build the ubiquitous language** — for each context, capture the canonical terms and the *anti-terms* (a "User" in Identity is not the same thing as a "User" in Billing — name the conflict explicitly).

Output is captured as ADRs and a glossary, not as code. Implementation comes after the boundaries are stable.

## Subdomain classification

The most important strategic question: **which capabilities deserve your best engineers?**

| Type | Definition | Signal | Investment | Build vs. Buy |
|---|---|---|---|---|
| **Core** | What the business genuinely differentiates on. Hard to copy. Direct revenue / strategic moat. | Customers chose us *because of this*. | Highest — best engineers, most iteration, deepest model. | Build, in-house. |
| **Supporting** | Necessary for the business but not differentiating. Specific to the company. | Customers don't care, but it makes Core possible. | Modest — sound engineering, no over-investment. | Build (or assemble), but don't gold-plate. |
| **Generic** | Solved problem; commodity capability. | Multiple commercial / OSS solutions exist; you would not build this from scratch in 2025. | Minimal — buy, integrate, customize only at the seams. | Buy / OSS / SaaS. |
| **Out-of-scope** | Capability the business needs but should not own. | Better-suited owner exists (partner, vendor, regulator). | Zero — integrate, don't build. | Integrate. |

**Single rule**: if you cannot answer "why is this Core" in one sentence that ties to revenue or competitive advantage, it's probably Supporting.

## Bounded context characteristics

A well-formed bounded context has all of these. If a candidate context misses two or more, it is not really a context — it's a partition you drew on a whiteboard.

- **One team can own it.** Two teams sharing a context means the boundary is wrong.
- **One internal vocabulary.** Every key term has exactly one meaning *inside* this context.
- **One transactional boundary.** Operations inside use one consistent state; cross-context coordination is via events / contracts.
- **One source of truth** for each piece of data it owns.
- **A public contract** — what other contexts may see (events, IDs, value objects), separated from internal types.
- **A reason to exist independently.** If two contexts always change together, they are one context drawn as two.

## Worked example: subdomain classification

A B2B SaaS for fleet logistics, mid-size team. Candidate capabilities and how they classify:

| Capability | Type | Why |
|---|---|---|
| Route optimization | **Core** | Pricing power comes from saving fuel / driver hours. Best engineers here. |
| Multi-tenant identity & access | **Generic** | Auth0 / Keycloak / Cognito solve this; no differentiation. Buy. |
| Customer billing | **Generic** | Stripe Billing covers 95%. Integrate, don't build. |
| Driver mobile app | **Supporting** | Required for the product, but the UI shell isn't the moat — the routes it shows are. |
| Reporting & dashboards | **Supporting** | Customers want them; doesn't drive purchase. Solid implementation, no over-investment. |
| Regulatory compliance reports | **Supporting** | Required to operate; not differentiating. Build to satisfy auditors. |
| Email / SMS notifications | **Generic** | Twilio / SendGrid. Integrate. |
| Predictive maintenance alerts | **Core** (aspirational) | If this becomes part of the pitch, promote to Core. Today: Supporting. |

The classification is not eternal — it changes when the business pivots. Predictive maintenance can move from Supporting to Core overnight when product strategy shifts. **Add this to the glossary's revisit triggers.**

## Anti-patterns

| Anti-pattern | Signal | Fix |
|---|---|---|
| **Data-driven contexts** | Contexts drawn by which tables they touch ("UserContext", "OrderContext"). | Draw by *capability* and *invariants*, not by schema. The Customer entity may legitimately live in three contexts with different shapes. |
| **Tech-team boundaries as contexts** | The "Frontend Context" or "API Context." | These are layers, not contexts. Contexts are slices of the business, not slices of the stack. |
| **Everything is Core** | Every capability gets the "Core" label. | Then nothing is. Force the bottom half of the list into Supporting / Generic; the discipline is the value. |
| **Glossary without anti-terms** | A list of definitions with no acknowledged conflicts. | Find the words that *mean different things in different contexts* — that's where bugs live. Document the conflict. |
| **One context per team, always** | Boundaries are drawn around the current org chart. | Conway's Law works both ways: bad boundaries → bad teams. Sometimes the right move is to reshape the team. Surface this to leadership. |
| **Big-bang context redesign** | Six-month rewrite to "do DDD properly." | Strangler pattern: bound the new context next to the legacy, route traffic gradually. Strategic DDD is incremental. |
| **No revisit trigger** | Classification documented once, never re-examined. | Each subdomain gets a trigger: "promote Predictive Maintenance to Core when it appears in the sales pitch." |
| **Premature DDD** | < 5 engineers, one product, no domain experts available. | Two-pizza team with one bounded context is fine. DDD pays off past a certain complexity threshold; below it, it's overhead. |

## Required artifacts (at minimum)

- **Subdomain classification table** (capability → Core/Supporting/Generic → why → revisit trigger).
- **Bounded context catalog** (name → purpose → owner team → key capabilities → public contract surface).
- **Glossary** (term → canonical meaning per context → known anti-terms → source: which expert said this).
- **Boundary decisions captured as ADRs** — use `architecture-decision-records` for the artifact.

## Selective reading rule

| File | When to read |
|---|---|
| `references/strategic-design-template.md` | Workshop & artifact templates: subdomain classification table, bounded context catalog format, glossary format, ADR templates for boundary decisions, common mistakes list. |

## Related skills

| Skill | This not that |
|---|---|
| `ddd` | Router + glossary + "is DDD worth it here?" gate for the ddd-* family. Use it when the stage is unclear or DDD vocabulary needs a single source of truth. |
| `ddd-context-mapping` | Relationships *between* defined contexts (Customer-Supplier, Conformist, ACL, OHS, Published Language). This skill draws the contexts; that one wires them together. |
| `ddd-tactical-patterns` | Code-level patterns *inside* one context (aggregates, value objects, repositories, domain events). Use after boundaries are stable. |
| `architecture` | The decision frame that surrounds strategic DDD — whether and to what depth DDD is warranted for this system. |
| `architecture-patterns` | Layout style (Onion / Clean / Layered) once contexts are defined. DDD strategic shapes the contexts; layout shapes the code inside each. |
| `architecture-decision-records` | Capture boundary decisions as ADRs — each context boundary is a one-way door and deserves the artifact. |
| `microservices-patterns-deep` | When (and only when) the team size / scaling pressure justifies extracting bounded contexts into separate services. |

## Limitations
- Strategic DDD cannot substitute for stakeholder access — without domain experts in the room, you are guessing at the territory.
- Classification (Core/Supporting/Generic) is a *current-strategy* call, not a permanent label. Build in revisit triggers.
- Big-bang strategic redesigns are usually wrong; prefer strangler / incremental discovery.
- Stop and ask if domain experts are unavailable, business strategy is unclear, or team boundaries are politically locked — strategic DDD outputs collapse without these inputs.
