# Repo memory — bushin marketplace + plugin

Project-scope rules for editing this repository. Auto-loaded by Claude Code when working inside `/Volumes/Work/www/VL/claude`.

The repo is a Claude Code marketplace shipping a single plugin `bushin`. Marketplace manifest at `.claude-plugin/marketplace.json`; plugin content under `bushin/`. `${CLAUDE_PLUGIN_ROOT}` resolves to `bushin/` once installed.

## Token budget

Final shape target: 10–15 agents, 50–80 skills, ~10 commands. Their `description` fields live in the system prompt **every turn**. Bodies and resources load only on activation.

Targets:
- Idle (plugin installed, nothing active): ≤ 2600 tokens
- Active (1 router + 2 siblings loaded): ≤ 6000 tokens
- Heavy (5 skills + 2 agents in conversation): ≤ 12 000 tokens

Per-item budget:

| Component | Budget |
|---|---|
| skill (router) description | ≤ 25 tokens (~110 chars) |
| skill (specific) description | ≤ 25 tokens (~100 chars) |
| agent description | ≤ 30 tokens (~120 chars) |
| command description | ≤ 25 tokens (~100 chars) |

Not in always-on prompt: `SKILL.md` bodies (loaded on activation), `skills/<name>/resources/*.md` (on demand from the body), command bodies (on invocation), hook scripts (runtime).

### Description rules

- Format: **what + when + when-NOT** in one sentence. The `NOT for X` clause is mandatory — it doubles trigger precision.
- ❌ `"Skill for working with Kotlin coroutines, providing best practices"` — noise.
- ✅ `"Kotlin coroutines: structured concurrency, dispatchers, exceptions, flows. NOT for RxJava/Reactor."`
- Router descriptions enumerate siblings: `"Kotlin idioms router → kotlin-idioms / kotlin-coroutines / kotlin-null-safety / …"`.
- Description is metadata for activation. Don't repeat what the body explains.

## Naming

Flat namespaces, kebab-case, domain prefixes:

```
bushin/skills/
├── methodology/                       # router
├── methodology-clarifying-questions/
├── kotlin/                            # router
├── kotlin-coroutines/
├── kotlin-null-safety/
├── …

bushin/agents/<name>.md                # flat
bushin/commands/<name>.md              # flat
```

Rules:
- Router = single domain word (`kotlin`, `spring`, `ddd`, `clean-code`, `testing`, `architecture`, `methodology`).
- Specific skill = `<router>-<concern>` (`kotlin-coroutines`).
- One skill = one directory = one `SKILL.md` (+ optional `resources/`).

## Frontmatter

Router skill:
```yaml
---
name: kotlin
description: "Kotlin idioms router → kotlin-idioms / kotlin-coroutines / kotlin-null-safety / …"
---
```

Specific skill:
```yaml
---
name: kotlin-coroutines
description: "Kotlin coroutines: structured concurrency, dispatchers, exceptions, flows. NOT for RxJava/Reactor."
---
```

Agent:
```yaml
---
name: architect
description: "Design new systems/features/subsystems upfront: patterns, contexts, data stores, contracts. NOT for small in-module changes."
model: opus
---
```

`tools:` only when restricting (e.g. read-only reviewer). Omit otherwise — agents inherit all tools.

`model:` accepts `opus`/`sonnet`/`haiku` or full IDs (`claude-opus-4-7`, `claude-sonnet-4-6`, `claude-haiku-4-5`). Default session model wins if omitted.

Command:
```yaml
---
name: review
description: "Pre-commit review of staged changes against checklist (correctness, scope, naming, tests, security)."
---
```

`model:` may be set on commands that need a specific model (e.g. `/challenge` → opus).

## Body conventions

### Skill `SKILL.md` — ≤ 150 lines

Headings: `# <name>` → `## When to use` → `## Procedure` (or `## Routing` for a router) → `## When NOT to use` → `## Resources` (optional).

If body grows past 150 lines, split into `resources/<concern>.md` and route from the body. This shifts cost from "loaded on activation" to "loaded on demand".

A router's `SKILL.md` body is itself a router: a small table mapping concerns to sibling skill names.

### Agent body — ≤ ~800 tokens

- `## Role` — one paragraph.
- `## Scope of decisions` — what this agent decides; what it does NOT decide.
- `## Procedure` — numbered steps.
- `## Output format` — exactly what the agent returns.

### Command body — self-contained prompt

- Treat it as instructions to a fresh Claude session.
- Use **AskUserQuestion** for branching; never ad-hoc text questions.
- Use **Read/Write/Bash** for file ops; no external scripts.
- Describe the **summary output** at the end.

## Hooks

`bushin/hooks/hooks.json` — single file, all events keyed inside an outer `hooks` wrapper:
```json
{
  "hooks": {
    "<Event>": [
      { "matcher": "", "hooks": [ { "type": "command", "command": "<shell>" } ] }
    ]
  }
}
```

Asset references use `${CLAUDE_PLUGIN_ROOT}` (NOT `CLAUDE_PLUGIN_DIR` — that's a common mistake, the variable doesn't exist):
```
afplay "${CLAUDE_PLUGIN_ROOT}/assets/sounds/stop.m4r" >/dev/null 2>&1 &
```

Trailing `&` so the hook doesn't block the next turn; `>/dev/null 2>&1` to suppress noise.

## MCP

One file per server in `bushin/mcp/<server>.json`. Each MCP server burns tokens for its tool schemas — measure cost when adding.

## Pre-commit checklist

Before committing a new agent / skill / command:

- [ ] Description ≤ budgeted chars; includes a `NOT for X` clause.
- [ ] Body ≤ 150 lines (skills) or ≤ ~800 tokens (commands).
- [ ] Naming follows the prefix convention.
- [ ] No `tools:` on agents unless intentionally restricting.
- [ ] `model:` set only if the role demands `opus` or `haiku` specifically.
- [ ] `/context` measurement still within token budget targets.

## How to measure

`/context` in a fresh session shows the "System prompt" line. Delta against an empty install = plugin's idle cost. Re-measure after each authoring phase.
