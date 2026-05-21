---
name: workflow
description: "/workflow <name>: drive change through 6 stages via producer agents, user-gated approves. NOT for browse/scaffold (see /change)."
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/tracking.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/roadmap.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/workflow.sh:*) Bash(grep:*) Bash(head:*) Bash(tail:*) Bash(wc:*) Bash(test:*) Read AskUserQuestion Task
---

The orchestrator for `.spec/changes/`. `/workflow <name>` resumes a change from its active stage's current state, delegating production to a sub-agent and gating advancement on user approval. The orchestrator **does not** write code, design, or research — every artifact is produced by a sub-agent per the `spec-workflow` skill's hand-off protocol.

**Mandatory:** Read `${CLAUDE_PLUGIN_ROOT}/skills/spec/workflow/SKILL.md` (paradigm) and `${CLAUDE_PLUGIN_ROOT}/skills/spec/lifecycle/SKILL.md` (state semantics) before driving the loop. They define the contract this command enforces.

## Argument routing

| Argument | Form |
|---|---|
| (empty) | Print usage hint + suggestion to `/change` to find a change name |
| `<name>` (resolves via `change.sh locate`) | **Drive** the orchestration loop |
| anything else | "Not found — run `/change` to list, or `/change \"<text>\"` to scaffold" |

## Procedure

### Step 0 — Parse arguments

1. Read `$ARGUMENTS`, trim, store as `NAME`.
2. If empty → print: `usage: /workflow <change-name> · run /change to list changes`. Exit.

### Step 1 — Locate change

`Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh locate --name "<NAME>"` → capture stdout as `$CP`. On exit 1 (not found): print `change "<NAME>" not found — run /change to browse or /change "<text>" to scaffold` and exit.

### Step 2 — Main loop (re-entered after every state mutation)

Each iteration of the loop:

1. `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/tracking.sh derive-status --change "$CP"` → `$STATUS`.
2. If `STATUS = declined` → print `change is declined (reason: ...).` Read `decline_reason` from `tracking.yaml`. Exit.
3. If `STATUS = done` → print `change is done — all stages completed/skipped.` Exit.
4. `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/tracking.sh derive-stage --change "$CP"` → `$STAGE`.
5. If `$STAGE = none` → print `all stages settled; status=$STATUS` + suggestion to `/change drill` for terminal Approve action. Exit.
6. `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/tracking.sh get-stage --change "$CP" --stage "$STAGE"` → `$STATE`.
7. `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/workflow.sh producer --stage "$STAGE"` → `$PRODUCER`.
8. `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/workflow.sh artifact --stage "$STAGE"` → `$ARTIFACTS` (tab-separated).

### Step 3 — Print context block

```
/workflow <NAME>
  status:   <STATUS>
  stage:    <STAGE>  (<STATE>)
  producer: <PRODUCER>
  artifact: <ARTIFACTS>   (path: $CP/<basename>)
```

### Step 4 — Branch on `$STATE`

#### 4.1 — `estimation` or `required`

**AskUserQuestion** (header `"Start stage"`):
- `"Start now"` — description `"Launches <PRODUCER>. Sets <STAGE> → in-progress."` (Recommended)
- `"Skip stage"` — description `"Marks <STAGE>: skipped. Loop advances to next stage."`
- `"Pause"` — description `"Exit the loop. State stays <STATE>."`

On **Start**:
1. `Bash`: `tracking.sh set-stage --change "$CP" --stage "$STAGE" --state in-progress --by user`.
2. **Launch producer** (see Step 5).
3. After Task returns → re-enter loop at Step 2.

On **Skip**:
1. `Bash`: `tracking.sh set-stage --change "$CP" --stage "$STAGE" --state skipped --by user`.
2. Re-enter loop at Step 2 (auto-advances).

On **Pause**: print final summary (Step 7), exit.

#### 4.2 — `pending` (blocked)

**AskUserQuestion** (header `"Resume blocked stage"`):
- `"Resume"` (Recommended) — description `"Marks <STAGE>: in-progress + launches <PRODUCER>."`
- `"Re-evaluate"` — description `"Marks <STAGE>: required. No producer launch."`
- `"Skip stage"` — description `"Marks <STAGE>: skipped."`
- `"Pause"` — description `"Exit. State stays pending."`

