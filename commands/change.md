---
name: change
description: "Change command. Bare = interactive (pick bucket → list → drill → actions). With text = LLM-scaffold new change in .spec/changes/backlog/."
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/tracking.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/roadmap.sh:*) Bash(grep:*) Bash(sort:*) Bash(head:*) Bash(tail:*) Bash(wc:*) Bash(test:*) Bash(ls:*) Read Write AskUserQuestion
---

Single entry point for working with `.spec/changes/`. Branches on argument presence.

- **No args** → pick a bucket (backlog / in-progress / done / declined) or add new. Show table. Optionally drill into a change for stage actions.
- **Free-form task text** → LLM-generate slug + title + description, scaffold new change in `backlog/`, write full task text to `propose.md`, offer to start work.

Every AskUserQuestion option is overridable via the auto-provided **Other** choice (free-form text).

This is the **only** user-facing slash command for `.spec/changes/` (besides `/setup`). All state setters that aren't user-driven (agent flips, internal moves) call `tracking.sh set-stage` and `change.sh move` directly via Bash — no slash command needed.

## Procedure

### Step 0 — Decide form

If `$ARGUMENTS` (trimmed) is empty → **Browse form** (Steps 1–5). Otherwise → **Add form** (Steps 6–10).

---

### Browse form

**Step 1 — Pick bucket.**

- **AskUserQuestion:** `"Which bucket to inspect?"` (header `"Bucket"`):
  - `"backlog"` — description: `"Not yet picked up. refinement/design/decomposition active or pending."`
  - `"in-progress"` — description: `"Actively worked on. implementation/verification/termination running."`
  - `"closed"` — description: `"done/ + declined/. Read-only history."`
  - `"add new"` — description: `"Skip browsing; scaffold a new change instead."`

- If `"add new"` → ask for task text (single-question prompt — accept free text via Other only), assign to `TASK_TEXT`, jump to **Step 6**.
- If `"closed"` → set `BUCKET_LIST="done declined"`, skip to Step 2 (list both).
- Otherwise → set `BUCKET_LIST="<picked>"`.

**Step 2 — Fetch + render table.**

For each bucket in `BUCKET_LIST`:

`Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh list --bucket <b>`. TSV columns: `bucket name title status stage stage_state scope roadmap last_event_at path`. Sort by `last_event_at` desc (column 9), keep top 10. Capture row count `N`.

If `N=0`:
- Print `<b>/ is empty.`
- Skip to Step 4.

Else render markdown table:
```
| Name | Title | Stage | State | Scope | Last event |
|---|---|---|---|---|---|
| add-2fa-totp | Add two-factor authentication via TOTP | refinement | need-approve | feature | 2026-05-21 16:00 |
```

If `N > 10`, append: `+ <N-10> more.`

For `declined/` rows, also surface `decline_reason:` via `grep '^decline_reason:' <path>/tracking.yaml`.

**Step 3 — Build candidate name list.**

Collect top 4 names across all listed buckets (by last_event_at desc) as `DRILL_OPTIONS`. If `N=0` → empty list, skip Step 4 drill option.

**Step 4 — Ask follow-up.**

- **AskUserQuestion:** `"What next?"` (header `"Action"`):
  - `"Drill into a change"` — description: `"Pick one to see stage history + take action. Skipped if list is empty."` (omit if empty)
  - `"Switch bucket"` — description: `"Pick a different bucket to inspect."`
  - `"Add new change"` — description: `"Scaffold a new change in backlog/."`
  - `"Exit"` — description: `"Done."`

- If `"Switch bucket"` → loop to Step 1.
- If `"Add new change"` → ask for task text via single-question free-text prompt → Step 6.
- If `"Exit"` → done.
- If `"Drill into a change"`:
  - **AskUserQuestion:** `"Which change?"` (header `"Change"`):
    - Show up to 4 names from `DRILL_OPTIONS` with description `"Title: <title> · stage: <stage>/<state>"`. Other = free-form name.
  - Set `CHANGE_NAME=<answer>`. Continue to Step 5.

**Step 5 — Drill into change.**

`Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh locate --name <CHANGE_NAME>` → `$CP`. On failure: report + loop back to Step 4.

