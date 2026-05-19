---
name: spec-validation
description: "Validation rules + severity reference for specs/deltas; structural (bash) vs semantic (Claude). NOT for authoring."
---

# spec-validation

The validation layer enforces format correctness and semantic consistency of specs and deltas. Implemented as a two-pass system:

- **Structural pass** — deterministic bash (`scripts/spec/validate-structural.sh`). Cheap, fast, no Claude context burn.
- **Semantic pass** — Claude reads multiple files, walks references, checks invariants that bash cannot easily express.

## When to use

- Implementing `/spec-validate`, `/spec-sync`, `/spec-archive`.
- Diagnosing a validation failure surfaced by another command.
- Explaining to a user why their spec/delta is rejected.

## Severity reference

ERROR — blocks `/spec-sync` and `/spec-archive` unless `--no-validate`.

| Code | Where | Trigger |
|---|---|---|
| `SPEC_MISSING_PURPOSE` | spec | no `## Purpose` H2 |
| `SPEC_MISSING_REQUIREMENTS` | spec | no `## Requirements` H2 |
| `SPEC_DUPLICATE_REQUIREMENT` | spec | requirement name appears twice |
| `SPEC_SCENARIO_HASH_COUNT` | spec | `#+ Scenario:` line with hash count ≠ 4 |
| `DELTA_NO_SECTION` | delta | none of ADDED/MODIFIED/REMOVED/RENAMED present |
| `DELTA_MISSING_NORMATIVE` | delta | ADDED/MODIFIED requirement body lacks SHALL/MUST/SHOULD/MAY |
| `DELTA_RENAMED_FORMAT` | delta | RENAMED entry doesn't match the FROM/TO backtick form |
| `DELTA_CROSS_SECTION` | delta | requirement name in two sections |
| `SEMANTIC_MODIFIED_UNKNOWN` | delta | MODIFIED name not present in current main spec |
| `SEMANTIC_RENAMED_CHAIN` | delta | MODIFIED/REMOVED in same file references pre-rename name after a RENAMED |
| `SEMANTIC_ARCHIVE_CONFLICT` | archive-time | MODIFIED name was removed/renamed by an earlier archived change |

WARNING — advisory; `--strict` promotes to ERROR.

| Code | Trigger |
|---|---|
| `SPEC_PURPOSE_TOO_SHORT` | Purpose body < 50 non-whitespace chars |
| `SPEC_NO_SCENARIO` | requirement has no scenarios |
| `DELTA_EMPTY_SECTION` | section header present, no entries |
| `TASKS_INCOMPLETE` | tasks.md has unchecked `[ ]` items at archive time |
| `CONTEXT_TOO_LARGE` | `.spec/project.md` or `config.yaml` `context:` > 50 KB |

## Two-pass procedure

1. **Structural pass** — call `scripts/spec/validate-structural.sh <file> --kind {spec|delta} [--strict]`.
   - Emits TSV findings on stderr; PASS/FAIL summary on stdout. Exit 0 = no errors, 1 = errors (or warnings under `--strict`).
   - Auto-detects kind from path (`.spec/changes/*/specs/*` → delta; else spec) when `--kind` is omitted.

2. **Semantic pass** — Claude reads multiple files in the current context (no subagent delegation):
   - For each `MODIFIED` entry in a delta, Read the corresponding canonical spec and check the name exists. If not → `SEMANTIC_MODIFIED_UNKNOWN`.
   - For each `RENAMED` chain, verify subsequent `MODIFIED`/`REMOVED` in the same file references the **new** name. If not → `SEMANTIC_RENAMED_CHAIN`.
   - Pre-archive only: for each `MODIFIED` referencing a name that may have been touched by a prior archive (compare against current canonical), flag `SEMANTIC_ARCHIVE_CONFLICT`.
   - Check `.spec/project.md` size; warn `CONTEXT_TOO_LARGE` if > 50 KB.

3. **Result aggregation** — combine findings; if any ERROR (or any WARNING under `--strict`) → overall FAIL. Report each finding as `<severity> <code> @ <file>:<line> — <message>`.

## When NOT to use

- Authoring specs/deltas → `spec-format`, `spec-delta-format`.
- Archive merge semantics → `spec-archive`.
- Lifecycle / status detection → `spec-lifecycle`.

## Anti-patterns

- Running only the structural pass before archive — semantic conflicts will surface as broken canonical specs later.
- Treating WARNINGs as ignorable. `--strict` mode exists; CI should use it.
- Bypassing with `--no-validate` outside of recovery scenarios. Log loudly when used.
- Re-implementing validation in command bodies. Always go through this skill + the bash helper.