Actions analogous to 4.1, plus Re-evaluate sets `required`.

#### 4.3 — `in-progress`

Producer was running but didn't reach `review` (timed out, was interrupted, or returned without marking). **AskUserQuestion** (header `"In-progress recovery"`):
- `"Re-invoke producer"` (Recommended) — description `"Re-launches <PRODUCER> with same inputs."`
- `"Mark review manually"` — description `"Producer finished out-of-band; advance to review state without re-launch."`
- `"Pause"` — description `"Exit. State stays in-progress."`

On **Re-invoke**: Launch producer (Step 5). Loop.

On **Mark review**: `tracking.sh set-stage --state review --by user`. Loop.

#### 4.4 — `review`

**Preview the artifact**. For each path in `$ARTIFACTS` (TAB-separated):
- `Read` `$CP/<basename>` (limit 200 lines). Print preview with header `--- <basename> (preview) ---`.
- If the file doesn't exist → print `(producer did not write <basename>)` — diagnostic; advise rework.

Then **AskUserQuestion** (header `"Review <STAGE>"`):
- `"Approve"` (Recommended) — description `"Marks <STAGE>: completed. Auto-advances to next stage."`
- `"Request rework"` — description `"Marks <STAGE>: in-progress. Re-launches <PRODUCER> with a rework note."`
- `"Reject"` — description `"Marks <STAGE>: rejected. Exits — upstream must reopen."`
- `"Pause"` — description `"Exit. State stays review."`

On **Approve**:
1. `Bash`: `tracking.sh set-stage --change "$CP" --stage "$STAGE" --state completed --by user`.
2. Re-enter loop at Step 2. (`derive-stage` will return the next non-settled stage; auto-advance is implicit.)

On **Request rework**:
1. **AskUserQuestion Other** asking for a single-line rework note ("Other" enables free-text).
2. `Bash`: `tracking.sh set-stage --change "$CP" --stage "$STAGE" --state in-progress --by user`.
3. Launch producer (Step 5) with `REWORK_NOTE` prepended to the prompt.
4. Loop.

On **Reject**:
1. **AskUserQuestion Other** asking for a single-line reason.
2. `Bash`: `tracking.sh set-stage --change "$CP" --stage "$STAGE" --state rejected --by user`.
3. Print rejection summary. Exit.

#### 4.5 — `completed` / `skipped`

Should not normally land here — `derive-stage` returns the first non-settled stage. If we do (race / inconsistency), `derive-stage` will return `none` next iteration and Step 2.5 handles it. Print diagnostic if reached: `unexpected terminal-state stage; re-check tracking.yaml`. Exit.

#### 4.6 — `rejected`

**AskUserQuestion** (header `"Rejected stage"`):
- `"Reopen"` (Recommended) — description `"Marks <STAGE>: required. Pick up from estimation/required branch."`
- `"Decline change"` — description `"Terminal. Asks for decline reason, moves change → declined/."`
- `"Pause"` — description `"Exit. State stays rejected."`

On **Reopen**: `tracking.sh set-stage --state required --by user`. Loop.

On **Decline**:
1. **AskUserQuestion Other** for reason.
2. `Bash`: `tracking.sh decline --change "$CP" --reason "<reason>" --by user`.
3. `Bash`: `change.sh move --name "$NAME" --to declined --by user`.
4. Exit.

### Step 5 — Launch producer (sub-protocol)

Producer mapping (lookup via `workflow.sh producer --stage <stage>`):

| Stage | Producer | Status in Phase 2A |
|---|---|---|
| refinement | `system-analyst` | **wired (Task launch)** |
| design | `architect` | **stub (not yet implemented)** |
| decomposition | `teamlead` | **stub** |
| implementation | `code-implementor` (per task, in loop) | **wired (task-loop, see Step 6)** |
| verification | `qa-engineer` | **stub** |
| termination | `termination-handler` | **stub** |

For **wired** stages:

`Task` invocation with:
- `subagent_type: "<PRODUCER>"`
- `description: "<STAGE> for <NAME>"`
- `prompt`: stage-specific template (below). Always pass `$CP`, `$STAGE`, and any `$REWORK_NOTE`.

