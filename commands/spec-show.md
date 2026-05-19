---
name: spec-show
description: "Compact summary of one spec or change (counts, states, first paragraph). NOT for full content — use Read."
allowed-tools: Read Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/parse-spec.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/parse-delta.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/tasks-progress.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/status.sh:*) Bash(test:*) Bash(ls:*) Bash(find:*)
---

Render a **compact summary** for one `.spec/` item. For full file contents, use `Read` directly — this command intentionally does not dump them.

Argument: `<id>` — capability name (`user-auth`), active change name (`add-2fa`), or archived change name.

## Procedure

1. **Resolve target.** Probe in order:
   - `test -d .spec/specs/<id>` → capability spec.
   - `test -d .spec/changes/<id>` → active change.
   - `find .spec/changes/archive -maxdepth 1 -type d -name "*<id>*"` → archived change (first match).
   - Else report `"item not found: <id>"` and stop.

2. **Capability mode** (`.spec/specs/<id>/spec.md`):
   - `Read` the spec file.
   - Extract first paragraph of `## Purpose` (everything between `## Purpose` and the next blank line).
   - `Bash`: `parse-spec.sh <file>` — TSV of requirements + scenarios.
   - Render:
     ```
     # Capability: <id>

     Purpose: <first paragraph, single line>

     Requirements: <count>
     | name | scenarios | line |
     | Login | 3 | 8 |
     ...

     Path: .spec/specs/<id>/spec.md
     ```

3. **Active change mode** (`.spec/changes/<id>/`):
   - `Bash`: `status.sh <id>` → per-artifact state.
   - `Bash`: `tasks-progress.sh .spec/changes/<id>/tasks.md` → `<done>/<total>`.
   - For each `find .spec/changes/<id>/specs -name spec.md` → run `parse-delta.sh` and count entries by section.
   - `Read` first paragraph of `proposal.md` (between H1 and the next blank line).
   - Render:
     ```
     # Change: <id> (active)

     ## Artifacts
     | artifact | state |
     | proposal | [x] |
     | specs    | [x] |
     | design   | [x] |
     | tasks    | [ ] |

     ## Deltas
     | capability | ADDED | MODIFIED | REMOVED | RENAMED |
     | user-auth | 2 | 1 | 0 | 0 |

     ## Tasks: <done>/<total>

     ## Proposal (first paragraph)
     <text>

     Path: .spec/changes/<id>/
     ```

4. **Archived change mode** — same as active, but report the archive path (`.spec/changes/archive/YYYY-MM-DD-<id>[-N]/`) and skip the `## Tasks` line (archived tasks are historical, not actionable).

## Important

- This is a **summary**, not a dumping ground. For the actual markdown body of any file, the user (or assistant) uses `Read <path>` — that's faster and shows everything verbatim.
- Don't read into `.spec/standards/` here; standards are surfaced via `/spec-list --standards`.
- Don't run any validation; that's `/spec-validate`'s job.
