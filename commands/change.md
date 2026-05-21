---
name: change
description: "Change command. Bare = all-buckets list + actions. With text = LLM-scaffold new change in .spec/changes/backlog/."
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/tracking.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/roadmap.sh:*) Bash(grep:*) Bash(sort:*) Bash(head:*) Bash(tail:*) Bash(wc:*) Bash(test:*) Bash(ls:*) Read Write AskUserQuestion Task
---

Single entry point for `.spec/changes/`.

- **No args** → list all 4 buckets (backlog → in-progress → done → declined), top 3 per bucket. Offer drill-down + add-new + exit.
- **Free-form task text** → LLM-generate slug + title + description, scaffold new change in `backlog/`, write full task text to `propose.md`, offer to start work.

Every AskUserQuestion option is overridable via the auto-provided **Other** choice (free-form text).

This is the **only** user-facing slash command for `.spec/changes/` (besides `/setup`). All state setters that aren't user-driven (agent flips, internal moves) call `tracking.sh set-stage` and `change.sh move` directly via Bash — no slash command needed.

## Procedure

### Step 0 — Decide form

If `$ARGUMENTS` (trimmed) is empty → **Browse form** (Steps 1–4). Otherwise → **Add form** (Steps 6–10).

---

### Browse form

**Step 1 — Fetch + render all 4 buckets.**

For EACH bucket in this fixed order — `backlog`, `in-progress`, `done`, `declined` — do:

1. `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh list --bucket <b>`. TSV columns (11): `bucket name title status stage stage_state scope roadmap last_event_at last_event_pretty path`.
2. Sort rows by `last_event_at` (column 9) desc.
3. Capture row count `N_b`.
4. Take top **`PER_BUCKET_LIMIT = 3`** rows.

Render the bucket section. Format:

```
<bucket>:
<icon>  <title>  <last_event_pretty>
<icon>  <title>  <last_event_pretty>
<icon>  <title>  <last_event_pretty>
+ <N-3> more.
```

Rules:
- Header line is the bucket name + `:` (lowercase, no markdown).
- Each row: icon (one glyph) + **two spaces** + title + **two spaces** + `last_event_pretty` (column 10 from TSV — already formatted as `wednesday [10:30] [25 feb]`).
- If `last_event_pretty` is `—` (fresh scaffold, no history yet), drop the trailing ` <date>` — just print `<icon>  <title>`.
- If `N_b == 0`: print `  (empty)` on a single indented line under the header (still emit the header).
- If `N_b > PER_BUCKET_LIMIT`: append `+ <N_b - PER_BUCKET_LIMIT> more.` as the last line of that section.
- One blank line between bucket sections.

**Icon by status (TSV column 4):**

| status | icon | codepoint |
|---|---|---|
| `backlog` | `○` | U+25CB |
| `in-progress` | `●` | U+25CF |
| `done` | `✓` | U+2713 |
| `declined` | `⊗` | U+2297 |

For `declined` rows: read `decline_reason:` via `grep '^decline_reason:' <path>/tracking.yaml` and print as an indented second line `   reason: <text>` (3 spaces of indent).

**Example complete output:**

```
backlog:
○  Refactor user service  monday [10:30] [19 may]
○  Migrate Postgres 15  sunday [16:00] [18 may]
+ 4 more.

in-progress:
●  Add two-factor authentication via TOTP  wednesday [16:00] [21 may]
●  Fix login rate limit  tuesday [09:15] [20 may]

done:
✓  Upgrade Kotlin 2.1  friday [12:00] [16 may]

declined:
⊗  Bad idea
   reason: duplicate of add-2fa-totp
```

`PER_BUCKET_LIMIT` will become configurable later — for now hardcoded to 3.

**Step 2 — Build `DRILL_OPTIONS`.**

Collect top 4 names ACROSS ALL buckets by `last_event_at` desc (so the drill picker shows the most recently touched changes regardless of bucket). If total rows across all buckets = 0 → `DRILL_OPTIONS` is empty.

**Step 3 — Action menu.**

- **AskUserQuestion:** `"What next?"` (header `"Action"`):
  - `"Drill into a change"` — description: `"Pick a change to see details + take action."` (omit if `DRILL_OPTIONS` empty)
  - `"Add new change"` — description: `"Scaffold a new change in backlog/. Asks for task text."`
  - `"Exit"` — description: `"Done."`

