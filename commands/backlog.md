---
name: backlog
description: "Backlog command. Bare = interactive list (top 10 + actions). With title = scaffold + offer to start work."
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/tracking.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/roadmap.sh:*) Bash(grep:*) Bash(sort:*) Bash(head:*) Bash(wc:*) Bash(test:*) Read AskUserQuestion
---

Interactive backlog command. Branches on argument presence:

- **No args** → list current backlog (top 10 + count), then interactively offer follow-ups (move to sprint / show sprint / show closed).
- **No args + empty backlog** → show empty table, then interactively offer to add a task with example titles.
- **With title** → scaffold new change, then interactively offer to start work right away.

Every AskUserQuestion option in this command can be answered with a free-form custom value via the auto-provided "Other" choice.

## Procedure

### Step 0 — Decide form

If `$ARGUMENTS` (after trimming) is empty → **List form** (Steps 1–4). Otherwise → **Add form** (Steps 5–7).

### List form

**Step 1 — Fetch backlog.**
`Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh list --bucket backlog`. Output is TSV with columns `bucket name active_stage active_stage_state scope roadmap last_event_at path`. Capture row count as `N`.

**Step 2a — Empty backlog (N=0).**
- Print: `backlog/ is empty.`
- **AskUserQuestion:** `"Backlog is empty. Add a task? (Pick an example, or type your own via Other.)"`
  - Options (header `"New task"`):
    - `"Add 2FA"` — description: `"Example: short title for a feature. Replace with anything via Other."`
    - `"Fix login rate limit"` — description: `"Example: bugfix-style title."`
    - `"Refactor user service"` — description: `"Example: refactor-style title."`
    - `"Skip — exit"` — description: `"Don't add anything. Exit."`
- If user picked an example or supplied a custom title via Other → set `TITLE=<chosen>` and **jump to Step 5** (treat as Add form).
- If user picked Skip → print `Backlog still empty. Run /backlog "<title>" to add a task anytime.` and exit.

**Step 2b — Non-empty backlog (N≥1).**

`Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh list --bucket backlog | sort -t$'\t' -k7,7r | head -10` — top 10 by `last_event_at` desc.

Render markdown table:
```
| Name | Active stage | State | Scope | Roadmap | Last event |
|---|---|---|---|---|---|
| add-2fa | analysis | need-approve | feature | — | 2026-05-20 16:00 |
...
```

If `N > 10`, append a line: `+ <N-10> more. Run /track <name> for full detail on any change.`

**Step 3 — Ask follow-up.**
- **AskUserQuestion:** `"What next?"` (header `"Action"`):
  - `"Move task(s) to sprint"` — description: `"Pick one or more changes to start implementation. Auto-moves to sprint/."`
  - `"Show sprint"` — description: `"Display the sprint table (changes in active implementation/verification)."`
  - `"Show closed"` — description: `"Display recent done/ and declined/ changes."`
  - `"Done"` — description: `"Exit. No further action."`

**Step 4 — Branch on answer.**

#### 4a. "Move task(s) to sprint"

- Take up to top 4 backlog names (by last_event_at desc) as candidate options.
- **AskUserQuestion (`multiSelect: true`):** `"Which task(s) to move to sprint? (Pick from list, or type names via Other — comma-separated for multiple.)"` (header `"Tasks"`):
  - `"<top1-name>"` — description: `"Active stage: <stage> · scope: <scope>"`
  - `"<top2-name>"` — description: `"Active stage: <stage> · scope: <scope>"`
  - `"<top3-name>"` — description: `"Active stage: <stage> · scope: <scope>"`
  - `"<top4-name>"` — description: `"Active stage: <stage> · scope: <scope>"`
  - (Auto-provided Other lets the user type any name, including comma-separated ones outside the top 4.)

- For each selected name `n`:
  1. `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh locate --name <n>` → `CP`. On exit 1/2 → record failure, continue with rest.
  2. `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/tracking.sh set-stage --change $CP --stage implementation --state in-progress --by user`. On exit 1 (invalid transition — e.g. already approved) → record failure.
  3. The set-stage call internally triggers derive-bucket → if it returns `sprint` (it will), the `/track` setter pattern would call `change.sh move`. **For this command, do it explicitly:** `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh move --name <n> --to sprint --by auto`.

- Final report:
  ```
  /backlog (move):
    moved to sprint:  <list of successful names>
    failed:           <list with diagnostic> (omit line if all succeeded)
    next: /sprint to see active changes, or /track <name> for detail
  ```

#### 4b. "Show sprint"

`Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh list --bucket sprint`. Render same 6-column table as `/sprint` does. Exit.

#### 4c. "Show closed"

`Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh list --bucket done` and `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh list --bucket declined`. Render two sub-tables (Done + Declined). For declined rows: `Bash`: `grep '^decline_reason:' <path>/tracking.yaml` per row to surface the reason. Exit.

#### 4d. "Done"

Print `OK.` and exit.

---

### Add form

**Step 5 — Parse args.**
Everything that isn't `--name <slug>` joins into `TITLE` (preserve spaces). If `--name <slug>` flag present, capture explicit slug override. (If reached from Step 2a, `TITLE` was already set there.)

**Step 6 — Scaffold.**
`Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh new --title "<TITLE>" [--name <slug>]`. Captures absolute path `CP`.
- Exit 1 (collision / invalid name) → relay diagnostic and exit.
- Exit 3 (template missing) → ask user to run `/setup` first; exit.

Print scaffold info:
```
/backlog (add):
  name:  <derived-name>
  title: "<TITLE>"
  path:  <CP>
  scope: <empty — analyst will set>
  stages: analysis=pending architecture=pending decomposition=pending implementation=pending verification=pending
```

**Step 7 — Offer to start work.**
- **AskUserQuestion:** `"Start work now?"` (header `"Start work"`):
  - `"Yes — start analysis"` — description: `"Set analysis to in-progress. Stays in backlog. Recommended for features."`
  - `"Yes — straight to sprint (skip planning)"` — description: `"Set implementation to in-progress. Auto-moves to sprint/. Skips analysis/architecture/decomposition. Use for trivial bugfixes."`
  - `"No — leave in backlog"` — description: `"Leave all stages pending. Resume later via /backlog or /track."`

- On `"start analysis"`:
  - `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/tracking.sh set-stage --change $CP --stage analysis --state in-progress --by user`.
  - Final report: `Started: analysis in-progress. Bucket: backlog (still). Next: agent writes requirements.md → /track <name> analysis need-approve.`

- On `"straight to sprint"`:
  - `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/tracking.sh set-stage --change $CP --stage implementation --state in-progress --by user`.
  - `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh move --name <derived-name> --to sprint --by auto`.
  - Final report: `Started: implementation in-progress. Bucket: backlog → sprint (auto-moved). Note: analysis/architecture/decomposition stayed pending — you skipped planning.`

- On `"leave in backlog"`:
  - No-op. Final report: `Left in backlog. Resume anytime with /backlog or /track <name>.`

## Important

- Step 4a's "move to sprint" intentionally skips planning stages (analysis/architecture/decomposition stay `pending`). The user has chosen to fast-track this change. Acceptable for tiny fixes; risky for features.
- "Other" is auto-provided for every AskUserQuestion in this command — users can always type custom titles or names.
- For comma-separated names in the multi-select Other field, split on `,`, trim whitespace, validate each.
- If `multiSelect: true` returns no selections (user cancelled), record as "No selection — nothing moved" and exit cleanly.
- This command is the **only** way to currently scaffold a change. There is no `/backlog-add` legacy alias.
