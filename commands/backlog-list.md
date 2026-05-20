---
name: backlog-list
description: "List changes in .spec/changes/backlog/ — active stage, scope, roadmap progress. NOT for sprint/done/declined."
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh:*) Read
---

List all changes currently in `backlog/`. Shows the active (= first non-approved/skipped) stage and its state, scope, roadmap progress (if applicable), and the timestamp of the last history event.

No arguments.

## Procedure

1. **Run lister.** `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh list --bucket backlog`.

2. **Render as markdown table.** Columns: `Name | Active stage | State | Scope | Roadmap | Last event`. Hide the absolute path column unless empty (single-line note).

   Example:
   ```
   | Name | Active stage | State | Scope | Roadmap | Last event |
   |---|---|---|---|---|---|
   | add-2fa | analysis | need-approve | feature | — | 2026-05-20 16:00 |
   | dark-mode | architecture | in-progress | feature | — | 2026-05-20 11:42 |
   ```

3. **Report counts** at the end:
   ```
   3 changes in backlog/
   ```

   If empty: `backlog/ is empty.`

## Important

- Strictly read-only. Does not call any state-changing helpers.
- Sort order: as returned by `change.sh list`. For different sorts, post-process with shell tools.
- For a single change's detail, use `/track <name>`.
