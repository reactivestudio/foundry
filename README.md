# foundry

Personal Claude Code marketplace shipping a single plugin `foundry` for a solo Kotlin / Spring Boot engineer. Installed natively via `/plugin install`; updated via `/plugin update`.

## Philosophy

- **Token efficiency without sacrificing quality.** Plugin ships 10–15 agents and 50–80 skills; the cost of "always on" descriptions is paid with strict per-item budgets (see `CLAUDE.md` at repo root for the budget table and authoring conventions). Bodies and resources load on demand only.
- **Each component knows its boundaries.** Architect doesn't write code. Reviewer doesn't make architectural decisions. Mechanical work is for Haiku; senior judgement is for Opus.
- **Adversarial thinking is built-in.** Non-trivial decisions pass through `/challenge` before they're accepted.
- **Plugin is project-scoped.** The plugin never touches `~/.claude/` — global Claude Code config stays user-managed. Plugin templates land in `<project>/.claude/` (which is `.gitignore`d), so per-project on/off and per-project tweaks are clean and local.

## Quick start

On a new machine:

```
> /plugin marketplace add <repo-url-or-local-path>
> /plugin install foundry@reactivestudio
```

Agents, commands, skills, hooks become available immediately on install. Nothing is copied to `~/.claude/` — your user-level config is untouched.

In each project where you want the plugin's settings/memory templates:

```
> /foundry:setup
```

This creates `<project>/.claude/CLAUDE.md` and `<project>/.claude/settings.json` from the plugin's templates and adds `.claude/` to `<project>/.gitignore`. Idempotent — re-run after `/plugin update` to pick up new template defaults.

## Per-project disable

The plugin is active in every project by default. To turn it off in a specific project (e.g. a Rust microservice where Kotlin/Spring agents are noise):

```
cd ~/work/some-non-kotlin-project
> /plugin disable foundry@reactivestudio
```

Claude Code writes the disable flag into the project's `.claude/settings.json` (exact key TBD — verify when first used). Re-enable with `/plugin enable foundry@reactivestudio`.

## What's inside

The marketplace and the plugin share this repository — both manifests live in `.claude-plugin/`, and the plugin content sits directly at the repo root. Claude Code's `${CLAUDE_PLUGIN_ROOT}` resolves to the repo root once installed.

- `.claude-plugin/marketplace.json` — marketplace catalog (this repo).
- `.claude-plugin/plugin.json` — plugin manifest.
- `CLAUDE.md` — project memory: token budget, naming conventions, frontmatter rules, pre-commit checklist. Auto-loaded by Claude Code when editing the plugin itself.
- `agents/` — agent definitions (architect, code-reviewer, security-reviewer, troubleshooter, specialists).
- `commands/` — meta-commands (`/challenge`, `/plan`, `/explain`, `/postmortem`, `/review`) and `setup`.
- `skills/` — skill directories, two-level nested namespace (`skills/<category>/<skill>/`).
- `hooks/hooks.json` — declarative event hooks (Stop event plays end-of-turn sound). Auto-loaded by Claude Code when plugin is active.
- `mcp/` — opt-in MCP server configs.
- `assets/sounds/` — binary assets used by hooks via `${CLAUDE_PLUGIN_ROOT}/assets/sounds/...`.
- `.claude-template/` — `CLAUDE.md` and `settings.json` source-of-truth templates, copied into `<project>/.claude/` by `/foundry:setup`. The **only** directory whose contents get *copied* anywhere; everything else stays in place and is read by Claude Code directly.

## Commands

### Project setup

| Command | Purpose |
|---|---|
| `/foundry:setup` | Seed `<project>/.claude/` with plugin templates (CLAUDE.md, settings.json), bootstrap optional `.spec/` 4-bucket workflow scaffold, optional MCP servers. Idempotent. Never touches `~/.claude/`. |

### `.spec/` change workflow (4 buckets + per-stage tracking)

A change moves through 4 directories — `backlog/` → `sprint/` → `done/` (or `→ declined/`). Each change has 5 stages (`analysis`, `architecture`, `decomposition`, `implementation`, `verification`), each with its own state (`pending | in-progress | need-approve | approved | pause | skipped`). Bucket is derived automatically from stages. Spec-commands are **state API only** — they don't generate content (agents do).

| Command | Purpose |
|---|---|
| `/backlog-add "<title>"` | Scaffold new change in backlog from title (auto-slug). |
| `/backlog-list` · `/sprint-list` · `/done-list` · `/declined-list` | List changes in each bucket. |
| `/sprint-add <name>` | Manual move backlog → sprint (usually auto on `implementation in-progress`). |
| `/accept <name>` | Manual move sprint → done (warns if stages not green). |
| `/decline <name> <reason>` | Terminal move ANY → declined with required reason. |
| `/track <name>` · `<name> <stage>` · `<name> <stage> <state>` | Unified tracker: 3 forms — summary, single-stage detail, setter (with auto-bucket-move). |

The `0.5.0` model is a breaking change from the openspec-style delta/canonical model used in `0.4.x`. Legacy `.spec/specs/` and `.spec/changes/archive/` are detected by `/setup` but not migrated automatically — copy what you need into the new structure manually (or, if low-stakes, just start fresh).

## Model routing

- **Haiku 4.5** — mechanical work (scaffolding, formatting, boilerplate) without a dedicated agent.
- **Sonnet 4.6** — default working horse: code, review, troubleshooting, specialists.
- **Opus 4.7** — architecture, hard trade-offs, `/challenge`, `/plan`.

Agents and commands override via `model:` in their frontmatter.

## Adding new components

See `CLAUDE.md` at the repo root — it's the project memory file Claude Code loads when editing the plugin. It defines naming conventions, frontmatter shapes, token budgets, body length limits, and the pre-commit checklist.
