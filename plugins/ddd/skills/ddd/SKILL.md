---
name: ddd
description: "Entry point and router for the ddd-* family — DDD vocabulary, pipeline navigation (Strategic → Context Mapping → Tactical), and the 'is DDD worth it here?' gating decision. Owns three things the per-stage siblings don't: the shared glossary (bounded context, ubiquitous language, subdomain, aggregate, value object, domain event, ACL, OHS, Conformist, Customer-Supplier, Published Language, Shared Kernel, anemic domain), the stage-routing logic (which ddd-* sibling actually applies to the question on the table), and the DDD-level anti-patterns (DDD-as-religion, big-bang rewrite, DDD-without-experts, context-as-layer, stage skipping). Use whenever the user mentions DDD, domain-driven design, bounded contexts, aggregates, value objects, domain events, ubiquitous language, anti-corruption layers, or asks 'should we use DDD here?' / 'is this a bounded context?' / 'where should this logic live?' — and especially when it's not yet clear which ddd-* sibling applies. Routes to ddd-strategic-design (where the boundary goes), ddd-context-mapping (how the contexts relate), or ddd-tactical-patterns (the code inside one context). Does NOT auto-trigger on greenfield code with no domain — for new code use karpathy-guidelines; for code-level smells use clean-code; for picking a layout (Onion/Clean/Layered) use architecture-patterns."
risk: safe
source: "custom — Eric Evans / Vaughn Vernon DDD pipeline, filtered for Kotlin/Spring practice"
date_added: "2026-05-12"
---

# DDD

> "Strategic DDD draws the lines. Context mapping wires the lines together. Tactical DDD fills in the code. Skip a stage and the next one fights you."

The **entry point and router** for the ddd-* family. It owns three things the per-stage siblings don't: the **shared vocabulary** (so the words mean the same thing everywhere), the **pipeline routing** (so you go to the right sibling for the question on the table), and the **gating decision** (so DDD isn't applied where classical CRUD would win).

For the deep dive on any single stage, follow the routing table to the owning sibling.

## When to use this skill

- The user mentions DDD, domain-driven design, bounded contexts, aggregates, ubiquitous language, ACL, OHS, value objects, or domain events — and it's not yet clear which stage they're at.
- Deciding **whether DDD is worth it** for this system (the gating question).
- Looking up a DDD term and wanting the canonical, project-consistent definition.
- Planning a system from scratch and needing to know the order of operations (Strategic → Mapping → Tactical).
- Auditing existing work to spot stage skipping ("we wrote aggregates but never drew bounded contexts").

## When NOT to use this skill

- **Writing new code with no domain rules** — that's `karpathy-guidelines`. DDD pays off when invariants exist; a config admin tool doesn't have them.
- **Refactoring code-level smells** — that's `clean-code` (smell vocabulary + cadence) or one of its `clean-code-*` siblings.
- **Picking an architecture layout** (Onion / Clean / Layered) — that's `architecture-patterns`. DDD slots *into* a layout; the layout itself is a different decision.
- **Deciding whether architecture work is even warranted** — that's `architecture` (front-of-funnel). Use it first if "do we need DDD?" is really "do we need any architectural rigor here?".
- **The deep dive on one DDD stage.** Once the stage is named, jump to the sibling that owns it (boundaries → `ddd-strategic-design`; relationships → `ddd-context-mapping`; code → `ddd-tactical-patterns`).

## The DDD pipeline

```
       [domain experts speak]
                │
                ▼
   ┌─────────────────────────────┐
   │  ddd-strategic-design        │   Where do the lines go?
   │                              │   Subdomains (Core/Supporting/Generic),
   │                              │   bounded contexts, ubiquitous language.
   └──────────────┬───────────────┘
                  │  contexts now exist on paper
                  ▼
   ┌─────────────────────────────┐
   │  ddd-context-mapping         │   How do the contexts relate?
   │                              │   ACL, OHS, Conformist, Customer-Supplier,
   │                              │   Published Language, Shared Kernel.
   └──────────────┬───────────────┘
                  │  relationships labelled
                  ▼
   ┌─────────────────────────────┐
   │  ddd-tactical-patterns       │   What does the code inside look like?
   │                              │   Aggregates, value objects, repositories,
   │                              │   domain events. Kotlin/Spring.
   └──────────────┬───────────────┘
                  │
                  ▼
              [code ships]
```

