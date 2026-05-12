---
name: architect-review
description: "Audit an existing or proposed architecture for smells, structural risks, and design weaknesses — bounded-context boundaries, dependency direction, data ownership, coupling, quality-attribute coverage (security/performance/scaling/observability), operational readiness, change resilience, ADR coverage. Returns a structured report with severity (Critical / Major / Minor / Suggestion) and concrete recommendations. Use when reviewing a module, service, or system design; before merging a structural change (new module, cross-context communication, API contract change, new persistence store, persistence-pattern change); when something feels off and you need a systematic second pass; or when the user explicitly asks for an architecture review. Catches issues like distributed monolith, anemic domain, god service, hidden coupling via shared DB, leaky abstraction, missing seams for change, premature microservices, layer-skipping, reversed dependency direction, async-for-async-sake."
risk: safe
source: custom
---

# Architecture Review

> "Code reviews find bugs. Architecture reviews find regrets."

A review is not a redesign. The goal is to surface the design as it stands, name the risks honestly, assign severity, and recommend the smallest change that addresses each finding. If you find yourself proposing a from-scratch rebuild, you've slipped from review into redesign — back up and re-scope.

## Use this skill when
- Reviewing an existing module, service, or system for structural issues.
- Before merging a non-trivial structural change (new module, new cross-context call, new persistence store, contract change, schema migration with downtime implications).
- Auditing a third-party design, RFC, or vendor proposal.
- Doing a periodic "is this still the right shape" pass on a maturing module.
- The user explicitly asks for an architecture review.

## Do not use this skill when
- The task is **making** the decision, not auditing one → `architecture`.
- The task is **picking** a layout pattern from scratch → `architecture-patterns`.
- The task is small code-level review (function/class quality, bugs, style) → `clean-code` (or any specific `clean-code-*` sibling) or `/review`.
- The task is a security-only deep audit → `/security-review` or `spring-security-and-auth`.
- The task is reviewing the test suite → use the `test-reviewer` subagent.
- The change is purely local and reversible (single file, single function) — architecture review overfits trivial changes.

## Review process (5 phases)

These phases are usually sequential; later passes may send you back to earlier ones if you find the scope was wrong.

1. **Scope the review.** What's in / out? Which concerns matter most for this system (security? evolvability? p99 latency? operational simplicity?)? What deadline pressure are we under? Without scope, every review degenerates into "what about everything."
2. **Pass 1 — boundaries & dependencies.** Module / context lines, dependency direction, who calls whom, who owns which data. → `checklists.md §1`
3. **Pass 2 — quality attributes.** For each NFR that matters, is there evidence in the design that it's actually addressed? → `checklists.md §2`
4. **Pass 3 — smells.** Walk the smell catalog. Each detected smell gets evidence (file/path, design-doc paragraph) and a severity. → `smells.md`
5. **Synthesize.** Group findings by severity, write the report, end with "what's working well." → `report-template.md`

## Severity model

Every finding gets exactly one severity. "Medium" is not allowed — if a finding can't earn one of these labels, it's a Suggestion, not a finding.

| Level | Meaning | Action |
|---|---|---|
| 🔴 **Critical** | Will cause an incident, data loss, security breach, or block delivery. | Fix before merge / before ship. |
| 🟠 **Major** | Will hurt later (perf, security, evolvability) but not block. | Fix this sprint, or add a tracking issue. |
| 🟡 **Minor** | Local risk or consistency issue. No production impact alone. | Fix opportunistically. |
| 💭 **Suggestion** | Opinion, not finding. Useful pattern or simplification. | Author's call. |

The honest cost of "everything is medium" is the same as no review — readers cannot prioritize. Insist on the gradient.

## Top architectural smells (full catalog of 36 smells with detectors in `smells.md`)

