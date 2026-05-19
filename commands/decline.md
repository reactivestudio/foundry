---
name: decline
description: "Move change to declined/ with required reason. Terminal. NOT for pausing (use /track <n> <stage> pause)."
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/change-locate.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/change-move.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/tracking-decline.sh:*) Read
---

Move a change from ANY bucket to `declined/`. Requires a reason — stored in `tracking.yaml` as `decline_reason:` and surfaced by `/declined-list`. Terminal: cannot un-decline (open a new change instead).

Arguments: `<name>` `<reason>` (both required).

## Procedure

1. **Locate.** `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change-locate.sh <name>`. Exit 1 → "not found"; exit 2 → "ambiguous".

2. **Verify not already declined.** If source path is already under `.spec/changes/declined/` → "already declined" (no-op, but optionally update `decline_reason` via `tracking-decline.sh` if a different reason was provided).

3. **Set decline_reason.** `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/tracking-decline.sh <abs-source-path> "<reason>" user`. This sets `decline_reason:` field + appends `{ _meta, declined, by: user }` history entry.

4. **Move.** `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change-move.sh <name> declined user`. (`change-move.sh` will also append a `{ _meta, moved-to-declined }` history entry — two `_meta` entries is intended: one for the decision, one for the move.)

5. **Report:**
   ```
   /decline:
     name: <name>
     from: <previous bucket>/
     to:   declined/
     reason: "<reason>"
     note: terminal — to revive, /backlog-add with a new name
   ```

## Important

- `<reason>` is a free-text string. Keep it short (one phrase). Quotes around multi-word reasons recommended.
- For temporary suspension (not terminal), use `/track <name> <stage> pause` — that keeps the change in its current bucket. `decline` is when you've actually decided NOT to do the work.
- Declined changes occupy the name slot — `change-name-validate.sh` will refuse re-using the same `<name>` even after decline.