**Stage-skipping is the most common DDD failure.** Tactical patterns built before contexts are stable get refactored every quarter. Context mapping done before subdomain classification optimises the wrong seams. Honour the order.

You can iterate within a stage — strategic design is rarely "done" — but don't jump ahead.

## Is DDD worth it here?

DDD is a tax. It pays off when invariants exist and the domain is complex enough that a behaviour-rich model out-earns the ceremony cost. Pay only when you have to.

**Signals DDD pays off:**
- The domain has rules that must hold *at write time* — financial, regulatory, safety-critical, contract-bound.
- The same validation rule appears in 3+ services and tends to drift.
- Domain experts describe invariants in their own language; the code doesn't enforce them ("an order can't be submitted empty", "a reservation can't overlap an existing one").
- Bugs cluster around "the system got into a state I didn't think was possible."
- Multiple subdomains exist; capabilities map to distinct business areas with their own vocabulary.
- Team size > 5 engineers, multiple sub-teams, long-lived product.

**Signals classical CRUD wins (skip DDD):**
- < 5 engineers, one product, one sub-team.
- A handful of tables with no real domain logic (admin tool, internal dashboard, config UI).
- Domain experts unavailable or strategy still in flux — strategic outputs collapse without them.
- The "rules" are just field validation that Bean Validation handles.
- Short-lived greenfield where speed > model purity.

**The honest middle ground:** anemic data class + Spring Data repository + Bean Validation is a legitimate architecture for the right problem. Don't gold-plate it into aggregates because the team likes DDD.

## Ubiquitous language (cross-skill glossary)

The vocabulary used consistently across all three ddd-* siblings. When a term reads differently in two siblings, this skill is the source of truth.

| Term | Means |
|---|---|
| **Subdomain** | A capability of the business. Classified Core (differentiating, build), Supporting (necessary, build cheaply), or Generic (commodity, buy / OSS). |
| **Bounded context** | A boundary within which a single model has a consistent vocabulary, one team owner, one transactional regime. The same word can mean different things in different contexts (a `User` in Identity ≠ a `User` in Billing). |
| **Ubiquitous language** | The exact vocabulary domain experts and code share *within one bounded context*. Not global; scoped to the context. |
| **Anti-term** | A word that means different things in different contexts. Naming the conflict explicitly is half the work. |
| **Context map** | The diagram of all bounded contexts plus the pattern label on every edge between them. |
| **Aggregate** | A cluster of objects that change together inside one transaction and share invariants. The boundary of consistency. |
| **Aggregate root** | The only entry point into an aggregate. External callers reach inside only through the root. |
| **Entity** | An object with identity that changes over time. Lives inside an aggregate, accessed through the root. |
| **Value object** | An object with no identity, defined by its values (`Money(amount, currency)`). Equality is by value, not by reference. |
| **Domain event** | A fact about something that happened in the domain (`OrderSubmitted`, `ReservationCancelled`). Past tense, named in the ubiquitous language. |
| **Repository** | An interface that loads and saves one aggregate root. The contract lives in the domain; the JPA implementation lives in persistence. |
| **Anti-Corruption Layer (ACL)** | A translation seam that converts an external / vendor / legacy model into your domain model. The most common right answer for vendor integration. |
| **Open-Host Service (OHS)** | A stable, documented service interface that an upstream context publishes for many downstreams. |
| **Published Language** | A neutral third schema two contexts agree to exchange in (industry standards like FHIR, ICalendar, SWIFT — or a team-defined schema). |
| **Conformist** | A downstream relationship where the downstream accepts the upstream's model as-is, with no translation. Cheap; brittle. |
| **Customer-Supplier** | Two cooperating teams where the upstream supplier serves the downstream customer, considering customer needs. Healthy default for internal integrations. |
| **Shared Kernel** | A small common module of code/types governed jointly by two contexts. Rare; high coordination cost. |
| **Partnership** | Two contexts whose roadmaps are inseparable. Often a smell pointing at a missing single context. |
| **Anemic domain model** | An object that holds data but not behaviour — logic lives in services that mutate the bag of getters/setters. The smell tactical DDD is built to fix. |
| **Process manager / saga** | A coordinator for a workflow that spans multiple aggregates, when one transaction isn't an option. |

