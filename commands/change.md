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

If `$ARGUMENTS` (trimmed) is empty → **Browse form** (Steps 1–6, loops in Step 5 / Step 6). Otherwise → **Add form** (Steps 7–11).

---

### Browse form

This form is a **tabbed UI** that loops until the user exits. State across iterations: `CURRENT_TAB` (default `"All"`). On every loop iteration: re-fetch counts, render tab header, render the current tab's list, ask the action menu.

**Step 1 — Fetch counts (every iteration).**

`Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh list` (no `--bucket` flag — emits TSV across all 4 buckets). TSV columns (11): `bucket name title status stage stage_state scope roadmap last_event_at last_event_pretty path`.

Compute counts:
- `N_backlog` = rows with col 1 = `backlog`
- `N_in_progress` = rows with col 1 = `in-progress`
- `N_done` = rows with col 1 = `done`
- `N_declined` = rows with col 1 = `declined`
- `N_closed` = `N_done + N_declined`
- `N_all` = total rows

**Step 2 — Render tab header.**

Print one line, with the active tab wrapped in `**…**` (markdown bold). Use ` · ` as separator. Use the literal names below — no other variations.

```
Tabs: **All [N_all]** · backlog [N_backlog] · in-progress [N_in_progress] · closed [N_closed]
```

Always exactly 4 tabs in this fixed order: `All`, `backlog`, `in-progress`, `closed`. (Note: `closed` combines `done + declined`.) Bold only the active tab; leave the others plain.

**Step 3 — Render list for the current tab.**

Pick rows for the current tab:
- `All` → all rows, sort by `last_event_at` (col 9) desc.
- `backlog` → rows with col 1 = `backlog`, sorted desc.
- `in-progress` → rows with col 1 = `in-progress`, sorted desc.
- `closed` → rows with col 1 ∈ `{done, declined}`, sorted desc.

Take top `TAB_LIMIT = 10`. Capture `N_tab` (rows in current tab).

If `N_tab = 0`:
- Print `  (empty)`.
- Skip to Step 4.

Else render as plain list, with status column aligned. Format per row:

```
<icon>  <status_padded>  <title>  <last_event_pretty>
```

Rules:
- `<icon>` = one glyph from the table below (selected by col 4 `status`).
- `<status_padded>` = TSV col 4 (`backlog | in-progress | done | declined`) padded with **right-side spaces** to width **11** (longest is `in-progress`). Example: `done       ` (4 chars + 7 spaces).
- Two spaces between each piece.
- `<last_event_pretty>` = TSV col 10 — already formatted as `[thursday, 21:56] [21 may]`.
- If `last_event_pretty` is `—` (fresh scaffold, no history), drop the trailing ` <date>` — just `<icon>  <status_padded>  <title>`.
- For `declined` rows: read `decline_reason:` via `grep '^decline_reason:' <path>/tracking.yaml` and print as a second line indented to align under the title column (15 spaces of indent), prefixed by `reason:`.
- After the last row, if `N_tab > TAB_LIMIT`: append `... and <N_tab - TAB_LIMIT> more in <CURRENT_TAB>.`

**Icon by status (TSV col 4):**

| status | icon | codepoint |
|---|---|---|
| `backlog` | `○` | U+25CB |
| `in-progress` | `●` | U+25CF |
| `done` | `✓` | U+2713 |
| `declined` | `⊗` | U+2297 |

**Example output (All tab, 12 items total):**

```
Tabs: **All [12]** · backlog [4] · in-progress [3] · closed [5]

●  in-progress  Add two-factor authentication via TOTP  [thursday, 21:56] [21 may]
●  in-progress  Tune login rate limit                   [thursday, 21:55] [21 may]
✓  done         Upgrade Kotlin 2.1                      [thursday, 12:00] [16 may]
⊗  declined     Refactor user service                   [thursday, 21:35] [21 may]
               reason: duplicate of larger refactor
○  backlog      Migrate Postgres 15                     [sunday, 16:00] [18 may]
... and 2 more in All.
```

**Step 4 — Build `DRILL_OPTIONS`.**

Top 4 names FROM THE CURRENT TAB's rows (already sorted desc), so the drill picker reflects what the user is currently looking at. Empty if `N_tab = 0`.

**Step 5 — Action menu.**

- **AskUserQuestion:** `"What next?"` (header `"Action"`):
  - `"Switch tab"` — description: `"Pick a different tab (All / backlog / in-progress / closed)."`
  - `"Drill into a change"` — description: `"Pick a change from the current tab to see details + take action."` (omit if `DRILL_OPTIONS` empty)
  - `"Add new change"` — description: `"Scaffold a new change in backlog/. Asks for task text."`
  - `"Exit"` — description: `"Done."`

Branch:

