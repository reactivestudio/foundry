# Authoring Conventions

Rules for adding agents, commands, skills, hooks and MCP fragments to this plugin. Keep these strict — they enforce the token budget defined in [token-budget.md](token-budget.md) and the architecture in [architecture.md](architecture.md).

## Naming

### Skills — flat namespace with prefixes

All skills live directly under `skills/`. No nesting. Use domain prefixes for organisation:

```
skills/
├── methodology/                    # router for methodology-*
├── methodology-clarifying-questions/
├── methodology-verification/
├── methodology-debugging/
├── kotlin/                          # router for kotlin-*
├── kotlin-idioms/
├── kotlin-coroutines/
├── kotlin-null-safety/
├── …
```

Rules:
- Router name = single domain word (`kotlin`).
- Specific skill name = `<router>-<concern>` (`kotlin-coroutines`). Kebab-case only.
- One skill = one directory = one `SKILL.md` file (+ optional `resources/`).

### Agents and commands — flat in their own directory

```
agents/<name>.md
commands/<name>.md
```

Kebab-case. One concern per file.

## Frontmatter

### Skill (router)
```yaml
---
name: kotlin
description: "Kotlin idioms router → kotlin-idioms / kotlin-coroutines / kotlin-null-safety / kotlin-generics / kotlin-dsl / kotlin-scope-functions."
---
```

### Skill (specific)
```yaml
---
name: kotlin-coroutines
description: "Kotlin coroutines: structured concurrency, dispatchers, exceptions, flows. NOT for RxJava/Reactor."
---
```

### Agent
```yaml
---
name: architect
description: "Design new systems/features/subsystems upfront: patterns, contexts, data stores, contracts. NOT for small in-module changes."
model: opus
---
```

`tools:` only when restricting. Omit otherwise.

`model:` accepted values: `opus`, `sonnet`, `haiku`, or full IDs (`claude-opus-4-7`, `claude-sonnet-4-6`, `claude-haiku-4-5`). Default session model wins if not set.

### Command
```yaml
---
name: review
description: "Pre-commit review of staged changes against checklist (correctness, scope, naming, tests, security)."
---
```

`model:` may be set for commands that need a specific model (e.g. `/challenge` → opus).

## Description budget

| Component | Char target | Token target |
|---|---|---|
| skill (router) | ≤ 110 | ≤ 25 |
| skill (specific) | ≤ 100 | ≤ 25 |
| agent | ≤ 120 | ≤ 30 |
| command | ≤ 100 | ≤ 25 |

Always end with "NOT for X" where it sharpens the trigger. The "NOT" clause prevents incorrect activation on adjacent topics.

## Body conventions

### Skill body (`SKILL.md`)

- Length ≤ ~150 lines.
- Heading hierarchy: `# <name>` → `## When to use` → `## Procedure` (or `## Routing` for a router) → `## When NOT to use` → `## Resources` (optional).
- If you have more than 150 lines, the body is *too thick* — split into `resources/<concern>.md` and route from the body.

### Agent body (`<name>.md`)

- `## Role` — one paragraph.
- `## Scope of decisions` — bulleted: what this agent decides; what it does NOT decide.
- `## Procedure` — numbered steps.
- `## Output format` — exactly what the agent returns.

### Command body (`<name>.md`)

- Single, self-contained prompt for Claude. Treat it as instructions to a fresh agent.
- Use **AskUserQuestion** for any branching choices; never ad-hoc text questions in the body.
- Use **Read/Write/Bash** for file operations; do not call out to external scripts.
- Always describe the **summary output** at the end of the command.

## Hooks

`hooks/<event>.json`:
```json
{
  "<event>": [
    { "matcher": "", "hooks": [ { "type": "command", "command": "<shell>" } ] }
  ]
}
```

Asset references use `${CLAUDE_PLUGIN_DIR}`:
```
afplay "${CLAUDE_PLUGIN_DIR}/assets/sounds/stop.m4r" >/dev/null 2>&1 &
```

Trailing `&` so the hook doesn't block the next turn; `>/dev/null 2>&1` to suppress stdout/stderr noise.

## MCP

One file per MCP server in `mcp/<server>.json`. Each MCP server burns tokens for its tool schemas — measure cost when adding one and record it in [token-budget.md](token-budget.md).

## Routers

Every domain (`methodology`, `kotlin`, `spring`, `ddd`, `clean-code`, `testing`, `architecture`) has a router skill. Its purpose:

1. **Discovery**: when Claude reads the skill list, it sees the broad domain and knows that specific concerns exist as siblings.
2. **Light token cost**: a router description is the cheapest item in the prompt — just an enumeration of siblings.
3. **Easy mental model**: open `skills/kotlin/SKILL.md` to see the map of all `kotlin-*` skills.

A router's `SKILL.md` body is itself a router: a small table mapping concerns to sibling skill names, plus pointers to `resources/` if needed.

## Pre-commit checklist (for the author)

Before committing a new agent/skill/command:

- [ ] Description ≤ budgeted chars; includes "NOT" clause.
- [ ] Body ≤ 150 lines (for skills) or ≤ ~800 tokens (for commands).
- [ ] Naming follows the prefix convention.
- [ ] No `tools:` on agents unless restricting.
- [ ] `model:` set if the role demands opus or haiku specifically.
- [ ] `/context` measurement matches the budget in [token-budget.md](token-budget.md).
