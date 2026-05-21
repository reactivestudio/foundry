# foundry-plugin — Claude Code Plugin for Palantir Foundry

> **⚠ Status: aspirational vision document.**
> Most of what follows describes an unbuilt Palantir Foundry–oriented plugin
> (orchestrator agent, skill-resolver, conflict-resolver, ADR loop, Foundry MCP, …)
> that has never been implemented in this repository.
>
> The **current** `foundry` plugin (v0.13.0) is a Kotlin / Spring Boot engineer's toolkit.
> See [README.md](./README.md) for installed commands. The actually-shipping `.spec/`
> subsystem is summarised in the [Current `.spec/` subsystem](#current-spec-subsystem-v0130)
> section below; the rest of this file is roadmap material kept for reference.

---

## Current `.spec/` subsystem (v0.13.0)

A change in `.spec/changes/` flows through 4 bucket directories (`backlog/`, `in-progress/`, `done/`, `declined/`) and 6 stages (`refinement`, `design`, `decomposition`, `implementation`, `verification`, `termination`), each with its own state from an 8-element set: `estimation | required | skipped | pending | in-progress | review | completed | rejected`.

### State machine (per stage)

```
estimation ──→ required ──→ in-progress ──→ review ──→ completed
   │              │     ↑      │   ↑           │            │
   │              ▼     │      ▼   │           ▼            ▼
   │           pending ─┘   pending └──── in-progress    rejected (← from anywhere; resume via upstream-fix)
   │              │  (blocked)
   ▼              ▼
skipped ◄────────────────── (any non-terminal state, when stage is unnecessary)
```

- `estimation` = initial; decide if the stage is needed.
- `required` = needed, not yet started.
- `pending` = needed and started, but currently blocked.
- `in-progress` = active work.
- `review` = artifact ready, awaiting user / peer approval.
- `completed` = approved (terminal-for-stage).
- `skipped` = decided not needed (terminal-for-stage).
- `rejected` = unrealizable as scoped; needs upstream stages revisited.

### Status derivation (auto)

Top-level `status:` mirrors the bucket and is derived from impl/verif/term states + decline_reason.

| Condition | Status / Bucket |
|---|---|
| `decline_reason:` field present | `declined` (terminal) |
| `implementation ∈ {estimation, required}` | `backlog` (impl not yet active) |
| All of `{implementation, verification, termination}` ∈ {completed, skipped} | `done` |
| otherwise | `in-progress` |

Once `implementation` leaves `{estimation, required}`, the change cannot return to `backlog`. `pending` (blocked) and `rejected` both keep status `in-progress`. `tracking.sh sync` rewrites both `status:` and `stage:` fields on every state mutation.

Top-level `stage:` is the first stage (in canonical order) whose state is **not** in `{completed, skipped}`; `none` if all stages are terminal (typical of a `done` change).

### YAML schema is flat

Stage values live as top-level keys in `tracking.yaml` — there is no nested `stages:` block. Order convention: `refinement` → `design` → `decomposition` → `implementation` → `verification` → `termination`. Both `status:` and `stage:` are derived and resynced on every write.

### Artifacts (filled by agents)

| Stage | Artifact | Owner role |
|---|---|---|
| (initial) | `tracking.yaml` + `propose.md` | `/change "<task text>"` (LLM scaffold) |
| refinement | `requirements.md` | system-analyst |
| design | `system-design.md` + `application-design.md` | architect |
| decomposition | `roadmap.md` | teamlead |
| implementation | code in project tree | code-implementor |
| verification | (runs Quality gates from roadmap.md) | verifier |
| termination | post-merge follow-up (docs, announce, deploy confirm) | role TBD |

`/change` is **state API only** — it does not generate domain content (except scaffolding `tracking.yaml` + `propose.md` and LLM-generating the slug/title/description from the original task text). Per-stage artifacts are written by agents.

### Commands (2 + setup)

| Command | Form | Purpose |
|---|---|---|
| `/change` | bare or `<bucket>` | Read-only tabbed browse: `All` / `backlog` / `in-progress` / `closed`. Each row: status icon · status · title (hard-cap 50) · created (pretty) · updated (relative) · progress (quartile-circle + `[done/total]`). No modal menu; navigate via `/change <arg>`. |
| `/change <slug>` | with slug | Drill into a change → context-aware action menu (start, send to review, approve, reject, skip, decline, set scope). All manual state mutations happen here. |
| `/change "<task text>"` | with text | LLM-generate slug (3-4 segments) + title + description. Scaffold in backlog. Write full task text to `propose.md`. Prompt for "Start work now?" |
| `/workflow <name>` | with slug | Orchestration loop. Reads active stage + state, delegates to the producer agent for that stage via Task tool, runs review-preview + AskUserQuestion (approve / rework / reject / pause), advances to next stage on approve. Implementation stage iterates roadmap tasks (1 per invocation). |
| `/foundry:setup` | — | Scaffold `.spec/` (4 buckets + standards/ + .template/) and project `.claude/`. |

There are no `/track`, `/in-progress`, `/closed`, `/done-list`, `/accept`, `/decline` commands — everything folds into `/change` (manual) or `/workflow` (orchestrator). Auto-move: `change.sh move` is invoked by the `/change` drill flow + by producer agents via `tracking.sh set-stage` (which syncs status). Agents that drive state directly call `tracking.sh set-stage` via Bash.

### Bash helpers (4 dispatch scripts in `scripts/spec/`)

| Script | Subcommands |
|---|---|
| `stage-state-machine.sh` | `validate --from <s> --to <s>`, `states`, `allowed-from --state <s>` |
| `tracking.sh` | `get-stage`, `set-stage`, `get-scope`, `set-scope`, `derive-status`, `derive-stage`, `sync` (= `sync-status` alias), `decline`, `append-history` (all with `--change <path>` + topic-specific flags) |
| `roadmap.sh` | `parse`, `status`, `ready`, `set-task-state` (all with `--roadmap <path>` + topic-specific flags) |
| `change.sh` | `validate-name`, `locate`, `new` (requires `--title --name --description`), `move`, `list` |
| `workflow.sh` | `producer --stage <s>`, `artifact --stage <s>`, `next-action --change <path>`, `stages` — lookup helpers backing `/workflow` (single source of truth for stage→agent table) |

All pure-bash, portable awk (no gawk extensions, no `yq` dep). Named-flag args throughout. The flat `tracking.yaml` schema is the contract these helpers depend on — see `skills/spec/conventions/SKILL.md`.

### Role agents (all shipped as of v0.13.0)

| Stage | Producer agent | Inputs | Output artifact(s) |
|---|---|---|---|
| refinement | `system-analyst` | `propose.md` + standards | `requirements.md` |
| design | `architect` | `requirements.md` + standards | `system-design.md` + `application-design.md` |
| decomposition | `teamlead` | requirements + designs | `roadmap.md` (main + Q tasks) |
| implementation | `code-implementor` (per task) | one `roadmap.md` task spec | code + tests |
| verification | `qa-engineer` | `roadmap.md` Q-tasks + code | `verification-report.md` |
| termination | `termination-handler` | full change context | `termination.md` + `CHANGELOG.md` append |

Every producer follows the same 7-step hand-off contract (see `spec-workflow` skill): read inputs → set stage `in-progress` → write artifact → set stage `review` → return structured report → stop. Producers do NOT call other agents — composition is the `/workflow` orchestrator's job.

### Skills

- `spec-workflow` — orchestration paradigm: stage→producer map, hand-off contract, state-branch logic
- `spec-lifecycle` — state machine + status/stage derivation
- `spec-conventions` — directory layout, naming, flat tracking.yaml schema
- `spec-standards` — long-lived project rules (`.spec/standards/*.md`)
- `spec-roadmap` — roadmap.md task syntax + Quality gates
- `spec-refinement` — FR/NFR taxonomy, scope categorisation, requirements.md schema
- `spec-design` — system-design.md + application-design.md schemas, patterns vocabulary
- `spec-decomposition` — atomicity rules, blocker DAG, Q-gate taxonomy
- `spec-verification` — Q-task categories + execution patterns, verification-report.md schema
- `spec-termination` — changelog conventions, migration notes, cleanup checklist

---

## Legacy vision (unimplemented — kept for reference)

## Table of contents

- [Overview](#overview)
- [Architecture](#architecture)
  - [Three-layer model](#three-layer-model)
  - [Orchestrator — who is it?](#orchestrator--who-is-it)
  - [Skill-resolver vs conflict-resolver](#skill-resolver-vs-conflict-resolver)
  - [Workflow lifecycle](#workflow-lifecycle)
  - [The implement loop](#the-implement-loop)
- [Plugin structure](#plugin-structure)
- [Commands reference](#commands-reference)
- [Agents reference](#agents-reference)
- [Skills reference](#skills-reference)
- [Spec documents](#spec-documents)
- [Hooks reference](#hooks-reference)
- [MCP servers](#mcp-servers)
- [Naming conventions](#naming-conventions)
- [Top 30 feature roadmap](#top-30-feature-roadmap)
- [Getting started](#getting-started)
- [Configuration](#configuration)

---

## Overview

This plugin is built around one core idea: **Claude Code is the runtime, not the brain**.
Claude Code knows how to read files, run bash, spawn subagents, and call MCP tools.
It does not know about your Foundry project, your ontology design principles, or your team conventions.

This plugin supplies that knowledge through three artifact types:

| Artifact | Naming | Purpose |
|---|---|---|
| **skill** | noun (`solid`, `adr`, `osdk`) | Declarative knowledge — what to know |
| **agent** | role (`reviewer`, `architect`) | Behavioural role — how to act |
| **command** | verb (`review`, `implement`, `design`) | Workflow — what to do and in what order |

Spec documents (`SPEC.md`, `STACK.md`, `ARCH.md`, …) are the live project memory that connects all three.

---

## Architecture

### Three-layer model

```
┌─────────────────────────────────────────────────────────┐
│  Layer 1 — Commands (verbs)                             │
│  /implement  /review  /design  /audit  /init  /migrate  │
│  Orchestrate agents. Describe workflow explicitly.      │
└───────────────────────┬─────────────────────────────────┘
                        │ spawns
┌───────────────────────▼─────────────────────────────────┐
│  Layer 2 — Agents (roles)                               │
│  orchestrator  architect  reviewer  implementor          │
│  skill-resolver  conflict-resolver  migrator             │
│  Know which skills to load. Apply knowledge explicitly. │
└───────────────────────┬─────────────────────────────────┘
                        │ loads
┌───────────────────────▼─────────────────────────────────┐
│  Layer 3 — Skills (nouns)                               │
│  solid  clean-code  adr  osdk  ontology-design           │
│  ddd  performance  foundry-branching  aip-logic          │
│  Static knowledge. May conflict. Version-controlled.    │
└─────────────────────────────────────────────────────────┘
                        ▲
                        │ feeds all layers
┌───────────────────────┴─────────────────────────────────┐
│  Spec documents (live project memory)                   │
│  SPEC.md  STACK.md  ARCH.md  STYLE.md  CONVENTIONS.md   │
│  ADR-log.md                                             │
│  Read by orchestrator at every SessionStart.            │
└─────────────────────────────────────────────────────────┘
```

### Orchestrator — who is it?

`orchestrator` is **our custom agent** (`agents/orchestrator.md`), not Claude Code itself.

Claude Code is the execution platform — it can run subagents, read files, execute bash, call MCP.
It does not know about your Foundry project, roles, or spec documents.

`orchestrator` is a markdown prompt that tells Claude Code *how to think* in the role of conductor:
read the specs, select agents, run them in the right order, control the loop.

```
Claude Code runtime              ← Anthropic's platform; executes instructions
    └── orchestrator agent       ← our custom "session brain"; knows the project
            ├── reads SPEC.md, STACK.md, ARCH.md
            ├── calls skill-resolver
            └── spawns other agents as subagents
```

The orchestrator itself writes no code. It coordinates.

### Skill-resolver vs conflict-resolver

These are two distinct agents with different responsibilities.

**`skill-resolver`** — fast, deterministic utility:
- Reads the task description + `STACK.md`
- Returns `{ skills, agents, conflicts }` as strict JSON
- Checks `ADR-log.md` — if a conflict was resolved before, it is automatically applied
- Does **not** interact with the user

**`conflict-resolver`** — interactive, decision-making agent:
- Receives a conflict pair from skill-resolver
- Analyses the semantic tension between the two skills
- Presents five options to the user:
  1. Prioritise skill A
  2. Prioritise skill B
  3. Apply both with a compromise rule
  4. Ignore both in this context
  5. Write an ADR and let the decision stand forever
- If the user picks "write ADR", conflict-resolver creates `ADR-NNN.md` and appends to `ADR-log.md`
- Future sessions with the same conflict skip the interactive step and apply the ADR automatically

```
skill-resolver
  → reads task + STACK.md
  → returns { skills, agents, conflicts }
  → if conflicts not empty
      → checks ADR-log.md
          → if ADR exists: apply automatically
          → if not: call conflict-resolver
              → user picks option
              → if ADR chosen: write ADR-NNN.md
```

### Workflow lifecycle

Every command follows this five-stage lifecycle:

```
1. parse      reads SPEC.md, STACK.md, ARCH.md; understands the task
     ↓
2. resolve    skill-resolver returns { skills, agents, conflicts }
              conflict-resolver handles any conflicts (interactive or ADR)
     ↓
3. dispatch   orchestrator spawns agents with the resolved skill set
              agents run in command-defined order
     ↓
4. loop       implementor → reviewer → feedback → implementor (repeat)
              exit on "approved" or after max iterations
     ↓
5. commit     drift-detector hook checks code vs SPEC.md
              conventional git commit message is proposed
```

### The implement loop

The loop lives in `commands/implement.md` and is expressed as structured text, not code.
Claude Code reads it and executes it.

```
LOOP (iteration = 1, max = 3):

  feedback = ""  if iteration == 1
           = reviewer.feedback  otherwise

  run agent: implementor
    inputs: (resolved_skills, design_doc, feedback)

  run agent: reviewer
    inputs: (resolved_skills, implementor.output)

  IF reviewer.status == "approved"
    → EXIT LOOP

  IF reviewer.status == "needs_changes" AND iteration < 3
    → iteration += 1 → repeat

  IF iteration == 3
    → show user reviewer.issues
    → ask: continue / abort / override
```

The reviewer always returns **strict JSON**, not markdown prose:

```json
{
  "status": "approved | needs_changes",
  "score": 8,
  "issues": [
    {
      "file": "transforms/my_transform.py",
      "line": 42,
      "skill": "solid",
      "rule": "Single Responsibility Principle",
      "severity": "major",
      "suggestion": "Split into two classes: DataLoader and DataValidator"
    }
  ],
  "feedback": "Brief summary for implementor to act on"
}
```

The implementor, on subsequent iterations, fixes **only** the flagged issues.
It does not refactor anything the reviewer did not flag.

---

## Plugin structure

```
foundry-plugin/
│
├── .claude-plugin/
│   └── plugin.json              # manifest: name, version, wires everything together
│
├── commands/                    # verbs — orchestrate agents, describe workflow
│   ├── implement.md
│   ├── review.md
│   ├── design.md
│   ├── audit.md
│   ├── init.md
│   ├── migrate.md
│   └── visualize.md
│
├── agents/                      # roles — know which skills to load, how to apply them
│   ├── orchestrator.md
│   ├── architect.md
│   ├── reviewer.md
│   ├── implementor.md
│   ├── migrator.md
│   ├── skill-resolver.md
│   └── conflict-resolver.md
│
├── skills/                      # nouns — static knowledge, may conflict
│   ├── solid.md
│   ├── clean-code.md
│   ├── adr.md
│   ├── osdk.md
│   ├── ontology-design.md
│   ├── ddd.md
│   ├── performance.md
│   ├── foundry-branching.md
│   └── aip-logic.md
│
├── hooks/
│   ├── session-start.sh         # SessionStart: load specs, resolve skill set
│   ├── post-edit-drift.sh       # PostToolUse: check code vs SPEC.md after edits
│   └── pre-commit-validate.sh   # PreToolUse: validate action types, permissions
│
├── mcp/
│   └── server.js                # MCP server: Foundry REST API adapter
│                                # tools: get_lineage, get_build_status, list_datasets
│
└── specs/                       # templates — copy to project root on /init
    ├── SPEC.md.template
    ├── STACK.md.template
    ├── ARCH.md.template
    ├── STYLE.md.template
    ├── CONVENTIONS.md.template
    └── ADR-log.md.template
```

---

## Commands reference

Commands are named as **verbs**. They describe a complete workflow: which agents to run, in what order, what skills to load, what the loop condition is, and what gates require user input.

| Command | Workflow | Key agents | Gate |
|---|---|---|---|
| `/init` | wizard → generate all spec docs → wire SessionStart hook | architect | user confirms each spec |
| `/implement` | parse → resolve → design → loop(implementor+reviewer) → commit | orchestrator, architect, implementor, reviewer | design approve; loop exit |
| `/review` | load skills → reviewer → structured report | reviewer | — |
| `/design` | architect → ARCH.md + ADR draft | architect, conflict-resolver | user approve |
| `/audit` | governance check → ontology risks → drift report | reviewer, architect | — |
| `/migrate` | OSv1→OSv2 plan → script → Foundry branch → proposal | migrator, architect | user approve plan |
| `/visualize` | fetch lineage via MCP/API → render DAG in terminal | lineage-fetcher, lineage-analyst | — |

### Example: `commands/implement.md`

```markdown
---
name: implement
description: Implements a task via orchestrator → agents → loop
---

## Step 1 — parse
Read SPEC.md, STACK.md, ARCH.md.
Task: $ARGUMENTS

## Step 2 — resolve skills
Run agent skill-resolver with the task.
Receive: { skills, agents, conflicts }
If conflicts and no ADR exists → run conflict-resolver, await user decision.

## Step 3 — design
Run agent architect with resolved skills.
Present design_doc to user.
STOP — await approve or revision from user.

## Step 4 — implement loop
LOOP (iteration = 1, max = 3):
  Run agent implementor with (skills, design_doc, reviewer_feedback)
  Run agent reviewer with (skills, implementor.output)
  IF reviewer.status == "approved" → EXIT LOOP
  IF reviewer.status == "needs_changes" AND iteration < 3 → iteration++ → repeat
  IF iteration == 3 → show issues, ask user

## Step 5 — commit
Trigger drift-detector hook.
Propose: git commit -m "feat(foundry): ..."
```

---

## Agents reference

Agents are named as **roles**. They know which skills to load, how to apply them, and what format to return.

### `orchestrator`

The session brain. Reads all spec documents at start. Calls skill-resolver. Spawns other agents in the order defined by the active command. Controls the loop. Does not write code.

### `architect`

Designs solutions. Loads `ddd`, `adr`, `ontology-design`, `solid` from the resolved skill set.
Applies ADR format: context → decision → consequences → alternatives.
Writes or updates `ARCH.md`. Creates ADR draft files.

### `reviewer`

Code review specialist. Loads `solid`, `clean-code`, `performance` (and others from resolved set).
Applies skills in fixed order: correctness → design → performance → conventions.
**Always returns strict JSON** — never markdown prose. This allows the loop to be deterministic.

### `implementor`

Code writer. Reads `ARCH.md`, `STYLE.md`, `CONVENTIONS.md`. Loads `osdk`, `clean-code`, `solid`, `foundry-branching`.
On first iteration: builds from design_doc.
On subsequent iterations: fixes only issues flagged by reviewer. Does not refactor unflagged code.
After each file, writes: `Applied: solid/SRP, clean-code/naming`.

### `skill-resolver`

Fast utility. Reads task + `STACK.md`. Returns `{ skills, agents, conflicts }` as JSON.
Checks `ADR-log.md` before flagging a conflict — if an ADR exists, applies it silently.
Contains a `CONFLICT_MATRIX` of known incompatible skill pairs.

```
CONFLICT_MATRIX = {
  "solid":          conflicts_with: ["performance"],
  "ontology-design":conflicts_with: ["ddd"],
  "clean-code":     conflicts_with: [],
  "adr":            conflicts_with: [],
  "osdk":           conflicts_with: [],
}
```

### `conflict-resolver`

Interactive. Receives a conflict pair. Analyses the semantic tension.
Presents five options, waits for user input:

1. Prioritise skill A
2. Prioritise skill B
3. Compromise (apply both with a scoping rule, e.g. "SOLID on module boundaries, performance inside hot paths")
4. Ignore both in this context
5. Write ADR — decision persists in all future sessions

If option 5 is chosen, creates `ADR-NNN.md` and appends to `ADR-log.md`.

### `migrator`

Foundry migration specialist. Handles OSv1 → OSv2 object type migration, schema drift, transform refactoring.
Loads `osdk`, `ontology-design`, `adr`. Generates migration script + Foundry Branching proposal.

---

## Skills reference

Skills are named as **nouns**. They describe knowledge. They can declare dependencies and known conflicts.

| Skill | Depends on | Conflicts with | Foundry relevance |
|---|---|---|---|
| `solid` | `clean-code` | `performance` | TypeScript/Python transforms, OSDK functions |
| `clean-code` | — | — | transform naming, dataset conventions |
| `adr` | — | — | all architectural decisions |
| `osdk` | — | — | object types, action types, functions, serverless |
| `ontology-design` | — | `ddd` | object types, link types, OSv2 patterns |
| `ddd` | — | `ontology-design` | bounded contexts, aggregates |
| `performance` | — | `solid` | lightweight pipelines, compute pushdown, virtual tables |
| `foundry-branching` | — | — | branch workflow, proposals, approval flow |
| `aip-logic` | — | — | AIP Logic files, LLM-backed workflows, AIP Evals |

### Skill dependency resolution

Skills declare `requires: []`. When a skill is activated, its dependencies are activated transitively.

```
clean-code is selected
  → no requires
solid is selected
  → requires: [clean-code]
  → clean-code already active → no-op
```

### Skill loading modes

Each skill supports two loading modes to manage token budget:

| Mode | Size | When used |
|---|---|---|
| `summary` | ~300 tokens | orchestrator initial pass, conflict detection |
| `full` | ~2000 tokens | agent active task execution |

The agent requests the appropriate mode based on its current task.

---

## Spec documents

Spec documents are the live project memory. They are generated by `/init` and maintained by agents.
The `SessionStart` hook loads them automatically at the start of every Claude Code session.

| File | Owner | Content |
|---|---|---|
| `SPEC.md` | `/init` + all agents | project overview, goals, constraints, active skills |
| `STACK.md` | `/init` + architect | languages, Foundry features, external integrations, active skill set |
| `ARCH.md` | architect | architectural decisions, ontology structure, data lineage |
| `STYLE.md` | `/init` + implementor | code style, formatters, naming conventions for transforms and OSDK |
| `CONVENTIONS.md` | `/init` + all agents | git workflow, directory structure, Foundry-specific agreements |
| `ADR-log.md` | conflict-resolver + architect | index of all ADRs with dates, statuses, and conflict pairs |

### `STACK.md` example

```markdown
# Stack

## languages
- Python 3.11 (transforms, functions)
- TypeScript 5 (OSDK apps, Workshop)

## foundry features
- Pipeline Builder (primary ETL)
- Ontology SDK v2
- Foundry Branching
- AIP Logic
- Marketplace

## active skills
- solid
- clean-code
- osdk
- ontology-design
- foundry-branching

## external integrations
- Databricks (via virtual tables + external pipelines)
```

---

## Hooks reference

| Hook | Event | Purpose |
|---|---|---|
| `session-start.sh` | `SessionStart` | Load all spec docs into session context; run skill-resolver for current working directory |
| `post-edit-drift.sh` | `PostToolUse` | After any file edit, check if changed transform is in known lineage; warn about downstream impact; compare code against SPEC.md |
| `pre-commit-validate.sh` | `PreToolUse` | Before git commit or Foundry branch push: validate action types, check permissions, scan for hardcoded secrets in transforms |

### Drift detection logic

The `post-edit-drift.sh` hook compares the changed file against `ARCH.md` and `SPEC.md`.
If the change introduces a pattern not described in the spec (e.g. a new dependency direction, a new object type reference), it prints a warning:

```
⚠ Drift detected: transforms/load_orders.py references object type
  "DeliveryRoute" which is not described in ARCH.md.
  Update ARCH.md or revert? [u]pdate / [r]evert / [i]gnore
```

---

## MCP servers

### `foundry-lineage-mcp` (`mcp/server.js`)

Wraps Foundry REST API v2. Provides lineage data to agents without browser access.

**Tools exposed:**

| Tool | Description |
|---|---|
| `get_lineage` | Returns upstream/downstream RIDs for a resource. Falls back to Compass API if lineage API unavailable. |
| `get_build_status` | Returns current build status and last successful build time for a dataset or transform. |
| `list_datasets` | Lists datasets in a project folder with name, RID, and staleness indicator. |

**Required environment variables:**

```
FOUNDRY_HOST=your-enrollment.palantirfoundry.com
FOUNDRY_TOKEN=your-oauth-token
FOUNDRY_LINEAGE_DEPTH=3   # optional, default 2
```

> **Note:** As of May 2026, Foundry's Workflow Lineage data is not exposed via a public REST API or public MCP tool.
> The `get_lineage` tool reconstructs lineage by traversing the Compass and Datasets APIs —
> it gives upstream/downstream dataset connections but not the full Workflow Lineage graph.
> A [community request](https://community.palantir.com/t/expose-resource-lineage-as-a-public-api/6496)
> to expose `GET /api/v2/resources/{rid}/lineage` as a public endpoint is open.
> When Palantir ships it, update `mcp/server.js` to call that endpoint directly.

---

## Naming conventions

These conventions apply to all plugin components:

| Component | Convention | Examples |
|---|---|---|
| commands | imperative verb | `implement`, `review`, `design`, `audit`, `init`, `migrate` |
| agents | role noun | `reviewer`, `architect`, `implementor`, `migrator`, `orchestrator` |
| skills | domain noun | `solid`, `clean-code`, `adr`, `osdk`, `ontology-design` |
| hooks | `{event}-{purpose}` | `session-start`, `post-edit-drift`, `pre-commit-validate` |
| spec docs | `UPPER.md` | `SPEC.md`, `STACK.md`, `ARCH.md` |
| ADRs | `ADR-NNN-{slug}.md` | `ADR-001-solid-vs-performance.md` |

---

## Top 30 feature roadmap

Grouped by category. Items marked 🔥 are considered highest-value (killer features).

### Ontology

| # | Feature | Type | Status |
|---|---|---|---|
| 1 | Ontology scaffold generator 🔥 | command | planned |
| 2 | Ontology diff & migration agent 🔥 | agent | planned |
| 3 | OSDK type-safe query builder | skill | planned |
| 4 | Action type validator | hook (PreToolUse) | planned |
| 5 | OSv2 migration assistant 🔥 | agent | planned |

### Pipelines

| # | Feature | Type | Status |
|---|---|---|---|
| 6 | Pipeline Builder reviewer | command | planned |
| 7 | Lightweight pipeline optimizer 🔥 | agent | planned |
| 8 | Transform TDD enforcer | hook (PostToolUse) | planned |
| 9 | Virtual tables architect | skill | planned |
| 10 | Media set pipeline builder | command | planned |
| 28 | Databricks external pipeline generator | command | planned |

### Developer experience

| # | Feature | Type | Status |
|---|---|---|---|
| 11 | VS Code ↔ Foundry sync 🔥 | hook (SessionStart) | planned |
| 12 | Foundry branching workflow 🔥 | command | planned |
| 13 | OSDK app deployer | agent | planned |
| 14 | Python functions scaffolder | command | planned |
| 15 | Token optimizer | hook (Stop) | planned |
| 26 | Security sweep (Foundry-aware) | hook (PreToolUse) | planned |
| 30 | Developer growth analyzer | skill | planned |

### Architecture

| # | Feature | Type | Status |
|---|---|---|---|
| 16 | Solution architecture reviewer 🔥 | agent | planned |
| 17 | Workflow lineage visualizer 🔥 | command | in progress |
| 18 | Multi-enrollment peering designer | skill | planned |
| 19 | Marketplace product packager | agent | planned |
| 20 | Data model governance audit | command | planned |
| 27 | Cross-stack deployment planner | agent | planned |

### AIOps / AIP

| # | Feature | Type | Status |
|---|---|---|---|
| 21 | AIP Logic orchestrator agent 🔥 | agent | planned |
| 22 | AI FDE session hook 🔥 | hook (SubagentStart) | planned |
| 23 | Workflow Lineage observability MCP 🔥 | MCP server | in progress |
| 24 | Automate trigger designer | command | planned |
| 25 | AIP cost optimizer | hook (PostToolUse) | planned |
| 29 | Foundry MCP context manager | MCP server | planned |

### Architecture ideas (backlog)

| # | Idea | Notes |
|---|---|---|
| B1 | conflict-resolver as ADR-writing agent | Semantic conflict analysis → ADR-NNN.md |
| B2 | Spec as live versioned document | `/init` → SPEC.md; SessionStart hook auto-loads |
| B3 | Skill dependency graph | `requires: []` in skill frontmatter; transitive resolution |
| B4 | Context budget manager | Skills have `summary` / `full` modes; agents choose |
| B5 | Spec drift detector | PostToolUse hook: code vs SPEC.md; warn before commit |
| B6 | Stack selector wizard | `/select-stack` interactive wizard; loads matching skills |

---

## Getting started

### 1. Install the plugin

```bash
/plugin install https://github.com/your-org/foundry-plugin
```

### 2. Set environment variables

```bash
export FOUNDRY_HOST=your-enrollment.palantirfoundry.com
export FOUNDRY_TOKEN=your-oauth-token
```

### 3. Initialise your project

Run `/init` in your project root. The wizard will ask about:
- Stack (languages, Foundry features, external integrations)
- Active skills for this project
- Paradigms and architectural constraints
- Code style and conventions

It generates: `SPEC.md`, `STACK.md`, `ARCH.md`, `STYLE.md`, `CONVENTIONS.md`, `ADR-log.md`.

### 4. Start working

```bash
/implement "add DeliveryRoute object type to the ontology"
/review
/design "redesign ingestion pipeline for Databricks virtual tables"
/audit
/visualize ri.foundry.main.dataset.c26f11c8-...
/migrate "migrate CustomerOrder from OSv1 to OSv2"
```

---

## Configuration

`plugin.json` wires all components together. Key fields:

```json
{
  "name": "foundry-plugin",
  "version": "1.0.0",
  "config": {
    "required": ["FOUNDRY_HOST", "FOUNDRY_TOKEN"],
    "optional": ["FOUNDRY_LINEAGE_DEPTH"]
  },
  "skills": [...],
  "commands": [...],
  "agents": [...],
  "hooks": [...],
  "mcpServers": [...]
}
```

Per-project skill activation lives in `STACK.md` under `## active skills`.
The `SessionStart` hook reads this list and passes it to skill-resolver at the start of every session.
Skills not listed are not loaded — this keeps context lean for projects that don't need the full set.

---

## Contributing

1. New **skills** go in `skills/` — noun filename, declare `requires` and `conflicts` in frontmatter
2. New **agents** go in `agents/` — role filename, describe which skills they load and what JSON they return
3. New **commands** go in `commands/` — verb filename, describe the full workflow step by step
4. Any new **conflict pair** must be added to `CONFLICT_MATRIX` in `agents/skill-resolver.md`
5. Resolved conflicts must produce an ADR in `ADR-log.md`
