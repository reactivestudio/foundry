---
name: backlog-add
description: "Scaffold new change in .spec/changes/backlog/ from title (auto-slug). NOT for moving existing changes."
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh:*) Read
---

Create a new change in `backlog/` from a single title argument. The slug-name is derived automatically (override with `--name <slug>` if needed). Scaffold contains `tracking.yaml` (all 5 stages = `pending`) + `proposal.md`-stub. Content is the user's / PM agent's job — this command only scaffolds.

Arguments: `<title>` (required) `[--name <slug>]` (optional override).

## Procedure

0. **(Recommended) Load conventions.** `Read ${CLAUDE_PLUGIN_ROOT}/skills/spec/conventions/SKILL.md` and `${CLAUDE_PLUGIN_ROOT}/skills/spec/workflow/SKILL.md` if you intend to immediately advance the change beyond the proposal stub.

1. **Parse args.** Title is the first non-flag argument (preserve spaces). If `--name <slug>` is present, capture the explicit slug.

2. **Scaffold.** `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change.sh new --title "<title>" [--name <slug>]`. On exit 1 (name collision / invalid) — relay diagnostic and stop. On exit 3 (template missing) — ask user to run `/setup` first.

3. **Report:**
   ```
   /backlog-add:
     name: <derived-name>
     title: "<title>"
     path: <absolute path>
     scope: <empty — analyst will set>
     stages: analysis=pending architecture=pending decomposition=pending implementation=pending verification=pending
     next: fill proposal.md with the problem statement (1-3 paragraphs), then /track <name> analysis in-progress
   ```

## Important

- Pure scaffold. Do **not** write requirements/design/roadmap content from this command — agents do that during their respective stages (see `spec-workflow`).
- If `.spec/changes/_template/` is missing in the project root and `$CLAUDE_PLUGIN_ROOT` is not exported, `change.sh new` fails with a clear message — run `/setup` to bootstrap.
- Slug derivation: lowercase, whitespace → `-`, strip non-`[a-z0-9-]`, collapse repeats. Examples: `"Add 2FA"` → `add-2fa`; `"Fix bug #42!"` → `fix-bug-42`.
