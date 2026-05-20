---
name: accept
description: "Manual move sprint → done. Warns if implementation/verification not approved. NOT for content edits."
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/tracking.sh:*) Read AskUserQuestion
---

Move a change from `sprint/` to `done/`. Normally auto-triggered when both `implementation` and `verification` reach `approved` (or `skipped`). Use this for manual override when you want to accept despite incomplete stages (rare; usually a smell).

Argument: `<name>` (required).

## Procedure

1. **Locate.** `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh locate --name <name>`. Exit 1 → "not found"; exit 2 → "ambiguous".

2. **Verify source bucket.** Must be under `.spec/changes/sprint/`. Otherwise refuse with the actual location.

3. **Check stages.** Two `Bash` calls:
   - `${CLAUDE_PLUGIN_ROOT}/scripts/spec/tracking.sh get-stage --change <abs-path> --stage implementation`
   - `${CLAUDE_PLUGIN_ROOT}/scripts/spec/tracking.sh get-stage --change <abs-path> --stage verification`

   - If both ∈ `{approved, skipped}` → proceed silently.
   - Otherwise → AskUserQuestion: "stages not green (implementation=<s1>, verification=<s2>) — accept anyway?" Options: **Accept anyway** / **Cancel**. On Cancel: stop.

4. **Move.** `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh move --name <name> --to done --by user`.

5. **Report:**
   ```
   /accept:
     name: <name>
     from: sprint/
     to:   done/
     implementation: <state>
     verification:   <state>
     warning: <only if states were not green>
   ```

## Important

- This command does **not** flip stage states. If you wanted to mark a stage as approved, use `/track <name> <stage> approved` first.
- Done changes are terminal — they are never automatically moved back. To re-open, use `/backlog-add` with a new name.
