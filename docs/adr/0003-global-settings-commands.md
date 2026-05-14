# ADR 0003 — In-plugin slash-commands for managing `~/.claude/` globals

- **Status:** Accepted
- **Date:** 2026-05-14
- **Deciders:** repo owner (solo)

## Context

Claude Code's plugin system natively auto-loads `agents/`, `commands/`, `skills/`, `hooks/` and `mcp/` straight from a plugin's directory. It does **not** manage user-level globals: `~/.claude/CLAUDE.md` (user memory), `~/.claude/settings.json` (model, permissions, env, plus runtime plugin-management state like `extraKnownMarketplaces` and `enabledPlugins`), and `~/.claude/.claudeignore`. These have to be present in `~/.claude/` for Claude Code to read them on every session.

We need a way for the plugin to ship templates for these files and reconcile them with whatever is already in `~/.claude/`, both on initial install and after `/plugin update`.

Options considered:

1. **In-plugin slash-commands** that copy from `.claude-global/` into `~/.claude/` with diff-prompt and backup. Driven by Claude using Read/Write/Bash/AskUserQuestion at runtime.
2. **External bash script** the user runs after `/plugin install`. Re-introduces the CLI surface ADR 0001 eliminated.
3. **`postinstall` hook in `plugin.json`** that copies files automatically. Risk: silent overwrites of user-modified globals; no diff-prompt UX; not sure if Claude Code supports this hook universally.
4. **Symlinks from plugin's `.claude-global/` to `~/.claude/`**. Re-introduces every symlink downside ADR 0001 rejected.
5. **Manual copy** from the README. Drifts immediately.

## Decision

Use **two in-plugin slash-commands**:

- **`/global-settings-setup`** — copy `.claude-global/*` into `~/.claude/`. Idempotent — same command for initial install and post-update sync. For `CLAUDE.md` and `.claudeignore` it's a plain copy with diff-prompt + backup. For `settings.json` it's a structured `jq` merge where existing values win on conflict, so plugin-management keys (`extraKnownMarketplaces`, `enabledPlugins`, `disabledPlugins`) and user customizations survive.
- **`/global-settings-show`** — read-only diagnostic: identical / drifted / missing per template file.

Both are markdown files in `bushin/commands/`. Body is a prompt for Claude; runtime execution uses Read/Write/Bash/AskUserQuestion. No external code.

Commands explicitly rejected for being mostly redundant with built-ins or with the two above:

- `/sync-globals` — separate verb for "run setup after /plugin update". Dropped: `/global-settings-setup` is idempotent and self-documenting.
- `/configure` — interactive sub-flow editor for `settings.json`. Dropped: Claude Code has `/config` built-in for model selection; for `permissions`/`env`/`hooks` editing the file directly with diff support beats blind AskUserQuestion chains.

## Rationale

| Factor | In-plugin commands (chosen) | External bash script | postinstall hook | Symlinks |
|---|---|---|---|---|
| Maintenance code | nil (just prompts) | bash script to maintain | depends on Claude Code support | nil but fragile |
| Idempotent re-run | yes, by design | yes if written carefully | unclear semantics | yes (same inode) |
| Diff-prompt UX before overwrite | yes (AskUserQuestion) | possible | typically no | n/a (silent overwrite via inode change) |
| Backup of pre-existing files | yes (`~/.claude/.bak/<UTC>/`) | possible | typically no | none |
| Preserves user `settings.json` runtime state | yes (structured merge) | possible | typically no | no (would lose edits) |
| Honours user-level CLAUDE.md edits | yes (drift detection, prompt) | depends | typically no | no |
| Works without leaving Claude Code | yes | no (terminal context switch) | yes (silent) | n/a |

## Consequences

- The two tuning commands are the canonical surface for `~/.claude/` management; the README and `docs/architecture.md` document them.
- `settings.json` MUST be merged, not copied — plain copy wipes Claude Code's plugin-management state and makes the freshly-installed plugin "disappear". The merge contract is documented in `bushin/commands/global-settings-setup.md`.
- The plugin's `.claude-global/settings.json` template intentionally **omits the `hooks` block** — the Stop hook is registered separately from `hooks/hooks.json` by Claude Code on install.
- Backups accumulate under `~/.claude/.bak/<UTC-timestamp>/`. Cleanup is on the user (a small cost; addressable by a future `/clean-backups` command if it ever becomes a problem).

## Reconsider when

- Claude Code adds first-class managed-globals support (e.g. `~/.claude/CLAUDE.md` becomes part of the plugin contract).
- The `settings.json` merge logic outgrows a single prompt-driven command (then extract a small `jq`-based script into `bushin/assets/scripts/`).