- If `"Add new change"` → ask for task text via a single-question free-text AskUserQuestion (the user types into Other), set `TASK_TEXT`, jump to **Step 6**.
- If `"Exit"` → done.
- If `"Drill into a change"`:
  - **AskUserQuestion:** `"Which change?"` (header `"Change"`):
    - Show up to 4 names from `DRILL_OPTIONS` with description `"<icon>  <title>  ·  <stage>/<state>"`. Other = free-form name.
  - Set `CHANGE_NAME=<answer>`. Continue to Step 4.

**Step 4 — Drill into change.**

`Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh locate --name <CHANGE_NAME>` → `$CP`. On failure: report + loop back to Step 3.

`Read` `$CP/tracking.yaml`. Render (prefix with the status icon from the Step 1 table):
```
<icon> <CHANGE_NAME> — <title>
  status:  <status>          stage: <stage>
  scope:   <scope>           bucket: <bucket>

  refinement     <state>
  design         <state>
  decomposition  <state>
  implementation <state>
  verification   <state>
  termination    <state>

  last 5 history entries:
    <at>  <stage>  <status>  (by <by>)
    …
```

If `$CP/roadmap.md` exists → also call `roadmap.sh status --roadmap $CP/roadmap.md` and show one line.

**Context-aware action menu.** Based on the active stage (`stage:` field) and its state:

| state of current stage | Action options (4 max) |
|---|---|
| `estimation` | Mark required · Skip stage · Set scope · Decline |
| `required` | Start (in-progress) · Mark blocked (pending) · Skip stage · Decline |
| `pending` (blocked) | Resume (in-progress) · Re-evaluate (required) · Skip stage · Decline |
| `in-progress` | Send to review · Mark blocked (pending) · Reject · Skip stage |
| `review` | Approve (completed) · Send back (in-progress) · Reject · Decline |
| `completed` (next stage in `estimation`) | Start next stage · Rework current · Decline · Back |
| `rejected` | Restart (in-progress) · Re-mark required · Decline · Back |
| `skipped` | Reactivate (required) · Decline · Back |
| terminal (`done`/`declined` status) | Show propose.md · Show requirements · Show roadmap · Back |

- **AskUserQuestion** with relevant options. Each label = imperative phrase.

**Executing actions** — each is a sequence of Bash calls. Use `--by user` for human-initiated transitions.

- **Start (in-progress)** — refinement special case (system-analyst takes over):
  1. `tracking.sh set-stage --change $CP --stage refinement --state in-progress --by user`.
  2. **Invoke `system-analyst` agent** via Task tool: `subagent_type: "system-analyst"`, `description: "Refine <name>"`, `prompt: "Refine the change at <CP>. Read propose.md + tracking.yaml + .spec/standards/*.md. Run clarifying-questions loop. Set scope. Write requirements.md. Mark refinement: review. Report back with the structured 'Refinement draft' template."`.
- **Start (in-progress)** — other stages: `tracking.sh set-stage --change $CP --stage <current> --state in-progress --by user`. (Future phases will wire architect / teamlead / verifier / terminator agents here.)
- **Mark required**: `tracking.sh set-stage --change $CP --stage <current> --state required --by user`.
- **Mark blocked (pending)**: `tracking.sh set-stage --change $CP --stage <current> --state pending --by user`.
- **Resume (in-progress)** / **Re-evaluate (required)** / **Send back (in-progress)**: `tracking.sh set-stage --change $CP --stage <current> --state <target> --by user`.
- **Send to review**: `tracking.sh set-stage --change $CP --stage <current> --state review --by user`.
- **Approve (completed)**: `tracking.sh set-stage --change $CP --stage <current> --state completed --by user`. Then read back `tracking.sh derive-status`; if it differs from current bucket → `change.sh move --name <name> --to <new-status> --by auto`.
- **Reject**: `tracking.sh set-stage --change $CP --stage <current> --state rejected --by user`. Stays in current bucket — upstream stages must be reopened to resolve.
- **Skip stage**: `tracking.sh set-stage --change $CP --stage <current> --state skipped --by user`. Auto-move on status change.
- **Start next stage**: identify next stage (refinement → design → decomposition → implementation → verification → termination) whose state is `estimation` or `required`; `tracking.sh set-stage --change $CP --stage <next> --state in-progress --by user`. Auto-move if status flipped.
- **Set scope**: AskUserQuestion with options `product / project / feature / bugfix` → `tracking.sh set-scope --change $CP --scope <value> --by user`.
- **Decline**: prompt for reason (free text via AskUserQuestion Other), then `tracking.sh decline --change $CP --reason "<reason>" --by user` + `change.sh move --name <name> --to declined --by user`.
- **Show propose.md / roadmap / requirements**: `Read` the file and print.

