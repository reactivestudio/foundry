# Theory — strategic DDD beyond the body

Seven framings that don't fit in `SKILL.md` but tip the procedure into working / not working.

## Discovery walk — start from where the business lives

The temptation is to draw boundaries by reading code or schemas. Wrong starting place. Walk this order:

1. **Public material** — website, marketing copy, sales pitch. What does the company *say* it does?
2. **Org chart** — departments, teams, reporting lines. Reality of capability ownership.
3. **Capability map** — what each team actually delivers, in business terms.
4. **For each capability**: "would the company still exist without this?"

Code is the *last* place to look. Code lies about boundaries — historic accidents, layering choices, and refactor debt all distort what the business actually values. The discovery walk surfaces the moat by tracing money and competitive pressure, not file imports.

## Granularity — the smallest coherent set of use cases

Subdomains are not "modules" or "services". They're capability clusters. The rule:

> A subdomain is as fine-grained as the smallest set of use cases that hangs together as one business outcome.

**Too coarse**: "Customer Management" lumps a Core capability (lifetime-value optimization) with a Generic one (account self-service). Best engineers split their time across both; classification is meaningless.

**Too fine**: "Profile Avatar Upload" is a feature, not a subdomain — no outcome, no investment decision, no team.

Test: can you write a one-sentence "why this is Core / Supporting / Generic" tied to revenue or competitive position? If yes, granularity is right. If the sentence has to mention multiple unrelated outcomes, split. If you can't write a coherent sentence at all, you have a feature, not a subdomain.

## Distillation — finding the Core inside a Core

A Core BC is rarely uniformly Core. Inside it, the same three labels apply recursively:

- **Core core** — the rules nobody else gets right (per-jurisdiction accrual policies; per-segment risk scoring with proprietary signals; pricing elasticity model trained on internal data). Best engineers, deepest iteration, slowest external dependencies.
- **Generic core** — solved mechanics the Core uses but doesn't differentiate on (date arithmetic, balance arithmetic, basic credit-bureau wrappers, document storage, ML training infrastructure). Libraries, vendors, OSS — same investment rules as any Generic.
- **Supporting core** — necessary plumbing inside the Core BC (audit logging, internal admin tooling, configuration management). Solid build, no gold-plating.

The investment rule recurses. Treating the whole Core BC as uniformly Core wastes best engineers on date math; treating it as uniformly Generic loses the moat to a library that almost-but-not-quite fits.

Test: take any Core BC, ask *"what part of this would a competitor copy us on if they saw the code?"* That part is the Core core. The rest is plumbing that happens to live in a Core context.

## A bounded context contains exactly three things

Model code + ubiquitous language + public contract. Anything else is implementation.

- **Model code** — entities, value objects, domain services *that speak the UL*. Implementation details (ORM mappings, transport DTOs, framework plumbing) don't count — they translate the UL out, not own it.
- **Ubiquitous language** — the *one* vocabulary used inside this BC. Lives in the code, the docs, and the conversation. Not negotiated cross-BC.
- **Public contract** — the surface other BCs may rely on: events, IDs, value objects exported as published language. Internal types stay internal.

The discipline: if you can't draw a clean line between "inside the BC" and "the contract it exposes", the BC isn't bounded.

## Physical = logical is the default — not the rule

A BC is *usually* a separate module / service / repo. That's the default because aligned boundaries cost less to maintain than misaligned ones. It's not mandatory:

- **Two BCs in one deployable**, separated only by package or module visibility — fine when the team is single and the contract is enforced by linting or build rules.
- **One BC across multiple deployables** — legitimate for scaling (Core split into write-side and read-side services); the BC stays logically one.

Premature distribution — splitting a BC into microservices before the team or load demands it — costs more than it buys. Strategic DDD says *where* the lines go; it does not mandate *deployment topology*.

## Ubiquitous language has zero technical terms

If "Repository", "Service", "Controller", "DTO", "Aggregate", "Entity" appear in the UL glossary, the UL has been polluted by implementation vocabulary. Domain experts don't say these words. The UL is the *business* vocabulary; technical scaffolding lives in code conventions, not in the language.

Test: read the glossary out loud to a non-technical stakeholder. They should recognize every term as something they've heard in a business meeting. Friction = a term that needs to be reframed or moved out of the UL entirely.

## Ubiquitous language is a living document

The UL on day one is provisional. As implementation reveals edge cases the experts hadn't articulated, the UL is updated — and that update propagates to the code. The flow runs both ways: expert refines the language → engineer renames a class; engineer discovers an ambiguity → expert resolves it with new vocabulary.

A frozen glossary is a dead UL. Treat it as version-controlled, with PRs from both engineers and domain experts welcome.
