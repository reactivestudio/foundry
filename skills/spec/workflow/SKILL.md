---
name: spec-workflow
description: "Stages → artifacts → agents mapping. What each stage produces. NOT for state machine — see spec-lifecycle."
---

# spec-workflow

Each of the 5 stages in a change produces a specific artifact (or pair), owned by a specific role. This skill is the contract that any agent picking up a stage follows. State transitions and bucket moves are not covered here — see `spec-lifecycle`.

## Pipeline

```
proposal.md ──► requirements.md ──► system-design.md      ──► roadmap.md ──► code + tests ──► gates
   (workflow)     (analyst)             + application-design.md     (teamlead)    (implementor)     (verifier)
                                       (architect)
```

Each downstream stage reads everything upstream + relevant `.spec/standards/*.md`.

## Stage 1 — `proposal.md`

| | |
|---|---|
| Owner | Workflow / initiator (user or `/backlog-add`) |
| Artifact | `proposal.md` |
| Lives at | `<change>/proposal.md` (scaffold-stub from `_template/`) |
| Required sections | `# <title>`, `## Intent` (1–3 paragraphs) |

The proposal is **incoming**. Keep it brief — problem + desired outcome. No requirements, no design, no tech. Subsequent stages expand.

## Stage 2 — `analysis` → `requirements.md`

| | |
|---|---|
| Owner | system-analyst agent (or generic Claude / human) |
| Artifact | `requirements.md` |
| Inputs | `proposal.md`, `.spec/standards/{project,glossary,…}.md`, project's own `docs/` if relevant |
| Required sections | `## Problem`, `## User stories`, `## Functional requirements`, `## Non-functional requirements`, `## Constraints`, `## Out of scope`, `## Open questions` |
| Side-effect | Set `scope:` field via `tracking-set-scope.sh <change-path> <product\|project\|feature\|bugfix> <by>` |
| Quality bar (need-approve) | All FR/NFR phrased with SHALL/MUST/SHOULD; all open questions answered or explicitly deferred; scope set |

**No tech.** No class names, no endpoints, no DB schemas. Business language only. If architect later says "this NFR is unimplementable", set `analysis: in-progress` again and revise.

## Stage 3 — `architecture` → `system-design.md` + `application-design.md`

| | |
|---|---|
| Owner | architect agent (or generic Claude / human) |
| Artifacts | `system-design.md` (C4 context+container), `application-design.md` (C4 component+code) |
| Inputs | `proposal.md`, `requirements.md`, `.spec/standards/{stack,architecture,anti-patterns}.md` |
| `system-design.md` sections | `## Components` (new/changed services), `## Contracts` (cross-service APIs, message schemas), `## Integrations`, `## Data flow`, `## Open questions` |
| `application-design.md` sections | `## Modules`, `## Key classes/interfaces`, `## Data models`, `## Patterns`, `## Open questions` |
| Quality bar (need-approve) | Both files present, no open questions, decisions traceable to a requirement |

If the change is purely internal (no new services / no integration changes), set `system-design.md` with a single `## Scope` note "no system-level impact" — do not skip the file unless the entire stage is set to `skipped`.

## Stage 4 — `decomposition` → `roadmap.md`

| | |
|---|---|
| Owner | teamlead agent (or generic Claude / human) |
| Artifact | `roadmap.md` |
| Inputs | All upstream + `.spec/standards/best-practices.md` |
| Format | See `spec-roadmap` skill (task headers + 5 bullet fields per task) |
| Quality bar (need-approve) | Every task has Estimate, Blockers, Assignee, State, Acceptance; Quality gates section present with at least one Q-task per project quality command |

`/track <name> decomposition approved` is the **plan approval gate**. Implementer agents start work only after this.

## Stage 5 — `implementation`

| | |
|---|---|
| Owner | code-implementor agent (or generic Claude / human) — one per task or grouped |
| Artifact | **no spec artifact** — only code in the project tree |
| Inputs | `roadmap.md` task entries, `requirements.md`, `system-design.md`, `application-design.md`, all relevant standards |
| Side-effect | Flip task state via `roadmap-set-task-state.sh <roadmap-path> <id> <state>` after the primary action (Write/Edit) of each task |
| Quality bar (need-approve) | All non-Q tasks `state: done` (or `rejected` with reason) |

When `implementation: in-progress` → change auto-moves to `sprint/`.

## Stage 6 — `verification`

| | |
|---|---|
| Owner | verifier agent (or generic Claude / human) |
| Artifact | **no spec artifact** — runs Quality gates from roadmap.md |
| Inputs | `roadmap.md` Q-tasks |
| Side-effect | Flip Q-task state via `roadmap-set-task-state.sh` only after the actual command exits green |
| Quality bar (need-approve) | All Q-tasks `state: done`. Any failure stays `pending` with diagnostic surfaced |

When `verification: approved` (with `implementation: approved|skipped`) → change auto-moves to `done/`.

## Back-edges

If a downstream stage discovers an upstream blocker:
- Set the upstream stage's state to `in-progress` (via `/track`). The state machine allows `approved → in-progress`.
- Owner of that stage re-does the work and re-submits via `need-approve`.
- History preserves the loop.

## When NOT to use

- State machine + bucket rules → `spec-lifecycle`.
- roadmap.md syntax + Quality gates format → `spec-roadmap`.
- Standards files + project context → `spec-standards`.
- Naming + tracking.yaml schema → `spec-conventions`.

## Anti-patterns

- Writing code before `decomposition: approved` — bypasses the planning gate.
- Mixing tech into `requirements.md` — locks architect into one approach.
- Skipping `need-approve` and going straight to `approved` — defeats human checkpoints (state machine allows it, but every stage owner should pause for review).
- Filling `roadmap.md` without Quality gates section — `verification` stage has nothing to run.
- Doing implementation directly in tracking.yaml or history.yaml — code lives in the project, not in `.spec/`.
