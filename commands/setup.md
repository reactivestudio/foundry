---
name: setup
description: "Init <project>/.claude/ for foundry: templates, gitignore, optional .spec/ + MCP servers. Idempotent. NOT for ~/.claude/."
allowed-tools: Read Write Edit Bash(git rev-parse:*) Bash(test:*) Bash(command:*) Bash(mkdir:*) Bash(pwd) Bash(cp:*) AskUserQuestion
---

Set up foundry in the **current project**. Templates land in `<project>/.claude/`; optional integrations (`.spec/` 4-bucket change workflow, MCP servers) land in the project root. Never touches `~/.claude/` or user-scope MCP config.

## What gets installed

Always (mandatory, with diff-prompt on conflict):

- `${CLAUDE_PLUGIN_ROOT}/.claude-template/CLAUDE.md`     → `<project>/.claude/CLAUDE.md`
- `${CLAUDE_PLUGIN_ROOT}/.claude-template/settings.json` → `<project>/.claude/settings.json`
- Entry `.claude/` appended to `<project>/.gitignore` if absent.

Optional (asked only when absent — silent skip on re-run):

- `<project>/.spec/` — 4-bucket change workflow with per-stage `tracking.yaml`. Scaffolded **locally** from `${CLAUDE_PLUGIN_ROOT}/.claude-template/spec/`. Bash-only file ops; no external deps. Includes `standards/` for long-lived project rules and `changes/_template/` (used by `change-new.sh`).
- `<project>/.mcp.json` with any subset of `context7`, `serena`.

Plugin hooks live in `hooks/hooks.json` and auto-load when foundry is active. Toggle per-project with `/plugin disable foundry@reactivestudio`.

## Hard rules for the writer

**The user must NOT see raw shell diagnostics.** These rules are non-negotiable:

- **Use `Read` / `Write` / `Edit` for everything you can.** Comparing files? `Read` both, compare in your head. Checking if `.gitignore` has an entry? `Read` it, look at the lines. Writing templates? `Write`. Appending to `.gitignore`? `Edit`. **Never** use `cmp`, `diff`, `grep`, `cat`, `cp`, `printf >>`, or `echo >>` from Bash for these.
- **Bash is allowed only for these operations** — nothing else:
  1. `git rev-parse --show-toplevel` (resolve project root, once).
  2. `test -d <abs-path>/.spec` (existence probe).
  3. `mkdir -p <abs-path>/.spec/changes/{backlog,sprint,done,declined} <abs-path>/.spec/standards` (create scaffold dirs).
  4. `pwd` (fallback when not in a git repo).
  5. `cp -r <plugin>/.claude-template/spec/changes/_template <project>/.spec/changes/_template` (copy template subtree when bootstrapping — recursive copy is the only way to copy a directory; do NOT script around it with Read/Write per-file).
