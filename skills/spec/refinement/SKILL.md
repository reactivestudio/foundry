---
name: spec-refinement
description: "Refinement-stage rules: FR/NFR taxonomy, scope categorisation, requirements.md schema. NOT for design/decomp."
---

# spec-refinement

Knowledge for the refinement stage: how to turn a raw `propose.md` into a structured `requirements.md`. Used primarily by the `system-analyst` agent but also by anyone driving refinement manually.

## When to use

- Writing or reviewing `requirements.md` during refinement stage.
- Setting `scope:` field in `tracking.yaml`.
- Deciding whether an unknown belongs in requirements or in design.

## Functional requirements (FR)

A functional requirement is an **observable behaviour** the system must exhibit. Format:

```
FR<n>: <verb> <object> when <condition> → <expected outcome>
```

Examples:
- `FR1: Generate a TOTP secret when a user enables 2FA → 32-byte base32 string returned to client.`
- `FR2: Reject login when supplied TOTP code mismatches current and ±1 RFC 6238 window → 401 with code "totp_invalid".`

Rules:
- **Atomic.** One verb → one outcome. If you see `and`/`or` in the verb phrase, split.
- **Testable.** Someone reading the FR must be able to write at least one test that proves it. If a test can't be sketched, the FR is too vague.
- **No implementation.** "Use HMAC-SHA1" is not an FR — it's a design choice. The FR is "verify TOTP codes per RFC 6238".
- **Numbered sequentially.** `FR1, FR2, ...`. No gaps when removing; renumber on rework.

## Non-functional requirements (NFR)

Quality attributes. Six canonical categories — only include those the change actually moves:

| Category | Examples |
|---|---|
| **Performance** | p50/p95/p99 latency, throughput (req/s), startup time, memory ceiling |
| **Security** | auth model, encryption-at-rest/in-transit, secret handling, audit logging, OWASP threat coverage |
| **Reliability** | SLA (99.x%), graceful degradation, fallback paths, retry/backoff, idempotency |
| **Observability** | metrics (Prometheus / OTel), structured logs, distributed traces, dashboards, alerts |
| **Compatibility** | browsers, OS, locales, API versions, backward-compat with prior schemas |
| **Maintainability** | test coverage floor, doc updates, deprecation path, runbook |

Rules:
- **Pin numbers.** "Fast" → `p95 ≤ 200ms`. "Reliable" → `99.9% over a rolling 30-day window`. If you can't pick a number, move it to Open questions with `assignee: user`.
- **Tie to a workload.** `p95 ≤ 200ms at 100 req/s sustained`. NFRs without workload context are meaningless.
- **Don't restate the framework defaults.** "Logs structured as JSON" — fine for greenfield, redundant if the project already does that. Lean on `.spec/standards/*.md` instead.

## Scope categorisation

Set `tracking.yaml.scope` to one of:

| Scope | When |
|---|---|
| `product` | Strategy-level or user-visible business capability that needs PM/UX review. Multi-team. Often spans multiple services. |
| `project` | Cross-cutting infra / platform change. Cross-team coordination but not strategy. New tool, migration, framework upgrade. |
| `feature` | Single product capability within an existing service. Owned by one team. Most changes land here. |
| `bugfix` | Restores expected behaviour. No new capability. The "expected" must be cited from existing docs / requirements / user report. |

When in doubt, pick the **lower-blast-radius** option. `bugfix` over `feature`, `feature` over `project`.

## Scope (In / Out) bullets

Distinct from the `scope:` field above — these are the In/Out lists inside `requirements.md`.

- **In bullets** — concrete capabilities this change delivers. 3–8 items.
- **Out bullets** — explicit exclusions. 2–5 items. **Mandatory.**

Out-bullets are the single most effective tool against scope creep. Examples:
- `Out: Recovery codes generation` (deferred — different RFC + storage strategy)
- `Out: SMS-based 2FA` (declined — security concerns; see Open questions)
- `Out: Admin reset of user 2FA secret` (deferred to follow-up)

## When to ask vs. defer to Open questions

**Ask the user** during clarifying-questions when the answer:
- Changes the scope (in vs out).
- Sets an NFR number (p95 target, SLA, retention window).
- Picks between mutually exclusive UX flows.

**Defer to Open questions** (assignee on each) when the answer:
- Is a design choice (architect should decide) — `assignee: architect`.
- Depends on running benchmarks not yet done — `assignee: verifier`.
- Requires legal/security review — `assignee: user` (forward to relevant party).

Cap clarifying-questions at **3 rounds**. The remainder goes to Open questions.

## `requirements.md` schema (cross-reference)

The template at `.spec/changes/.template/requirements.md` has the canonical section list:

```
# Requirements: <title>
## Context
## Problem
## Scope (In / Out)
## Functional requirements (FR1, FR2, …)
## Non-functional requirements (Performance / Security / Reliability / Observability / Compatibility / Maintainability)
## Constraints (Tech / Business / Legal)
## Open questions (Q1, Q2, …, each with assignee)
## Acceptance criteria (high-level AC1, AC2, …)
```

Always include all sections; mark empty ones `(none)` rather than removing.

## When NOT to use

- Writing system or application design → `system-design` / `application-design` skills.
- Breaking requirements into tasks → `task-decomposition` skill (Phase C).
- Running verification gates → `spec-roadmap` (Q-gates).

## Anti-patterns

- **FRs that describe code.** "The `TotpService` class shall expose a `generate()` method" — that's design, not a requirement.
- **NFRs as aspirations.** "Should be performant." Pin a number or surface as open question.
- **Skipping Out bullets.** A requirements doc without "Out" will scope-creep during implementation. Mandatory section.
- **Single-shot clarifying.** Asking 15 questions in one round overwhelms the user and shows you haven't filtered for load-bearing ambiguity. ≤3 questions per round, ≤3 rounds total.
- **Inventing requirements past `propose.md`.** If the user didn't ask for X and clarifying didn't surface X, X doesn't belong. Surface as Open question if you think it matters.
