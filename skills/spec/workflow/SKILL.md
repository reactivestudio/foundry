---
name: spec-workflow
description: "Orchestration paradigm: stage→agent map, hand-off via tracking.yaml + artifacts, approve-loop. NOT for stage content rules."
---

# spec-workflow

Paradigm doc for the `/workflow <name>` orchestrator. Explains how the orchestrator drives a change through its 6 stages by delegating production to **producer-agents** and gating advancement on **user approval**. The orchestrator itself **does not write code or research** — composition is its only job.

## When to use

- Reading this before invoking `/workflow` for the first time.
- Building or modifying a producer-agent (`system-analyst`, `architect`, `teamlead`, `code-implementor`, `qa-engineer`, `termination-handler`) — the hand-off protocol below is the contract.
- Wiring up a new stage (rare — there are six and we don't add them lightly).

## Stage → producer mapping (canonical)

Single source of truth: `scripts/spec/workflow.sh producer --stage <s>` and `artifact --stage <s>`. Reproduced here for reference:

| Stage | Producer agent | Input artifacts | Output artifact(s) |
|---|---|---|---|
| refinement | `system-analyst` | `propose.md` + standards | `requirements.md` |
| design | `architect` | `requirements.md` + standards | `system-design.md` + `application-design.md` |
| decomposition | `teamlead` | requirements + designs | `roadmap.md` (main + Q tasks) |
| implementation | `code-implementor` (per task, in loop) | one `roadmap.md` task spec | code + tests for that task |
| verification | `qa-engineer` | `roadmap.md` Q-tasks + code | `verification-report.md` |
| termination | `termination-handler` | full change context | `termination.md` + `CHANGELOG.md` append |

All stages except implementation are **single-shot**: orchestrator launches the producer once per `/workflow` iteration. Implementation is a **task-loop**: orchestrator iterates `roadmap.sh ready` and invokes `code-implementor` per task.

## Hand-off protocol (producer contract)

Every producer-agent **must** follow this 7-step contract:

1. **Read `tracking.yaml`** — assert active stage = expected; refuse if not.
2. **Read input artifacts** per the mapping above. For all stages also read `.spec/standards/*.md`.
3. **Mark `in-progress`** — `tracking.sh set-stage --stage <s> --state in-progress --by <agent>` (skip if already in-progress).
4. **Produce** the output artifact via `Write` (or `Edit` on rework). One file per call.
5. **Mark `review`** — `tracking.sh set-stage --stage <s> --state review --by <agent>`.
6. **Return** a structured report (the agent's `## Output format`). Orchestrator forwards the report verbatim to the user.
7. **Stop.** Do not advance state past `review`; do not invoke other agents; do not commit.

Producers **must NOT**:
- Approve their own work (`completed` is set by user via orchestrator).
- Skip ahead to a later stage.
- Call other sub-agents — composition is the orchestrator's responsibility.

## State branching (orchestrator logic)

For each iteration, the orchestrator reads the active stage's state and branches:

| State | User options | On approve | On reject / rework |
|---|---|---|---|
| `estimation` / `required` | Start · Skip · Pause | start → `in-progress` + launch producer | n/a (no work yet) |
| `pending` (blocked) | Resume · Re-evaluate · Skip · Pause | resume → `in-progress` + launch producer | mark `required` (re-evaluate) |
| `in-progress` | Re-invoke producer · Mark review · Pause | re-launch producer | manual mark `review` |
| `review` | Approve · Rework · Reject · Pause | `completed` + auto-advance to next stage | `in-progress` + relaunch producer w/ rework note (rework); `rejected` (reject) |
| `completed` / `skipped` | — | (auto-advance handled by `derive-stage`) | — |
| `rejected` | Reopen · Decline | reopen → `required` | `decline` → terminal |

`pause` exits the loop without changing state. Next `/workflow <name>` resumes from the same point.

## Implementation stage exception (task-loop)

When `stage = implementation` and `state = in-progress`, orchestrator runs a sub-loop:

1. `roadmap.sh ready --roadmap <CP>/roadmap.md` → list of ready task IDs.
2. Empty list → either all main tasks done (suggest mark `review`) or blocker cycle (escalate to user).
3. Pick first ready task (or AskUserQuestion to let user pick).
4. `roadmap.sh set-task-state --task-id <id> --state in-progress`.
5. `Task(subagent_type=code-implementor, prompt=<task-spec>)` — orchestrator passes change-path + task-id; code-implementor reads roadmap.md itself.
6. On agent's `READY-TO-COMMIT` → `roadmap.sh set-task-state --task-id <id> --state done`. On `BLOCKED` → `--state blocked`.
7. Phase 2 caps the loop at **1 task per `/workflow` invocation** to avoid runaway. User re-invokes to continue.

## What orchestrator does NOT do

- Write code, design, or research — that's the producer-agent's job.
- Approve work without the user — every `review → completed` transition requires explicit user input via AskUserQuestion.
- Bypass stage-state-machine validation — every transition goes through `tracking.sh set-stage`, which calls `stage-state-machine.sh validate`.
- Mutate `roadmap.md` task states outside the implementation task-loop.

## When NOT to use

- Browsing changes (list/drill/scaffold) → `/change` and skill `spec-conventions`.
- Manual stage transitions (one-off) → `/change drill` or direct `tracking.sh set-stage`.
- Writing the artifact content itself → per-stage skill (`spec-refinement`, `spec-design`, `spec-decomposition`, `spec-verification`, `spec-termination`).

## Anti-patterns

- **Orchestrator reads/writes the artifact files.** Never. The producer reads inputs and writes the output. Orchestrator only Reads the artifact for the **review preview** when presenting to the user.
- **Producer calls another producer.** Forbidden. If `architect` needs more requirements, it returns to the orchestrator and the user decides whether to reopen refinement.
- **Skipping `review` state.** Producer must transition `in-progress → review` before returning. Orchestrator detects drift (still `in-progress` after Task return) and prompts user to mark `review` manually.
- **Loop within orchestrator without user input.** Every iteration of the main loop must terminate at an AskUserQuestion or an exit; never silent-cycle.
