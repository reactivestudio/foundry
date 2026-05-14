---
name: global-settings-show
description: "Read-only diagnostic: status of ~/.claude/ globals vs plugin sources. Lists managed/drifted/user-only files."
---

Read-only diagnostic command. **Do not modify any files.**

## What to report

For each managed source (`${CLAUDE_PLUGIN_ROOT}/.claude-global/{CLAUDE.md,settings.json,claudeignore}`) and its corresponding target (`~/.claude/CLAUDE.md`, `~/.claude/settings.json`, `~/.claude/.claudeignore`), determine the state:

| State | Meaning |
|---|---|
| **identical** | `cmp -s` returns 0; target matches plugin source |
| **drifted** | both exist but differ; user has local edits or plugin updated |
| **target-missing** | plugin has a source, but `~/.claude/` does not — never been set up |
| **user-only** | (rare) target exists in `~/.claude/` but no corresponding plugin source — out of scope of this command, but if seen, report under "Other" |

Also report the backup directory state:
- Path: `~/.claude/.bak/`
- Number of backup runs (subdirectory count)
- Most recent timestamp

## Procedure

1. Resolve `CLAUDE_PLUGIN_ROOT` via `echo "$CLAUDE_PLUGIN_ROOT"`. If empty, ask the user.
2. For each pair, run `cmp -s source target` and an `stat` on each side. Capture state.
3. For drifted files, run a short `diff -u source target | head -n 20` to give a preview (do **not** dump the full diff unless the user asks).
4. List `~/.claude/.bak/` contents: count of subdirectories and the latest one.

## Output format

```
Globals status (from /global-settings-show)
Plugin: <CLAUDE_PLUGIN_ROOT>
Target: ~/.claude/

  CLAUDE.md       <state>
  settings.json   <state>
  .claudeignore   <state>

Backups: <N> backup run(s); latest: <path or "none">

[If any drifted file:]
Drift preview (first 20 lines):
<short diffs>

Tip: run /global-settings-setup to bring drifted files in line with the plugin (with diff-prompt and backup; idempotent on identical files).
```

This command is purely informational. It does not write, move, or back up anything.
