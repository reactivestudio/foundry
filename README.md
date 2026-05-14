# bushin-skills

Personal Claude Code marketplace shipping a single plugin `bushin-skills` for a solo Kotlin / Spring Boot engineer. Installed natively via `/plugin install`; updated via `/plugin update`.

## Philosophy

- **Token efficiency without sacrificing quality.** Plugin ships 10–15 agents and 50–80 skills; the cost of "always on" descriptions is paid with strict per-item budgets (see [docs/token-budget.md](docs/token-budget.md)). Bodies and resources load on demand only.
- **Each component knows its boundaries.** Architect doesn't write code. Reviewer doesn't make architectural decisions. Mechanical work is for Haiku; senior judgement is for Opus.
- **Adversarial thinking is built-in.** Non-trivial decisions pass through `/challenge` before they're accepted.
- **One plugin, native toggle.** Per-project disable is a native Claude Code feature — no custom mechanism needed.

## Quick start

On a new machine:

```
> /plugin marketplace add <repo-url-or-local-path>
> /plugin install bushin-skills@reactivestudio
> /setup-global-settings
```

That's it. Agents, commands, skills, hooks become available immediately on install. `/setup-global-settings` copies `CLAUDE.md`, `settings.json` and `.claudeignore` into `~/.claude/` with a diff-prompt and backup.

Updates:

```
> /plugin update          # refresh plugin content (agents/skills/commands/hooks/assets)
> /sync-globals           # bring ~/.claude/ in line with refreshed plugin templates
```

Per-project disable: use Claude Code's native `/plugin disable bushin-skills@reactivestudio` from inside the project, or edit `<project>/.claude/settings.json`. See [docs/per-project-disable.md](docs/per-project-disable.md).

## What's inside

- `.claude-plugin/marketplace.json` — marketplace catalog at the repo root.
- `bushin-skills/` — the plugin itself (Claude Code's `${CLAUDE_PLUGIN_ROOT}` resolves here once installed):
  - `.claude-plugin/plugin.json` — plugin manifest.
  - `agents/` — 10–15 agent definitions (architect, code-reviewer, security-reviewer, troubleshooter, specialists).
  - `commands/` — meta-commands (`/challenge`, `/plan`, `/explain`, `/postmortem`, `/review`) and tuning commands (`/setup-global-settings`, `/sync-globals`, `/show-globals`, `/configure`).
  - `skills/` — 50–80 skill directories, flat namespace, prefixed names (`kotlin`, `kotlin-coroutines`, `spring`, `spring-aop`, …). Top-level router skills point to siblings.
  - `hooks/` — declarative event hooks (e.g. `stop.json` for end-of-turn sound).
  - `mcp/` — opt-in MCP server configs.
  - `assets/sounds/` — binary assets used by hooks via `${CLAUDE_PLUGIN_ROOT}/assets/sounds/...`
  - `.claude-global/` — `CLAUDE.md`, `settings.json`, `.claudeignore` source-of-truth templates, copied into `~/.claude/` by `/setup-global-settings` and `/sync-globals`. The only directory whose contents are *copied* anywhere.
- `docs/` — architecture, token budget, authoring conventions, per-project disable, ADRs (marketplace-level documentation, lives at repo root).

## Tuning toolkit

| Command | Purpose |
|---|---|
| `/setup-global-settings` | Initial copy of plugin globals into `~/.claude/`. Idempotent. |
| `/sync-globals` | Re-sync after `/plugin update`. |
| `/show-globals` | Read-only diagnostic: identical / drifted / missing. |
| `/configure` | Interactive editor for `~/.claude/settings.json`: model, permissions, env, hooks. |

## Model routing

- **Haiku 4.5** — mechanical work (scaffolding, formatting, boilerplate) without a dedicated agent.
- **Sonnet 4.6** — default working horse: code, review, troubleshooting, specialists.
- **Opus 4.7** — architecture, hard trade-offs, `/challenge`, `/plan`.

The session default is set in `.claude-global/settings.json` (`claude-sonnet-4-6`). Agents and commands override via `model:` in their frontmatter.

## Adding new components

See [docs/authoring.md](docs/authoring.md). One agent = one file. One skill = one `SKILL.md` under ~150 lines plus optional `resources/`. Description budgets per [docs/token-budget.md](docs/token-budget.md).

## Why not a CLI installer / symlinks / multiple plugins?

See [docs/adr/0001-marketplace-over-cli.md](docs/adr/0001-marketplace-over-cli.md) and [docs/adr/0002-single-plugin-over-split.md](docs/adr/0002-single-plugin-over-split.md).
