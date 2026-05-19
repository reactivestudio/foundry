---
name: spec-status
description: "Per-artifact state ([x]/[ ]/[-]) for one or all active changes. NOT for canonical specs."
allowed-tools: Read Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/status.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/tasks-progress.sh:*) Bash(ls:*)
---

Report per-artifact state for one change or every active change. State meanings (from skill `spec-lifecycle`):
- `[x]` artifact file exists
- `[ ]` dependencies satisfied, file missing (next to create)
- `[-]` dependency missing (blocked)

Argument: `--change <name>` for a single change, or no argument for all.

## Procedure

1. **Resolve target list.**
   - With `--change <name>` → just `<name>`.
   - Without → list active changes via `Bash`: `ls .spec/changes/` (filter out `archive`).

2. **For each change** run `${CLAUDE_PLUGIN_ROOT}/scripts/spec/status.sh <name>`. Parse TSV: `artifact\tstate\tpath`.

3. **Also run** `${CLAUDE_PLUGIN_ROOT}/scripts/spec/tasks-progress.sh .spec/changes/<name>/tasks.md` for the task `done/total` figure.

4. **Render markdown**:

```
## <change-name>
| artifact | state |
| proposal | [x]  |
| specs    | [x]  |
| design   | [x]  |
| tasks    | [ ]  |

Tasks: 0/0 complete
Next artifact to create: tasks
```

When listing all changes, render one section per change. If no active changes → report `"no active changes"`.

## Important

- Always defer to `status.sh` for state classification; do not re-implement the dependency graph in this command.
- The "next artifact" line is the first artifact in `proposal → specs → design → tasks` order with state `[ ]`. If all `[x]`, say `change is implementation-ready (run /spec-apply)`.
