---
name: spec-decomposition
description: "Decomposition-stage rules: atomic tasks, blockers, Q-gates, estimation. NOT for syntax — see spec-roadmap."
---

# spec-decomposition

Knowledge for the decomposition stage: turn requirements + designs into an executable plan (`roadmap.md`). The artifact's **syntax** lives in `spec-roadmap`; this skill covers the **process and quality bar**. Used by the `teamlead` agent.

## When to use

- Producing `roadmap.md` during decomposition stage.
- Deciding what counts as one task vs. two.
- Designing the blocker DAG (parallelism + ordering).
- Choosing where Q-gates land.

## Process

1. **Read inputs.** `requirements.md` (FR list — every FR maps to ≥1 task or is explicitly out-of-scope), `system-design.md` (integration tasks), `application-design.md` (module/port/contract tasks). `.spec/standards/*.md` for project conventions.
2. **Bucket tasks by layer** before sizing — domain model → contracts → adapters → integration → docs. Forces you to think top-down.
3. **Size to atomicity.** Each task ≤4 hours of focused work. If estimate exceeds, split.
4. **Wire blockers.** Each task lists prerequisites that must be `done` before it can start. Result is a DAG (no cycles).
5. **Define Q-gates.** One Q-gate per quality concern (functional / integration / perf / security). Each Q blocks on all main tasks it verifies.
6. **Assign owners.** Default `code-implementor`. Set `qa-engineer` for all `Q*` quality tasks.
7. **Cross-check FRs.** Every FR has ≥1 task whose Acceptance cites it. No silent dropping.

## Atomicity rules

A task is atomic when:
- **One verb.** "Create TotpService" — yes. "Create TotpService and wire to controller" — no, split.
- **One artifact area.** Single module, single contract, single migration. Cross-cutting (e.g. "add metrics everywhere") splits per area.
- **One acceptance check.** If acceptance has `and`/`or` between mutually independent properties, split.
- **Independent reversibility.** Reverting one task should leave the system buildable (even if partial-feature).

Anti-examples (split required):
- "Implement 2FA backend + frontend" — split: backend service, persistence, REST endpoints, frontend UI.
- "Add caching" — too vague. Pick: cache layer module, cache invalidation, cache metrics, etc.

## Estimation

Choose from a small discrete set: `15m | 30m | 1h | 2h | 4h`. Coarse on purpose — humans aren't accurate beyond this resolution. If a task feels like `8h`, split it.

Q-gates: usually `30m`–`2h` depending on whether tests must be written or only run.

## Blocker DAG

Format per task: `Blockers: <task-id-list>` or `Blockers: —` (no prerequisites).

Rules:
- Listed blockers must be **earlier in the roadmap** (no forward refs).
- No cycles. `roadmap.sh ready` will detect breakage but you should avoid them by construction.
- Aim for **maximum parallelism** in the early layers (domain model + contracts often parallelisable). Sequential dependencies emerge only at integration.
- Don't list transitive blockers — only direct prerequisites. (`C blocked by B, B blocked by A` → C lists `B`, not `A B`.)

## Q-gates (Quality tasks)

Convention: `Q1`, `Q2`, … prefix. `Assignee: qa-engineer`. State machine same as regular tasks (`pending → in-progress → done`).

Per-Q-gate **Acceptance** is the verification criterion — what the `qa-engineer` actually runs:

| Type | Acceptance form | Example |
|---|---|---|
| Tests | `<command> exits 0; all tests pass` | `./gradlew test` |
| Integration | `<scenario> end-to-end works against staging` | `signup + login with TOTP succeeds` |
| Performance | `<endpoint> p95 ≤ <target> at <load>` | `POST /verify p95 ≤ 50ms @ 100 RPS` |
| Security | `<threat-model-item> mitigated` | `no plaintext TOTP secret in DB` |

Q-gates **block on all main tasks** they cover. Verification stage only marks `review` when all Qs are `done` (or explicitly `rejected` with reason).

## Owner assignments

| Role | Owns |
|---|---|
| `code-implementor` | Default for all main tasks (Domain model / Adapters / Contracts / Integration) |
| `qa-engineer` | All Q-gates |
| Other | Rare — e.g. `architect` for a follow-up design refinement task. Don't introduce new owners without a reason. |

## Quality bar (when to mark `review`)

- Every FR from `requirements.md` is referenced in at least one task's Acceptance or explicitly Out.
- All `Open questions` from refinement/design are either resolved or surfaced as tasks (`Q-`-prefixed or main).
- Blocker graph is acyclic and verified via `roadmap.sh ready` returning a non-empty set after parsing.
- Coverage of NFRs by Q-gates: each NFR has a Q-gate or is explicitly marked "covered by existing infrastructure".

## When NOT to use

- Roadmap **syntax** (task header format, field names) → `spec-roadmap` skill.
- Implementing tasks → `code-implementor` agent.
- Running Q-gates → `qa-engineer` agent + `spec-verification` skill.

## Anti-patterns

- **Tasks named like FRs.** `Task 1: FR1 — Generate TOTP secret`. Acceptance gets bloated with FR repetition. Instead: `Task 1: Implement TotpSecretGenerator (covers FR1)`. Acceptance cites FR.
- **Mega-blockers.** `Task 10 blockers: 1, 2, 3, 4, 5, 6, 7, 8, 9` — almost certainly only 2–3 are actual prerequisites. Slim down.
- **No parallelism.** A linear chain of 12 tasks is usually wrong — domain model + contracts can be parallel.
- **Q-gates as afterthought.** Single "Q1: run tests" gate isn't enough. Cover NFRs explicitly — security, perf, observability — each its own Q.
- **Missing acceptance.** A task without observable Acceptance is unverifiable. Add or split.