- **No shell operators in Bash calls.** No `&&`, `||`, `;`, `|`, `>>`, `<<`, backticks, or `\`-continuations. Each Bash call must be a single clean command. Operators trigger Claude Code's "shell operators require approval" prompt — that's the noise the user is angry about.
- **Every Bash call carries a short human `description`.** Example: `"Resolve project root"`, `"Check if .spec exists"`, `"Create .spec scaffold dirs"`. Never let bare shell be the only thing the user reads.
- **Report progress as one human line per phase.** E.g. `Templates: 2 identical · .gitignore: already covers .claude/ · .spec: absent (will ask)`. Don't dump shell stdout to chat.

## Procedure

1. **Resolve project root** — one Bash call: `git rev-parse --show-toplevel`. On failure (no git repo), AskUserQuestion whether to use `pwd` instead. Call this resolved absolute path `R` for the rest of the procedure.

2. **Templates.** For each `(source, target)` in:
   - `${CLAUDE_PLUGIN_ROOT}/.claude-template/CLAUDE.md` → `R/.claude/CLAUDE.md`
   - `${CLAUDE_PLUGIN_ROOT}/.claude-template/settings.json` → `R/.claude/settings.json`

   `Read` source. Attempt `Read` of target.
   - Target missing → `Write` source contents to target. Record `written`.
   - Target identical (same contents) → silent skip. Record `identical`.
   - Target differs → emit a compact diff inline in chat (compute it yourself — don't shell out), then AskUserQuestion with options **Overwrite** / **Keep existing** / **Show full diff**. On *Show full* → print full content of both files side-by-side, re-ask. On *Overwrite* → `Write`. On *Keep* → leave target as-is. Record `overwritten` / `kept`.

3. **`.gitignore` — entry `.claude/`.** Attempt `Read` of `R/.gitignore`.
   - Missing → `Write` a new file containing exactly `.claude/\n`. Record `gitignore: added`.
   - Present without exact-match line `.claude/` → `Edit` to append. Record `gitignore: added`.
   - Already contains `.claude/` → silent skip. Record `gitignore: already present`.

4. **`.spec/` (optional, project-scope).** Probe in two stages.

   **4a. Top-level probe.** One Bash call: `test -d R/.spec`.
   - Exit non-zero (absent) → AskUserQuestion: **"Bootstrap `.spec/` (4-bucket change workflow) in this project?"**
     - **Yes, bootstrap** — `description: "Scaffolds <project>/.spec/ with standards/README.md (long-lived rules), 4 bucket dirs (backlog/sprint/done/declined), and changes/_template/ used by /backlog-add. No external deps."`
     - **No, skip** — `description: "Don't bootstrap. You can re-run /setup later to add it."`
     - On Yes: bootstrap full scaffold (see 4c). Record `.spec: bootstrapped`. Proceed to step 5.
     - On No: record `.spec: skipped`. Skip step 5.
   - Exit 0 (present) → continue to 4b for completeness check.

   **4b. Completeness probe (when `.spec/` already exists).** Attempt `Read` of each scaffold target — if `Read` errors with "file not found", the file is missing. Targets:
   - `R/.spec/standards/README.md`
   - `R/.spec/changes/_template/tracking.yaml`
   - `R/.spec/changes/_template/proposal.md`

   Also check (Bash `test -d`) the directory markers:
   - `R/.spec/standards`
   - `R/.spec/changes/backlog`, `R/.spec/changes/sprint`, `R/.spec/changes/done`, `R/.spec/changes/declined`
   - `R/.spec/changes/_template`

   Detect **legacy** artifacts from the old delta-merge model (record but do NOT delete):
   - `R/.spec/specs/` (was canonical capability specs)
   - `R/.spec/changes/archive/` (was archived changes)
   - `R/.spec/project.md` (now moved into standards/)
   - `R/.spec/config.yaml` (delta-merge rules — obsolete)

   - All new-model targets present → record `.spec: already present (complete)`. Proceed to step 5 only if `.gitignore` lacks any opinion about `.spec/`.
   - Any new-model target missing → AskUserQuestion: **"Found `.spec/` but scaffold is incomplete (missing: <list>). Top up missing files?"**
     - **Yes, top up** — write only the missing files / mkdir the missing dirs (see 4c). Don't touch existing files. Record `.spec: topped up (<n> files written)`.
     - **No, leave as is** — record `.spec: already present (incomplete, user declined top-up)`.
   - If legacy artifacts detected, append to record: `(legacy: <list>)`. Surface in final summary as a migration note.

   **4c. Bootstrap / top-up file operations** (referenced by 4a and 4b):
   - `Bash`: `mkdir -p R/.spec/changes/backlog R/.spec/changes/sprint R/.spec/changes/done R/.spec/changes/declined R/.spec/standards` (idempotent — safe to run unconditionally).
   - For each `(src, dst)` pair where `dst` does NOT exist:
     - `${CLAUDE_PLUGIN_ROOT}/.claude-template/spec/standards/README.md`  → `R/.spec/standards/README.md`

     `Read` source, `Write` destination verbatim. **Never overwrite an existing file** — only write the ones the user is missing.
   - If `R/.spec/changes/_template/` is missing as a directory, `Bash`: `cp -r ${CLAUDE_PLUGIN_ROOT}/.claude-template/spec/changes/_template R/.spec/changes/_template`. (Recursive copy is the only practical way to copy a directory subtree; the template files inside contain `{{...}}` placeholders that `change-new.sh` substitutes at scaffold time.)

5. **`.spec/` gitignore policy** (only if `.spec/` was just bootstrapped, OR exists and `.gitignore` has no opinion). `Read` `R/.gitignore`, look for exact line `.spec/`.
   - Already listed → record `.spec gitignore: already ignored`. Don't prompt.
   - Not listed → AskUserQuestion: **"Commit `.spec/` to git, or keep it local?"**
     - **Commit (recommended)** — `description: "Treat specs as project artifacts: PRs review proposals, git history tracks decisions, archive/ preserves history."`
     - **Add to .gitignore** — `description: "Keep .spec/ local-only. Pick this if you're experimenting solo or the team hasn't bought in yet."`
     - On Commit → record `.spec gitignore: committed`.
     - On Add → `Edit` `.gitignore` to append `.spec/`. Record `.spec gitignore: added`.

6. **MCP servers (optional, project-scope).** Attempt `Read` of `R/.mcp.json`. If missing, treat as `{"mcpServers":{}}`. Note which canonical servers (`context7`, `serena`) are already registered.
   - Both already present → record `mcp: already configured`. Don't prompt.
   - Else AskUserQuestion (multiSelect, exclude already-present entries): **"Register MCP servers in this project's `.mcp.json`?"**
     - **Context7** — `description: "Real-time, version-aware library docs (React, Vue, Spring, etc.) fetched on demand. Useful when the LLM's training data is stale."`
     - **Serena** — `description: "Code intelligence: symbolic navigation, find-references, refactor across the project. Requires Python + the serena package on PATH."`
     - **None** — `description: "Skip MCP for this project. You can re-run /setup later."`
     - For each selected, add canonical entry:
       - `context7` → `{"command":"npx","args":["-y","@context7/mcp@latest"]}`
       - `serena` → `{"command":"python","args":["-m","serena.mcp"],"env":{"SERENA_PROJECT_DIR":"."}}`
     - `Write` `.mcp.json` back with 2-space indent. Preserve any pre-existing keys untouched. Record per-server: `added` or `already present`.
   - If None / no selection → record `mcp: skipped`.

## Final summary

```
foundry:setup complete:
  templates: written=N, identical=M, overwritten=K, kept=L
  gitignore: <added | already present>
  .spec: <bootstrapped | topped up: N files | already present (complete) | already present (incomplete, declined) | skipped>
  .spec legacy: <list of detected legacy paths, only if any>
  .spec gitignore: <committed | added | already ignored | n/a>
  mcp:
    context7: <added | already present | skipped>
    serena:   <added | already present | skipped>
