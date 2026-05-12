---
name: architecture
description: "Front-of-funnel architecture decision-making — surfacing requirements, framing constraints, generating options, weighing trade-offs, choosing what level of architectural rigor a problem deserves. Use BEFORE picking a layout pattern (architecture-patterns), BEFORE writing the ADR artifact (architecture-decision-records), and BEFORE estimating capacity (system-design-fundamentals). Use when starting a new service/module, evaluating a non-trivial change (new persistence store, new integration, new boundary), framing discovery with stakeholders, or deciding whether an architectural intervention is even justified."
risk: safe
source: custom
---

# Architecture Decisions

> "Requirements drive architecture. Constraints rule out options. Trade-offs pick the winner."

## Use this skill when
- Designing a new service, module, or subsystem from a problem statement.
- A non-trivial decision is on the table: new persistence store, new integration vendor, new module boundary, new async path, new auth flow.
- Framing discovery with stakeholders — what are we actually solving, for whom, under what constraints.
- Evaluating whether a proposed change is justified (vs. status quo + small fix).
- Anyone in the room can name a desired outcome but nobody can name the constraints — that's the moment.

## Do not use this skill when
- The pattern choice itself is the task (Layered vs. Onion vs. Clean vs. DDD overlay) → `architecture-patterns`.
- The decision is already made and you just need to write it up → `architecture-decision-records`.
- Auditing an existing design for smells / structural risk → `architect-review`.
- Sizing for scale, back-of-envelope capacity, reference architectures → `system-design-fundamentals`.
- Mapping subdomains and bounded contexts → `ddd-strategic-design`.
- Picking between microservices and a modulith for operational reasons → `microservices-patterns-deep`.
- The task is a localized refactor or bug fix with no cross-component impact — architecture skills overfit small problems.

## Decision process (7 phases)

These phases are usually cyclic. Phase 4 will send you back to Phase 1; that's the job, not a flaw.

1. **Surface requirements** — functional ("what should it do") AND non-functional ("how well, under what load, with what guarantees"). If you can't list the top 3 NFRs that matter, you are not ready to decide.
2. **Classify constraints** — team size, expertise, timeline, budget, compliance, existing stack, contracts you can't change. Constraints rule out options faster than requirements pick them.
3. **Identify dominant quality attributes** — usually 2–3 that actually drive the design (latency, throughput, consistency, evolvability, operational simplicity, cost). You cannot optimize all of them; admit which you'll trade.
4. **Generate ≥ 2 real options** — including the cheapest credible one ("status quo + small fix"). One-option "decisions" are justifications, not decisions.
5. **Compare on trade-offs** — for each option: what does it cost (build, run, learn), what does it buy, what does it foreclose, what does it defer? → `trade-off-analysis.md`
6. **Decide** — with explicit reasoning tied to phase 3 (which quality attributes won, which lost).
7. **Set a revisit trigger** — a concrete metric or event that means "reconsider": "team > 10", "p95 > 200ms", "second vendor onboarded", "regulated tenant". Without this, decisions ossify.

## Reversibility heuristic

Before agonizing, check: is this a **one-way door** (hard to undo: data migrations, public contracts, multi-team adoption) or a **two-way door** (easy to undo: in-process abstraction, internal helper, single-service config)?

- Two-way doors: bias to act. Cost of being wrong = small. Cost of deliberating = real.
- One-way doors: deliberate. Generate more options, demand stronger evidence, write the ADR.

## Selective reading rule

| File | When to read |
|---|---|
| `context-discovery.md` | Phases 1–3 — gathering requirements, constraints, and which quality attributes dominate. |
| `trade-off-analysis.md` | Phases 4–6 — option comparison and decision matrix. |
| `decision-anti-patterns.md` | Whenever the choice feels obvious, or the pull of "everyone is using X" is strong, or you only have one option on the table. |

## Decision anti-patterns (short list — full list in `decision-anti-patterns.md`)

- **Resume-driven design** — choosing tech that looks good on a CV, not the one that fits.
- **Hype-driven** — "Kafka because everyone uses Kafka" without naming the problem Kafka solves here.
- **Single-option "decision"** — presenting one option as inevitable instead of comparing alternatives.
- **Premature optimization for scale you don't have** — designing for 100k users when you have 100; designing for multi-region when you have one office.
- **Premature pattern application** — introducing CQRS / event sourcing / microservices "in case we need it later".
- **Missing revisit trigger** — "we'll switch when needed" without naming the metric that means "needed".
- **Reversibility blindness** — agonizing over a two-way door, or sleepwalking through a one-way one.
- **Solving for the loudest voice** — designing around the most senior opinion in the room rather than the requirements.

## What good looks like

A decision is well-formed when it can be summarized as:

> Given **<requirements>** and **<constraints>**, we chose **<option>** because it optimizes for **<quality attribute>** at the acceptable cost of **<traded attribute>**. We'll reconsider if **<revisit trigger>**.

If your draft decision can't fit that sentence, you're missing a phase.

## Validation checklist

Before considering the decision "done":

- [ ] Top 3 NFRs named and prioritized.
- [ ] Constraints listed (team, time, budget, compliance, existing stack).
- [ ] ≥ 2 real options compared (one of them cheap/incremental).
- [ ] Dominant quality attributes identified, traded ones acknowledged.
- [ ] Reversibility classified (one-way vs. two-way door).
- [ ] Revisit trigger written (a metric, not a feeling).
- [ ] If one-way door: ADR drafted → `architecture-decision-records`.

## Related skills

| Skill | Role |
|---|---|
| `architecture-patterns` | Pick the layout pattern (Layered/Onion/Clean/DDD overlay) once you've decided architecture is warranted. |
| `architecture-decision-records` | Write the ADR artifact once the decision is made. |
| `architect-review` | Audit an existing design for smells/risks (this skill makes decisions; that one critiques them). |
| `system-design-fundamentals` | Capacity estimation and reference architectures for the chosen shape. |
| `ddd-strategic-design` | Subdomain classification and bounded-context discovery (a strategic input to architecture). |
| `microservices-patterns-deep` | Cross-service operational concerns once microservices are on the table. |

## Limitations

- This skill is about **forming** good decisions, not stamping authority on them — final calls belong to the team.
- For technology-specific implementation details, delegate to the specialist skill listed above.
- Stop and ask if requirements, constraints, or success criteria are unclear — phase 1 is the most common skipped step.
