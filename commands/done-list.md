---
name: done-list
description: "List successfully completed changes in .spec/changes/done/. NOT for in-progress or declined."
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/list-changes.sh:*) Read
---

List all changes in `done/` — `implementation` and `verification` both `approved` (or `skipped`). Shows scope, roadmap progress (mostly all-done), last event timestamp.

No arguments.

## Procedure

1. **Run lister.** `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/list-changes.sh --done`.

2. **Render as markdown table.** Columns: `Name | Scope | Roadmap | Completed at`.
   (Active stage is empty for done changes; skip that column.)

3. **Report counts** at the end:
   ```
   12 changes in done/
   ```

   If empty: `done/ is empty.`

## Important

- Strictly read-only.
- Done changes are kept indefinitely as history. If a name needs to be re-used, find the old one here and either rename or pick a different angle.
- For a single change's full audit trail, use `/track <name>` (reads tracking.yaml history).
