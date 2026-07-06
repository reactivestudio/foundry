---
name: spec-lifecycle
description: Change lifecycle state machine for foundry — bucket transitions, serial invariant, tracking.yaml schema, history.log format. Use when handling /foundry:change mutations or reading a change's state.
---

# Change Lifecycle

A **change** = one unit of work moving through CRISPY stages. Phase 1 implements only the bucket-level state machine; stage-level state (`questions`, `research`, …) arrives in later phases.

## Buckets

| Bucket | Meaning | Mutable? |
|---|---|---|
| `backlog` | proposed, not started | yes |
| `in-progress` | active work | yes |
| `done` | completed | **terminal** — no exits |
| `declined` | abandoned (with reason) | yes (can revive) |

Filesystem layout in the **target project**:

```
.foundry/changes/
  ├── backlog/<slug>/{tracking.yaml, proposal.md, history.log, …}
  ├── in-progress/<slug>/…
  ├── done/<slug>/…
  ├── declined/<slug>/…
  └── .template/{tracking.yaml, proposal.md}
```

## Transition matrix

| From → To | Allowed? | Extra requirements |
|---|:---:|---|
| `backlog` → `in-progress` | ✓ | **serial**: no other change in `in-progress` |
| `backlog` → `declined` | ✓ | `reason` required |
| `in-progress` → `done` | ✓ | — |
| `in-progress` → `declined` | ✓ | `reason` required |
| `in-progress` → `backlog` | ✓ | logged (pause / re-scope) |
| `declined` → `backlog` | ✓ | — |
| `done` → anything | ✗ | terminal |
| `backlog` → `done` | ✗ | cannot skip implementation |

Validation lives in `scripts/cli/spec/state-machine.sh` and is invoked from `scripts/cli/store/change.sh move` — never bypass.

## Serial invariant

At most **one** change in `in-progress` at any time ([MISSIONS §7](../../../roadmap/MISSIONS.md)). State machine rejects the second `→ in-progress` move with exit code 1 and stderr listing the current in-progress slug.

## `tracking.yaml` schema (flat YAML)

One `key: value` per line, no nesting — parseable with `grep`/`awk`:

```yaml
slug: add-rate-limiting
title: Rate limiting for /api/orders
status: backlog
created_at: 2026-05-24T10:00:00Z
updated_at: 2026-05-24T10:00:00Z
decline_reason: <only when status=declined>
```

Stage-level fields (added in Phase 2+) will use the prefix `stage_<name>: <state>`, e.g. `stage_questions: completed`. Same flat shape.

## `history.log` format (TSV, append-only)

Alongside `tracking.yaml`. One line per event:

```
<ISO-8601 UTC>\t<actor>\t<event>\t<details>
```

Actors so far: `user`, `state-machine`. Events: `created`, `moved`. Detail field is free-form, may be empty.

Append-only — no rotation, no edits. To inspect: `tracking.sh history-tail <dir> [n]`.

## Scripts (the only sanctioned mutation paths)

- `scripts/cli/store/change.sh new|locate|path|move|list|show` — CRUD orchestration
- `scripts/cli/store/tracking.sh init|get|set|history|history-tail` — flat YAML + history I/O
- `scripts/cli/spec/state-machine.sh validate-bucket|check-serial|list-buckets` — transition + invariant checks

**Hard rule:** never edit `.foundry/changes/**` files by hand. All mutations go through `change.sh`.
