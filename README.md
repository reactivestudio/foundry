# bushin

Personal Claude Code marketplace shipping a single plugin `bushin` for a solo Kotlin / Spring Boot engineer. Installed natively via `/plugin install`; updated via `/plugin update`.

## Philosophy

- **Token efficiency without sacrificing quality.** Plugin ships 10–15 agents and 50–80 skills; the cost of "always on" descriptions is paid with strict per-item budgets (see `CLAUDE.md` at repo root for the budget table and authoring conventions). Bodies and resources load on demand only.
- **Each component knows its boundaries.** Architect doesn't write code. Reviewer doesn't make architectural decisions. Mechanical work is for Haiku; senior judgement is for Opus.
- **Adversarial thinking is built-in.** Non-trivial decisions pass through `/challenge` before they're accepted.
- **One plugin, native toggle.** Per-project disable is a native Claude Code feature — no custom mechanism needed.

## Quick start

On a new machine:

```
> /plugin marketplace add <repo-url-or-local-path>
> /plugin install bushin@reactivestudio
> /global-settings-setup
```

That's it. Agents, commands, skills, hooks become available immediately on install. `/global-settings-setup` reconciles `CLAUDE.md`, `settings.json` and `.claudeignore` from the plugin's `.claude-global/` into `~/.claude/` with diff-prompt + backup (and a structured merge for `settings.json` so plugin-management keys are preserved).

Updates:

```
> /plugin update                # refresh plugin content
> /global-settings-setup        # re-run after update; idempotent on unchanged files
```

## Per-project disable

The plugin is active in every project by default. To turn it off in a specific project (e.g. a Rust microservice where Kotlin/Spring agents are noise):

```
cd ~/work/some-non-kotlin-project
> /plugin disable bushin@reactivestudio
```

Claude Code writes the disable flag into the project's `.claude/settings.json` (exact key TBD — verify when the disable is first used). Re-enable with `/plugin enable bushin@reactivestudio`. In all other projects the plugin keeps working unchanged.

## What's inside

- `.claude-plugin/marketplace.json` — marketplace catalog (this repo).
- `CLAUDE.md` — project memory: token budget, naming conventions, frontmatter rules, pre-commit checklist. Auto-loaded by Claude Code when editing the plugin.
- `bushin/` — the plugin itself (Claude Code's `${CLAUDE_PLUGIN_ROOT}` resolves here once installed):
  - `.claude-plugin/plugin.json` — plugin manifest.
  - `agents/` — agent definitions (architect, code-reviewer, security-reviewer, troubleshooter, specialists).
  - `commands/` — meta-commands (`/challenge`, `/plan`, `/explain`, `/postmortem`, `/review`) and tuning commands (`/global-settings-setup`, `/global-settings-show`).
  - `skills/` — skill directories, flat namespace, prefixed names (`kotlin`, `kotlin-coroutines`, `spring`, `spring-aop`, …). Top-level router skills point to siblings.
  - `hooks/hooks.json` — declarative event hooks (Stop event plays end-of-turn sound).
  - `mcp/` — opt-in MCP server configs.
  - `assets/sounds/` — binary assets used by hooks via `${CLAUDE_PLUGIN_ROOT}/assets/sounds/...`.
  - `.claude-global/` — `CLAUDE.md`, `settings.json`, `.claudeignore` source-of-truth templates. The **only** directory whose contents get *copied* anywhere — `/global-settings-setup` copies them into `~/.claude/`. Everything else lives in place inside the plugin; Claude Code reads it directly.

## Tuning toolkit

| Command | Purpose |
|---|---|
| `/global-settings-setup` | Copy plugin globals into `~/.claude/` with diff-prompt and backup. `settings.json` takes a structured merge (existing keys win, so `extraKnownMarketplaces` and `enabledPlugins` survive). Idempotent. |
| `/global-settings-show` | Read-only diagnostic: identical / drifted / missing. |

## Model routing

- **Haiku 4.5** — mechanical work (scaffolding, formatting, boilerplate) without a dedicated agent.
- **Sonnet 4.6** — default working horse: code, review, troubleshooting, specialists.
- **Opus 4.7** — architecture, hard trade-offs, `/challenge`, `/plan`.

The session default is set in `bushin/.claude-global/settings.json` (`claude-sonnet-4-6`). Agents and commands override via `model:` in their frontmatter.

## Adding new components

See `CLAUDE.md` at the repo root — it's the project memory file Claude Code loads when editing the plugin. It defines naming conventions, frontmatter shapes, token budgets, body length limits, and the pre-commit checklist.