```

Omit the `.spec` / `mcp` lines if they were never relevant on this run (both already present and silently skipped). If Serena was added, add a note: `serena requires Python + serena package on PATH`. If any MCP was added, add: `restart the session for new MCP servers to load`. If legacy `.spec/` artifacts were detected, add: `note: legacy artifacts from old delta-merge model detected — see README migration guide`. After a fresh `.spec` bootstrap, suggest: `next: populate .spec/standards/*.md (project.md, stack.md, …), then /backlog-add "<title>" to create your first change`.

## Important

- Writes only inside `R/`. Never touches `~/.claude/` or user-scope MCP config.
- The project-scope `settings.json` does NOT contain plugin-management state (`enabledPlugins`, `extraKnownMarketplaces` etc.) — that lives in user-scope. Plain copy is safe.
- `.spec/` and MCP are **opt-in per-project**. Always ask before installing, and only when absent.
- `.spec/standards/` is a long-lived freeform directory (stack / architecture / best-practices / anti-patterns / glossary / project context). Edited directly; never archived. Agents read on-demand for relevant context.
- `.spec/changes/_template/` holds the scaffold (`tracking.yaml`, `proposal.md`) copied verbatim by `change-new.sh` when running `/backlog-add`. Edit only if you want to change the per-change starter content for THIS project.
- `.mcp.json` is project-scope and conventionally checked in. For private config, the user should use `.mcp.local.json` (gitignored) — mention this when MCP is selected for the first time.
- Idempotent: re-run after `/plugin update` to refresh templates, or anytime to top-up. Already-present `.spec/` / MCP entries are skipped silently.
