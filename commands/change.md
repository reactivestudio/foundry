---
name: change
description: "Change command. Bare = interactive list (top 10 + actions). With text = LLM-scaffold new change in .spec/changes/backlog/."
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/tracking.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/roadmap.sh:*) Bash(grep:*) Bash(sort:*) Bash(head:*) Bash(wc:*) Bash(test:*) Read Write AskUserQuestion
---

Interactive change command — single entry point for working with `.spec/changes/`. Branches on argument presence:

- **No args** → list current backlog (top 10 + count), then interactively offer follow-ups.
- **No args + empty backlog** → show empty table, then interactively offer to add a task.
- **With free-form task text** → LLM-generate slug + short description, scaffold new change in `backlog/`, write full task text to `propose.md`, then offer to start work.

Every AskUserQuestion option can be answered with a free-form custom value via the auto-provided "Other" choice.

## Procedure

### Step 0 — Decide form

If `$ARGUMENTS` (after trimming) is empty → **List form** (Steps 1–4). Otherwise → **Add form** (Steps 5–9).

---

### List form

**Step 1 — Fetch backlog.**
`Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh list --bucket backlog`. Output is TSV with columns `bucket name title active_stage active_stage_state scope roadmap last_event_at path`. Capture row count as `N`.

**Step 2a — Empty backlog (N=0).**
- Print: `backlog/ is empty.`
- **AskUserQuestion:** `"Backlog is empty. Add a task? (Pick an example, or type your own task text via Other.)"`
  - Options (header `"New task"`):
    - `"Add 2FA"` — description: `"Example title."`
    - `"Fix login rate limit"` — description: `"Example bugfix-style title."`
    - `"Refactor user service"` — description: `"Example refactor-style title."`
    - `"Skip — exit"` — description: `"Don't add. Exit."`
- If user picked an example or supplied custom text via Other → set `TASK_TEXT=<chosen>` and **jump to Step 5** (Add form).
- If Skip → print `Backlog still empty. Run /change "<text>" to add a task anytime.` and exit.

**Step 2b — Non-empty backlog (N≥1).**

`Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh list --bucket backlog | sort -t$'\t' -k8,8r | head -10` — top 10 by `last_event_at` desc (column 8).

Render markdown table:
```
| Name | Title | Active stage | State | Scope | Last event |
|---|---|---|---|---|---|
| add-2fa-totp | Add two-factor authentication via TOTP | refinement | need-approve | feature | 2026-05-21 16:00 |
...
```

If `N > 10`, append: `+ <N-10> more. Run /track <name> for detail on any change.`

**Step 3 — Ask follow-up.**
- **AskUserQuestion:** `"What next?"` (header `"Action"`):
  - `"Move task(s) to in-progress"` — description: `"Pick one or more changes to start implementation. Auto-moves to in-progress/."`
  - `"Show in-progress"` — description: `"Display the in-progress table."`
  - `"Show closed"` — description: `"Display recent done/ and declined/."`
  - `"Done"` — description: `"Exit. No further action."`

**Step 4 — Branch on answer.**

#### 4a. "Move task(s) to in-progress"

- Take top 4 backlog names (by last_event_at desc) as candidate options.
- **AskUserQuestion (`multiSelect: true`):** `"Which task(s) to move? (Pick from list, or type names via Other — comma-separated.)"` (header `"Tasks"`):
  - `"<top1-name>"` — description: `"Title: <title> · scope: <scope>"`
  - `"<top2-name>"` — description: `"Title: <title> · scope: <scope>"`
  - `"<top3-name>"` — description: `"Title: <title> · scope: <scope>"`
  - `"<top4-name>"` — description: `"Title: <title> · scope: <scope>"`

- For each selected name `n`:
  1. `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh locate --name <n>` → `CP`. On exit 1/2 → record failure, continue.
  2. `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/tracking.sh set-stage --change $CP --stage implementation --state in-progress --by user`. On exit 1 (invalid transition) → record failure.
  3. `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh move --name <n> --to in-progress --by auto`.

- Final report:
  ```
  /change (move):
    moved to in-progress: <list of successful names>
    failed:               <list with diagnostic>  (omit line if all succeeded)
    next: /in-progress to see active changes, /track <name> for detail
  ```

#### 4b. "Show in-progress"

`Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh list --bucket in-progress`. Render 6-column table same as `/in-progress` does. Exit.

#### 4c. "Show closed"

`Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh list --bucket done` and `--bucket declined`. Render two sub-tables. For declined rows: `grep '^decline_reason:' <path>/tracking.yaml` to surface reason. Exit.

#### 4d. "Done" → Exit.

---

### Add form

**Step 5 — Receive `TASK_TEXT`.**
If reached from Step 2a, `TASK_TEXT` is already set. Otherwise `TASK_TEXT` = `$ARGUMENTS` verbatim. If `--name <slug>` flag is present, capture explicit slug override and strip from `TASK_TEXT`.

