---
name: spec-lifecycle
description: "Feature-change artifact graph + states; vs long-lived standards/. NOT for archive merge semantics."
---

# spec-lifecycle

Two kinds of artifacts live inside `.spec/`:

1. **Feature specs** — pass through a change-lifecycle (`proposal → specs → design → tasks → implementation → archive`). They evolve via delta operations.
2. **Long-lived specs** (`.spec/standards/*.md`) — freeform documents that persist for the project's lifetime. Edited directly. No lifecycle, no archival. See `spec-standards`.

This skill describes the **feature-change lifecycle**.

## When to use

- Implementing `/spec-new`, `/spec-continue`, `/spec-status`, `/spec-list`.
- Deciding which artifact to generate next for a partially-filled change.
- Explaining to a user why a status reports `[ ]` vs `[-]`.

## Artifact dependency graph (feature changes only)

```
proposal.md  ──►  specs/<cap>/spec.md  ──►  design.md  ──►  tasks.md  ──►  implementation
```

- `proposal.md` — why & what. No upstream dependency.
- `specs/<cap>/spec.md` (delta) — what changes. Depends on proposal (uses rationale to scope deltas).
- `design.md` — how. Depends on the deltas (knows what behaviour is changing).
- `tasks.md` — concrete checklist. Depends on design.
- Implementation — depends on tasks.

## Status states

For each artifact in an active change, `scripts/spec/status.sh <name>` reports one of:

- `[x]` — artifact file exists.
- `[ ]` — dependencies satisfied, artifact file missing (this is the *next* artifact to create).
- `[-]` — dependency missing; cannot create yet.

These states apply **only** to feature-change artifacts. `.spec/standards/*.md` files have no lifecycle and never appear in `status.sh` output.

Examples:

| proposal | specs | design | tasks | meaning |
|---|---|---|---|---|
| `[ ]` | `[-]` | `[-]` | `[-]` | freshly-scaffolded change |
| `[x]` | `[ ]` | `[-]` | `[-]` | proposal done; specs next |
| `[x]` | `[x]` | `[x]` | `[ ]` | tasks next |
| `[x]` | `[x]` | `[x]` | `[x]` | ready for `/spec-apply` |

## Workflow

**One-shot (default):**
```
/spec-propose <description>   # creates all four artifacts in current context
/spec-apply <change>          # loads context for implementation (no auto-delegation)
/spec-archive <change> -y     # validate → merge deltas → relocate to archive
```

**Stepwise (for high-stakes changes):**
```
/spec-new <change-name>        # empty scaffold
/spec-continue <change>        # generate next missing artifact (repeat)
/spec-apply <change>
/spec-archive <change> -y
```

`/spec-sync` may be inserted before archive for stacking (merge deltas without archiving — see `spec-archive`).

Both flows can be mixed.

## Procedure (next-artifact selection)

1. Run `scripts/spec/status.sh <change>` → TSV of per-artifact state.
2. Find the first artifact in `proposal → specs → design → tasks` order with state `[ ]`. That is the next artifact.
3. If all four are `[x]`, the change is implementation-ready (call `/spec-apply`).
4. If any state is `[-]`, the upstream dependency is missing; create that first.

## When NOT to use

- Long-lived `.spec/standards/*.md` → `spec-standards` skill.
- Archival merge order / collision handling → `spec-archive` skill.
- Spec / delta format rules → `spec-format`, `spec-delta-format`.
- Validation severity → `spec-validation`.

## Anti-patterns

- Skipping `proposal.md` "to save time" — every other artifact loses context.
- Filling `tasks.md` before `design.md` exists — tasks reference design decisions.
- Treating `[x]` as "frozen". Any artifact can be re-edited; status only tracks existence.
- Hardcoding the dependency graph in command bodies — always defer to `status.sh`.
- Putting long-lived project rules inside a feature change's `design.md`. They belong in `.spec/standards/*.md`.
