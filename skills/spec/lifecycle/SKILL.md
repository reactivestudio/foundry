---
name: spec-lifecycle
description: "Per-stage state machine (8 states) + status/stage derivation for .spec/changes/. NOT for YAML schema — see spec-conventions."
---

# spec-lifecycle

A change in `.spec/changes/` has **6 stages** (`refinement`, `design`, `decomposition`, `implementation`, `verification`, `termination`), each with its own state from an 8-element set. The directory lives in one of 4 buckets (`backlog/`, `in-progress/`, `done/`, `declined/`). The top-level `status:` and `stage:` fields are **derived** from the stages — not stored independently.

## When to use

- Driving state changes (via `/change` drill or direct `tracking.sh` calls from agents).
- Reasoning about why a change is in `backlog/` vs `in-progress/`.
- Performing a decline (no slash command — see Decline procedure).

## Stage state machine (8 states)

| State | Meaning |
|---|---|
| `estimation` | Initial. Decide whether this stage is needed for this change. |
| `required` | Decided needed, not yet started. May be waiting on scheduling / caller. |
| `skipped` | Decided not needed for this change (terminal-for-stage). |
| `pending` | Needed and started, but currently blocked by an external factor. |
| `in-progress` | Active work by the owning agent. |
| `review` | Artifact ready, awaiting user / peer review. |
| `completed` | Review approved (terminal-for-stage, success). |
| `rejected` | Unrealizable as currently scoped — needs upstream stages revisited (compromise / clarification). Stays here until upstream-fix path resumes work. |

Allowed transitions (enforced by `stage-state-machine.sh validate`):

```
estimation   → required | skipped | in-progress     (in-progress = decide + start in one step)
required     → pending | in-progress | skipped
pending      → in-progress | required | skipped     (unblock, re-eval need, or de-scope)
in-progress  → review | pending | rejected | skipped
review       → completed | in-progress | rejected   (approved, rework, or unrealizable)
completed    → in-progress | rejected               (back-edges from downstream)
skipped      → required | in-progress               (reclassified)
rejected     → required | in-progress               (upstream fixed, resume)
```

`estimation` is initial-only — no transition returns to it.

## Status derivation

Top-level `status:` is computed from `implementation`, `verification`, `termination` + presence of `decline_reason`, applied in order:

1. `decline_reason:` field present → `declined` (terminal)
2. `implementation ∈ {estimation, required}` → `backlog` (impl not yet active)
3. All of `{implementation, verification, termination}` ∈ `{completed, skipped}` → `done`
4. Otherwise → `in-progress`

**Key invariant:** once `implementation` moves past `{estimation, required}`, the change cannot return to `backlog` (only to `in-progress`, `done`, or `declined`). A `pending` (= blocked) impl still counts as `in-progress` for bucket purposes. A `rejected` stage likewise keeps status `in-progress` until upstream-fix work resumes.

## Stage derivation

Top-level `stage:` is the first stage (in canonical order) whose state is **not** in `{completed, skipped}` — i.e. the first stage that still has work due. If every stage is `completed` or `skipped`, `stage: none`.

Practical consequence: a freshly scaffolded change has `stage: refinement` (because refinement is `estimation`, which is not terminal). After refinement completes, `stage` becomes `design`, and so on.

## After any state change

Whether driven by `/change` drill or direct `tracking.sh set-stage`:

1. `tracking.sh set-stage` writes new state + history entry + calls `sync` (rewrites `status:` and `stage:` fields).
2. Caller compares new `status` to current bucket. If they differ → `change.sh move --to <new-status>`. No history entry is added for the move; the persistent audit is the bucket location itself + history of stage flips that triggered it.

## Stage purpose (informal)

| Stage | Typical artifact | Owner role |
|---|---|---|
| `refinement` | `requirements.md`; `scope` set | system-analyst |
| `design` | `system-design.md` + `application-design.md` | architect (future) / user |
| `decomposition` | `roadmap.md` (atomic tasks + Q-gates) | teamlead (future) / user |
| `implementation` | code changes; task states flipped in roadmap.md | code-implementor |
| `verification` | Q-task runs; bug-fix iterations | verifier (future) / user |
| `termination` | post-merge follow-up: docs update, announcement, retro, deployment confirmation | role TBD / user |

Role-agents are partly out of scope today; for now treat owners as Claude doing the work directly, except `system-analyst` (refinement) and `code-implementor` (implementation) which already exist.

## Back-edges (rework loops)

When a later stage detects upstream issues:

- **Soft rework**: set the upstream stage from `completed` → `in-progress`. The work resumes; once re-reviewed and re-completed, downstream picks up.
- **Hard reject**: set the current stage to `rejected`. This signals "unrealizable as currently scoped". To resume, an upstream stage must be reopened, the conflict resolved, and downstream stages set back to `required` / `in-progress`.

History preserves the full trail (each flip = one entry).

## `decline` vs `pause`-equivalent

`pause` is no longer a state. To park a change indefinitely, use `pending` (blocked — temporary) or `rejected` (cannot be done now) at the active stage, or perform a full decline for the whole change:

| | `decline` | `pending`/`rejected` |
|---|---|---|
| Scope | whole change | single stage |
| Bucket effect | move to `declined/` | stays (counts as in-progress) |
| Terminal? | yes | no (resume any time) |
| Reason field | yes (`decline_reason:`) | none |
| Audit | `decline_reason:` field | per-stage history entry |

## Procedure (manual workflow drive)

1. **Create**: `/change "<task text>"` → LLM generates slug + title + description → scaffold in `backlog/`, all stages = `estimation`, status = `backlog`, stage = `refinement`.
2. **Start refinement**: `/change` → drill → action "Start (in-progress)". `system-analyst` agent takes over: clarifying-questions → set scope → write `requirements.md` → mark `refinement: review`.
3. **User reviews**: `/change` → drill → "Approve (completed)" or "Send back (in-progress)".
4. **Repeat** for `design` (writes system-design.md + application-design.md) and `decomposition` (writes roadmap.md).
5. **Implementation**: `/change` → drill → "Start (in-progress)" → status flips to `in-progress`, auto-move to `in-progress/`. Code-implementor flips roadmap tasks via `roadmap.sh set-task-state`.
6. When all main roadmap tasks done: `/change` → drill → "Send to review" → user approves → `completed`.
7. **Verification**: similar — verifier runs Q-tasks, marks review when green.
8. **Termination**: post-merge tasks (docs, announce, deploy confirm) → review → completed → auto-move to `done/`.

If at any point a stage hits an unresolvable blocker → set it to `rejected`, reopen an upstream stage to resolve the conflict.

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
- Skipping `review` step — flipping `in-progress` → `completed` directly loses the human checkpoint. Allowed by state machine, but defeats the purpose.
- Using `pending` for "we'll never do this" — `pending` is for temporary blocks. Use `rejected` (per-stage) or full decline (whole change).
- Renumbering or rewriting history entries — append-only audit.
- Skipping `termination` for non-trivial features — post-merge work (docs, announce) usually exists; either do it (advance to completed) or explicitly skip.
