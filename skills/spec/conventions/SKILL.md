---
name: spec-conventions
description: "Naming (kebab-case), 4-bucket directory layout, tracking.yaml schema. NOT for state machine — see spec-lifecycle."
---

# spec-conventions

Naming, directory layout, and `tracking.yaml` schema for `.spec/`. Independent of state semantics (covered by `spec-lifecycle`) and artifact content (covered by `spec-workflow`).

## When to use

- Validating user-supplied change names.
- Choosing a name for a new change.
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
    ├── _template/                  # used by change-new.sh; do not edit per-project
    │   ├── tracking.yaml
    │   └── proposal.md
    ├── backlog/<name>/             # analysis → architecture → decomposition → pending-approval
    ├── sprint/<name>/              # implementation, verification
    ├── done/<name>/                # successfully completed
    └── declined/<name>/            # terminal, includes decline_reason
```

Inside each `<name>/`:

```
<name>/
├── tracking.yaml                   # always present
├── proposal.md                     # always present (scaffold-stub from _template)
├── requirements.md                 # appears after analysis stage starts
├── system-design.md                # appears after architecture stage starts
├── application-design.md           # appears after architecture stage starts
└── roadmap.md                      # appears after decomposition stage starts
```

Files appear progressively. Agents write them; spec-commands never generate content.

## Naming

- **Change names** (`changes/<bucket>/<name>/`) — kebab-case. Imperative / descriptive. Examples: `add-dark-mode`, `fix-login-rate-limit`, `migrate-postgres-15`.

  Validated by `change-name-validate.sh`:
  - Must match `^[a-z][a-z0-9]*(-[a-z0-9]+)*$`.
  - Must be unique across **all 4 buckets** (`backlog`, `sprint`, `done`, `declined`).
  - Must not equal a reserved name (`backlog`, `sprint`, `done`, `declined`, `_template`).

  No date-prefix. Coined once, used everywhere. Reusing a finished change's name → rejected (rename or pick a different angle).

- **Task IDs** in `roadmap.md` — `[A-Z]?[0-9]+(\.[0-9]+)*`. Examples: `1`, `2.1`, `Q1`, `Q2.3`. Q-prefix = Quality gate (Assignee: verifier).

## `tracking.yaml` schema

**Bash helpers depend on this schema.** Humans should edit only the `title` and (rarely) `priority`-like top-level scalars. State changes go through `tracking-set-stage.sh`, `tracking-set-scope.sh`, `tracking-decline.sh`.

```yaml
id: <name>                          # matches directory basename
title: "<human title>"              # quoted; can be edited freely
scope: ""                           # "" | product | project | feature | bugfix
stages:
  analysis:       pending
  architecture:   pending
  decomposition:  pending
  implementation: pending
  verification:   pending
history:
  - { at: "YYYY-MM-DD HH:MM", stage: _meta, status: created, by: workflow }
  # …append-only…

# Optional, only when declined:
decline_reason: "<reason text>"
```

### Field rules

- **Top-level scalars** (`id`, `title`, `scope`, `decline_reason`) — one per line, `key: value` form.
- **`stages:` block** — exactly 5 entries with names `analysis`, `architecture`, `decomposition`, `implementation`, `verification`. Each value is one of 6 stage states. Indentation: 2 spaces. Value column alignment is preserved by helpers (cosmetic; not load-bearing).
- **`history:` block** — append-only flow-style entries. Each entry: `{ at, stage, status, by }`. Always the **last** section in the file (helpers append to end of file).
- **Pseudo-stage `_meta`** — used for change-level events: `created`, `declined`, `moved-to-backlog|sprint|done|declined`.

### Why strict schema

Parsers are pure-bash (portable awk, no `yq`). Any structural deviation (extra indentation, multi-line strings, quoted booleans) silently breaks `tracking-get-stage.sh`. If you need to rescue a broken file, use helpers to rewrite from scratch.

## When NOT to use

- State machine + transitions → `spec-lifecycle`.
- Per-stage artifact contents (what goes in requirements.md, etc.) → `spec-workflow`.
- `roadmap.md` task format → `spec-roadmap`.
- Standards files → `spec-standards`.

## Anti-patterns

- Inventing your own bucket (e.g. `archive/`, `in-review/`) — only 4 are recognised by helpers and commands.
- Renaming a change after creation — breaks `change-locate.sh` if anyone references the old name; preserve via `decline` + new `backlog-add` instead.
- Adding new fields to `tracking.yaml` without updating helpers — parsers ignore unknown keys but writers (`tracking-set-stage.sh`) will not preserve them through rewrites.
- Editing history entries — they are an audit log; append-only by helpers.
- "Fix-things" or "misc" change names — too vague to be useful in history.
