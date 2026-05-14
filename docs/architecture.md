# Architecture

## Mental model

The repository is a **Claude Code marketplace** that ships **one plugin, `bushin`**, containing all agents, commands, skills, hooks, MCP integrations and assets a solo Kotlin/Spring Boot engineer needs.

```
┌──────────────────────────────────────────────────┐
│  claude/  (this repo = marketplace)              │
│  ──────────────────────────────────────────────  │
│  .claude-plugin/marketplace.json                 │
│  docs/                                           │
│  README.md                                       │
│                                                  │
│  bushin/  (the plugin)                           │
│    .claude-plugin/plugin.json                    │
│    .claude-global/  ← copied into ~/.claude/     │
│    agents/   commands/   skills/                 │
│    hooks/    mcp/                                │
│    assets/sounds/   ← referenced by hooks        │
└────────────────────┬─────────────────────────────┘
                     │
   /plugin marketplace add  /  install bushin
                     │
                     ▼
┌──────────────────────────────────────────────────┐
│  Claude Code runtime                             │
│  ──────────────────────────────────────────────  │
│  - reads agents/commands/skills/hooks from       │
│    the plugin directory directly                 │
│  - ${CLAUDE_PLUGIN_ROOT} env var points to it     │
│  - hooks can reference assets via that var       │
│                                                  │
│  Slash-commands in the plugin operate on:        │
│  /global-settings-setup, /global-settings-show   │
│        │                                         │
│        ▼  uses Read/Write/Bash/AskUserQuestion   │
│  ┌──────────────────────────────────────┐        │
│  │  ~/.claude/                          │        │
│  │  ──────────────────                  │        │
│  │  CLAUDE.md       ← copied from       │        │
│  │  settings.json     plugin's          │        │
│  │  .claudeignore     .claude-global/   │        │
│  │  .bak/<UTC>/     ← previous globals  │        │
│  └──────────────────────────────────────┘        │
└──────────────────────────────────────────────────┘
```

## Component contract

All plugin paths below are inside `bushin/`; `${CLAUDE_PLUGIN_ROOT}` resolves to that directory after `/plugin install`.

- **Marketplace manifest** (`.claude-plugin/marketplace.json`) — top-level descriptor listing the plugin(s) shipped from this repo. Source field is a relative path `./bushin` per Claude Code's plugin-marketplace schema. Single source for `/plugin marketplace add <repo>`.
- **Plugin manifest** (`bushin/.claude-plugin/plugin.json`) — name, version, description, author, keywords. Claude Code reads this on install.
- **Agent** (`bushin/agents/<name>.md`) — one file. Frontmatter: `name`, `description`, optional `model` (defaults to current session's), optional `tools` (defaults to all). Body: role, scope of decisions, output format.
- **Command** (`bushin/commands/<name>.md`) — one file. Triggered by `/<name>`. Body is a prompt for Claude — at runtime Claude executes it using its available tools.
- **Skill** (`bushin/skills/<name>/SKILL.md`) — one directory per skill, flat namespace with prefixed names (`kotlin`, `kotlin-coroutines`, …). Frontmatter: `name`, `description` (the trigger). Body kept under ~150 lines; heavy material lives in `skills/<name>/resources/*.md`, loaded by Claude on demand.
- **Hook** (`bushin/hooks/hooks.json`) — declarative event → command(s). Commands may reference assets via `${CLAUDE_PLUGIN_ROOT}`.
- **MCP fragment** (`bushin/mcp/<server>.json`) — opt-in MCP server configs. Phase 6.
- **Globals templates** (`bushin/.claude-global/`) — `CLAUDE.md`, `settings.json`, `.claudeignore`. The **only** directory whose contents get *copied* anywhere — into `~/.claude/` by `/global-settings-setup`.
- **Sound asset** (`bushin/assets/sounds/...`) — referenced by hooks via `${CLAUDE_PLUGIN_ROOT}/assets/sounds/...`. Not copied.

## Two paths into `~/.claude/`

Plugins do not touch `~/.claude/` directly. Two surfaces of the plugin do:

1. **Auto-loaded by Claude Code** — agents, commands, skills, hooks, MCP. The plugin's files stay in place; Claude Code reads them where they are.
2. **Copied by `/global-settings-setup`** — `CLAUDE.md`, `settings.json`, `.claudeignore`. Plugin ships templates; the command copies them with diff-prompting + backup, and for `settings.json` does a structured merge that preserves the user's plugin-management keys (`extraKnownMarketplaces`, `enabledPlugins`, `disabledPlugins`). Idempotent — re-run after `/plugin update` to pick up new template defaults.

## Per-project disable

Native Claude Code feature — no custom code required. To disable `bushin` in a specific project, use `/plugin disable bushin@reactivestudio` from inside that project, or add the equivalent key to `<project>/.claude/settings.json`. See `per-project-disable.md` for the exact key once verified.

## Token economy

The plugin is large (10–15 agents, 50–80 skills, ~12 commands). Always-in-prompt cost is paid by **descriptions only** (frontmatter). Bodies and `resources/` are progressively loaded. See `token-budget.md` for the budget and authoring rules to stay under it.

## What this architecture deliberately avoids

- **No symlinks.** Plugin content stays in the plugin directory; globals are copied.
- **No bash CLI.** All installation/maintenance is slash-commands interpreted by Claude.
- **No plugin split for granularity.** One plugin; per-project disable is binary and native.
- **No `rules/` directory.** Rules fold into `CLAUDE.md` (always-on) or into skill bodies (on-demand).
- **No nesting in `skills/`.** Flat namespace with prefixed names is the convention.
- **No automated tests on content.** Verification is `/context` token measurements plus manual sanity per phase.
