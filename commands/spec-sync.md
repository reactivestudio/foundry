---
name: spec-sync
description: "Merge change deltas into canonical specs WITHOUT archiving. NOT for full archive lifecycle."
allowed-tools: Read Write Edit Glob Grep Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/validate-structural.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/parse-delta.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/parse-spec.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/status.sh:*) Bash(ls:*) AskUserQuestion
---

Merge a change's delta specs into the canonical `.spec/specs/<cap>/spec.md` files **without** archiving the change. Useful for mid-work checkpointing or stacking subsequent changes on top of in-flight work.

Argument: `<change-name>` (optional).

Activate skills `spec-archive`, `spec-delta-format`, `spec-validation`.

## Procedure

1. **Resolve change name** (same logic as `/spec-apply`).

2. **Pre-merge validation (strict)**. Invoke the same logic as `/spec-validate <change> --strict` inline in this context (no subagent): structural pass + semantic pass per skill `spec-validation`. Any ERROR → abort with the findings table; do not touch canonical specs.

3. **Plan the merge**. For each `.spec/changes/<name>/specs/<cap>/spec.md`:
   - `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/parse-delta.sh <file>` to enumerate ops by section.
   - Read the corresponding canonical `.spec/specs/<cap>/spec.md` (create with stub if it doesn't exist).
   - Plan operations in order **RENAMED → REMOVED → MODIFIED → ADDED**.

4. **Confirm**. AskUserQuestion summary: "Merge N capabilities into canonical specs? <change> stays active (not archived)."
   - **Proceed** — apply the merges.
   - **Show plan** — print the operations table, then re-ask.
   - **Abort** — stop.

5. **Apply merge**. For each capability, in order:
   - Compute the merged canonical text by applying RENAMED → REMOVED → MODIFIED → ADDED to the current canonical content. Use `Read` + in-memory transformation + `Write`. Be precise about block boundaries (a requirement block starts at `### Requirement: <Name>` and ends at the next `###` or `##` or EOF).
   - Re-run `validate-structural.sh <canonical> --kind spec` after the write. Any new errors → abort (manual cleanup needed) and report which capability is in a bad state.

6. **Leave change folder intact**. Do not relocate. The change continues to live in `.spec/changes/<name>/`.

7. **Report**:
   ```
   /spec-sync:
     change: <name>
     capabilities merged: <list>
     ops applied: RENAMED=r REMOVED=k MODIFIED=m ADDED=a
     post-merge canonical: PASS (all touched specs validate)
     change folder: still active at .spec/changes/<name>/
     note: subsequent deltas in this change should reference the updated canonical
   ```

## Important

- Sync writes canonical specs. If you have uncommitted work in `.spec/specs/`, commit it first to make rollback easy.
- Successive deltas in the same change after a sync should reference the **new** canonical state (e.g. MODIFIED uses the renamed name).
- Sync does NOT mark anything in `tasks.md` — that's `/spec-apply`'s job.
