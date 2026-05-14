---
name: setup-global-settings
description: "Copy plugin globals (CLAUDE.md, settings.json, .claudeignore) into ~/.claude/ with diff-prompt and backup. Idempotent."
---

You are about to install or refresh user-level Claude Code globals from this plugin's `.claude-global/` into the user's `~/.claude/`.

## Source → target map

- `${CLAUDE_PLUGIN_ROOT}/.claude-global/CLAUDE.md`     → `~/.claude/CLAUDE.md`
- `${CLAUDE_PLUGIN_ROOT}/.claude-global/settings.json` → `~/.claude/settings.json`
- `${CLAUDE_PLUGIN_ROOT}/.claude-global/claudeignore`  → `~/.claude/.claudeignore`

## Procedure

1. Resolve the plugin directory:
   ```bash
   echo "$CLAUDE_PLUGIN_ROOT"
   ```
   If the variable is empty, stop and ask the user to provide the plugin path manually.

2. Ensure `~/.claude/` exists (`mkdir -p`).

3. Set `BACKUP_DIR="$HOME/.claude/.bak/$(date -u +%Y%m%dT%H%M%SZ)"`. Do **not** create it yet — only create it the first time it's actually needed in step 4c.

4. For each (source, target) pair above:
   a. **Target absent** → write the source contents to target. Record as "written".
   b. **Target identical** (`cmp -s source target` → 0) → skip silently. Record as "identical".
   c. **Target differs** → run `diff -u source target | head -n 60` and show the output. Ask via AskUserQuestion:
      - **Overwrite (backup first)**
      - **Keep existing**
      - **Show full diff**
      
      On *Show full diff* → print full `diff -u`, then re-ask.
      On *Overwrite* → `mkdir -p "$BACKUP_DIR"`, `mv` the existing target into `$BACKUP_DIR/`, then write the new contents. Record as "overwritten".
      On *Keep existing* → record as "kept".

5. Print a final summary:
   ```
   Setup complete:
     written: N
     identical: M
     overwritten: K  (backups in ~/.claude/.bak/<timestamp>/)
     kept:    L
   ```

## Important

- Never overwrite a differing target without backing it up first.
- The plugin's `settings.json` template does **not** contain a `hooks` section — the Stop hook is registered automatically by Claude Code from `hooks/hooks.json` when the plugin is installed. If the user's existing `~/.claude/settings.json` had a custom `hooks` block, it will appear as a diff and the user will be prompted explicitly.
- This command is idempotent: running it again on an already-set-up `~/.claude/` is fully silent (all targets identical).
