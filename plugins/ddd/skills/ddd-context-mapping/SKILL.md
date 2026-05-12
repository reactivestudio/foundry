---
name: ddd-context-mapping
description: "Map relationships between bounded contexts using the canonical DDD context-mapping patterns: Customer-Supplier, Conformist, Anti-Corruption Layer (ACL), Open-Host Service (OHS), Published Language, Shared Kernel, Partnership, Big Ball of Mud, Separate Ways. Define integration contracts, prevent domain leakage across boundaries, plan ACLs for vendor or legacy integration, decide contract ownership (who is upstream vs. downstream), and capture power dynamics between contexts. Use when integrating two or more bounded contexts, designing an anti-corruption layer for an external vendor (GitHub, Jira, Slack, Salesforce, etc.) or a legacy system, choosing how a new context will consume an existing one, or auditing a context map for missing translation seams. Use AFTER ddd-strategic-design has drawn the contexts; for code inside one context, use ddd-tactical-patterns; for the wire-level REST/gRPC contract, use api-design-principles."
risk: safe
source: custom
---

# DDD Context Mapping

> "A bounded context without a context map is an island pretending to be the world."

Context mapping is how separate domains talk without contaminating each other. Get the relationship pattern wrong and one context's vocabulary, model drift, or breaking change cascades into another. Get it right and a vendor outage or a model refactor stops at the seam.

