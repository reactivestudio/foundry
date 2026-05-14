---
name: global-settings-setup
description: "Copy plugin globals (CLAUDE.md, settings.json, .claudeignore) into ~/.claude/ with diff-prompt and backup. Idempotent."
---

You are about to install or refresh user-level Claude Code globals from this plugin's `.claude-global/` into the user's `~/.claude/`.

## Source → target map

- `${CLAUDE_PLUGIN_ROOT}/.claude-global/CLAUDE.md`     → `~/.claude/CLAUDE.md`            (plain copy)
- `${CLAUDE_PLUGIN_ROOT}/.claude-global/settings.json` → `~/.claude/settings.json`        (structured merge — see below)
- `${CLAUDE_PLUGIN_ROOT}/.claude-global/claudeignore`  → `~/.claude/.claudeignore`        (plain copy)

## Preamble

1. Resolve the plugin directory:
   ```bash
   echo "$CLAUDE_PLUGIN_ROOT"
   ```
   If the variable is empty, stop and ask the user to provide the plugin path manually.

2. Ensure `~/.claude/` exists (`mkdir -p`).

3. Set `BACKUP_DIR="$HOME/.claude/.bak/$(date -u +%Y%m%dT%H%M%SZ)"`. Do **not** create it yet — only create it the first time it's actually needed.

## Plain-copy procedure (CLAUDE.md, .claudeignore)

For each of these two (source, target) pairs:

a. **Target absent** → write the source contents to target. Record as "written".
b. **Target identical** (`cmp -s source target` → 0) → skip silently. Record as "identical".
c. **Target differs** → run `diff -u source target | head -n 60` and show the output. Ask via AskUserQuestion:
   - **Overwrite (backup first)**
   - **Keep existing**
   - **Show full diff**

   On *Show full diff* → print full `diff -u`, then re-ask.
   On *Overwrite* → `mkdir -p "$BACKUP_DIR"`, `mv` the existing target into `$BACKUP_DIR/`, then write the new contents. Record as "overwritten".
   On *Keep existing* → record as "kept".

## Structured-merge procedure (settings.json)

`settings.json` cannot be blindly overwritten — Claude Code stores plugin-management state in this file (`extraKnownMarketplaces`, `enabledPlugins`, `disabledPlugins`). A plain copy would wipe marketplace registrations and uninstall the plugin from the user's perspective.

The merge contract:
- The plugin's template provides **defaults** for user-config keys (`model`, `permissions`, `env`, `autoCompactWindow`, etc.).
- The user's existing **plugin-management keys** are always preserved verbatim.
- Other user-customized keys (e.g. theme, custom env vars) — same as plugin-management keys, always preserved.

In effect: existing wins for every conflicting key; template only fills in keys that aren't already present.

Procedure:

1. **Target absent** → write the template directly. Record as "written".

2. **Target exists** → compute the effective merged content:
   ```bash
   TEMPLATE="${CLAUDE_PLUGIN_ROOT}/.claude-global/settings.json"
   TARGET="$HOME/.claude/settings.json"
   MERGED=$(jq -s '.[0] * .[1]' "$TEMPLATE" "$TARGET")
   ```
   (`jq`'s `*` operator deep-merges; right-hand side wins on conflict, so existing values from `TARGET` override template defaults.)

3. Compare `MERGED` to the existing `TARGET`:
   - **Equal** → silent skip. Record as "identical".
   - **Differ** → show a diff between `TARGET` and `MERGED` (`diff -u <(cat "$TARGET") <(echo "$MERGED")`), then prompt the same three-way AskUserQuestion as above.
   - On *Overwrite* → `mkdir -p "$BACKUP_DIR"`, `mv "$TARGET" "$BACKUP_DIR/"`, write `MERGED` to `$TARGET`. Record as "overwritten".
   - On *Keep existing* → record as "kept".
   - On *Show full diff* → print the full diff, then re-ask.

## Final summary

```
Setup complete:
  written: N
  identical: M
  overwritten: K  (backups in ~/.claude/.bak/<timestamp>/)
  kept:    L
```

## Important

- Never overwrite a differing target without backing it up first.
- The plugin's `settings.json` template does **not** contain a `hooks` block — the Stop hook is registered automatically by Claude Code from `hooks/hooks.json` when the plugin is installed.
- Never strip keys from the user's existing `settings.json` — the merge is additive (template fills in missing keys; existing keys win).
- This command is idempotent: running it again is fully silent if no template values have changed.
