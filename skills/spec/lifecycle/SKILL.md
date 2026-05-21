---
name: spec-lifecycle
description: "Per-stage state machine + status/stage derivation for .spec/changes/. NOT for YAML schema — see spec-conventions."
---

# spec-lifecycle

A change in `.spec/changes/` has **6 stages** (`refinement`, `design`, `decomposition`, `implementation`, `verification`, `termination`), each with its own state. The directory lives in one of 4 buckets (`backlog/`, `in-progress/`, `done/`, `declined/`). The top-level `status:` and `stage:` fields are **derived** from the stages — not stored independently.

## When to use

- Driving state changes (via `/change` drill or direct `tracking.sh` calls from agents).
- Reasoning about why a change is in `backlog/` vs `in-progress/`.
- Performing a decline (no slash command — see Decline procedure).

## Stage state machine

Each stage has one of 6 states:

| State | Meaning |
|---|---|
| `pending` | Not started. |
| `in-progress` | Active work by the owning agent. |
| `need-approve` | Artifact ready, awaiting user review. |
| `approved` | User approved; downstream stages may proceed. |
| `pause` | Deferred — we'll come back later. Does **not** trigger bucket change. |
| `skipped` | Stage deemed unnecessary for this change. |

Allowed transitions (enforced by `stage-state-machine.sh validate`):

```
pending      → in-progress | skipped
in-progress  → need-approve | pause | skipped
pause        → in-progress | skipped
need-approve → approved | in-progress     (in-progress = rework after rejection)
approved     → in-progress | skipped       (back-edge: later stage flags rework)
skipped      → in-progress                 (rare: stage reclassified as needed)
```

`pending` is only reachable as initial state — no transition returns to it.

## Status derivation

Top-level `status:` is computed from `implementation`, `verification`, `termination` + presence of `decline_reason`, applied in order:

1. `decline_reason:` field present → `declined` (terminal)
2. `implementation == pending` → `backlog` (planning ongoing or work not yet started)
3. All of `{implementation, verification, termination}` ∈ `{approved, skipped}` → `done`
4. Otherwise → `in-progress`

Key invariant: once `implementation` leaves `pending`, the change cannot return to `backlog` (only to `in-progress`, `done`, or `declined`). A pending `termination` after a completed `verification` keeps the change `in-progress` until termination is closed (approved or skipped). This is intentional — post-merge work like docs/announce belongs in `in-progress/` until done.

`pause` is a **marker**, not a status driver — a paused change stays in its current bucket. To remove a long-paused change from active listings, decline it with reason `"paused indefinitely"`.

## Stage derivation

Top-level `stage:` is the first stage (in order refinement → design → … → termination) whose state is in `{in-progress, need-approve, pause}`. If no such stage exists, `stage: none`.

## After any state change

Whether driven by `/change` drill or direct `tracking.sh set-stage`:

1. `tracking.sh set-stage` writes new state + history entry + calls `sync` (rewrites `status:` and `stage:` fields).
2. Caller compares new `status` to current bucket. If they differ → `change.sh move --to <new-status>`. No history entry is added for the move; the persistent audit is the bucket location itself + history of stage flips that triggered it.

## Stage purpose (informal)

| Stage | Typical artifact | Owner role |
|---|---|---|
| `refinement` | `requirements.md`; `scope` set | system-analyst (future) / user |
| `design` | `system-design.md` + `application-design.md` | architect (future) / user |
| `decomposition` | `roadmap.md` (atomic tasks + Q-gates) | teamlead (future) / user |
| `implementation` | code changes; task states flipped in roadmap.md | code-implementor |
| `verification` | Q-task runs; bug-fix iterations | verifier (future) / user |
| `termination` | post-merge follow-up: docs update, announcement, retro, deployment confirmation | role TBD / user |

Role-agents are partly out of scope today; for now treat owners as Claude doing the work directly.

## Back-edges (rework loops)

When a later stage detects upstream issues, set the upstream stage from `approved` → `in-progress`:

- Architect realises requirement R is unimplementable → set `refinement: in-progress` → revise `requirements.md` → mark `need-approve` → user approves → fix propagates.
- Teamlead finds the design has no realistic decomposition → similar loop for `design`.

History preserves the full trail (each flip = one entry).

## `decline` vs `pause`

| | `decline` | `pause` |
|---|---|---|
| Scope | whole change | per stage |
| Bucket effect | move to `declined/` | stay |
| Terminal? | yes | no (resume any time) |
| Reason field | yes (`decline_reason:`) | no |
| Audit | `decline_reason:` field | per-stage history entry |

## Procedure (manual workflow drive)

1. Create: `/change "<task text>"` → LLM-generates slug + title + description → scaffold in `backlog/`, all stages = `pending`, status = `backlog`, stage = `none`.
2. Start refinement: `/change` → drill → "Start refinement". Or directly: `tracking.sh set-stage --change <path> --stage refinement --state in-progress --by user`.
3. Agent writes `requirements.md`, calls `tracking.sh set-scope --change <path> --scope <s> --by <who>`, then sets `refinement: need-approve`.
4. User reviews → drill → "Approve" (or "Send back" → rework).
5. Repeat for `design` and `decomposition`.
6. Drill → "Start implementation" (or set directly) → status becomes `in-progress`, auto-move to `in-progress/`. Code-implementor flips roadmap tasks via `roadmap.sh set-task-state`.
7. All main tasks done → `implementation: need-approve` → user approves.
8. `verification: in-progress` → verifier runs Q-tasks. All green → `need-approve` → approved.
9. `termination: in-progress` → post-merge tasks (docs, announce, deploy confirm) → `need-approve` → approved → auto-move to `done/`.

## Decline procedure (no slash command)

There is no `/decline`. Decline is rare and user-initiated by natural language ("decline X because Y"), or from `/change` drill-down → "Decline".

Direct sequence:
1. `change.sh locate --name <name>` → `$CP`.
2. `tracking.sh decline --change $CP --reason "<reason>" --by user` → writes `decline_reason:` + syncs status to `declined`.
3. `change.sh move --name <name> --to declined --by user`.

Declines occupy the name slot — `change.sh validate-name` refuses re-use. That is intentional.

## When NOT to use

- YAML schema / field shape → `spec-conventions`.
- `roadmap.md` syntax + Quality gates → `spec-roadmap`.
- Standards files / long-lived rules → `spec-standards`.

## Anti-patterns

- Manually editing `tracking.yaml` (especially `status:` / `stage:`) — derived fields; next `set-stage` overwrites. Bash parsers depend on strict schema; one stray quote breaks `tracking.sh get-stage`.
- Skipping `need-approve` step — flipping `in-progress` → `approved` directly loses the human checkpoint. Allowed by state machine, but defeats the purpose.
- Using `pause` instead of decline for "we'll never do this" — `pause` keeps the change in active listings forever.
- Renumbering or rewriting history entries — append-only audit.
- Skipping `termination` for non-trivial features — post-merge work (docs, announce) usually exists; either do it (advance to approved) or explicitly skip (`skipped`).