**Step 6 — LLM-generate slug + title + description.**

This is a thinking step — you (Claude) produce three values from `TASK_TEXT`:

- **`TITLE`** — human-readable phrase, **up to ~120 chars**, single line. Imperative, specific.
  - Example: TASK_TEXT = `"Добавить двухфакторку через TOTP, чтобы можно было сканировать QR в Google Authenticator. RFC 6238."`
  - TITLE = `"Add two-factor authentication via TOTP"`

- **`SLUG`** — kebab-case identifier, **3-4 segments**, concise but descriptive. Must match `^[a-z][a-z0-9]*(-[a-z0-9]+)*$`. Avoid generic stems like "fix" or "add" if a more specific stem exists. If user provided `--name <slug>` override, use that instead.
  - Example: SLUG = `"add-2fa-totp"`

- **`DESCRIPTION`** — **multi-line, up to ~500 chars**. Several short paragraphs or 2-4 sentences expanding the title with what / why / scope context. Stored as a YAML `|`-literal block.
  - Example DESCRIPTION:
    ```
    Adds TOTP-based 2FA per RFC 6238 with Google Authenticator compatibility.
    Supports QR-code provisioning and backup recovery codes.
    Integrates with existing Spring Security configuration without breaking change.
    ```

If TASK_TEXT is too short to extract a meaningful TITLE / DESCRIPTION (≤ 20 chars), reuse it as TITLE and set DESCRIPTION to TITLE.

**Step 7 — Scaffold.**

`Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh new --title "<TITLE>" --name "<SLUG>" --description "<DESCRIPTION>"`. For multi-line descriptions, pass the whole string in double quotes — `change.sh new` reads it via ENVIRON-style awk and indents each line by 2 spaces under `description: |` in the YAML. Capture stdout (absolute path) as `CP`.
- Exit 1 (slug collision / invalid name) → if collision and user didn't pass `--name`, regenerate SLUG with an extra differentiating segment and retry once. After second failure → ask user for explicit slug.
- Exit 3 (template missing) → `run /foundry:setup first`. Exit.

**Step 8 — Write `propose.md` with full task text.**

`Read` `$CP/propose.md` (scaffold contains only `# <TITLE>\n`). `Write` it back as:

```markdown
# <TITLE>

## Intent

<TASK_TEXT — verbatim, may be multi-paragraph>
```

Keep TASK_TEXT verbatim. This is the source of truth for "what was originally requested" — agents later enrich it with `## Requirements`, `## Open questions`, etc.

Print scaffold report:
```
/change (add):
  name:  <SLUG>
  title: "<TITLE>"
  description: "<DESCRIPTION>"
  path:  <CP>
  status: backlog
  stages: refinement=pending design=pending decomposition=pending implementation=pending verification=pending
  propose.md: written (<TASK_TEXT length> chars)
```

**Step 9 — Offer to start work.**
- **AskUserQuestion:** `"Start work now?"` (header `"Start work"`):
  - `"Yes — start refinement"` — description: `"Set refinement to in-progress. Stays in backlog. Recommended for features."`
  - `"Yes — straight to in-progress (skip planning)"` — description: `"Set implementation to in-progress. Auto-moves to in-progress/. Skips refinement/design/decomposition. Use for trivial bugfixes."`
  - `"No — leave in backlog"` — description: `"Leave all stages pending. Resume later via /change or /track."`

- On `"start refinement"`:
  - `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/tracking.sh set-stage --change $CP --stage refinement --state in-progress --by user`.
  - Final: `Started: refinement in-progress. Status: backlog. Next: agent writes requirements.md → /track <name> refinement need-approve.`

- On `"straight to in-progress"`:
  - `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/tracking.sh set-stage --change $CP --stage implementation --state in-progress --by user`.
  - `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh move --name <SLUG> --to in-progress --by auto`.
  - Final: `Started: implementation in-progress. Status: in-progress (auto-moved). Note: refinement/design/decomposition stayed pending — planning skipped.`

- On `"leave in backlog"`:
  - No-op. Final: `Left in backlog. Resume with /change or /track <name>.`

## Important

- Step 6 is **purely LLM** — `change.sh new` requires explicit `--name` and `--description`; no slug auto-derivation.
- Step 8 writes the full original task text verbatim into `propose.md` — preserve user wording.
- Step 4a's "move to in-progress" intentionally skips planning. Acceptable for tiny fixes; risky for features.
- For comma-separated names in multi-select Other field, split on `,`, trim whitespace, validate each via `change.sh locate`.
- If `multiSelect: true` returns no selections, record `No selection — nothing moved` and exit cleanly.
- This is the only command that scaffolds changes. There is no legacy `/backlog` or `/backlog-add` alias.
