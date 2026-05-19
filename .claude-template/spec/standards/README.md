# `.spec/standards/` — long-lived project rules

Put markdown files here that should govern **every** spec and every implementation in this project. The full foundry `/spec-*` command suite (propose, continue, apply, …) reads every file in this directory before authoring or implementing — so anything you put here will be respected.

## Suggested files (none are required)

- **`stack.md`** — tech stack constraints (language/framework versions, allowed deps, runtime requirements).
- **`architecture.md`** — architectural pattern choices (layered / hexagonal / CQRS), service boundaries, communication style.
- **`best-practices.md`** — "prefer X over Y", testing approach, naming conventions.
- **`anti-patterns.md`** — "do NOT do X", traps, performance gotchas specific to this codebase.
- **`glossary.md`** — project-specific terminology.

Add any other category you need — `security.md`, `compliance.md`, `migration-strategy.md`, etc. The directory is freeform.

## Rules

- Freeform markdown. No `ADDED/MODIFIED/REMOVED` deltas. Just edit.
- No lifecycle — these files are never archived.
- Keep each file tight: 50–200 lines typical, ≤ 500 always. Total budget ≤ 50 KB combined.
- Standards should be **actionable**, not aspirational. "We value clean code" is noise. "Functions ≤ 30 lines" is a rule.
- Standards override implicit assumptions, but they do **not** override an explicit user request — they prompt a discussion when in tension.

## See also

- `/spec-list --standards` — list current standards.
- `spec-standards` skill — full reference.

Delete this README when you're done reading it (or leave it; `/spec-list --standards` includes it without complaint).