`Read` `$CP/tracking.yaml`. Render:
```
<CHANGE_NAME> — <title>
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

**Context-aware action menu.** Based on current `stage:` field and its state:

| current `stage` / state | Action options (4 max) |
|---|---|
| `none` (all pending) | Start refinement · Set scope · Decline · Back |
| `<X>` `in-progress` | Mark need-approve · Pause · Skip stage · Back |
| `<X>` `need-approve` | Approve (advance) · Send back (rework) · Decline · Back |
| `<X>` `approved` (next stage pending) | Start next stage · Rework current · Decline · Back |
| `<X>` `pause` | Resume · Skip stage · Decline · Back |
| terminal (`done`/`declined`) | Show propose.md · Show roadmap · Show requirements · Back |

- **AskUserQuestion** with relevant options. Each label = imperative phrase ("Mark need-approve", "Send back", etc.).

**Executing actions** — each is a sequence of Bash calls. Use `--by user` for human-initiated transitions.

- **Start refinement**: `tracking.sh set-stage --change $CP --stage refinement --state in-progress --by user`.
- **Mark need-approve**: `tracking.sh set-stage --change $CP --stage <current> --state need-approve --by user`.
- **Approve (advance)**: `tracking.sh set-stage --change $CP --stage <current> --state approved --by user`. Then if status changed (read back via `tracking.sh derive-status`) and differs from bucket → `change.sh move --name <name> --to <new-status> --by auto`.
- **Send back (rework)**: `tracking.sh set-stage --change $CP --stage <current> --state in-progress --by user`.
- **Pause**: `tracking.sh set-stage --change $CP --stage <current> --state pause --by user`.
- **Resume**: `tracking.sh set-stage --change $CP --stage <current> --state in-progress --by user`.
- **Skip stage**: `tracking.sh set-stage --change $CP --stage <current> --state skipped --by user`. Auto-move on status change.
- **Start next stage**: identify next pending stage in order (refinement → design → decomposition → implementation → verification → termination); `tracking.sh set-stage --change $CP --stage <next> --state in-progress --by user`. Auto-move if status flipped.
- **Set scope**: AskUserQuestion with options `product / project / feature / bugfix` → `tracking.sh set-scope --change $CP --scope <value> --by user`.
- **Decline**: prompt for reason (free text via single AskUserQuestion or Other), then `tracking.sh decline --change $CP --reason "<reason>" --by user` + `change.sh move --name <name> --to declined --by user`.
- **Show propose.md / roadmap / requirements**: `Read` the file and print.

After each action, re-render the change view (loop in Step 5) until user picks "Back" or "Exit".

---

### Add form

**Step 6 — Receive `TASK_TEXT`.**

If reached from Step 1/4, `TASK_TEXT` is the user's free-form answer. Otherwise `TASK_TEXT` = `$ARGUMENTS` verbatim. If `--name <slug>` is present, capture explicit slug override and strip from `TASK_TEXT`.

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

**Step 9 — Write `propose.md` with full task text.**

`Read` `$CP/propose.md` (scaffold contains only `# <TITLE>\n`). `Write` it back as:

```markdown
# <TITLE>

## Intent

<TASK_TEXT verbatim, may be multi-paragraph>
```

Print:
```
/change (add):
  name:        <SLUG>
  title:       "<TITLE>"
  description: "<DESCRIPTION>"
  path:        <CP>
  status:      backlog
  stage:       none
  propose.md:  written (<TASK_TEXT length> chars)
```

**Step 10 — Offer to start work.**

- **AskUserQuestion:** `"Start work now?"` (header `"Start work"`):
  - `"Yes — start refinement"` — description: `"refinement → in-progress. Stays in backlog/. Recommended for features."`
  - `"Yes — straight to implementation"` — description: `"implementation → in-progress. Auto-moves to in-progress/. Skips refinement/design/decomposition. Trivial bugfixes only."`
  - `"No — leave in backlog"` — description: `"All stages stay pending. Resume later via /change."`

- On `"start refinement"`:
  - `Bash`: `tracking.sh set-stage --change $CP --stage refinement --state in-progress --by user`.
  - Final: `Started: refinement in-progress. status=backlog stage=refinement. Next: write requirements.md → /change → drill → Mark need-approve.`

- On `"straight to implementation"`:
  - `Bash`: `tracking.sh set-stage --change $CP --stage implementation --state in-progress --by user`.
  - `Bash`: `change.sh move --name <SLUG> --to in-progress --by auto`.
  - Final: `Started: implementation in-progress. status=in-progress (auto-moved) stage=implementation. Planning stages stayed pending.`

- On `"leave in backlog"`:
  - Final: `Left in backlog. Resume via /change.`

## Important

- Step 7 is purely LLM — `change.sh new` requires explicit `--name` and `--description`.
- Step 9 writes the full original task text verbatim into `propose.md`.
- "Straight to implementation" intentionally skips planning. Risky for features.
- For free-form names supplied via Other, validate via `change.sh locate` (must resolve to exactly one dir).
- This is the only command that scaffolds, lists, or mutates `.spec/changes/`. Stage setters are invoked from drill-down (Step 5) or directly via Bash by agents.
