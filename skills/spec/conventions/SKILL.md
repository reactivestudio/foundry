---
name: spec-conventions
description: "Naming (kebab-case slug), 4-bucket directory layout, tracking.yaml schema. NOT for state machine — see spec-lifecycle."
---

# spec-conventions

Naming, directory layout, and `tracking.yaml` schema for `.spec/`. Independent of state semantics (covered by `spec-lifecycle`) and artifact content (covered by `spec-workflow`).

## When to use

- Validating user-supplied or LLM-generated change slugs.
- Choosing a slug for a new change.
- Writing or parsing `tracking.yaml` — the schema below is the **contract** that bash helpers depend on.

## Directory layout

```
.spec/
├── standards/                      # long-lived freeform docs (no lifecycle)
│   ├── README.md                   # delete after populating
│   ├── stack.md                    # suggested
│   ├── architecture.md             # suggested
│   ├── project.md                  # suggested (project context)
│   └── <custom>.md
└── changes/
    ├── .template/                  # used by `change.sh new`; do not edit per-project
    │   ├── tracking.yaml
    │   └── propose.md
    ├── backlog/<name>/             # not yet in active work (any stage state)
    ├── in-progress/<name>/         # implementation or verification active
    ├── done/<name>/                # successfully completed
    └── declined/<name>/            # terminal, includes decline_reason
```

Inside each `<name>/`:

```
<name>/
├── tracking.yaml                   # always present
├── propose.md                      # always present (scaffold-stub from .template, body = original task text)
├── requirements.md                 # appears after refinement stage starts
├── system-design.md                # appears after design stage starts
├── application-design.md           # appears after design stage starts
└── roadmap.md                      # appears after decomposition stage starts
```

Files appear progressively. Agents write them; spec-commands never generate content (except scaffold).

## Naming

- **Change names / slugs** (`changes/<bucket>/<name>/`) — kebab-case, **3-4 segments**, LLM-generated from the original task text. Examples: `add-2fa-totp`, `fix-login-rate-limit`, `migrate-postgres-15`.

  Validated by `change.sh validate-name`:
  - Must match `^[a-z][a-z0-9]*(-[a-z0-9]+)*$`.
  - Must be unique across **all 4 buckets** (`backlog`, `in-progress`, `done`, `declined`).
  - Must not equal a reserved name (`backlog`, `in-progress`, `done`, `declined`, `.template`).

  No date-prefix. Coined once, used everywhere. Reusing a finished change's name → rejected (pick a different angle).

- **Task IDs** in `roadmap.md` — `[A-Z]?[0-9]+(\.[0-9]+)*`. Examples: `1`, `2.1`, `Q1`, `Q2.3`. Q-prefix = Quality gate (Assignee: verifier).

## `tracking.yaml` schema

**Bash helpers depend on this schema.** Humans should edit only `title` and `description`. State changes go through `tracking.sh` subcommands (`set-stage`, `set-scope`, `decline`, `sync-status`).

```yaml
id: add-2fa-totp                            # = directory basename (slug, 3-4 segments)
title: "Add two-factor authentication via TOTP"
description: |
  Adds TOTP-based 2FA per RFC 6238 with Google Authenticator support.
  Supports QR-code provisioning and recovery codes.
  Multi-line, up to ~500 chars.
status: backlog                             # derived: backlog | in-progress | done | declined
scope: ""                                   # "" | product | project | feature | bugfix
stages:
  refinement:     pending
  design:         pending
  decomposition:  pending
  implementation: pending
  verification:   pending
history:
  - { at: "2026-05-21 19:47:14", stage: refinement, status: in-progress, by: user }
  # …append-only, ONLY stage transitions…

# Optional, only when declined:
decline_reason: "<reason text>"
```

### Field rules

- **Top-level scalars** (`id`, `title`, `status`, `scope`, `decline_reason`) — one per line, `key: value` form.
- **`title:`** — single-line quoted string, up to ~120 chars. Imperative phrase.
- **`description:`** — YAML `|`-literal block (multi-line, up to ~500 chars). Each body line indented 2 spaces. Helpers WRITE it (multi-line aware); only commands read it (Claude parses tracking.yaml as text for `/track` display).
- **`status:` is derived** — `tracking.sh` recomputes it (via `sync-status`) on every state mutation. Never edit by hand; the next `set-stage` will overwrite drift.
- **`stages:` block** — exactly 5 entries with names `refinement`, `design`, `decomposition`, `implementation`, `verification`. Each value is one of 6 stage states. Indentation: 2 spaces. Value column alignment is cosmetic.
- **`history:` block** — append-only flow-style entries. Each entry: `{ at, stage, status, by }`. `at` is `YYYY-MM-DD HH:MM:SS` (seconds precision). Always the **last** section in the file (helpers append to end). **Only stage transitions** — no `lifecycle`, no `moved-to-*`, no `created`. Empty history at scaffold time is normal.

### Why strict schema

Parsers are pure-bash (portable awk, no `yq`). Any structural deviation (extra indentation, multi-line strings, quoted booleans) silently breaks `tracking.sh get-stage`. To rescue a broken file, use helpers to rewrite from scratch.

## When NOT to use

- State machine + transitions → `spec-lifecycle`.
- Per-stage artifact contents (what goes in requirements.md, etc.) → `spec-workflow`.
- `roadmap.md` task format → `spec-roadmap`.
- Standards files → `spec-standards`.

## Anti-patterns

- Inventing your own bucket (e.g. `archive/`, `in-review/`) — only 4 are recognised by helpers and commands.
- Renaming a change after creation — breaks `change.sh locate` if anyone references the old name; preserve via decline + new change with a fresh slug.
- Adding new fields to `tracking.yaml` without updating helpers — parsers ignore unknown keys but writers (`tracking.sh set-stage`) won't preserve them through rewrites.
- Editing history entries — they are an append-only audit log.
- Editing `status:` by hand — it's derived from stages; the next `set-stage` overwrites it.
- "Fix-things" or "misc" slugs — too vague to be useful in history. Use a specific stem.
