---
name: change
description: "Change command. Bare = All-tab list (read-only print). Args: bucket name, slug, or free-form text for scaffold."
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/tracking.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/roadmap.sh:*) Bash(grep:*) Bash(sort:*) Bash(head:*) Bash(tail:*) Bash(wc:*) Bash(test:*) Bash(ls:*) Read Write AskUserQuestion Task
---

Single entry point for `.spec/changes/`. The **browse view is read-only** — it prints a tabbed list and a usage-hint footer, no interactive menu. Navigation between tabs / drill / scaffold happens via subsequent `/change <arg>` invocations.

## Argument routing

`/change` dispatches on `$ARGUMENTS` (trimmed):

| Argument | Form |
|---|---|
| (empty) | **Browse** the `All` tab |
| `all`, `backlog`, `in-progress`, `closed` | **Browse** that tab |
| any token that resolves via `change.sh locate --name <token>` (exit 0) | **Drill** into that change |
| anything else | **Add** — scaffold a new change from the free-form task text |

ESC (or just sending the next message) ends the command — there is no modal loop in browse. Drill keeps a small action menu for stage transitions.

## Procedure

### Step 0 — Decide form

1. Read `$ARGUMENTS`, trim whitespace, store as `ARG`.
2. If `ARG` is empty → set `CURRENT_TAB="All"`, go to **Browse** (Steps 1–4).
3. If `ARG` ∈ `{all, backlog, in-progress, closed}` (case-insensitive, normalised) → set `CURRENT_TAB="<arg>"`, go to **Browse**.
4. Else attempt `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh locate --name "<ARG>"` (single token only — strip surrounding whitespace, do **not** split on whitespace). If exit 0 → set `CHANGE_NAME=<ARG>`, go to **Drill** (Step 5).
5. Else → set `TASK_TEXT=<ARG>`, go to **Add** (Step 6).

`locate` returns exit 1 (not found) → fall through to Add. Don't show the error; the missing-slug case is a legitimate scaffold trigger.

---

### Browse form

Read-only. Print the tab header, the current tab's list, and a usage-hint footer. **No AskUserQuestion** — no modal prompt. The user navigates by issuing another `/change <arg>` (or natural language).

**Step 1 — Fetch counts (every iteration).**

`Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh list` (no `--bucket` flag — emits TSV across all 4 buckets). TSV columns (13): `bucket name title status stage stage_state scope progress created_at created_pretty updated_at updated_rel path`.

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

Pick + sort rows:
- `All` → all rows, sort by **bucket-priority then `updated_at` desc**. Bucket priority: `backlog=0`, `in-progress=1`, `done=2`, `declined=3`. Implementation: iterate the 4 buckets in this fixed order, sort each by `updated_at` desc, concatenate, then take top 10.
- `backlog` / `in-progress` → single-bucket filter, sort by `updated_at` (col 11) desc.
- `closed` → bucket-priority order (`done` first, then `declined`), `updated_at` desc within each. Then take top 10.

Capture `N_tab` after filtering, before truncating to `TAB_LIMIT = 10`.

If `N_tab = 0`:
- Print `  (empty)`.
- Skip to Step 4.

Else render as a plain list. Each row has 6 visual segments:

```
<icon>  <status_padded>  <title_padded>  <created_padded>  <updated_rel_padded>  <progress>
```

Rules:
- `<icon>` = one glyph from the table below (selected by col 4 `status`).
- `<status_padded>` = TSV col 4, right-padded to width **11**.
- `<title_padded>` = TSV col 3, **hard-capped to 50 visible chars**. If longer than 50: take first 49 chars and append `…` (U+2026). Then right-pad to **exactly 50**. No exceptions — alignment must hold for every row.
- `<created_padded>` = TSV col 10 (`created_pretty`), right-padded to width **27**.
- `<updated_rel_padded>` = TSV col 12 (`updated_rel`), right-padded to width **12** (longest realistic: `[365 d ago]` = 12 chars).
- `<progress>` = rendered from TSV col 8 (`progress` = `"done/total"`). See rendering rules below. Last column → no padding.
- Two spaces between each segment.
- For `declined` rows: read `decline_reason:` via `grep '^decline_reason:' <path>/tracking.yaml` and print as a second line indented **16 spaces** (aligns under the title column), prefixed by `reason:`.
- After the last row, if `N_tab > TAB_LIMIT`: append `... and <N_tab - TAB_LIMIT> more in <CURRENT_TAB>.`

