# Theory — bounded contexts & context mapping

Depth behind the SKILL.md tables: what a bounded context actually is, ubiquitous language in practice, the subdomain trichotomy in detail, per-pattern deep-dive for all nine context-mapping patterns, and ACL structure.

## Bounded context — the definition

Khononov (2021): *"A Bounded Context defines a boundary, inside of which a Ubiquitous Language can be used freely. Outside of it, the language's terms may have different meanings."*

A BC is **three boundaries collapsed into one**:

- **Linguistic** — inside, one term has one meaning.
- **Model** — inside, the same simplification of reality applies; outside, a different simplification fits.
- **Ownership** — inside, one team owns evolution; outside, another does.

It is also a **physical** boundary, not a logical one. Independent release cycle, separate schema, possibly different stack — if none of these hold, you may have a module, not a BC.

A **microservice is a BC, but not vice versa**. One BC may be a monolith, part of one, or several services. Service boundary is an implementation choice; context boundary is about language and model consistency (Khononov, 2018).

## Ubiquitous language in practice

Not a glossary in a wiki. The same words used by domain experts, analysts, and engineers — and **baked into the code**. If domain experts say "order" and the code says `OrderEntity`, you don't have UL; you have translation.

The discipline:

- One term → one meaning *inside one BC*. Software does not tolerate ambiguity.
- Renaming code to match the spoken term is cheap; ignoring the mismatch compounds.
- The moment a glossary entry needs a "here this term means…" qualifier, an undocumented context boundary already exists.

UL is **not** preserved across BCs. A `User` in Identity (login subject) and a `User` in Billing (party with addresses and invoices) are not the same word; they happen to share spelling.

## Subdomain types — depth

Khononov classifies on a **Core Domain Chart** of two axes: complexity of business rules × volatility (rate of change).

- **Core** — high complexity, high volatility. Competitive advantage. Build in-house. Apply full tactical DDD (aggregates, domain events, careful model). Senior engineers belong here.
- **Supporting** — moderate complexity, contained rules. Enables Core but isn't differentiating. Pragmatic build; outsourcing OK. Plain transaction scripts often beat heavy modeling.
- **Generic** — high complexity but industry-solved. Buy/SaaS/OSS. Building in-house is reinvention. Auth, billing, identity providers, email sending — Generic regardless of technical difficulty.

Type ≠ technical complexity. Cryptography is Generic (solved); a 30-line "compute discount on subscription pause" can be Core because it is unique and changing.