## Use this skill when
- Integrating two or more bounded contexts that need to exchange data.
- Designing an anti-corruption layer for an external vendor (GitHub, Jira, Slack, Salesforce, Stripe, etc.) or a legacy system.
- Deciding **power dynamics** between contexts: who is upstream (drives the contract), who is downstream (consumes), who shares ownership.
- Auditing a system for missing translation seams (one context's types leaking into another).
- Choosing how a new context will consume an existing one — Conformist (cheap, coupled) vs. ACL (expensive, decoupled).
- Capturing the relationships as a published context map for new team members.

## Do not use this skill when
- You have a single bounded context with no integrations — there is nothing to map.
- You are still **defining** the bounded contexts themselves → `ddd-strategic-design` comes first.
- You only need code-level patterns *inside* one context (aggregates, repositories) → `ddd-tactical-patterns`.
- The task is **wire-level contract design** (REST resource shape, gRPC service definition, HTTP status codes, pagination) → `api-design-principles`. Context mapping decides *which* pattern; api-design decides *what bytes go over the wire*.
- The task is selecting cloud infrastructure / mesh / gateway tooling → `microservices-patterns-deep`.

## The 7+2 canonical patterns

The first 7 are the ones you'll actually pick from. The last 2 are descriptive: they name a situation rather than prescribe a solution.

| Pattern | Power dynamic | Who owns the contract | When to pick |
|---|---|---|---|
| **Customer-Supplier** | Upstream supplier serves a downstream customer; both teams collaborate. | Supplier owns the contract but considers customer needs. | Two teams that talk; customer has leverage. The healthy default for internal integrations. |
| **Conformist** | Downstream accepts upstream's model as-is, no translation. | Upstream — downstream has zero influence. | Upstream is stable / external / immovable AND its model is acceptable to use directly in the downstream. Cheap and brittle. |
| **Anti-Corruption Layer (ACL)** | Downstream translates upstream's model into its own. | Downstream owns the *translation*; upstream owns its model. | Upstream's model is messy, legacy, vendor-controlled, or hostile to your domain. The most common right answer for vendor integration. |
| **Open-Host Service (OHS)** | Upstream publishes a stable, documented service for many downstreams. | Upstream — but with public-API discipline. | Many downstreams consume this context; upstream invests in API stability and documentation. |
| **Published Language** | Both sides agree on a third, neutral schema for exchange. | Joint — schema is the contract, not either model. | Stable cross-team / cross-org exchange where neither side's model should win. Often paired with OHS. Examples: standard ICalendar / SWIFT / FHIR / industry schemas. |
| **Shared Kernel** | Two contexts share a small common module of code/types. | Joint, with explicit governance. | Two contexts that genuinely share invariants AND have tight communication discipline. Rare; high coordination cost. |
| **Partnership** | Two contexts succeed or fail together; tightly coupled by intent. | Joint. | Two contexts whose roadmaps are inseparable. Often signals the contexts should be one — re-examine boundaries. |
| **Big Ball of Mud** *(descriptive)* | No coherent model; vocabulary mixes. | Nobody really. | What you find, not what you choose. Diagnose it, contain it with an ACL at the seam to healthy contexts. |
| **Separate Ways** *(descriptive)* | Contexts are intentionally not integrated. | N/A. | Integration cost is not worth the value. Honest answer when teams over-integrate by reflex. |

## How to pick a pattern (per pair of contexts)

1. **Direction**: who depends on whom? Draw the arrow upstream → downstream.
2. **Influence**: can the downstream demand changes to the upstream's model?
   - Yes, easy → Customer-Supplier.
   - No, upstream is fixed → choose ACL (defensive) or Conformist (cheap accept).
3. **Vendor or legacy upstream?** → ACL (almost always). Vendor models are not your domain.
4. **Many downstreams of one upstream?** → OHS, optionally with Published Language.
5. **Two contexts always change together?** → Re-examine boundaries first; Partnership is a *symptom*, often pointing to a missing single context.
6. **Sharing code feels tempting?** → It usually isn't. Shared Kernel only when invariants genuinely overlap AND coordination cost is acceptable.

## Example context map (ASCII)

```
                            ┌───────────────────────────┐
                            │  Identity (Generic)        │
                            │  OHS + Published Language  │
                            └────────────┬───────────────┘
                                         │  OHS
                                         ▼
   ┌──────────────────┐            ┌─────────────┐            ┌───────────────────┐
   │  Pricing (Core)  │◀──ACL──────│  Checkout   │──Customer/Supplier──▶│ Orders │
   └──────────────────┘            │   (Core)    │            └───────────────────┘
                                   └─────┬───────┘
                                         │  ACL
                                         ▼
                            ┌───────────────────────────┐
                            │  Payments (Vendor: Stripe) │
                            │  Conformist? NO — ACL.     │
                            └───────────────────────────┘
```

Read this map left to right, top to bottom: **arrows point at the upstream**. Each edge has a pattern label that names the relationship.

## Anti-Corruption Layer — the workhorse pattern

The ACL deserves its own paragraph because it's the right answer ~70% of the time when integrating with external vendors or legacy systems. The shape:

1. **Adapter layer** translates upstream calls into upstream's model (`StripeChargeRequest`, not `Payment`).
2. **Translator** converts between upstream model and your domain model in both directions.
3. **Port** in your domain (a Kotlin `interface`) exposes only domain types — no vendor types leak in.

Result: a Stripe SDK upgrade or vendor swap touches the adapter + translator. Your domain remains unchanged. The cost is the translation code; the benefit is that your domain isn't held hostage to vendor decisions.

Implementation specifics (Spring/Kotlin) live in `references/context-map-patterns.md` under "Where the ACL lives in code."

## Contract ownership matrix

For every context pair, document this — it prevents "who owns this?" arguments later:

| Context pair | Upstream | Downstream | Pattern | Contract owner | Breaking change policy |
|---|---|---|---|---|---|
| Checkout → Payments | Stripe (vendor) | Checkout | ACL | Vendor owns API; we own translator | Vendor versions; we adapt at the seam |
| Checkout → Orders | Checkout | Orders | Customer-Supplier | Checkout team, with Orders input | Major version bump + deprecation period |
| Identity → Checkout | Identity | Checkout | OHS | Identity team | Backward-compat required; new fields opt-in |

## Anti-patterns

| Anti-pattern | Signal | Fix |
|---|---|---|
| **Conformist to a vendor** | Vendor types appear in your domain (`StripeCustomer` as a domain field). | ACL. Always. Vendor models are not your domain — even when they "look similar." |
| **Implicit Big Ball of Mud** | No declared context map; teams discover relationships by reading code. | Draw the map — even a wrong map is better than no map; it surfaces the disagreements. |
| **Shared Kernel as escape hatch** | "Let's just share these types to avoid duplication." | Shared Kernel needs governance; without it, the kernel grows, both contexts couple, refactoring becomes coordinated surgery. Prefer Published Language or duplication. |
| **ACL that leaks** | Adapter returns vendor types up the call stack into the domain. | Translation is non-negotiable. The ACL exists to *stop* the leak; if it leaks, it isn't an ACL. |
| **Partnership as default** | Every pair of contexts is "joint ownership." | Partnership is high coordination cost; reserve it for genuinely inseparable roadmaps. Default to Customer-Supplier. |
| **Missing power-dynamic label** | The map shows arrows but not pattern labels — what kind of relationship is unclear. | Pattern label is part of the map. Without it, "we integrate with X" means nothing. |
| **One-way ACL on a two-way conversation** | ACL handles upstream → us calls, but us → upstream calls send domain types directly. | ACL is bidirectional. Outbound calls also translate domain → vendor model. |
| **Pattern picked by tech, not by power** | "We have a vendor SDK so it's Conformist." | The SDK is implementation; the pattern is power dynamics. You can use a vendor SDK behind an ACL — they are different layers. |

## Output of context-mapping work

At minimum:
- **Context map diagram** (ASCII or visual) — all contexts, all edges, all pattern labels.
- **Per-edge contract ownership matrix** — upstream / downstream / pattern / owner / breaking-change policy.
- **ACL design for each vendor / legacy upstream** — adapter, translator, port boundaries.
- **Known coupling risks and mitigation plan** — the seams that worry you, in writing.
- **ADRs for irreversible choices** (which vendor to integrate against; ACL vs. Conformist for a high-traffic edge) → `architecture-decision-records`.

## Selective reading rule

| File | When to read |
|---|---|
| `references/context-map-patterns.md` | Deep dive: full pattern catalog with code, ACL structure in Spring/Kotlin, mapping templates, contract-ownership matrix template, risks per pattern, common mistakes. |

## Related skills

| Skill | This not that |
|---|---|
| `ddd` | Router + glossary + "is DDD worth it here?" gate for the ddd-* family. Use it when the stage is unclear or DDD vocabulary needs a single source of truth. |
| `ddd-strategic-design` | Defines the contexts themselves. This skill assumes contexts exist and maps their relationships. |
| `ddd-tactical-patterns` | Code patterns *inside* one context. This skill is about the seams *between*. |
| `api-design-principles` | Wire-level contract (REST resource shape, gRPC proto, status codes, pagination). This skill decides *which* contract pattern; that one shapes the bytes. |
| `architecture-decision-records` | Capture context-mapping decisions as ADRs — every irreversible upstream / downstream choice deserves the artifact. |
| `messaging-rabbitmq-spring` | Async cross-context integration via events / Published Language over a queue. |
| `microservices-patterns-deep` | When contexts become separate services, this skill picks the relationship; microservices-patterns picks the gateway / mesh / discovery story. |
| `architect-review` | Audit a context map for smells (leaking ACLs, missing labels, premature Shared Kernel). |

## Limitations
- Context mapping cannot align teams that leadership has separated for non-domain reasons — surface the conflict, document the cost, escalate.
- Patterns describe relationships at a point in time. Revisit when ownership changes, vendor changes, or context boundaries shift.
- An ACL has a real maintenance cost. Don't add one between two healthy internal contexts that share vocabulary — Customer-Supplier is cheaper.
- Stop and ask if upstream/downstream is ambiguous, or if a "context" you're mapping is actually a layer (UI / DB) rather than a real bounded context — strategic design comes first.
