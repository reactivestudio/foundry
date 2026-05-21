---
name: in-progress
description: "List changes in .spec/changes/in-progress/ — implementation/verification active. NOT for backlog/closed."
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh:*) Read
---

List all changes currently in `in-progress/` — i.e. with `implementation` or `verification` actively in progress. Shows title, active stage, state, scope, roadmap progress, last event.

No arguments. Read-only.

## Procedure

1. **Run lister.** `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh list --bucket in-progress`.

2. **Render as markdown table.** Columns: `Name | Title | Active stage | State | Scope | Roadmap | Last event`.

   Example:
   ```
   | Name | Title | Active stage | State | Scope | Roadmap | Last event |
   |---|---|---|---|---|---|---|
   | add-2fa-totp | Add 2FA via TOTP | implementation | in-progress | feature | 3/5 done | 2026-05-20 18:12:30 |
   | dark-mode | Dark mode toggle | verification | in-progress | feature | 7/7 done · Q1 pending | 2026-05-20 17:30:11 |
   ```

3. **Report counts:** `N changes in in-progress/`. If empty: `in-progress/ is empty.`

## Important

- Strictly read-only.
- A change auto-moves into `in-progress/` when `/track <name> implementation in-progress` is set. Manual move via `change.sh move --name <n> --to in-progress` is supported but almost never needed.
- For a single change's detail (including roadmap-ready tasks), use `/track <name>`.
