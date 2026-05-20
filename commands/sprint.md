---
name: sprint
description: "List changes in .spec/changes/sprint/ — implementation/verification active. NOT for backlog/closed."
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh:*) Read
---

List all changes currently in `sprint/` — i.e. with `implementation` or `verification` actively in progress. Shows active stage, state, scope, roadmap progress, last event.

No arguments. Read-only.

## Procedure

1. **Run lister.** `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh list --bucket sprint`.

2. **Render as markdown table.** Columns: `Name | Active stage | State | Scope | Roadmap | Last event`.

   Example:
   ```
   | Name | Active stage | State | Scope | Roadmap | Last event |
   |---|---|---|---|---|---|
   | add-2fa | implementation | in-progress | feature | 3/5 done | 2026-05-20 18:12 |
   | dark-mode | verification | in-progress | feature | 7/7 done · Q1 pending | 2026-05-20 17:30 |
   ```

3. **Report counts:** `N changes in sprint/`. If empty: `sprint/ is empty.`

## Important

- Strictly read-only.
- A change auto-moves into `sprint/` when `/track <name> implementation in-progress` is fired. Manual move via bash `change.sh move --name <n> --to sprint` is supported but almost never needed.
- For a single change's detail (including roadmap-ready tasks), use `/track <name>`.
