# Token Budget

The plugin ships at scale: 10–15 agents, 50–80 skills, ~12 commands. Their `description` fields live in Claude's system prompt **on every turn**. Bodies and resources are loaded only when needed. This document defines the budget and the authoring rules that keep us under it.

## Targets

| Metric | Target |
|---|---|
| Idle plugin overhead (just installed, nothing activated) | **≤ 2600 tokens** |
| Active session (1 router skill + 2 sibling skills loaded) | **≤ 6000 tokens** |
| Heavy session (5 specific skills + 2 agents in conversation) | **≤ 12 000 tokens** |

These are reviewed and updated with actuals as authoring progresses. Final numbers go into the bottom of this file.

## Per-component budget

| Component | Per-item budget | Final count target | Always-in-prompt total |
|---|---|---|---|
| skill `description` | ≤ 25 tokens (~80 chars) | 70 | ~1750 |
| agent `description` | ≤ 30 tokens (~100 chars) | 12 | ~360 |
| command name + short description | ~15 tokens | 12 | ~180 |
| globals `CLAUDE.md` | ~300 tokens | 1 (always loaded as user memory) | ~300 |
| Stop hook | trivial | 1 | n/a (runtime only) |
| **subtotal idle** | | | **~2590** |

## Not in the always-on prompt

- `SKILL.md` body (`# Heading`, etc.) — loaded when Claude activates the skill (description match).
- `skills/<name>/resources/*.md` — loaded only when the activated `SKILL.md` instructs Claude to read them.
- Command bodies — loaded only when the user invokes the slash-command.
- Hook scripts — execute at runtime, never enter the prompt.
- MCP tool schemas — only present when an MCP server is enabled in the session.

## Authoring rules

### 1. Description = "what + when + when-NOT", one sentence

- ❌ Bad: `"Skill for working with Kotlin coroutines, providing best practices and patterns for asynchronous programming"` — 18 tokens of which 12 are noise.
- ✅ Good: `"Kotlin coroutines: structured concurrency, dispatchers, exceptions, flows. NOT for RxJava/Reactor."` — 22 tokens, every word load-bearing.

The `when-NOT` part doubles the precision of skill matching and prevents accidental activation on adjacent topics.

### 2. Router skill descriptions are the lightest

A router (`kotlin`, `spring`, `ddd`, `clean-code`, `testing`, `architecture`, `methodology`) exists only to route. Its description points to siblings.

- ✅ `"Kotlin idioms router → kotlin-idioms / kotlin-coroutines / kotlin-null-safety / kotlin-generics / …"` — 18 tokens.

### 3. `SKILL.md` body ≤ ~150 lines

If you need to explain more than ~150 lines, that overflow goes into `skills/<name>/resources/*.md`. The `SKILL.md` body then contains a small "if X → read resources/X.md, if Y → read resources/Y.md" router.

This shifts cost from "always loaded once activated" to "only loaded when needed for this specific concern".

### 4. No verbose `tools:` lists on agents

Default = all tools available. Restrict (`tools: Read, Grep, Glob`) only when the role demands isolation (e.g. a read-only reviewer that must not write).

### 5. Don't repeat what the body says

Description is metadata for activation. The body explains what to do once activated. Repetition burns tokens twice.

## How to measure

After each authoring phase, run `/context` in a fresh session with the plugin installed and read the "tokens" line for **System prompt** vs **Free space**. The delta against an empty plugin install is the plugin's idle cost.

Record actuals in the table below.

## Actuals (filled in as phases complete)

| Phase | Date | Skill count | Agent count | Command count | Idle tokens added | Notes |
|---|---|---|---|---|---|---|
| 1 (skeleton + tuning) | TBD | 0 | 0 | 4 | TBD | baseline of just the tuning toolkit |
| 2 (senior agents + meta) | TBD | 0 | 4–5 | 9 | TBD | |
| 3 (methodology + clean-code) | TBD | ~14 | 4–5 | 9 | TBD | |
| 4 (kotlin + spring) | TBD | ~39 | 4–5 | 9 | TBD | |
| 5 (ddd + testing + architecture + specialists) | TBD | ~64 | 12–13 | 9 | TBD | |
| 6 (MCP enabled, one server) | TBD | ~64 | 12–13 | 9 | TBD | report cost of each MCP |
| 7 (polish + scaffold/trace/test-gap) | TBD | ~64 | 12–13 | 12 | TBD | final numbers |
