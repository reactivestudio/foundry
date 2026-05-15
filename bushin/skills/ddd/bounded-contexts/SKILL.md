---
name: bounded-contexts
description: "Design bounded contexts and integrations: language, splits, ACL/OHS/Conformist. NOT for aggregates."
---

# bounded-contexts

A bounded context is the boundary inside which one ubiquitous language and one model are consistent. Outside, the same term may mean something different. Strategic DDD lives here — above tactical patterns (aggregates, value objects), below team/system architecture.

Each `resources/<concern>.md` covers one axis — theory (definitions, per-pattern depth) or practices (bad/best examples). Open the relevant resource when designing or reviewing a context boundary or integration seam.

## When to use

- Carving a new system into contexts; deciding what belongs in one model.
- Integrating with another team's context, an external vendor (Stripe, GitHub, Salesforce), or a legacy system.
- Reviewing a context map for missing translation seams, leaking vendor types, or ambiguous ownership.
- Debating whether to split one context into two, or merge two anemic ones.
- Choosing an integration pattern: ACL vs Conformist vs OHS.

## Subdomain types

Classify each subdomain on **complexity × volatility** ([theory](resources/theory.md)):

| Type | Volatility | What to do | DDD investment |
|---|---|---|---|
| **Core** | High; rules change with the business | Build in-house; senior engineers | Full — aggregates, events, careful model |
| **Supporting** | Low–medium; rules contained | Build pragmatically; can outsource | Light — clean code, plain CRUD often fine |
| **Generic** | Low; industry-solved | Buy / SaaS / OSS | None — adopt vendor model |

Type ≠ technical complexity. Cryptography is Generic (solved). Subdomains migrate between types — context strategy must adapt.

## Splitting signals

One context should become two when **any** of these appears ([theory](resources/theory.md)):

- **Linguistic friction** — one term, multiple meanings (`User` as login subject vs `User` as billed party). Glossary needs "here it means…".
- **Conflicting invariants** — same model has rules of the form *"if context A, then X; if context B, then Y"*.
- **Divergent change rates** — one part of the model churns weekly; another is stable for years. They suffer in the same context.
- **Team / ownership boundary** — two teams persistently conflict over one file. Conway's Law as signal, not as decree.

Subdomains are **discovered**; bounded contexts are **designed** (Khononov). Mapping is many-to-many, not 1:1.

## Context-mapping patterns — picker

For each pair of contexts, name the relationship. Khononov groups them by team dynamics ([theory](resources/theory.md) for depth):

| Group | Pattern | Pick when |
|---|---|---|
| **Cooperation** | **Partnership** | Two teams adapt contracts together; high coordination, no upstream/downstream. |
| | **Shared Kernel** | Genuinely shared invariants + governance. Keep it small. |
| **Customer–Supplier** | **Conformist** | Upstream stable; its model acceptable; translation not worth it. |
| | **Anticorruption Layer** | Upstream is vendor / legacy / messy. **Default for external integration.** |
| | **Open-Host Service** | Upstream serves many downstreams; invests in a stable public contract. Often paired with **Published Language** (OpenAPI, .proto, CloudEvents). |
| **Separate Ways** | **Separate Ways** | Integration cost > value. Honest answer, not failure. |
| *Anti-pattern* | **Big Ball of Mud** | Diagnosed, not chosen. Cordon with an ACL at the seam. |

A **microservice is a bounded context, but not vice versa** — a BC may be a monolith, a slice of one, or several services.

## Procedure

When invoked on a real design or review:

1. **Name the subdomain type** for each context — Core / Supporting / Generic. This sets the investment level.
2. **List the ubiquitous-language terms** of each context. Where the same word means different things — a boundary already exists; make it explicit.
3. **For each integration edge**: who is upstream, who is downstream, what is the pattern, who owns the schema, what is the breaking-change policy. Write it down.
4. **For each vendor / legacy upstream**: design the ACL — Facade + Adapter + Translator. The domain must not import vendor SDK types.
5. **Check translation direction** — inbound *and* outbound calls translate. Outbound is the commonly forgotten half.
6. **Draw the map** — even an ASCII map is better than none. The map is the artifact; without it there is no shared understanding.

## Restraint defaults

Default answers when tempted ([practices](resources/practices.md) shows what evidence flips each):

- **Add an ACL between two internal contexts?** No — Customer-Supplier is cheaper. Flip when translation pain is real and recurring.
- **Split a context?** No — until a named signal above appears. Speculative splits = two anemic contexts + the integration tax.
- **Introduce a Shared Kernel?** No — until two contexts share *invariants*, not just *data shapes*. Without governance the kernel grows; both contexts then become coupled.
- **Conformist to a vendor?** Almost always no — vendor models are not your domain. ACL.
- **Published Language for two internal consumers?** No — overhead beats benefit. PL pays off with many downstreams or cross-org exchange.
- **Equate BC with microservice?** No — service boundary is implementation; context boundary is language. One BC can be one or several services.

## Red flags

- Vendor types (`StripeCustomer`, `GitHubUser`) in domain code — ACL is leaking or absent.
- A glossary entry needs "here this word means…" — implicit context boundary, make it explicit.
- A BC with one entity and three CRUD endpoints — that's a module; merge or rename.
- Inbound translation present, outbound calls send domain types raw to the vendor — bidirectional leak.
- Context map mixes subdomains (problem) and contexts (solution) on the same nodes — the map is meaningless.
- "We have their SDK so we're Conformist" — SDK is implementation, pattern is power. SDK lives inside an ACL.
- `WebContext` / `DbContext` / `UiContext` — slicing by technical layer, not by domain.
- "Partnership" on every edge — Partnership is the most expensive pattern. Default is Customer-Supplier.

## When NOT to use

- Pure CRUD without business complexity — strategic DDD overhead beats the benefit.
- Class-level structure inside one module — that's `architecture/application/solid` and `grasp`.
- Wire-level contract details (REST status codes, gRPC streaming, pagination, retries) — separate concern; this skill stops at *which* pattern.
- Tactical DDD inside a context (aggregates, value objects, repositories, domain events) — future siblings in `ddd/`.
- Microservice decomposition motivated only by scaling — different problem.
- Team-org conflicts dressed as model problems — name the org issue first.

## Resources

- [theory](resources/theory.md) — definitions of bounded context and ubiquitous language; subdomain types in depth; per-pattern deep-dive of all 9 mapping patterns; ACL structure.
- [practices](resources/practices.md) — bad/best code examples: naming collision, ACL leak, OHS + Published Language versioning, Shared Kernel drift, Conformist trap, Separate Ways done right.

## Source

V. Khononov, *Learning Domain-Driven Design* (O'Reilly, 2021), Part I — subdomains, ubiquitous language, complexity, integration. Foundational vocabulary from E. Evans, *Domain-Driven Design* (2003), Part IV. ACL structure per Microsoft Azure Architecture Center. Post-2021 evolution in V. Khononov, *Balancing Coupling in Software Design* (Pearson, 2024).
