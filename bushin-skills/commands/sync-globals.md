---
name: sync-globals
description: "Re-sync ~/.claude/ from plugin's .claude-global/ after a /plugin update. Same logic as /setup-global-settings — kept as a separate verb for UX clarity."
---

This command performs **exactly the same procedure as `/setup-global-settings`**. It exists as a separate name so the intent is self-documenting:

- `/setup-global-settings` is what you run **once on a fresh machine**.
- `/sync-globals` is what you run **after `/plugin update`** when you want the plugin's refreshed `.claude-global/` to propagate into `~/.claude/`.

Follow the procedure in [`setup-global-settings.md`](setup-global-settings.md). The diff-prompt + backup discipline is identical: nothing is overwritten without showing the user what changes and putting the old file into `~/.claude/.bak/<timestamp>/`.

After running, if there were no drifts, the summary should show `identical: 3, written: 0, overwritten: 0, kept: 0` — that is the expected steady state.
