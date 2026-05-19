---
name: spec-standards
description: ".spec/standards/*.md — long-lived freeform docs (stack, arch, practices). NOT for feature specs."
---

# spec-standards

`.spec/standards/` holds long-lived markdown documents that encode the **permanent worldview** of the project: tech stack constraints, architectural principles, recommendations, hard «do not do this» rules, glossary. They are read by every context-loading `/spec-*` command and influence every spec and every implementation.

## When to use

- When the user wants to encode a project-wide rule that should govern **every** future change (e.g. "no global mutable state", "all DB access goes through Repository pattern", "use PostgreSQL 16 features freely").
- When `/spec-propose`, `/spec-continue`, or `/spec-apply` should auto-load this knowledge.
- During project onboarding — fill in the obvious categories before writing the first feature spec.

## Categories (recommended, not enforced)

Each file is freeform markdown. Suggested categories:

| File | Holds |
|---|---|
| `stack.md` | Library / framework / language versions; allowed and forbidden dependencies; runtime requirements. |
| `architecture.md` | Pattern choices (layered? hexagonal? CQRS?), service boundaries, communication style (sync/async). |
| `best-practices.md` | "Prefer X over Y"; recommended testing approach; naming conventions if non-obvious. |
| `anti-patterns.md` | "Do NOT do X"; known traps; legacy constraints; performance gotchas specific to this project. |
| `glossary.md` | Project-specific terms; domain vocabulary; what a "tenant" / "order" / "session" actually means in this codebase. |
| `<custom>.md` | Any other long-lived category — `security.md`, `compliance.md`, `migration-strategy.md`, etc. |

Nothing forces these exact names. The directory is freeform.

## Properties

- **No lifecycle.** No `proposal → specs → design → tasks` chain; not subject to `/spec-archive`.
- **Direct edits.** Update with `Edit` or normal Claude-Code discussion. No ADDED/MODIFIED/REMOVED delta semantics.
- **Always loaded.** `/spec-propose`, `/spec-continue`, `/spec-apply` glob `.spec/standards/*.md` and load every file into the active context before authoring or implementing.
- **Never archived.** Even after thousands of feature changes, standards stay in place.
- **`/spec-list --standards`** shows the inventory.

## Authoring

Procedure when writing or updating a standard:

1. Pick the right file (or create a new one with a precise name).
2. Write tight, prescriptive content. Standards should be **actionable**, not aspirational:
   - Bad: «We value clean code».
   - Good: «Functions ≤ 30 lines. Repository methods named `find*` / `save*` / `delete*` — no other prefixes».
3. Keep it short. Long standards get ignored (or burn tokens for nothing). 50–200 lines per file is typical; under 500 always.
4. Total `.spec/standards/*` budget: ≤ 50 KB combined (warning surfaced by `/spec-validate`). Specs that need more context belong in `.spec/specs/<cap>/spec.md`.
5. When a standard is in tension with an old `.spec/specs/<cap>/spec.md`, the standard wins for new work; the canonical spec is a legacy record until rewritten via a change.

## How `/spec-*` commands consume standards

```
/spec-propose <description>
  1. Load .spec/project.md
  2. Load .spec/config.yaml
  3. **Load every .spec/standards/*.md**
  4. Author proposal / specs / design / tasks
     — each must respect standards/

/spec-continue [change]
  → same loading sequence; single artifact

/spec-apply [change]
  → loads standards + change artifacts; standards constrain implementation choices
```

If a standard contradicts something the user just asked for, the assistant should **surface the contradiction** and ask, not silently override. The user can edit the standard (acknowledging the new direction) or rephrase the request.

## When NOT to use

- Feature-specific requirements → those go in `.spec/specs/<cap>/spec.md` (via deltas inside a change).
- Per-change implementation decisions → those go in `design.md` of the change.
- Tactical task lists → `tasks.md`.
- Project context (one paragraph "what is this codebase") → `.spec/project.md`.

## Anti-patterns

- Putting a single feature's requirements into `.spec/standards/`. That belongs in `specs/<cap>/`.
- Standards as wish-lists ("we should write more tests"). Either make it actionable or delete it.
- 1000-line `architecture.md`. Split or trim. Standards are loaded **every** command — bloat is taxed.
- Editing standards mid-change without recording why. Mention the change in the standards file's own commit, or open a normal change to formalise the rule update.
- Treating `/spec-standards` as a command — it isn't. Edit the files directly.