Stage-specific prompts:

- **refinement** (system-analyst):
  ```
  Refine the change at <CP>. Read propose.md + tracking.yaml + .spec/standards/*.md.
  Run clarifying-questions loop. Set scope via tracking.sh set-scope.
  Write requirements.md per the spec-refinement schema.
  Mark refinement: review via tracking.sh set-stage.
  Return the structured 'Refinement draft' report.
  <REWORK_NOTE if any>
  ```

- **implementation** (code-implementor — see Step 6 task-loop): single-task prompt.

For **stub** stages (Phase 2A): instead of `Task`, print:

```
producer <PRODUCER> for stage <STAGE> is not yet implemented (Phase 2A).
Options:
  - mark stage skipped (loop continues)
  - mark stage review manually (if you wrote the artifact by hand)
  - pause workflow
```

Then **AskUserQuestion** with those three options. Apply chosen action and re-enter loop or exit.

### Step 6 — Implementation task-loop (when `$STAGE = implementation` and `$STATE = in-progress`)

Special-case: instead of one Task launch, iterate roadmap tasks.

1. Assert `$CP/roadmap.md` exists. If not → print `roadmap.md missing — go back to decomposition (mark it in-progress)`. Exit.
2. `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/roadmap.sh status --roadmap "$CP/roadmap.md"` → counts.
3. If `pending=0 in-progress=0 blocked=0` and `done+rejected = total` → all settled. **AskUserQuestion**: `"Mark implementation: review"` (Recommended) or `"Pause"`. On approval: `tracking.sh set-stage --state review --by user`. Loop.
4. `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/roadmap.sh ready --roadmap "$CP/roadmap.md"` → newline-separated task IDs (`$READY`).
5. If `$READY` empty:
   - In-progress tasks exist → print task table (parse via `roadmap.sh parse`), advise picking one up manually.
   - Else (all blocked) → print blocker cycle warning + task table.
   - Exit.
6. Pick first ready task as `$TASK_ID` (Phase 2A: first, not picker). Phase 2A caps at 1 task per `/workflow` invocation.
7. `Bash`: `roadmap.sh set-task-state --roadmap "$CP/roadmap.md" --task-id "$TASK_ID" --state in-progress`.
8. **Task** invocation:
   - `subagent_type: "code-implementor"`
   - `description: "Roadmap task <TASK_ID>"`
   - `prompt`: `"Execute roadmap task <TASK_ID> from <CP>/roadmap.md. The task block is your structured spec — enumerate its Acceptance bullets as §1, §2, etc. Read .spec/standards/*.md for project conventions. Apply tests-first if behaviour change. Return your structured READY-TO-COMMIT or BLOCKED report."`
9. After Task returns:
   - If report contains `READY-TO-COMMIT` → `roadmap.sh set-task-state --task-id "$TASK_ID" --state done`.
   - Else → `roadmap.sh set-task-state --task-id "$TASK_ID" --state blocked` + show the BLOCKED reason.
10. Print task summary. **Exit the command** (do not loop — Phase 2A cap of 1 task per invocation). User re-invokes `/workflow <NAME>` to continue.

### Step 7 — Final summary (on pause / completion)

Print one block:

```
/workflow <NAME> — paused
  status:    <STATUS>
  stage:     <STAGE>  (<STATE>)
  artifact:  <ARTIFACTS>
  next:      <next-action hint via `workflow.sh next-action --change "$CP"`>
```

If a state mutation happened this invocation, list it (e.g. `mutated: refinement estimation → in-progress`).

## Important

- **Read `spec-workflow` SKILL.md before driving.** The hand-off protocol is the contract producers follow; orchestrator must enforce it.
- **One loop iteration = one user input.** Never silent-cycle past an AskUserQuestion.
- **Orchestrator never writes artifact content.** Only `Read`s for the review preview.
- **Phase 2A scope:** refinement (real Task) + implementation (real task-loop) wired. Other stages print stub message + AskUserQuestion (skip/mark-review/pause). Wire them in Phase 2B/2C/2D.
- **Auto-bucket move** happens via `tracking.sh sync` (called transitively by `set-stage`). Orchestrator does not call `change.sh move` directly except on Decline.
