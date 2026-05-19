---
name: declined-list
description: "List declined changes in .spec/changes/declined/ with decline_reason. NOT for active changes."
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/list-changes.sh:*) Bash(grep:*) Read
---

List all changes in `declined/`. Augments the base list with `decline_reason` (read directly from each change's `tracking.yaml`).

No arguments.

## Procedure

1. **Run lister.** `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/list-changes.sh --declined`. If empty output → report `declined/ is empty.` and stop.

2. **For each declined change** (one path per row in the TSV), `Bash`: `grep '^decline_reason:' <path>/tracking.yaml` to extract the reason. Strip the `decline_reason: ` prefix and surrounding quotes.

3. **Render as markdown table.** Columns: `Name | Reason | Declined at`.

   Example:
   ```
   | Name | Reason | Declined at |
   |---|---|---|
   | add-sms-fallback | superseded by add-totp | 2026-05-21 10:00 |
   | rate-limit-v2 | scope too large; split first | 2026-05-19 14:23 |
   ```

4. **Report counts** at the end:
   ```
   2 changes in declined/
   ```

## Important

- Strictly read-only.
- `decline_reason` is required for declined changes (set by `tracking-decline.sh`). If missing, render `—` and surface a warning at the end (file corruption / manual move).
- For a single change's full history, use `/track <name>`.
