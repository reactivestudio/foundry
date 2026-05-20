---
name: sprint-list
description: "List changes in .spec/changes/sprint/ — active stage, scope, roadmap progress. NOT for backlog/done/declined."
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh:*) Read
---

List all changes currently in `sprint/` — i.e. with `implementation` or `verification` actively in progress. Shows active stage, state, scope, roadmap progress, last event.

No arguments.

## Procedure

1. **Run lister.** `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh list --bucket sprint`.

2. **Render as markdown table.** Columns: `Name | Active stage | State | Scope | Roadmap | Last event`.

3. **Report counts** at the end:
   ```
   2 changes in sprint/
   ```

   If empty: `sprint/ is empty.`

## Important

- Strictly read-only.
- For a single change's detail (including roadmap-ready tasks), use `/track <name>`.
