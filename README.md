# claude

Personal Claude Code configuration library for a solo Kotlin / Spring Boot engineer.

Clone once, attach to any project via an interactive CLI wizard. Updates propagate to every linked project on `git pull`.

## Philosophy

- **Token efficiency without sacrificing quality.** The main lever is *precise context* — Claude reads exactly the files needed, not more.
- **Each component knows its boundaries.** Architect doesn't write code. Reviewer doesn't make architectural decisions. Mechanical work is for Haiku; senior judgement is for Opus.
- **Adversarial thinking is built-in.** Non-trivial decisions pass through `/challenge` before they're accepted.
- **Composable, not monolithic.** Agents, slash-commands, rules, skills and MCP fragments are independent. The wizard picks what fits the current project.

## Quick start

```bash
# 1) Clone (anywhere; ~/code/claude is fine)
git clone <repo-url> ~/code/claude

# 2) Install global preferences and senior agents into ~/.claude/
~/code/claude/bin/claude-global

# 3) In each project, run the wizard to pick stack-specific components
cd ~/work/some-spring-project
~/code/claude/bin/claude-init
```

Re-run either command at any time; both are idempotent and ask before overwriting.

## What's inside

- `bin/` — `claude-init` (project wizard) and `claude-global` (one-shot global install).
- `components/` — atomic, reusable pieces: agents, commands, rules, skills, MCP servers.
- `global/` — templates symlinked into `~/.claude/` (CLAUDE.md, settings.json with model routing, .claudeignore).
- `docs/` — architecture, wizard flow, authoring guides, ADRs.
- `templates/` — boilerplate for new agents/commands/rules.

## Model routing

- **Haiku 4.5** — mechanical work (scaffolding, formatting, boilerplate) without a dedicated agent.
- **Sonnet 4.6** — default working horse: code, review, troubleshooting, specialists.
- **Opus 4.7** — architecture, hard trade-offs, `/challenge`, `/plan`.

Routing lives in `global/settings.json` (default) and is overridden per-agent via `model:` frontmatter and per-command in the command file. See [docs/model-routing.md](docs/model-routing.md).

## Adding new components

See `templates/` and `docs/authoring-*.md`. One agent = one file. One skill = one file under 200 lines. No deep folder hierarchies inside a single component.

## Why not a marketplace / plugins / profiles?

See [docs/adr/0001-symlink-over-marketplace.md](docs/adr/0001-symlink-over-marketplace.md) and [docs/adr/0002-wizard-over-profiles.md](docs/adr/0002-wizard-over-profiles.md).
