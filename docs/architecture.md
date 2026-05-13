# Architecture

## Mental model

The repository is a **library of atomic components** plus **two CLI entrypoints** that materialise selected components into the right Claude Code directories on the host machine via **relative symlinks**.

```
┌──────────────────────────────────────────┐         ┌────────────────────────┐
│  claude/  (this repo, cloned once)       │         │  ~/.claude/            │
│  ───────────────────────────────         │         │  ──────────────────    │
│  global/CLAUDE.md                  ──────┼─symlink─┤  CLAUDE.md             │
│  global/settings.json              ──────┼─symlink─┤  settings.json         │
│  components/agents/architect.md    ──────┼─symlink─┤  agents/architect.md   │
│  components/commands/global/*.md   ──────┼─symlink─┤  commands/*.md         │
│                                          │         └────────────────────────┘
│                                          │
│                                          │         ┌────────────────────────┐
│                                          │         │  <project>/.claude/    │
│                                          │         │  ──────────────────    │
│  components/agents/*-specialist.md ──────┼─symlink─┤  agents/*.md           │
│  components/commands/project/*.md  ──────┼─symlink─┤  commands/*.md         │
│  components/rules/*.md             ──────┼─symlink─┤  rules/*.md            │
│  components/mcp/*.json             ──────┼─gen────►│  .mcp.json (merged)    │
└──────────────────────────────────────────┘         └────────────────────────┘
        ▲                                                       ▲
        │                                                       │
   claude-global                                            claude-init
   (one-shot global install)                          (interactive per-project wizard)
```

## Boundaries

**Global vs project.**
- *Global* artefacts apply to every project: personal preferences, response style, baseline model routing, universal senior agents (architect, code-reviewer, security-reviewer, troubleshooter), meta-commands (`/challenge`, `/plan`, `/explain`, `/postmortem`).
- *Project* artefacts depend on the stack: Kotlin idioms, Spring conventions, DDD boundaries, specialist agents (`spring-boot-specialist`, `ddd-modeler`), project scaffolding commands, MCP servers wired to project resources.

A component is authored for exactly one scope. The CLI scripts know where each component goes — there is no scope ambiguity.

**Symlinkable vs mergeable.**
- *Symlinkable* — self-contained files with unique names: agents, commands, rules, skills, the global `CLAUDE.md` and `claudeignore`. They are created as relative symlinks pointing into this repo. `git pull` propagates updates instantly.
- *Mergeable* — files that several components contribute to: `.mcp.json`, `settings.json`. These cannot be symlinked because multiple sources collide. The wizard generates them from selected JSON fragments via `jq`.

## Component contract

- **Agent** — one `.md` file in `components/agents/`. Frontmatter declares `name`, `description`, `model`, optional `tools`. Body defines the role, scope of decisions it can make, and the format of its output. No agent crosses into another agent's territory.
- **Command** — one `.md` file in `components/commands/{global,project}/`. Defines a reusable workflow triggered by `/<name>`. Frontmatter may pin a model.
- **Rule** — one `.md` file in `components/rules/`. A focused set of constraints around a single concern (Kotlin idioms, Spring conventions, etc.). Linked into the project's `.claude/rules/` and referenced from the project `CLAUDE.md`.
- **Skill** — one `.md` file under 200 lines in `components/skills/<domain>/`. Description must contain a precise trigger so Claude knows when to invoke it. Heavy theory belongs in `docs/`, not in skill files.
- **MCP server** — one `.json` fragment in `components/mcp/`. The wizard merges selected fragments into the project's `.mcp.json`.

## Update flow

1. Component author commits to this repo.
2. Each linked project picks up the update on the next `git pull` here, since `.claude/<component>.md → <repo>/components/.../<component>.md` resolves through the symlink.
3. No re-running of `claude-init` is required for content updates. Re-run is only needed to *change the selection* of components.

## What this architecture deliberately avoids

- **No profile manifests.** The wizard asks questions; there are no YAML profiles to maintain.
- **No composability syntax (`--profile a --profile b`).** Adds complexity without solo-user benefit.
- **No lock files for reversibility.** Re-running the wizard regenerates `.claude/` from current answers.
- **No marketplace plugin metadata.** All components are plain files; discovery is by directory listing.
- **No multi-stack support in v1.** Kotlin / Spring Boot only. Adding Python / JS later is mechanical: new rules and specialists, no architectural changes.