- **Switch tab** → nested AskUserQuestion `"Which tab?"` (header `"Tab"`):
  - `"All"` — `"All changes across every bucket [<N_all>]."`
  - `"backlog"` — `"Not yet picked up [<N_backlog>]."`
  - `"in-progress"` — `"Implementation / verification / termination active [<N_in_progress>]."`
  - `"closed"` — `"done + declined combined [<N_closed>]."`

  Set `CURRENT_TAB` to the answer (or to the literal Other free-text if user typed one), then loop back to Step 1.

- **Add new change** → ask for task text via a single free-text AskUserQuestion (Other only), set `TASK_TEXT`, jump to **Step 7** (Add form).

- **Exit** → stop the loop.

- **Drill into a change**:
  - **AskUserQuestion:** `"Which change?"` (header `"Change"`):
    - Show up to 4 names from `DRILL_OPTIONS` with description `"<icon>  <title>  ·  <stage>/<state>"`. Other = free-form name.
  - Set `CHANGE_NAME=<answer>`. Continue to **Step 6** (Drill).

**Step 6 — Drill into change.**

`Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh locate --name <CHANGE_NAME>` → `$CP`. On failure: report + loop back to Step 5.

`Read` `$CP/tracking.yaml`. Render (prefix with the status icon from Step 3):
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

After each action, re-render the change view (loop in Step 6) until user picks "Back" (return to browse loop, Step 1) or "Exit" (stop entirely).

---

### Add form

**Step 7 — Receive `TASK_TEXT`.**

If reached from Step 5 ("Add new change"), `TASK_TEXT` is the user's free-form answer. Otherwise `TASK_TEXT` = `$ARGUMENTS` verbatim. If `--name <slug>` is present, capture explicit slug override and strip from `TASK_TEXT`.

**Step 8 — LLM-generate slug + title + description.**

Thinking step. From `TASK_TEXT` produce:

- **`TITLE`** — single-line imperative phrase, up to ~120 chars.
- **`SLUG`** — kebab-case, 3-4 segments, matches `^[a-z][a-z0-9]*(-[a-z0-9]+)*$`. Use `--name` override if provided.
- **`DESCRIPTION`** — multi-line, up to ~500 chars (YAML `|`-literal block).

If `TASK_TEXT` ≤ 20 chars, reuse as TITLE and set DESCRIPTION to TITLE.

**Step 9 — Scaffold.**

`Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh new --title "<TITLE>" --name "<SLUG>" --description "<DESCRIPTION>"`. Pass multi-line DESCRIPTION in double quotes — `change.sh new` indents body lines under `description: |`. Capture stdout (absolute path) as `CP`.

- Exit 1 (collision / invalid) → if collision and no `--name` override, regenerate SLUG with an extra differentiating segment and retry once. After second failure → ask user for explicit slug.
- Exit 3 (template missing) → tell user to run `/foundry:setup` first. Exit.

**Step 10 — Inject `TASK_TEXT` into `propose.md`'s `## Intent` section.**

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

**Step 11 — Offer to start work.**

- **AskUserQuestion:** `"Start work now?"` (header `"Start work"`):
  - `"Yes — start refinement"` — description: `"refinement: estimation → in-progress. Stays in backlog/. Recommended for features."`
  - `"Yes — straight to implementation"` — description: `"implementation: estimation → in-progress. Auto-moves to in-progress/. Skips refinement/design/decomposition. Trivial bugfixes only."`
  - `"No — leave in backlog"` — description: `"All stages stay in estimation. Resume later via /change."`

- On `"start refinement"`:
  - `Bash`: `tracking.sh set-stage --change $CP --stage refinement --state in-progress --by user`.
  - **Invoke `system-analyst` agent** via Task tool (same invocation as Step 6 "Start (in-progress)" action for refinement). The agent runs the clarifying-questions loop, sets scope, writes `requirements.md`, marks `refinement: review`, and reports back.
  - Final (after agent returns): forward the agent's structured "Refinement draft" report to the user and append: `Next: user reviews requirements.md → /change → drill <name> → Approve (completed).`

- On `"straight to implementation"`:
  - `Bash`: `tracking.sh set-stage --change $CP --stage implementation --state in-progress --by user`.
  - `Bash`: `change.sh move --name <SLUG> --to in-progress --by auto`.
  - Final: `Started: implementation in-progress. status=in-progress (auto-moved) stage=implementation. Planning stages stayed in estimation.`

- On `"leave in backlog"`:
  - Final: `Left in backlog. Resume via /change.`

## Important

- Step 8 is purely LLM — `change.sh new` requires explicit `--name` and `--description`.
- Step 10 writes the full original task text verbatim into `propose.md`.
- "Straight to implementation" intentionally skips planning. Risky for features.
- For free-form names supplied via Other, validate via `change.sh locate` (must resolve to exactly one dir).
- This is the only command that scaffolds, lists, or mutates `.spec/changes/`. Stage setters are invoked from drill-down (Step 6) or directly via Bash by agents.
- `TAB_LIMIT = 10` is hardcoded in Step 3. Will become configurable later.
