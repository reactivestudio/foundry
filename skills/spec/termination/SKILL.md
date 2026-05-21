---
name: spec-termination
description: "Termination-stage rules: changelog, migration notes, cleanup checklist, retrospective. NOT for verification."
---

# spec-termination

Knowledge for the termination stage: the post-verification finish-up that wraps a change before it's marked `done`. Produces `termination.md` (per-change record) and optionally appends to a repo-level `CHANGELOG.md`. Used by the `termination-handler` agent.

## When to use

- Closing a change after verification has passed.
- Writing or reviewing `termination.md`.
- Updating repo-level `CHANGELOG.md` for a change.
- Listing cleanup items that became visible only after implementation finished.

## What termination covers

Four concerns. Cover each that applies; skip with `(n/a)` for those that don't.

### 1. Changelog entry

If the repo has a `CHANGELOG.md` (root or `docs/`), append an entry per its existing format. Common shapes:

| Format | Entry shape |
|---|---|
| Keep a Changelog | `### Added / Changed / Fixed / Removed` under the next unreleased version section |
| Conventional | terse line under appropriate header |
| Free-form | repo-specific — match existing tone |

Rules:
- Single line if possible. Cite change name + 1-sentence outcome.
- Reference any breaking-change call-outs.
- Don't fabricate version numbers — leave under `## [Unreleased]` if uncertain.

If no `CHANGELOG.md` exists, **don't create one** unless explicitly in `requirements.md`. Note the absence in `termination.md`.

### 2. Migration notes (only if breaking)

If the change is breaking (API contract change, removed feature, DB schema migration requiring backfill, env-var rename):

```
## Migration notes (breaking)

### What broke
- <observable behaviour change>

### Required action
1. <step user/operator takes>
2. …

### Rollback
- <how to revert if needed; or "irreversible — see DB backfill in roadmap.md:Task X">
```

Pull breaking-flag from `requirements.md` NFR-compatibility or design's Key decisions. If you can't determine breakingness — ask user via Open question.

### 3. Cleanup checklist

Things that exist in the codebase **because of this change** and should be removed at some point. Common items:

| Cleanup item | When to remove |
|---|---|
| Feature flag wrapper | After feature is stable (cite criterion — date / metric) |
| Deprecated code path / old API version | After consumers migrated |
| Migration helper / backfill script | After last DB shard processed |
| TODO comments referencing this change | When their gating condition resolves |
| Documentation pointers to deprecated pages | After 1 release cycle |

Each item: file path + condition for removal + suggested next-change-slug (optional).

If no cleanup items exist, mark `(none)`. Don't fabricate.

### 4. Retrospective bullet

1–2 sentences honest about what went well or surprised the team. Optional but valuable for future estimation calibration.

Examples:
- "Decomposition estimate was 8h; actual ~14h. Auth integration unexpectedly required two-leg OAuth refactor."
- "Implementation went fast (3h vs. 6h estimated) — design's port/adapter sketch was unusually complete."

Skip if nothing meaningful to add. Don't pad.

## `termination.md` schema

```
# Termination: <title>

## Summary
- change: <name>
- scope: <scope>
- impl tasks completed: <n>/<total>  · Q-gates passed: <q>/<total>

## Changelog entry
<appended to CHANGELOG.md? yes — under <section>; or: no CHANGELOG.md in repo>
<entry text verbatim>

## Migration notes
<breaking? yes/no>
<if yes: full schema as above; if no: "n/a — non-breaking">

## Cleanup
- <file:line> | <removal condition> | <suggested follow-up slug>
- …
(or: "(none)")

## Retrospective
<1–2 sentences; or "(none)">
```

## Quality bar (when to mark `termination: review`)

- `termination.md` exists with all four sections (each filled or explicitly marked `n/a`).
- If breaking → migration notes section is complete and actionable.
- If `CHANGELOG.md` exists in repo → appended (Bash via Read+Write, NOT a separate stage).
- Cleanup items are concrete (file paths cited where possible) — not vague "remove old code".

## When NOT to use

- During implementation — cleanup items surface after, not during, the work.
- For verification → `spec-verification` skill.
- Writing project-level conventions → `.spec/standards/*.md`.

## Anti-patterns

- **Generic changelog entry.** "Various improvements" — useless. Cite the change name + concrete outcome.
- **Fabricated retrospective.** If nothing notable happened, write `(none)`. Don't fill space.
- **Cleanup as TODO dump.** Cleanup items should have **a condition for removal**, not just "remove later". If no condition is identifiable, the item is junk.
- **Migration notes without rollback.** Every breaking change needs a rollback story, even if "irreversible — must redeploy old version". Skipping this loses operator trust.
- **Touching code in termination.** Termination produces docs / changelog only. Code changes belong to implementation; if you find broken code, surface as a follow-up change, don't fix in termination.
