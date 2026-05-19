# `.spec/standards/` — long-lived project rules

Put markdown files here that should govern **every** spec and every implementation in this project. Agents and commands read this directory on demand for ambient context.

## Suggested files (none are required)

- **`stack.md`** — tech stack constraints (language/framework versions, allowed deps, runtime requirements).
- **`architecture.md`** — architectural pattern choices (layered / hexagonal / CQRS), service boundaries, communication style.
- **`best-practices.md`** — "prefer X over Y", testing approach, naming conventions.
- **`anti-patterns.md`** — "do NOT do X", traps, performance gotchas specific to this codebase.
- **`glossary.md`** — project-specific terminology.
- **`project.md`** *(or `context.md`)* — purpose, scope, who the project is for. Project-level context that doesn't fit elsewhere.

Add any other category you need — `security.md`, `compliance.md`, `migration-strategy.md`, etc. The directory is freeform.

## Rules

- Freeform markdown. Just edit.
- No lifecycle — these files are never archived.
- Keep each file tight: 50–200 lines typical, ≤ 500 always. Total budget ≤ 50 KB combined.
- Standards should be **actionable**, not aspirational. "We value clean code" is noise. "Functions ≤ 30 lines" is a rule.
- Standards override implicit assumptions, but they do **not** override an explicit user request — they prompt a discussion when in tension.

## See also

- `spec-standards` skill — full reference.

Delete this README when you've populated the directory.