## Routing table

Where to go after this skill, by the question on the table.

| The question / symptom on the table | Go to |
|---|---|
| "Where should the boundary go?" / "What's the bounded context here?" | `ddd-strategic-design` |
| "Is this Core, Supporting, or Generic?" / "Build vs. buy?" | `ddd-strategic-design` |
| "How do I build a ubiquitous language with domain experts?" | `ddd-strategic-design` |
| "We're integrating Stripe / GitHub / Salesforce — what shape?" | `ddd-context-mapping` (ACL is almost always the answer) |
| "How does context A talk to context B?" / "Who owns the contract?" | `ddd-context-mapping` |
| "Conformist vs. ACL vs. OHS vs. Published Language?" | `ddd-context-mapping` |
| "How do I refactor this anemic service into aggregates?" | `ddd-tactical-patterns` |
| "Where should this validation live?" | `ddd-tactical-patterns` (inside the aggregate, not the service) |
| "One repository per entity or per root?" | `ddd-tactical-patterns` (per root) |
| "Where do domain events fire?" | `ddd-tactical-patterns` (aggregate emits; persistence dispatches after commit) |
| "Value object or primitive?" | `ddd-tactical-patterns` |
| "Should we even use DDD here?" | **this skill** — see "Is DDD worth it here?" above |
| "What's a bounded context, in one sentence?" | **this skill** — see glossary above |
| "Which DDD stage are we at?" | **this skill** — see pipeline above |

## Routing to adjacent (non-DDD) skills

When the question looks DDD-shaped but really lives elsewhere.

| The question | Go to |
|---|---|
| "What does the REST resource shape look like for this aggregate?" | `api-design-principles` (the wire-level contract; DTOs ≠ aggregates) |
| "Onion vs. Clean vs. Layered for this context's layout?" | `architecture-patterns` |
| "Capture this context-boundary or vendor-ACL decision" | `architecture-decision-records` |
| "Read model diverges from the aggregate shape" | `cqrs-implementation` |
| "JPA mapping / column shape / index strategy" | `database-design` (persistence model ≠ domain model) |
| "Bounded contexts → separate services?" | `microservices-patterns-deep` (decide *if* and *when*; modulith first) |
| "Async cross-context integration via events" | `messaging-rabbitmq-spring` |
| "Kotlin idioms (`@JvmInline value class`, sealed) for tactical DDD" | `clean-code-objects-and-data` |
| "Who should own this method?" (general, not DDD-specific) | `grasp-patterns` (Information Expert is the parallel) |
| "Do we need architecture rigor here at all?" | `architecture` (front-of-funnel decision) |

## Cross-cutting anti-patterns (DDD-level)

These are anti-patterns at the *whole-DDD-approach* level, distinct from the in-stage anti-patterns each sibling owns.

| Anti-pattern | Signal | Fix |
|---|---|---|
| **DDD as religion** | Full tactical DDD (aggregates, factories, value objects, events) applied to a 3-table admin tool with no invariants. | Honour the gating decision above. DDD is a tax paid for invariants; pay only when you have them. Anemic + Spring Data is fine. |
| **Big-bang DDD rewrite** | "Six-month rewrite to do DDD properly." | Strangler instead: stand up one new bounded context next to the legacy and route traffic gradually. DDD is incremental; big-bang is the failure mode. |
| **DDD without domain experts** | Strategic outputs (subdomains, contexts, glossary) produced by engineers in a vacuum. | Stop and surface. Without expert access you're guessing at the territory; the map will be wrong. Escalate the access gap before continuing. |
| **Stage skipping** | Aggregates being written but no one has drawn the bounded contexts; or context-mapping patterns chosen before subdomains are classified. | Honour the pipeline order. Tactical work built on unstable boundaries gets refactored every quarter. |
| **Context as layer** | "Frontend Context", "API Context", "Database Context". | Contexts slice the business, not the stack. The frontend is a layer; "Pricing" is a context. Redraw using domain capabilities. |
| **Anemic domain + DDD ceremony** | The team has aggregate roots, repositories, and value-object IDs — but business logic still lives in `*Service` classes that mutate the aggregate via setters. | Ceremony without behaviour is bureaucracy. Either move logic onto the aggregate (`order.submit()`, not `orderService.submit(order)`), or admit it's CRUD and drop the ceremony. |
| **DDD because team likes DDD** | Adopting DDD as a uniform style across the org, including subdomains that are clearly Generic CRUD. | Match the rigor to the subdomain. Core gets the full investment; Generic gets the cheapest viable shape. Uniformity is the smell. |
| **Vendor types as ubiquitous language** | `StripeCustomer`, `GitHubIssue`, `SalesforceLead` appearing in domain code. | ACL. Vendor models are not your domain even when they look similar. The ACL exists to *stop* the leak; if vendor types reach the domain, you don't have one. |
| **Premature microservices around contexts** | Bounded contexts extracted into separate services before they're stable, "because DDD says so". | DDD says nothing about deployment. Modulith first (one app, multiple modules with enforced boundaries). Extract to services only when scaling / team-size / blast-radius pressure forces the split. |
| **No revisit trigger on subdomain classification** | Strategic classification (Core/Supporting/Generic) documented once and never re-examined; the business pivots and the classification rots. | Each subdomain gets a revisit trigger ("promote Predictive Maintenance to Core when it appears in the sales pitch"). Strategic DDD outputs decay; build in the prompt to refresh them. |

