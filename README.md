# bushin

Personal Claude Code marketplace shipping a single plugin `bushin` for a solo Kotlin / Spring Boot engineer. Installed natively via `/plugin install`; updated via `/plugin update`.

## Philosophy

- **Token efficiency without sacrificing quality.** Plugin ships 10–15 agents and 50–80 skills; the cost of "always on" descriptions is paid with strict per-item budgets (see `CLAUDE.md` at repo root for the budget table and authoring conventions). Bodies and resources load on demand only.
- **Each component knows its boundaries.** Architect doesn't write code. Reviewer doesn't make architectural decisions. Mechanical work is for Haiku; senior judgement is for Opus.
- **Adversarial thinking is built-in.** Non-trivial decisions pass through `/challenge` before they're accepted.
- **Plugin is project-scoped.** The plugin never touches `~/.claude/` — global Claude Code config stays user-managed. Plugin templates land in `<project>/.claude/` (which is `.gitignore`d), so per-project on/off and per-project tweaks are clean and local.

## Quick start

On a new machine:

```
> /plugin marketplace add <repo-url-or-local-path>
> /plugin install bushin@reactivestudio
```

Agents, commands, skills, hooks become available immediately on install. Nothing is copied to `~/.claude/` — your user-level config is untouched.

In each project where you want the plugin's settings/memory templates:

```
> /bushin:setup
```

This creates `<project>/.claude/CLAUDE.md` and `<project>/.claude/settings.json` from the plugin's templates and adds `.claude/` to `<project>/.gitignore`. Idempotent — re-run after `/plugin update` to pick up new template defaults.

## Per-project disable

The plugin is active in every project by default. To turn it off in a specific project (e.g. a Rust microservice where Kotlin/Spring agents are noise):

```
cd ~/work/some-non-kotlin-project
> /plugin disable bushin@reactivestudio
```

Claude Code writes the disable flag into the project's `.claude/settings.json` (exact key TBD — verify when first used). Re-enable with `/plugin enable bushin@reactivestudio`.

## What's inside

- `.claude-plugin/marketplace.json` — marketplace catalog (this repo).
- `CLAUDE.md` — project memory: token budget, naming conventions, frontmatter rules, pre-commit checklist. Auto-loaded by Claude Code when editing the plugin itself.
- `bushin/` — the plugin (Claude Code's `${CLAUDE_PLUGIN_ROOT}` resolves here once installed):
  - `.claude-plugin/plugin.json` — plugin manifest.
  - `agents/` — agent definitions (architect, code-reviewer, security-reviewer, troubleshooter, specialists).
  - `commands/` — meta-commands (`/challenge`, `/plan`, `/explain`, `/postmortem`, `/review`) and `setup`.
  - `skills/` — skill directories, flat namespace, prefixed names (`kotlin`, `kotlin-coroutines`, `spring`, `spring-aop`, …). Top-level router skills point to siblings.
  - `hooks/hooks.json` — declarative event hooks (Stop event plays end-of-turn sound). Auto-loaded by Claude Code when plugin is active.
  - `mcp/` — opt-in MCP server configs.
  - `assets/sounds/` — binary assets used by hooks via `${CLAUDE_PLUGIN_ROOT}/assets/sounds/...`.
  - `.claude-template/` — `CLAUDE.md` and `settings.json` source-of-truth templates, copied into `<project>/.claude/` by `/bushin:setup`. The **only** directory whose contents get *copied* anywhere; everything else stays in place and is read by Claude Code directly.

## Commands

| Command | Purpose |
|---|---|
| `/bushin:setup` | Seed `<project>/.claude/` with plugin templates (CLAUDE.md, settings.json) and gitignore the dir. Idempotent. Never touches `~/.claude/`. |

## Model routing

- **Haiku 4.5** — mechanical work (scaffolding, formatting, boilerplate) without a dedicated agent.
- **Sonnet 4.6** — default working horse: code, review, troubleshooting, specialists.
- **Opus 4.7** — architecture, hard trade-offs, `/challenge`, `/plan`.

Agents and commands override via `model:` in their frontmatter.

## Adding new components

See `CLAUDE.md` at the repo root — it's the project memory file Claude Code loads when editing the plugin. It defines naming conventions, frontmatter shapes, token budgets, body length limits, and the pre-commit checklist.
