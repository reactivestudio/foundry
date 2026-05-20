---
name: sprint-add
description: "Manual move backlog → sprint. Usually unnecessary (auto on implementation in-progress). NOT for content edits."
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh:*) Read
---

Move a change from `backlog/` to `sprint/` explicitly. This is a **manual override** — normally `/track <name> implementation in-progress` triggers the move automatically (see `spec-lifecycle`).

Argument: `<name>` (required).

## Procedure

1. **Locate.** `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh locate --name <name>`. Exit 1 → "change not found"; exit 2 → "ambiguous (multiple buckets)".

2. **Verify source bucket.** Path must be under `.spec/changes/backlog/`. If under `sprint/` already → "already in sprint" (no-op). If under `done/` or `declined/` → refuse: "cannot move from done/declined to sprint — these are terminal".

3. **Move.** `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh move --name <name> --to sprint --by user`. `change.sh move` appends `{ _meta, moved-to-sprint, by: user }` history entry automatically.

4. **Report:**
   ```
   /sprint-add:
     name: <name>
     from: backlog/
     to:   sprint/
     note: stages unchanged; use /track <name> implementation in-progress to actually start implementation work
   ```

## Important

- Does not change any stage state. Only moves directory + appends `_meta` history.
- Auto-move from `/track <name> implementation in-progress` is the normal flow. Use `/sprint-add` only when you want the bucket move decoupled from the stage flip.
