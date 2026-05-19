---
name: spec-standards
description: ".spec/standards/*.md — long-lived freeform docs (stack, arch, project context). NOT for per-change artifacts."
---

# spec-standards

`.spec/standards/` holds long-lived markdown documents that encode the **permanent worldview** of the project: tech stack constraints, architectural principles, recommendations, hard "do not do this" rules, glossary, project context. They are read by agents on demand for ambient context.

## When to use

- Encoding a project-wide rule that should govern **every** future change (e.g. "no global mutable state", "all DB access goes through Repository pattern").
- Capturing project context (purpose, scope, who-for) — put it in `standards/project.md` (or `context.md`).
- Onboarding — fill obvious categories before authoring the first change.

## Categories (recommended, not enforced)

Each file is freeform markdown. Suggested:

| File | Holds |
|---|---|
| `project.md` *(or `context.md`)* | Purpose, target users, scope, key business constraints. The thing previously written in `.spec/project.md`. |
| `stack.md` | Language / framework / runtime versions; allowed and forbidden dependencies. |
| `architecture.md` | Pattern choices (layered? hexagonal? CQRS?), service boundaries, sync vs async. |
| `best-practices.md` | "Prefer X over Y"; testing approach; non-obvious naming conventions. |
| `anti-patterns.md` | "Do NOT do X"; known traps; performance gotchas specific to this codebase. |
| `glossary.md` | Project-specific terms; domain vocabulary. |
| `<custom>.md` | Any other long-lived category — `security.md`, `compliance.md`, `migration-strategy.md`, etc. |

Nothing forces these exact names. The directory is freeform.

## Properties

- **No lifecycle.** Not subject to stages, buckets, or `tracking.yaml`.
- **Direct edits.** Update with `Edit` / `Write` / regular conversation. Never archived.
- **On-demand loading.** Agents read what's relevant when they need it (e.g. system-analyst reads `project.md` + `glossary.md`; architect reads `architecture.md` + `stack.md`).

## Authoring

1. Pick the right file (or create a new one with a precise name).
2. Write tight, prescriptive content:
   - Bad: "We value clean code".
   - Good: "Functions ≤ 30 lines. Repository methods named `find*` / `save*` / `delete*` — no other prefixes".
3. Keep it short. 50–200 lines per file typical; under 500 always.
4. Total `.spec/standards/*` budget: ≤ 50 KB combined. Standards loaded multiple times per session burn tokens — bloat is taxed.
5. When a standard conflicts with what a user just asked for, **surface the contradiction** before silently overriding. The user can edit the standard or rephrase the request.

## When NOT to use

- Per-change requirements → `requirements.md` inside the change.
- Per-change architecture decisions → `system-design.md` / `application-design.md`.
- Per-change task lists → `roadmap.md`.
- Bucket / stage state → `tracking.yaml` (managed by `tracking-*.sh` helpers).

## Anti-patterns

- Putting a single feature's requirements into standards — that belongs in the change.
- Standards as wish-lists ("we should write more tests") — make it actionable or delete.
- 1000-line `architecture.md` — split or trim.
- Editing standards mid-change without recording why — at minimum mention the rationale in the same commit; better, open a separate change for the rule update.
- Treating `spec-standards` as a command — it is a skill (knowledge reference). Edit files directly.
