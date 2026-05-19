---
name: track
description: "Change tracker — 3 forms: summary, single-stage, stage setter (with auto-move). NOT for content edits."
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/change-locate.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/tracking-get-stage.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/tracking-set-stage.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/tracking-active-stage.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/tracking-derive-bucket.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/change-move.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/roadmap-status.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/roadmap-ready.sh:*) Bash(test:*) Bash(ls:*) Bash(grep:*) Bash(tail:*) Read
---

Unified change tracker. Three forms based on argument count.

| Form | Args | Behaviour |
|---|---|---|
| 1 | `<name>` | **Summary** — all stages, scope, artifacts present, roadmap progress, last 5 history events. |
| 2 | `<name> <stage>` | **Single-stage detail** — that stage's state + history filtered to entries about it + who should act next. |
| 3 | `<name> <stage> <state>` | **Setter** — validate transition, write tracking.yaml, auto-recompute bucket, auto-move if needed. |

## Procedure

0. **(For Form 3 — Recommended) Load context.** `Read ${CLAUDE_PLUGIN_ROOT}/skills/spec/lifecycle/SKILL.md` and `${CLAUDE_PLUGIN_ROOT}/skills/spec/workflow/SKILL.md` if you intend to set a state — these explain valid transitions and who owns each stage.

1. **Locate.** `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change-locate.sh <name>`. Exit 1 → "not found"; exit 2 → "ambiguous". Capture absolute path as `$CP` and bucket name from it.

2. **Branch on form (arg count).**

### Form 1 — Summary

a. `Bash`: read each stage via `tracking-get-stage.sh $CP <stage>` for the 5 stages.
b. `Bash`: `tracking-active-stage.sh $CP` → active stage name (or empty).
c. `Bash`: read scope from `$CP/tracking.yaml` (grep `^scope:`).
d. `Bash`: `test -f $CP/<artifact>.md` for each of: requirements, system-design, application-design, roadmap. (proposal.md always present.)
e. If `roadmap.md` present: `Bash`: `roadmap-status.sh $CP/roadmap.md`.
f. `Bash`: `tail -5 $CP/tracking.yaml | grep '^  - { at:'` for last events (or whole history if shorter).

Render:
```
/track <name>:
  bucket: <bucket>
  scope: <scope or —>
  active stage: <stage or — (all done)>
  stages:
    analysis:       <state>
    architecture:   <state>
    decomposition:  <state>
    implementation: <state>
    verification:   <state>
  artifacts: proposal.md [requirements.md] [system-design.md] [application-design.md] [roadmap.md]
  roadmap: <pending=N in-progress=M done=K blocked=L rejected=R total=T   OR  not yet>
  recent history:
    - <last 5 entries verbatim>
  path: <CP>
```

### Form 2 — Single-stage detail

a. Validate `<stage>` ∈ `{analysis, architecture, decomposition, implementation, verification}`. Otherwise refuse with the list.
b. `Bash`: `tracking-get-stage.sh $CP <stage>` → state.
c. `Bash`: `grep '^  - { at:.*stage: <stage>,' $CP/tracking.yaml` (filter history to this stage).
d. From `spec-workflow` knowledge, identify owner role + expected artifact + next action.

Render:
```
/track <name> <stage>:
  state: <state>
  owner role: <role from spec-workflow>
  artifact: <expected artifact filename(s)>
  history:
    - <each entry for this stage>
  next action:
    <prose based on state — e.g. "agent <role> should write <artifact> and run /track <name> <stage> need-approve when ready">
```

### Form 3 — Setter

a. Validate `<state>` ∈ `{pending, in-progress, need-approve, approved, pause, skipped}`. Otherwise refuse.
b. `Bash`: `tracking-derive-bucket.sh $CP` → BEFORE-bucket (for comparison).
c. `Bash`: `tracking-set-stage.sh $CP <stage> <state> user`. On exit 1 (invalid transition) → relay validator's stderr and stop.
d. `Bash`: `tracking-derive-bucket.sh $CP` → AFTER-bucket.
e. If `AFTER-bucket != current bucket of $CP`:
   - `Bash`: `change-move.sh <name> <AFTER-bucket> auto`.
   - Capture new path; future references to `$CP` should use the new path.

Render:
```
/track <name> <stage> <state>:
  transition: <old-state> → <state>
  scope unchanged
  bucket: <current bucket>  [→ <new bucket> (auto-moved)]
  history entries appended: <count — 1 for set-stage, +1 if moved>
  next: <prose pointer based on resulting state — e.g. "stage now need-approve; user reviews and runs /track <name> <stage> approved or in-progress (rework)">
```

## Important

- Form 3 NEVER moves to/from `declined/` — use `/decline` for that.
- Form 3's auto-move uses `change-move.sh` which itself appends a `_meta/moved-to-*` history entry; the report must reflect the two-entry append.
- Skill reads in step 0 are optional in Forms 1 and 2 (they are pure read-only summaries); they are recommended for Form 3 because that's where state validation matters.
- For a quick "what's next" answer without setting anything, prefer `/track <name>` (Form 1) — it shows the active stage and recent history at a glance.
