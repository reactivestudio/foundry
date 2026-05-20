---
name: spec-lifecycle
description: "Per-stage state machine + bucket derivation for .spec/changes/. NOT for artifact content rules — see spec-workflow."
---

# spec-lifecycle

A change in `.spec/changes/` has **5 stages** (`analysis`, `architecture`, `decomposition`, `implementation`, `verification`), each with its own state. The directory `<change>/` lives in one of 4 buckets (`backlog/`, `sprint/`, `done/`, `declined/`). The bucket is **derived** from the stages — not stored independently.

## When to use

- Implementing the `/track` command (Form 3 setter) or the listing commands (`/backlog`, `/sprint`, `/closed`).
- Performing a decline operation in response to a user request (no slash command — see Decline procedure below).
- Reasoning about why a change is in `backlog/` vs `sprint/`.
- Understanding what a stage's `pause` / `need-approve` status means.

## Stage state machine

Each stage has one of 6 states:

| State | Meaning |
|---|---|
| `pending` | Not started. |
| `in-progress` | Active work by the owning agent. |
| `need-approve` | Artifact ready, awaiting user review. |
| `approved` | User approved; downstream stages may proceed. |
| `pause` | Deferred — we'll come back later. Does **not** trigger bucket change. |
| `skipped` | Stage deemed unnecessary for this change (e.g. bugfix may skip `architecture`). |

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

## Bucket derivation

Bucket is computed from `stages.implementation` + `stages.verification`:

| Condition | Bucket |
|---|---|
| `implementation` ∈ {in-progress, need-approve} OR `verification` ∈ {in-progress, need-approve} | `sprint` |
| `implementation` ∈ {approved, skipped} AND `verification` ∈ {approved, skipped} | `done` |
| otherwise (analysis/architecture/decomposition active, or everything paused/pending) | `backlog` |
| explicit decline (bash, see below) | `declined` (terminal, manual only) |

`pause` is a **marker**, not a bucket trigger — a paused change stays where it is. To remove a long-paused change from active listings, perform a decline (see Decline procedure below) with reason `"paused indefinitely"`.

After any stage state change via `/track <name> <stage> <state>`, the command:
1. Calls `tracking.sh set-stage` (writes new state + history entry).
2. Calls `tracking.sh derive-bucket` (computes desired bucket).
3. If desired ≠ current → `change.sh move` + appends `{ stage: _meta, status: moved-to-<bucket>, by: auto }` history entry.

## Back-edges (rework loops)

When a later stage detects upstream issues, set the upstream stage from `approved` → `in-progress` (or `need-approve` → `in-progress` if it hasn't been approved yet):

- `architect` realises requirement R is unimplementable → `/track <n> analysis in-progress` → analyst revises requirements.md → `/track <n> analysis need-approve` → user approves → analyst's fix propagates downstream.
- `teamlead` finds the design has no realistic decomposition → similar loop for `architecture`.

History preserves the full trail (each state flip is one entry).

## `decline` and `pause`

| | `decline` | `pause` |
|---|---|---|
| Scope | whole change | per stage |
| Bucket effect | move to `declined/` | stay |
| Terminal? | yes | no (resume any time) |
| Reason field | yes (`decline_reason:`) | no |
| Audit | `_meta/declined` history entry | per-stage history entry |

## Procedure (manual workflow drive)

1. Create: `/backlog "<title>"` → scaffold in `backlog/`, all stages = `pending`.
2. Start analysis: `/track <name> analysis in-progress`.
3. Agent writes `requirements.md`, calls `tracking.sh set-scope --change <path> --scope <s> --by <who>` (via Bash), then `/track <name> analysis need-approve`.
4. User reviews → `/track <name> analysis approved` (or `/track <name> analysis in-progress` to send back for rework).
5. Repeat for `architecture` (writes system-design.md + application-design.md) and `decomposition` (writes roadmap.md).
6. `/track <name> implementation in-progress` → auto-move to `sprint/`. Implementor flips roadmap tasks via `roadmap.sh set-task-state`.
7. When all main roadmap tasks done: `/track <name> implementation need-approve` → user approves.
8. `/track <name> verification in-progress` → verifier runs Q-tasks. When all green: `/track <name> verification need-approve` → user approves → auto-move to `done/`.

## Decline procedure (no slash command)

There is no `/decline` command — a decline is rare and user-initiated by natural language ("decline X because Y"). When you receive such a request:

1. **Locate.** `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh locate --name <name>`. Capture absolute path as `$CP`.
2. **Set decline_reason + history.** `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/tracking.sh decline --change $CP --reason "<reason>" --by user`.
3. **Move.** `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh move --name <name> --to declined --by user` (also appends `_meta/moved-to-declined`).
4. Report `from: <bucket>/ → to: declined/`, the reason, and that decline is terminal (revive = new change with new name).

Declines occupy the name slot — `change.sh validate-name` refuses re-use. That is intentional.

## When NOT to use

- Artifact content / per-stage authorship → `spec-workflow`.
- Roadmap.md syntax + Quality gates → `spec-roadmap`.
- Standards files / long-lived rules → `spec-standards`.
- Naming + tracking.yaml schema → `spec-conventions`.

## Anti-patterns

- Manually editing `tracking.yaml` instead of using helpers — bash parsers depend on strict schema; one stray quote breaks `tracking.sh get-stage`.
- Skipping `need-approve` step — flipping straight from `in-progress` → `approved` loses the human checkpoint. Allowed by state machine, but defeats the purpose.
- Using `pause` instead of `decline` for "we'll never do this" — `pause` keeps the change in active listings forever.
- Hardcoding bucket name in agent prompts — always derive via `tracking.sh derive-bucket` to stay consistent.
- Renumbering history entries or rewriting old `{ stage, status, by }` lines — history is append-only audit.
