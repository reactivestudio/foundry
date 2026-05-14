# ADR 0003 — `/setup-global-settings` (in-plugin slash-commands) for managing `~/.claude/` globals

- **Status:** Accepted
- **Date:** 2026-05-14
- **Deciders:** repo owner (solo)

## Context

Claude Code's plugin system natively auto-loads `agents/`, `commands/`, `skills/`, `hooks/` and `mcp/` straight from a plugin's directory. It does **not** manage user-level globals: `~/.claude/CLAUDE.md` (user memory), `~/.claude/settings.json` (model, permissions, env, user-level hooks), and `~/.claude/.claudeignore`. These have to be present in `~/.claude/` for Claude Code to read them on every session.

We need a way for the plugin to ship templates for these files and reconcile them with whatever is already in `~/.claude/`, on initial install and after `/plugin update`.

Options considered:

1. **In-plugin slash-commands** that copy from `.claude-global/` into `~/.claude/` with diff-prompt and backup. Driven by Claude using Read/Write/Bash/AskUserQuestion at runtime.
2. **External bash script** the user runs after `/plugin install`. Re-introduces the CLI surface ADR 0001 eliminated.
3. **`postinstall` hook in `plugin.json`** that copies files automatically. Risk: silent overwrites of user-modified globals; no diff-prompt UX; not sure if Claude Code supports this hook universally.
4. **Symlinks from plugin's `.claude-global/` to `~/.claude/`**. Re-introduces every symlink downside ADR 0001 rejected.
5. **Manual copy** from the README. Drifts immediately.

## Decision

Use **in-plugin slash-commands**: `/setup-global-settings`, `/sync-globals`, `/show-globals`, `/configure`.

- `/setup-global-settings` — initial copy from `.claude-global/*` into `~/.claude/`. Idempotent.
- `/sync-globals` — same procedure; separate name to make intent clear after `/plugin update`.
- `/show-globals` — read-only diagnostic of identical / drifted / missing.
- `/configure` — interactive editor for `~/.claude/settings.json` (model, permissions, env, hooks).

All four are markdown files in `commands/`. Body is a prompt for Claude; the runtime execution uses Read/Write/Bash/AskUserQuestion. No external code on our side.

## Rationale

| Factor | In-plugin commands (chosen) | External bash script | postinstall hook | Symlinks |
|---|---|---|---|---|
| Maintenance code | nil (just prompts) | bash script to maintain | depends on Claude Code support | nil but fragile |
| Idempotent re-run | yes, by design | yes if written carefully | unclear semantics | yes (same inode) |
| Diff-prompt UX before overwrite | yes (AskUserQuestion) | possible | typically no | n/a (silent overwrite via inode change) |
| Backup of pre-existing files | yes (`~/.claude/.bak/<UTC>/`) | possible | typically no | none |
| Honours user-level edits | yes (drift detection, prompt) | depends | typically no | no (would lose edits) |
| Works without leaving Claude Code | yes | no (terminal context switch) | yes (silent) | n/a |

## Consequences

- The four tuning commands are the canonical surface for `~/.claude/` management; the README and `docs/architecture.md` document them.
- The plugin's `.claude-global/settings.json` template intentionally **omits the `hooks` block** — the Stop hook is registered separately from `hooks/stop.json` by Claude Code on install. This keeps a clean separation: hook lives with the plugin, not with user-level globals.
- A user who manually edits `~/.claude/CLAUDE.md` or `~/.claude/settings.json` will be prompted on the next `/sync-globals` — diff shown, choice {overwrite-with-backup / keep / view-full-diff}. Their work is never silently lost.
- Backups accumulate under `~/.claude/.bak/<UTC-timestamp>/`. Cleanup is on the user (a small cost; addressable by a future `/clean-backups` command if it ever becomes a problem).

## Reconsider when

- Claude Code adds first-class managed-globals support (e.g. `~/.claude/CLAUDE.md` becomes part of the plugin contract).
- The four commands become too thin and could be consolidated (e.g. `/setup-global-settings` and `/sync-globals` merging into one named verb).
