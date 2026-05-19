---
name: spec-archive
description: "Validate, merge deltas, relocate change to archive/YYYY-MM-DD-<name>/. NOT for mid-work merges."
allowed-tools: Read Write Edit Glob Grep Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/validate-structural.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/parse-delta.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/parse-spec.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/tasks-progress.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/archive-relocate.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/status.sh:*) Bash(ls:*) AskUserQuestion
---

Complete a change: validate, merge deltas into canonical specs, and relocate the change folder to `.spec/changes/archive/YYYY-MM-DD-<name>/`.

Arguments: `<change-name>` (or several, with `--bulk`). Flags: `-y`/`--yes`, `--bulk`, `--skip-specs`, `--no-validate`.

## Procedure

0. **Load merge + validation rules first (MANDATORY).** `Read` these skill bodies before touching any canonical spec or moving any directory:
   - `${CLAUDE_PLUGIN_ROOT}/skills/spec/archive/SKILL.md`
   - `${CLAUDE_PLUGIN_ROOT}/skills/spec/delta-format/SKILL.md`
   - `${CLAUDE_PLUGIN_ROOT}/skills/spec/validation/SKILL.md`
   - `${CLAUDE_PLUGIN_ROOT}/skills/spec/format/SKILL.md`

   Critical rules from the reads: merge order is **RENAMED → REMOVED → MODIFIED → ADDED**; line-based merge preserves nested `####`/`#####` inside requirement bodies; if canonical spec is missing for a capability, create it from scratch with `# <Cap> Specification` + `## Purpose` + `## Requirements` + ADDED requirements appended; force flags (`--no-validate`, `--skip-specs`, `--bulk`, `-y`) each have specific semantics — see the skill.

1. **Parse args**. Determine target list. With `--bulk`, every positional argument after `--bulk` is a target. Otherwise, single target (or AskUserQuestion if absent and there's ambiguity).

2. **Validation pass** (unless `--no-validate`). For each target, run the same logic as `/spec-validate <change> --strict` inline in this context (no subagent): structural + semantic. With `--bulk`, if **any** target fails, abort the entire bulk; no merges happen. (`--no-validate` skips this gate but emits a loud warning.)

3. **Tasks check** (advisory). For each target, run `tasks-progress.sh tasks.md`. If `done < total`, emit WARNING. With `-y`, proceed despite; without `-y`, AskUserQuestion: continue / cancel.

4. **Confirm overall plan** (unless `-y`). AskUserQuestion: "Archive <N> change(s): <list>? Validate→merge→relocate."
   - **Proceed** — go.
   - **Abort** — stop.

5. **For each target** (in order):
   - **Merge** (unless `--skip-specs`):
     - For each `.spec/changes/<name>/specs/<cap>/spec.md`:
       - `parse-delta.sh` → get ops by section.
       - Read canonical (stub if missing).
       - Apply **RENAMED → REMOVED → MODIFIED → ADDED**, stage to in-memory result, `Write` back.
       - Post-write structural re-check on canonical via `validate-structural.sh ... --kind spec`. Bad state → abort the bulk (cannot continue safely); report which target/capability is broken.
   - **Relocate**:
     - `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/archive-relocate.sh <name>`.
     - Capture target path from stdout (`.spec/changes/archive/YYYY-MM-DD-<name>[-N]/`).
   - **Record outcome** per target: `archived: <name> → <target-path>`. Note `-N` suffix if same-day collision was resolved.

6. **Report**:
   ```
   /spec-archive:
     mode: single | bulk (N changes) | skip-specs | no-validate
     archived:
       - <name1>  →  archive/<date>-<name1>/
       - <name2>  →  archive/<date>-<name2>-2/  (same-day collision)
     canonical specs merged: <count>
     warnings: <task incompleteness, etc.>
     status: COMPLETE | PARTIAL (<x> archived, <y> failed)
   ```

## Important

- `--bulk` is atomic at the validation gate but **not** during merge — if merge of target N fails, targets 1..N-1 are already in canonical and the script cannot roll back. Surface this clearly. Recovery: complete the remaining merges manually, or `git restore .spec/`.
- `--no-validate` is for **recovery only**. The summary must include "validation bypassed" in red prose when used.
- The change folder relocates to `archive/`; subsequent commands referring to `.spec/changes/<name>/` will fail until the user knows where it went.
- After archive, `git status` should show: modified canonical specs + renamed change dir. Stage and commit as one logical change.