| Smell | Quick signal | Why it hurts |
|---|---|---|
| **Distributed monolith** | Multiple services, but a release of one forces a coordinated release of N. | Worst of both worlds — split ops cost, no split benefits. |
| **Anemic domain** | Entities are getter/setter bags; logic lives in services. | Invariants escape, every caller re-implements them. |
| **God service / aggregate** | One module owns > ~50% of writes or > ~7 entities. | Single point of contention, huge blast radius, hard to evolve. |
| **Hidden coupling via shared DB** | Two modules write the same table, or read each other's internal columns. | Schema change in one breaks the other; the "boundary" is fiction. |
| **Leaky abstraction** | Domain / contract code imports framework / vendor / persistence types. | The abstraction doesn't pay for itself; swap cost is just moved. |
| **Missing seam for change** | A known upcoming change (multi-tenancy, second vendor, new currency) has no place to land. | Future-you pays compound interest. |
| **Premature microservices** | Service count > team size / 3, or services share owners. | Conway's Law violated; ops cost without team benefit. |
| **Layer-skipping** | Controllers calling repositories directly, bypassing the service / domain layer. | Either the layer is useless (delete it) or the skip is a bug (fix it). |
| **Reversed dependency direction** | Domain depends on infrastructure (e.g. `@Entity` annotations driving domain rules). | Domain tests need a DB; refactors cascade through Spring. |
| **Single-store reflex** | Postgres for everything, even when one workload screams "search" or "analytics". | OLTP suffers, analytics suffers, indexes multiply. |
| **Async-for-async-sake** | Synchronous workflow wrapped in Rabbit / Kafka with no real decoupling need. | All the eventual-consistency cost, none of the benefit. |
| **Anaemic ADRs / no revisit triggers** | Decisions written as "we chose X"; no "when to reconsider." | Decisions ossify; nobody dares change them. |

## Checklist headlines (full lists in `checklists.md`)

The five concern groups every review should walk:

1. **Boundaries & coupling** — are module lines defended by the type system, or only by convention?
2. **Dependency direction & data ownership** — does anything point inward toward the domain that shouldn't? Is there one writer per piece of data?
3. **Quality attributes** — for each NFR that matters, what design choice addresses it, and what is the evidence?
4. **Change resilience** — known upcoming changes have a landing place; reversible / irreversible decisions are correctly classified.
5. **Operational readiness** — health checks, metrics, structured logs, alerting, runbook, deploy/rollback story.

A sixth concern — **documentation & decision trail** — is light but mandatory: are non-obvious decisions captured as ADRs, with revisit triggers?

## Anti-patterns in review itself

- **Rubber-stamping.** "LGTM" with no findings means you didn't actually review. Every architecture has something worth flagging — at minimum, a Suggestion or two.
- **Bikeshedding.** Spending the review on names and indentation while the dependency graph is upside-down. Always pass §1 first.
- **Hindsight scope creep.** "Also you should rewrite X" — out of scope. Note it as a Suggestion, don't expand the review.
- **Reviewing the proposer, not the design.** Findings are about the artifact, not the author. Keep language neutral and evidence-based.
- **Late review.** Reviewing an architectural choice *after* the code is in production is mostly theater. Surface this if you see it ("this review should have happened at the RFC stage").

## Output

Findings always end up in a structured report — see `report-template.md` for the full template. Minimum structure:

```
# Architecture Review: <subject>
## Scope (what's in, what's out, which concerns matter)
## Summary (2-3 sentence verdict)
## Findings (grouped by severity, with evidence + recommendation)
## What's working well (2-4 bullets — review is not just bad news)
```

## Selective reading rule

| File | When to read |
|---|---|
| `smells.md` | Phase 4 — walking the smell catalog with detectors, severity guidance, and "why it hurts." |
| `checklists.md` | Phases 2–3 — by-concern checklists for the structural and NFR passes. |
| `report-template.md` | Phase 5 — writing the report. |

## Related skills

| Skill | Role |
|---|---|
| `architecture` | Make the decision (this skill audits decisions already made). |
| `architecture-patterns` | Pick the pattern (this skill checks if the pick was right). |
| `architecture-decision-records` | Write the ADR (this skill checks whether ADR coverage is honest). |
| `clean-code` / `/review` | Code-level review — one layer below this. |
| `spring-security-and-auth` / `/security-review` | Deep security audit (security is a *concern* in this review, not the whole review). |
| `system-design-fundamentals` | Capacity sizing & reference architectures — useful when a finding triggers re-sizing work. |

## Limitations
- A review names the risk; the team owns the fix. Severity is a recommendation, not an authority gate.
- This skill does not run automated tools (ArchUnit, Modulith verifier, dependency analyzers) — but it should *recommend* them when the manual review reveals a gap that one of those tools would catch in CI.
- Stop and ask if scope / concerns / deadline pressure are unclear before producing findings.