After each action, re-render the change view (loop in Step 4) until user picks "Back" or "Exit".

---

### Add form

**Step 6 — Receive `TASK_TEXT`.**

If reached from Step 3 ("Add new change"), `TASK_TEXT` is the user's free-form answer. Otherwise `TASK_TEXT` = `$ARGUMENTS` verbatim. If `--name <slug>` is present, capture explicit slug override and strip from `TASK_TEXT`.

**Step 7 — LLM-generate slug + title + description.**

Thinking step. From `TASK_TEXT` produce:

- **`TITLE`** — single-line imperative phrase, up to ~120 chars.
- **`SLUG`** — kebab-case, 3-4 segments, matches `^[a-z][a-z0-9]*(-[a-z0-9]+)*$`. Use `--name` override if provided.
- **`DESCRIPTION`** — multi-line, up to ~500 chars (YAML `|`-literal block).

If `TASK_TEXT` ≤ 20 chars, reuse as TITLE and set DESCRIPTION to TITLE.

**Step 8 — Scaffold.**

`Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh new --title "<TITLE>" --name "<SLUG>" --description "<DESCRIPTION>"`. Pass multi-line DESCRIPTION in double quotes — `change.sh new` indents body lines under `description: |`. Capture stdout (absolute path) as `CP`.

- Exit 1 (collision / invalid) → if collision and no `--name` override, regenerate SLUG with an extra differentiating segment and retry once. After second failure → ask user for explicit slug.
- Exit 3 (template missing) → tell user to run `/foundry:setup` first. Exit.

**Step 9 — Inject `TASK_TEXT` into `propose.md`'s `## Intent` section.**

`Read` `$CP/propose.md`. The scaffold has three sections: `## Intent`, `## Context`, `## Notes`. Each starts with a `<!-- … -->` HTML comment as a placeholder.

Locate the `## Intent` section. Replace its placeholder comment with `TASK_TEXT` verbatim (multi-paragraph OK — keep blank lines as authored). **Leave `## Context` and `## Notes` sections untouched** — those are pre-refinement spaces for the user / system-analyst to fill.

Resulting structure:
```markdown
# <TITLE>

## Intent

<TASK_TEXT verbatim>

## Context

<!-- Background: what's currently happening, … -->

## Notes

<!-- Free-form space … -->
```

`Write` the result back.

Print:
```
/change (add):
  name:        <SLUG>
  title:       "<TITLE>"
  description: "<DESCRIPTION>"
  path:        <CP>
  status:      backlog
  stage:       refinement (all stages: estimation)
  propose.md:  written (<TASK_TEXT length> chars)
```

**Step 10 — Offer to start work.**

- **AskUserQuestion:** `"Start work now?"` (header `"Start work"`):
  - `"Yes — start refinement"` — description: `"refinement: estimation → in-progress. Stays in backlog/. Recommended for features."`
  - `"Yes — straight to implementation"` — description: `"implementation: estimation → in-progress. Auto-moves to in-progress/. Skips refinement/design/decomposition. Trivial bugfixes only."`
  - `"No — leave in backlog"` — description: `"All stages stay in estimation. Resume later via /change."`

- On `"start refinement"`:
  - `Bash`: `tracking.sh set-stage --change $CP --stage refinement --state in-progress --by user`.
  - **Invoke `system-analyst` agent** via Task tool (same invocation as Step 4 "Start (in-progress)" action for refinement). The agent runs the clarifying-questions loop, sets scope, writes `requirements.md`, marks `refinement: review`, and reports back.
  - Final (after agent returns): forward the agent's structured "Refinement draft" report to the user and append: `Next: user reviews requirements.md → /change → drill <name> → Approve (completed).`

- On `"straight to implementation"`:
  - `Bash`: `tracking.sh set-stage --change $CP --stage implementation --state in-progress --by user`.
  - `Bash`: `change.sh move --name <SLUG> --to in-progress --by auto`.
  - Final: `Started: implementation in-progress. status=in-progress (auto-moved) stage=implementation. Planning stages stayed in estimation.`

- On `"leave in backlog"`:
  - Final: `Left in backlog. Resume via /change.`

## Important

- Step 7 is purely LLM — `change.sh new` requires explicit `--name` and `--description`.
- Step 9 writes the full original task text verbatim into `propose.md`.
- "Straight to implementation" intentionally skips planning. Risky for features.
- For free-form names supplied via Other, validate via `change.sh locate` (must resolve to exactly one dir).
- This is the only command that scaffolds, lists, or mutates `.spec/changes/`. Stage setters are invoked from drill-down (Step 4) or directly via Bash by agents.
