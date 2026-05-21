---
name: track
description: "Change tracker — 3 forms: summary, single-stage, stage setter (with auto-move). NOT for content edits."
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/tracking.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/roadmap.sh:*) Bash(test:*) Bash(ls:*) Bash(grep:*) Bash(tail:*) Read
---

Unified change tracker. Three forms based on argument count.

| Form | Args | Behaviour |
|---|---|---|
| 1 | `<name>` | **Summary** — title, description, status, all stages, scope, artifacts present, roadmap progress, last 5 history events. |
| 2 | `<name> <stage>` | **Single-stage detail** — that stage's state + history filtered to entries about it + who should act next. |
| 3 | `<name> <stage> <state>` | **Setter** — validate transition, write tracking.yaml, auto-resync status, auto-move if bucket changes. |

## Procedure

0. **(For Form 3 — Recommended) Load context.** `Read ${CLAUDE_PLUGIN_ROOT}/skills/spec/lifecycle/SKILL.md` and `${CLAUDE_PLUGIN_ROOT}/skills/spec/workflow/SKILL.md`.

1. **Locate.** `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh locate --name <name>`. Exit 1 → "not found"; exit 2 → "ambiguous". Capture absolute path as `$CP` and bucket name from it.

2. **Branch on form (arg count).**

### Form 1 — Summary

a. `Read $CP/tracking.yaml` to capture `title:`, `description:`, `status:`, `scope:` fields directly.
b. For each of the 5 stages: `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/tracking.sh get-stage --change $CP --stage <stage>`.
c. `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/tracking.sh active-stage --change $CP` → active stage name (or empty).
d. `Bash`: `test -f $CP/<artifact>.md` for each of: requirements, system-design, application-design, roadmap. (`propose.md` always present.)
e. If `roadmap.md` present: `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/roadmap.sh status --roadmap $CP/roadmap.md`.
f. `Bash`: `tail -5 $CP/tracking.yaml | grep '^  - { at:'` for last events.

Render:
```
/track <name>:
  title: "<title>"
  description: "<description>"
  status: <status>
  scope: <scope or —>
  active stage: <stage or — (all done)>
  stages:
    refinement:     <state>
    design:         <state>
    decomposition:  <state>
    implementation: <state>
    verification:   <state>
  artifacts: propose.md [requirements.md] [system-design.md] [application-design.md] [roadmap.md]
  roadmap: <pending=N in-progress=M done=K blocked=L rejected=R total=T  OR  not yet>
  recent history:
    - <last 5 entries verbatim>
  path: <CP>
```

### Form 2 — Single-stage detail

a. Validate `<stage>` ∈ `{refinement, design, decomposition, implementation, verification}`. Otherwise refuse with the list.
b. `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/tracking.sh get-stage --change $CP --stage <stage>` → state.
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
  next action: <prose based on state>
```

### Form 3 — Setter

a. Validate `<state>` ∈ `{pending, in-progress, need-approve, approved, pause, skipped}`. Otherwise refuse.
b. `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/tracking.sh derive-status --change $CP` → BEFORE-status (for comparison).
c. `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/tracking.sh set-stage --change $CP --stage <stage> --state <state> --by user`. On exit 1 (invalid transition) → relay stderr and stop. The set-stage call internally syncs the top-level `status:` field via `sync_status_field`.
d. `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/tracking.sh derive-status --change $CP` → AFTER-status.
e. If `AFTER-status != BEFORE-status` AND `AFTER-status != "declined"`:
   - `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh move --name <name> --to <AFTER-status> --by auto`.
   - Capture new path; future references use new path.

Render:
```
/track <name> <stage> <state>:
  transition: <old-state> → <state>
  status: <BEFORE-status> [→ <AFTER-status> (auto-moved)]
  history entries appended: <count — 1 for set-stage, +1 if moved>
  next: <prose pointer based on resulting state>
```

## Important

- Form 3 **never** moves to/from `declined/`. To decline a change: invoke `tracking.sh decline --change $CP --reason "<reason>" --by user` then `change.sh move --name <name> --to declined --by user` directly (see `spec-lifecycle`).
- Form 3's auto-move uses `change.sh move` which itself appends a `lifecycle/moved-to-*` history entry and re-syncs the destination's `status:` field.
- Skill reads in step 0 are optional for Forms 1 and 2; recommended for Form 3 (state validation matters).
- For a quick "what's next" answer without setting anything, prefer `/track <name>` (Form 1).
