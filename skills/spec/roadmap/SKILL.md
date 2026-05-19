---
name: spec-roadmap
description: "roadmap.md syntax: tasks, fields, blockers, Quality gates. Parallelism derived from blockers."
---

# spec-roadmap

`roadmap.md` is the teamlead's artifact produced during the `decomposition` stage. It is a flat list of atomic tasks with explicit blockers, estimates, and assignees. Parallelism is **derived** from blockers, not a stored field.

## When to use

- Authoring `roadmap.md` during decomposition stage.
- Implementing `roadmap-parse.sh` / `roadmap-ready.sh` / `roadmap-status.sh` / `roadmap-set-task-state.sh`.
- Implementing `/track <name>` summary view (shows roadmap progress).

## Task format

Each task is one block starting with an H2 heading:

```markdown
## <ID>. <title>
- **Estimate:** <value>
- **Blockers:** <comma-separated IDs or —>
- **Assignee:** <agent-name>
- **State:** <pending | in-progress | done | blocked | rejected>
- **Acceptance:** <one-line criterion for marking done>
```

All 5 fields are required. Authors may add prose between blocks but parser ignores it.

### Field values

| Field | Allowed values | Notes |
|---|---|---|
| `Estimate` | `15m`, `30m`, `1h`, `2h`, `4h` | Discrete bins. Important for orchestrator's context-window planning. |
| `Blockers` | comma-separated task IDs (e.g. `1, 2`) or `—` (or `-`) for none | All listed IDs must exist in the same roadmap. Circular = author error. |
| `Assignee` | foundry agent name (`code-implementor`, `verifier`, `architect`, …) | Used by `/track <name>` to group ready tasks. |
| `State` | `pending`, `in-progress`, `done`, `blocked`, `rejected` | Mutated only by `roadmap-set-task-state.sh`. |
| `Acceptance` | free-text criterion | What makes the task verifiably done. |

### Task IDs

Pattern: `[A-Z]?[0-9]+(\.[0-9]+)*`. Examples:
- `1`, `2`, `10` — main tasks
- `1.1`, `2.3` — nested decomposition
- `Q1`, `Q2`, `Q3` — Quality gates (Q-prefix convention)

IDs are stable. Never renumber when inserting — give new tasks fresh numbers.

## Quality gates convention

Final tasks in the roadmap. Convention:
- ID prefixed with `Q` (e.g. `Q1`, `Q2`).
- `Assignee: verifier`.
- `Blockers:` includes all main task IDs (or `—` if running gates in parallel with implementation is genuinely safe).
- One Q-task per project quality command (test suite, lint, typecheck, format check).

Detect commands from `CLAUDE.md` + build manifests (`build.gradle.kts`, `package.json`, `Cargo.toml`, `Makefile`, …). Examples:

```markdown
## Q1. Run `./gradlew test` — confirm green
- **Estimate:** 15m
- **Blockers:** 1, 2, 3, 4, 5
- **Assignee:** verifier
- **State:** pending
- **Acceptance:** all tests green; exit 0
```

Verifier flips Q-task `state: done` **only after** the actual command exits green. Failing run = stays `pending` with diagnostic surfaced.

## Parallelism

Tasks with **disjoint transitive blocker sets** can run in parallel. Parser does not enforce this — it's the orchestrator's responsibility to compute the ready set (`roadmap-ready.sh`) and group by safety.

`roadmap-ready.sh` rule: task is ready iff `state == pending` AND all `Blockers` have `state == done`. Empty blockers (`—`) → immediately ready.

## Relationship to tracking.yaml

Roadmap.md's tasks are an **internal** concern of the decomposition+implementation stages. The change-level `tracking.yaml` has **no** `roadmap_state` field — plan approval lives in `stages.decomposition` (transitions `pending → in-progress → need-approve → approved`). Per-task progress lives only inside roadmap.md.

## Helper reference

| Helper | Use |
|---|---|
| `roadmap-parse.sh <path>` | Extract all tasks as TSV (id, title, est, blockers, assignee, state, acceptance) |
| `roadmap-status.sh <path>` | Aggregate counts by state |
| `roadmap-ready.sh <path>` | List task IDs whose blockers are all done and own state is pending |
| `roadmap-set-task-state.sh <path> <id> <state>` | Atomic single-field rewrite |

## Parser limitation — code fences

The parser is **line-based**, not AST-aware. A task header pattern (`## <ID>. <title>`) inside a triple-backtick block will be treated as a real task. Avoid quoting `## 1. Example` inside fenced examples within roadmap.md. If you must show example task syntax, use indented fences or a quote prefix.

## When NOT to use

- Stage transitions in tracking.yaml → `spec-lifecycle`.
- Stage authorship rules (who writes what) → `spec-workflow`.
- Naming conventions → `spec-conventions`.

## Anti-patterns

- Inventing a "parallel" field per task — parallelism comes from disjoint blocker sets, not from a tag.
- Quality gates without `Assignee: verifier` — breaks the verification stage's ability to find its work.
- Forgetting Quality gates section entirely — verification stage has nothing to run.
- Renumbering tasks when inserting — breaks blocker references and history.
- Quoting `## 1.` task headers inside code fences — parser treats them as real tasks.
- Writing `Estimate: 25m` (non-discrete bin) — orchestrator can't plan context windows.