**Subdomains migrate.** A Core today can become Supporting tomorrow (a competitor's SaaS commoditizes it) or Generic (the industry standardizes). The map of subdomain types is a snapshot. BC strategy must follow — what justified a Core-grade aggregate model may not justify it in three years.

## Subdomain vs bounded context

*"Subdomains are discovered; bounded contexts are designed."* (Khononov)

Subdomain = problem space (what the business does). BC = solution space (how we model it). The mapping is **many-to-many**:

- One subdomain may live in several BCs — e.g. a single billing subdomain split into Invoicing and Dunning when their languages diverge.
- One BC may serve several subdomains — e.g. an internal admin BC covering Reporting and Configuration for two subdomains that share a small operator-facing model.

Khononov rejects the "one subdomain ⇔ one BC" myth as wishful symmetry.

## Context-mapping patterns — per-pattern depth

Naming follows Khononov's book TOC: **Anticorruption Layer** (one word), **Open-Host Service** (hyphenated). Evans (2003) writes "ANTICORRUPTION LAYER" / "OPEN HOST SERVICE"; Microsoft uses "Anti-corruption Layer". Pick one and be consistent.

### Cooperation group

**Partnership** — two teams own contracts jointly; both adapt as needed; no upstream/downstream. High coordination cost. Works inside a single team or two co-located teams with shared planning. Outside that scope decays into Customer-Supplier under the hood — make the change explicit when it happens.

**Shared Kernel** — two contexts share a small kernel of code/types representing genuine common *invariants* (not "convenient" shared DTOs). Requires governance: every kernel change is a coordinated release. Works when the shared invariants are stable and small. Decays into Big Ball of Mud when the kernel grows without governance.

### Customer–Supplier group

**Conformist** — downstream accepts upstream's model verbatim, no translation layer. Cheapest pattern. Acceptable when upstream is stable, its model is acceptable for downstream use, and translation cost outweighs vendor coupling. Almost never the right choice for an *external vendor* — vendor models are not your domain.

**Anticorruption Layer (ACL)** — downstream owns a translation layer between upstream's model and its own. Costs translation code; buys insulation. Default for vendor (Stripe, GitHub, Salesforce) and legacy integrations. See "ACL structure" below.

**Open-Host Service (OHS)** — upstream invests in a stable, documented service designed for many downstreams. Typically published as REST/gRPC/event contracts with a deprecation policy. Often paired with **Published Language** — a formal schema (OpenAPI, gRPC `.proto`, CloudEvents, JSON-LD) — so the contract is *the* artifact, not either team's internal model.

### Separate Ways

**Separate Ways** — no integration. Khononov's three reasons: (1) communication between teams is too costly; (2) duplicating Generic functionality is cheaper than integrating; (3) models differ too much for cheap translation. Choose it openly rather than letting non-integration emerge from neglect.

### Anti-pattern

**Big Ball of Mud** — no coherent model; vocabulary mixes; ownership is unclear. A diagnosis, not a chosen pattern. Containment: place an ACL at every seam between the mud and a healthy context; do not let the mud's model leak inward.

## ACL structure

Microsoft / Evans canonical three components:

- **Facade** — a simplified interface hiding the external system's full surface, exposing only what the downstream needs.
- **Adapter** — protocol translation. SDK calls, HTTP, gRPC, message envelopes.
- **Translator** — model translation. Vendor types ↔ domain types in both directions when called for.

In hexagonal terms, the domain sees only a **Port** (an interface declared in the domain). The ACL implements that Port. No reachable type in the domain originated outside the ACL.

Evans: *"internally, the layer translates in one or both directions as necessary."* Direction is determined by need. Inbound (us reading vendor) translates almost always. Outbound (us calling vendor) translates whenever a domain value is being sent — easy to forget, and the most common leak.

The ACL is the natural home for **failure semantics**: retries, exponential backoff, circuit breaking, malformed-payload handling, rate-limit handling. These do not belong in the domain.

**One ACL per upstream**, not one ACL "for vendors." Each vendor's model is its own translation surface. A unified facade across vendors is premature abstraction.

ACLs are sometimes **temporary** — bridges during migration from legacy to new. Decommission them when the legacy is gone. Other ACLs are permanent (vendor will not be replaced soon). Decide which kind you're building when you build it.

## Directional pitfalls

A late-stage mistake: a Customer-Supplier edge is set up correctly, then someone extracts shared logic from the upstream into the downstream's module *"because that's where it's used most now."* The direction has just flipped — the upstream now depends on the downstream.

Signal: a module that was clearly downstream (`:returns` consuming `:orders`) starts being imported by its former upstream (`:orders` now imports `:returns`). Even if the Gradle cycle is broken via an interface, the *language* has flipped — the original upstream now speaks the downstream's vocabulary.

Three healthy responses, in order of preference:

1. **Keep the logic in the upstream.** The downstream calls via a port. Direction stays, no module change.
2. **Recognize a third context.** If the logic genuinely belongs to neither (e.g., a `:pricing` capability both consume), extract it as its own upstream. Both original contexts become downstream of the new module.
3. **Duplicate the logic.** If the two contexts mean different things by the same word (`Refund` in `:orders` = refund-on-cancellation vs `Refund` in `:returns` = refund-on-return), duplicate. Two contexts, two calculators. Shared code would be the mistake.

Anti-response: let the original downstream become the upstream because "it grew faster." The team that built it last quarter now owns vocabulary for the team that built the upstream three years ago — the most common cause of *"why does `:orders` depend on this random `:returns` thing?"* auditing later.

## Practical heuristics not in the SKILL.md body

- **Start with wide BC boundaries**; narrow as conflicts surface. Splitting later is cheap; merging two drifted contexts is expensive.
- **One context per single ubiquitous language.** If you cannot write the glossary without "here it means" qualifiers, you are already across a boundary.
- **The context map is an artifact.** It lives in a repo, a wiki, or a diagram-as-code file. If it only lives in someone's head, it does not exist.
- **Re-examine the map** at vendor change, team reorg, or when one BC absorbs more than ~2x its expected scope.