## Required reading order, by situation

| You are… | Read these, in this order |
|---|---|
| Starting a new system from scratch | `architecture` → this skill → `ddd-strategic-design` → `ddd-context-mapping` → `architecture-patterns` → `ddd-tactical-patterns` |
| Inheriting a monolith you need to carve | this skill → `ddd-strategic-design` → `ddd-context-mapping` (label the existing seams first) → strangle incrementally |
| Integrating a vendor (Stripe, GitHub, etc.) | this skill → `ddd-context-mapping` (ACL section) → `api-design-principles` (the wire-level shape) |
| Refactoring an anemic service | this skill (gate: is DDD worth it here?) → `ddd-tactical-patterns` → `clean-code-objects-and-data` |
| Adding a new capability to an existing system | this skill → `ddd-strategic-design` (which context owns it? new context?) → tactical or mapping depending on the answer |
| Capturing a DDD-level decision | this skill → `architecture-decision-records` |

## Related skills

- `ddd-strategic-design` / `ddd-context-mapping` / `ddd-tactical-patterns` — the three siblings this router points at.
- `architecture` — front-of-funnel decision frame; use it to decide whether DDD-depth rigor is warranted at all.
- `architecture-patterns` — the layout style (Onion / Clean / Layered) inside one bounded context; DDD slots in.
- `architecture-decision-records` — capture context boundaries, vendor ACL choices, and "do we use DDD here?" decisions as ADRs.
- `cqrs-implementation` — when the read model diverges from the aggregate shape. Aggregates remain the write side; queries hit projections.
- `microservices-patterns-deep` — when bounded contexts become separate services; this skill says *which* contexts, that skill says *how* to operate them.
- `messaging-rabbitmq-spring` — async cross-context integration via domain events or Published Language over a queue.
- `api-design-principles` — the wire-level contract that exposes aggregates / context boundaries to external callers.
- `clean-code-objects-and-data` — Kotlin idioms (`@JvmInline value class`, sealed hierarchies, immutable collections) that make tactical DDD ergonomic.
- `grasp-patterns` — GRASP Information Expert is the responsibility-assignment vocabulary parallel to DDD's aggregate root; use it when DDD-context discipline isn't the frame.
- `clean-code` — code-smell vocabulary and refactoring cadence; complementary, not overlapping.
- `karpathy-guidelines` — for greenfield code with no domain. DDD is for domains with invariants; karpathy-guidelines is for code generally.

## Limitations

- This skill is a router and a glossary, not a tutorial. The deep dive on any topic lives in the sibling it points to.
- The gating decision ("is DDD worth it here?") is heuristic, not algorithmic. If signals are mixed, lean cheap — under-investing is easier to recover from than over-investing.
- Strategic DDD outputs need domain experts. The router cannot substitute for stakeholder access — name the gap and escalate.
- DDD vocabulary is widely known but not uniformly defined. When this glossary disagrees with an external source, this glossary wins *for this project* — the goal is project-internal consistency.
- Stop and ask if it's unclear whether the user is asking about DDD at all, or about a code-level smell that DDD won't fix (e.g., "this class is too long" → `clean-code-classes`, not aggregates).
