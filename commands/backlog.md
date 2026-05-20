---
name: backlog
description: "Backlog command: no args → list table; with title → scaffold new change in .spec/changes/backlog/."
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh:*) Read
---

Unified backlog command. Smart dispatch on arguments:

- **No args** → list all changes currently in `backlog/`.
- **With a title (free-form text)** → scaffold a new change in `backlog/` from that title. Slug auto-derived; override with `--name <slug>`.

## Procedure

### Form 1 — list (no arguments)

1. **Run lister.** `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh list --bucket backlog`.

2. **Render as markdown table.** Columns: `Name | Active stage | State | Scope | Roadmap | Last event`.

   Example:
   ```
   | Name | Active stage | State | Scope | Roadmap | Last event |
   |---|---|---|---|---|---|
   | add-2fa | analysis | need-approve | feature | — | 2026-05-20 16:00 |
   | dark-mode | architecture | in-progress | feature | — | 2026-05-20 11:42 |
   ```

3. **Report counts:** `N changes in backlog/`. If empty: `backlog/ is empty.`

### Form 2 — add (one or more arguments treated as title)

0. **(Recommended) Load conventions.** `Read ${CLAUDE_PLUGIN_ROOT}/skills/spec/conventions/SKILL.md` and `${CLAUDE_PLUGIN_ROOT}/skills/spec/workflow/SKILL.md`.

1. **Parse args.** Everything that isn't `--name <slug>` joins into the title (preserve spaces). If `--name <slug>` flag is present, capture explicit slug override.

2. **Scaffold.** `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh new --title "<title>" [--name <slug>]`.
   - Exit 1 (collision / invalid name) → relay diagnostic and stop.
   - Exit 3 (template missing) → ask user to run `/setup` first.

3. **Report:**
   ```
   /backlog (add):
     name: <derived-name>
     title: "<title>"
     path: <absolute path>
     scope: <empty — analyst will set>
     stages: analysis=pending architecture=pending decomposition=pending implementation=pending verification=pending
     next: fill proposal.md with the problem statement (1-3 paragraphs), then /track <name> analysis in-progress
   ```

## Dispatch rule

If `$ARGUMENTS` (after trimming) is empty → **Form 1**. Otherwise → **Form 2**.

A user who wants to filter the list by name should use `/track <name>` (single-change detail) instead.

## Important

- Form 2 is pure scaffold — does **not** generate requirements / design / roadmap content. Agents do that during their stages (see `spec-workflow`).
- Slug derivation: lowercase, whitespace → `-`, strip non-`[a-z0-9-]`, collapse repeats. Examples: `"Add 2FA"` → `add-2fa`; `"Fix bug #42!"` → `fix-bug-42`.
- For a single change's detail, use `/track <name>`. For sprint / closed buckets, use `/sprint` and `/closed`.
