---
name: spec-conventions
description: "Naming (kebab-case slug), 4-bucket directory layout, flat tracking.yaml schema. NOT for state machine — see spec-lifecycle."
---

# spec-conventions

Naming, directory layout, and `tracking.yaml` schema for `.spec/`. State semantics live in `spec-lifecycle`.

## When to use

- Validating user-supplied or LLM-generated change slugs.
- Choosing a slug for a new change.
- Writing or parsing `tracking.yaml` — the schema below is the **contract** bash helpers depend on.

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
    ├── backlog/<name>/             # not yet in active work
    ├── in-progress/<name>/         # implementation / verification / termination active
    ├── done/<name>/                # all terminal stages reached
    └── declined/<name>/            # terminal, includes decline_reason
```

Inside each `<name>/`:

```
<name>/
├── tracking.yaml                   # always present
├── propose.md                      # always present (scaffold-stub; body = original task text)
├── requirements.md                 # appears after refinement starts
├── system-design.md                # appears after design starts
├── application-design.md           # appears after design starts
└── roadmap.md                      # appears after decomposition starts
```

## Naming

- **Change names / slugs** — kebab-case, 3-4 segments, LLM-generated from the task text. Examples: `add-2fa-totp`, `fix-login-rate-limit`, `migrate-postgres-15`.

  Validated by `change.sh validate-name`:
  - Must match `^[a-z][a-z0-9]*(-[a-z0-9]+)*$`.
  - Must be unique across **all 4 buckets**.
  - Must not equal reserved names (`backlog`, `in-progress`, `done`, `declined`, `.template`).

- **Task IDs** in `roadmap.md` — `[A-Z]?[0-9]+(\.[0-9]+)*`. `Q`-prefix = Quality gate (`Assignee: verifier`).

## `tracking.yaml` schema — flat

```yaml
id: add-2fa-totp                            # = directory basename
title: "Add two-factor authentication via TOTP"
description: |
  Adds TOTP-based 2FA per RFC 6238 with Google Authenticator support.
  Supports QR-code provisioning and recovery codes.
status: backlog                             # derived: backlog | in-progress | done | declined
stage: refinement                           # derived: refinement | design | … | termination | none
scope: ""                                   # "" | product | project | feature | bugfix
created_at: "2026-05-21 22:15:13"           # set at scaffold time; never mutated
updated_at: "2026-05-21 22:15:15"           # auto-refreshed on every tracking.sh mutation
progress: "3/12"                            # auto-synced from roadmap.md task states (done/total)
refinement:     estimation                  # state per stage; see spec-lifecycle for state machine
design:         estimation
decomposition:  estimation
implementation: estimation
verification:   estimation
termination:    estimation
history:
  - { at: "2026-05-21 19:47:14", stage: refinement, status: in-progress, by: user }
  # …append-only, ONLY real stage transitions…

# Optional, only when declined:
decline_reason: "<reason text>"
```

### Field rules

- **Top-level scalars** (`id`, `title`, `status`, `stage`, `scope`, `decline_reason`) — one per line, `key: value`.
- **`title:`** — single-line quoted, up to ~120 chars. Imperative phrase.
- **`description:`** — YAML `|`-literal block, multi-line, up to ~500 chars. Body indented 2 spaces.
- **`status:` and `stage:` are derived** — `tracking.sh sync` recomputes both on every state mutation. Never edit by hand; the next `set-stage` overwrites drift.
- **`created_at:`** — written once at scaffold time by `change.sh new`; never mutated thereafter. Immutable audit of when the change first appeared.
- **`updated_at:`** — auto-refreshed by `tracking.sh sync` on every mutation (`set-stage`, `set-scope`, `decline`, etc.). Top-level convenience field so `change.sh list` doesn't have to parse history.
- **`progress:`** — `"done/total"` snapshot of the roadmap. Initial `"0/0"` at scaffold time. Auto-synced by `tracking.sh sync_roadmap_progress` (part of `sync_all`) and after `roadmap.sh set-task-state`. If `roadmap.md` is absent → stays at `"0/0"`.
- **Stage keys** (`refinement` … `termination`) — exactly 6 top-level keys, no nested `stages:` block. Each value is one of **8 stage states**: `estimation | required | skipped | pending | in-progress | review | completed | rejected`. Order convention: refinement → design → decomposition → implementation → verification → termination. Value column alignment is cosmetic. Initial state for every stage at scaffold time is `estimation`.
- **`history:` block** — append-only flow-style entries. Each: `{ at, stage, status, by }`. `at` is `YYYY-MM-DD HH:MM:SS` (seconds precision). Always the **last** section. **Only real stage transitions** — no `created`, no `moved-to-*`, no `scope-set:*`, no `lifecycle`. Empty history at scaffold time is normal.

### Why strict + flat schema

Parsers are pure-bash + portable awk (no `yq`). Flat top-level keys are trivial to read (`^<stage>: <value>$`); the previous nested `stages:` block needed indentation tracking. Any structural deviation silently breaks `tracking.sh get-stage`. To rescue a broken file, use helpers to rewrite from scratch.

## When NOT to use

- State machine + transitions → `spec-lifecycle`.
- `roadmap.md` task format → `spec-roadmap`.
- Standards files → `spec-standards`.

## Anti-patterns

- Inventing your own bucket (e.g. `archive/`, `in-review/`) — only 4 are recognised.
- Renaming a change after creation — breaks `change.sh locate` references; preserve via decline + new change with a fresh slug.
- Adding new fields without updating helpers — parsers ignore unknown keys but writers (`set-stage`, `sync`) won't preserve them through rewrites.
- Editing history entries — append-only audit log.
- Editing `status:` or `stage:` by hand — both derived; next `set-stage` overwrites.
- Re-nesting stage keys under `stages:` — breaks the flat-parser awk patterns.
- "Fix-things" or "misc" slugs — too vague. Use a specific stem.