**Progress rendering rules** (from `"done/total"`):
- Parse `done` and `total` as integers (`"0/0"` → done=0, total=0).
- Pick the quartile-circle icon by completion percentage:

  | condition | icon | meaning |
  |---|---|---|
  | `done == 0` | `○` (U+25CB) | nothing done |
  | `0 < pct ≤ 37`  | `◔` (U+25D4) | ~quarter |
  | `37 < pct ≤ 62` | `◑` (U+25D1) | ~half |
  | `62 < pct < 100` | `◕` (U+25D5) | ~three-quarter |
  | `done == total` (and total > 0) | `●` (U+25CF) | full |

  Where `pct = done * 100 / total` (integer division). Always show the icon, including for `0/0` (renders as `○ [0/0]`).
- Format: `<icon> [<done>/<total>]` — icon, single space, bracketed counts.
- Examples: `0/0 → ○ [0/0]`, `1/4 → ◔ [1/4]`, `5/10 → ◑ [5/10]`, `7/10 → ◕ [7/10]`, `8/8 → ● [8/8]`.

**Status icons (TSV col 4):**

| status | icon | codepoint |
|---|---|---|
| `backlog` | `○` | U+25CB |
| `in-progress` | `●` | U+25CF |
| `done` | `✓` | U+2713 |
| `declined` | `⊗` | U+2297 |

(Yes, the `○` / `●` glyphs are reused in both the status column and the progress column. Position disambiguates: status is column 2, progress is the last column.)

**Example output (All tab, 12 items total — bucket-priority order):**

```
Tabs: **All [12]** · backlog [4] · in-progress [3] · closed [5]

○  backlog      Migrate Postgres 15                                 [sunday, 16:00] [18 may]    [3 d ago]     ○ [0/0]
○  backlog      Add metrics across the whole project                [thursday, 22:41] [21 may]  [5 min ago]   ○ [0/0]
●  in-progress  Add two-factor authentication via TOTP              [tuesday, 09:00] [19 may]   [12 min ago]  ◔ [3/12]
●  in-progress  Tune login rate limit                               [tuesday, 14:30] [19 may]   [2 h ago]     ◔ [5/21]
✓  done         Upgrade Kotlin 2.1                                  [friday, 10:00] [16 may]    [5 d ago]     ● [8/8]
⊗  declined     Refactor user service                               [thursday, 21:30] [21 may]  [4 min ago]   ○ [0/0]
                reason: duplicate of larger refactor
... and 6 more in All.
```

**Step 4 — Render footer hints.**

Print one blank line, then a single one-line footer summarising the user's next moves:

```
Hint: /change <bucket>  switch tab  ·  /change <name>  drill in  ·  /change "<text>"  scaffold new
```

`<bucket>` = one of `all | backlog | in-progress | closed`. `<name>` = any change slug. **No AskUserQuestion** — the command ends after this line. The user re-invokes `/change` with the desired argument (or just sends a normal message).

**Step 5 — Drill into change.**

`Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh locate --name <CHANGE_NAME>` → `$CP`. On failure: report and stop (the user can re-invoke `/change` to browse the list).

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

After each action, re-render the change view (loop in Step 5) until user picks "Back" / "Done" — then stop. The user can return to the list by re-invoking `/change`.

---

### Add form

**Step 6 — Receive `TASK_TEXT`.**

`TASK_TEXT` is the free-form text passed to `/change` (Step 0 routed here because the arg didn't match a tab name or existing slug). If `--name <slug>` is present in the text, capture it as an explicit slug override and strip from `TASK_TEXT`.

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
  - **Invoke `system-analyst` agent** via Task tool (same invocation as Step 5 "Start (in-progress)" action for refinement). The agent runs the clarifying-questions loop, sets scope, writes `requirements.md`, marks `refinement: review`, and reports back.
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
- For free-form names supplied via Other in drill action prompts, validate via `change.sh locate` (must resolve to exactly one dir).
- This is the only command that scaffolds, lists, or mutates `.spec/changes/`. Stage setters are invoked from drill-down (Step 5) or directly via Bash by agents.
- `TAB_LIMIT = 10` is hardcoded in Step 3. Will become configurable later.
