---
name: spec-apply
description: "Load change context (tasks/design/specs/standards) for implementation. NOT for spec authoring."
allowed-tools: Read Write Edit Glob Grep Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/status.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/tasks-progress.sh:*) Bash(ls:*) AskUserQuestion Task
---

Load a change's full implementation context (tasks + design + deltas + canonical specs + standards) into the current conversation and hand off to **the current assistant**. No automatic delegation.

Argument: `<change-name>` (optional; inferred when only one active change has pending tasks). Optional flag: `--agent <name>` (explicit delegation to a specific foundry agent).

## Procedure

1. **Resolve change name.**
   - Supplied → use.
   - Else: `Bash`: `ls .spec/changes/` (filter `archive`). For each entry, run `tasks-progress.sh tasks.md`; pick those with pending tasks (`done < total`). Single → use. Multiple → AskUserQuestion. Zero with pending → `"no changes have pending tasks"`.

2. **Sanity-check artifacts.** `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/status.sh <name>`. All four must be `[x]`. If `tasks` or `design` is `[ ]/[-]` → `"missing artifact — run /spec-continue first"` and stop.

3. **Load context.** Read into current conversation, in this order:
   - `.spec/project.md` — project context.
   - `.spec/config.yaml` — `rules` (especially anything that constrains code structure).
   - **Every** `.spec/standards/*.md` — long-lived constraints (these are the most important reads; they govern HOW the implementation should be shaped).
   - `.spec/changes/<name>/proposal.md` — why & what.
   - `.spec/changes/<name>/design.md` — how.
   - **Every** `.spec/changes/<name>/specs/<cap>/spec.md` — delta requirements (the contract the code must satisfy).
   - For each capability touched by deltas, the canonical `.spec/specs/<cap>/spec.md` if present (so the agent knows pre-existing behaviour).
   - `.spec/changes/<name>/tasks.md` — the checklist to drive against.

4. **Print a tight summary** of what was loaded:
   ```
   /spec-apply context loaded:
     change: <name>
     pending tasks: <done>/<total>
     standards consulted: <list>
     capabilities (delta): <list>
     handoff: continue in this conversation, or delegate to a foundry agent.
   ```

5. **Branch on `--agent <name>` flag**:
   - **Absent (default)** — Do **not** call `Task`. The current assistant continues directly, using the loaded context, implementing pending tasks tests-first, marking `[x]` in `tasks.md` via `Edit` as each task completes. Each changed line must trace to a delta requirement.
   - **Present** — `Task` with `subagent_type: <name>`. Pass the loaded context + instruction: "implement pending tasks in tasks.md against design.md + delta specs + standards/; mark [x] as you finish each; respect every constraint in standards/." This is the only place this command may delegate, and only when the user asked explicitly.

6. **Working principles during implementation** (current assistant or delegated agent):
   - Tests-first when behaviour changes (characterisation tests if legacy code; TDD if greenfield).
   - Minimal diff per task.
   - After each task, run the project's test / typecheck / lint commands; mark `[x]` only when green.
   - Do not touch out-of-scope files unless tasks explicitly demand it.
   - When something contradicts standards/ — STOP and surface the conflict; do not silently violate.

7. **Final report** (after implementation, by current assistant or returned by the delegated agent):
   ```
   /spec-apply done:
     change: <name>
     tasks completed this run: <n>
     tasks remaining: <m>
     files changed: <count> (see git diff)
     verification: tests PASS|FAIL · typecheck PASS|FAIL · lint PASS|FAIL
     open questions for next step: <list or none>
     next: /spec-validate <name> --strict  →  /spec-archive <name> -y
   ```

## Important

- **No automatic delegation.** This command is a **context loader**, not an agent dispatcher. Multi-agent workflows are the user's composition: «загрузил контекст → выбираю кого пускать» (current chat, `code-implementor`, `architect` for design review, parallel worktrees, etc.).
- `.spec/standards/*.md` overrides any local impulse: if a standards file says "no global state" and the easiest impl uses a singleton, change the approach.
- Implementation is not the command's responsibility — it ends after loading context (or after the optional delegated agent finishes).
- Re-running `/spec-apply` is safe: it always picks up pending `[ ]` tasks; completed ones are untouched.
