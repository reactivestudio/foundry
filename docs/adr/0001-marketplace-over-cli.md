# ADR 0001 — Native marketplace over custom bash CLI

- **Status:** Accepted
- **Date:** 2026-05-14
- **Supersedes:** previous 0001 (symlink-over-marketplace) and previous 0002 (wizard-over-profiles), both removed
- **Deciders:** repo owner (solo)

## Context

Three approaches were tried before settling on the current model:

1. **Custom bash CLI (`bin/claude-global`) + relative symlinks from this repo into `~/.claude/` and `<project>/.claude/`.** Worked, but introduced fragility (broken symlinks if repo moves), indirection during debugging, and risk of accidental writes back into the versioned repo from a quick `~/.claude/` edit.

2. **Interactive wizard (`claude-init`) + symlinks.** Same symlink downsides plus an extra layer of bash code to maintain.

3. **Manual copy with documented instructions.** Drifts immediately, no idempotency, no native mechanism for `/plugin update`-style refresh.

## Decision

Use **Claude Code's native marketplace + plugin system**. The repository *is* a marketplace; the root *is* the single plugin `bushin`. Installation and updates are done via `/plugin marketplace add`, `/plugin install`, and `/plugin update`. User-level globals (`CLAUDE.md`, `settings.json`, `.claudeignore`) — which the plugin system does not manage directly — are handled by an in-plugin slash-command `/setup-global-settings` (see ADR 0003).

## Rationale

| Factor | Bash CLI + symlinks | Manual copy | Native marketplace (chosen) |
|---|---|---|---|
| First-run UX on a new machine | `git clone` + `bin/claude-global` + `bin/claude-init` | clone + manual file copies | `/plugin marketplace add` + `/plugin install` + `/setup-global-settings` |
| Auto-discovery of agents/commands/skills/hooks | symlink each into `~/.claude/...` | copy each | **built in** — Claude Code reads plugin directory directly |
| Update flow | `git pull` (instant via symlinks) | re-copy manually | `/plugin update` |
| Sharability | clone the repo + run scripts | manually copy | `/plugin marketplace add <repo-url>` works for anyone |
| Maintenance code in repo | ~400 lines bash | nil | nil |
| Indirection / debugging | symlinks add a layer | none | none |
| Risk of accidental writes back into repo | high (edit `~/.claude/settings.json` → actually edits repo file) | none (copies are independent) | none (plugin files stay in repo; `~/.claude/` is independent) |
| Per-project disable | not native; would require custom flag | not native | **built in** (`/plugin disable …@…` per project) |

The native mechanism removes every custom moving part: no CLI, no symlinks, no shell scripts. Maintenance shrinks to authoring `.md` and `.json` files. Distribution is solved automatically.

## Consequences

- The repository's root directory layout is fixed by Claude Code conventions (`.claude-plugin/`, `agents/`, `commands/`, `skills/`, `hooks/`, `mcp/`, `assets/`).
- User-level globals (`~/.claude/CLAUDE.md`, `~/.claude/settings.json`, `~/.claude/.claudeignore`) are **not** auto-managed by plugin install. They are handled by the plugin's own `/setup-global-settings` and `/sync-globals` slash-commands, which copy from `.claude-global/` into `~/.claude/` with diff-prompt + backup.
- Lock-in to Claude Code's plugin schema. If the schema changes incompatibly, manifests must be migrated. This is a small surface (two JSON files).

## Reconsider when

- Claude Code drops or significantly changes plugin support.
- The plugin needs to be distributed to non-Claude-Code consumers.
- Multiple parallel "flavours" need to coexist on one machine without rebuilding the plugin (a problem the current setup does not have).
