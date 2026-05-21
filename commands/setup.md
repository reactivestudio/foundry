---
name: setup
description: "Init <project>/.claude/ for foundry: templates, gitignore, optional .spec/ + MCP servers. Idempotent. NOT for ~/.claude/."
allowed-tools: Read Write Edit Bash(git rev-parse:*) Bash(command:*) Bash(mkdir:*) Bash(pwd) AskUserQuestion
---

Set up foundry in the **current project**. Templates land in `<project>/.claude/`; optional integrations (`.spec/` 4-bucket change workflow, MCP servers) land in the project root. Never touches `~/.claude/` or user-scope MCP config.

## What gets installed

Always (mandatory, with diff-prompt on conflict):

- `${CLAUDE_PLUGIN_ROOT}/.claude-template/CLAUDE.md`     → `<project>/.claude/CLAUDE.md`
- `${CLAUDE_PLUGIN_ROOT}/.claude-template/settings.json` → `<project>/.claude/settings.json`
- Entry `.claude/` appended to `<project>/.gitignore` if absent.

Opt-in (always asked, idempotent — re-runs never overwrite existing files):

- `<project>/.spec/` — 4-bucket change workflow with per-stage `tracking.yaml`. Scaffolded **locally** from `${CLAUDE_PLUGIN_ROOT}/.claude-template/spec/`. Includes `standards/` for long-lived project rules and `changes/.template/` (used by `change.sh new`).
- `<project>/.mcp.json` with any subset of `context7`, `serena`.

Plugin hooks live in `hooks/hooks.json` and auto-load when foundry is active. Toggle per-project with `/plugin disable foundry@reactivestudio`.

## Hard rules for the writer

**The user must NOT see raw shell diagnostics.** These rules are non-negotiable:

- **Use `Read` / `Write` / `Edit` for everything you can.** Including existence probes — `Read` returns a clear "file not found" error you can detect, far more reliable than interpreting `test`'s exit codes. Comparing files? `Read` both, compare in your head. Checking if `.gitignore` has an entry? `Read` it, look at the lines. Writing templates? `Write`. Appending to `.gitignore`? `Edit`. **Never** use `cmp`, `diff`, `grep`, `cat`, `cp`, `test`, `ls`, `printf >>`, or `echo >>` from Bash for these.
- **Bash is allowed only for these operations** — nothing else:
  1. `git rev-parse --show-toplevel` (resolve project root, once).
  2. `pwd` (fallback when not in a git repo).
  3. `mkdir -p <abs-path>/.spec/changes/backlog <abs-path>/.spec/changes/in-progress <abs-path>/.spec/changes/done <abs-path>/.spec/changes/declined <abs-path>/.spec/changes/.template <abs-path>/.spec/standards` (create scaffold dirs — idempotent, no-op if all exist).
- **All paths must be absolute and pre-substituted.** When the procedure says `R/.spec/...`, you must expand `R` to the actual project root before placing the Bash call. Never literally type `R/.spec` in a Bash invocation — bash treats `R` as a relative path and probes the wrong location. Same rule for `${CLAUDE_PLUGIN_ROOT}` — that env var is fine to leave unsubstituted *inside Bash* (the shell expands it), but never inside Read/Write `file_path` arguments.
- **Do not probe `.spec/` existence at all.** The procedure now ALWAYS asks the user about `.spec/` and ALWAYS runs the idempotent scaffold loop on Yes. Probing led to wrong-branch heuristics in pilot testing. The only `Read`-as-probe is per-file inside the scaffold loop: each destination file is `Read` to decide whether to `Write` it.
- **No shell operators in Bash calls.** No `&&`, `||`, `;`, `|`, `>>`, `<<`, backticks, or `\`-continuations. Each Bash call must be a single clean command.
- **Every Bash call carries a short human `description`.** Example: `"Resolve project root"`, `"Create .spec scaffold dirs"`. Never let bare shell be the only thing the user reads.
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

4. **`.spec/` — MANDATORY step. Always execute. NEVER skip based on heuristics.**

   This step has exactly two branches: **Ask** (4a) and **Scaffold-or-Skip** (4b). There is no probe and no "if it already exists, skip silently" shortcut. The AskUserQuestion below MUST fire on every run of `/foundry:setup`, even if you suspect `.spec/` is already populated — re-runs are idempotent by design (existing files are never overwritten), so re-asking costs nothing.

   **4a. Ask the user.** AskUserQuestion: **"Set up `.spec/` scaffold in this project? (Idempotent — existing files are never touched.)"**
   - **Yes (Recommended)** — `description: "Creates / refreshes <R>/.spec/ with standards/README.md, 4 bucket dirs (backlog/in-progress/done/declined), and changes/.template/ used by /change. Files that already exist are left untouched."`
   - **Skip** — `description: "Do not touch .spec/ on this run. Re-run /setup later to add or refresh it."`

   On **Skip** → record `.spec: user-skipped`. Skip step 5 entirely. Jump to step 6.

   On **Yes** → execute 4b. **Do not short-circuit.** All three sub-steps below MUST run in order.

   **4b. Scaffold (always runs on Yes — idempotent).**

   **4b.1. Create directories.** One Bash call with the resolved absolute path `<R>` substituted in literally (NEVER leave `<R>` or `R` unexpanded):
   ```
   mkdir -p <R>/.spec/changes/backlog <R>/.spec/changes/in-progress <R>/.spec/changes/done <R>/.spec/changes/declined <R>/.spec/changes/.template <R>/.spec/standards
   ```
   `mkdir -p` is a no-op for existing dirs. Always run.

   **4b.2. Read+Write each of 3 template files.** Initialize counters `written=0`, `existing=0`. For EACH of the following 3 `(src, dst)` pairs — in this order, with NO short-circuit:

   1. `src = ${CLAUDE_PLUGIN_ROOT}/.claude-template/spec/standards/README.md`
      `dst = <R>/.spec/standards/README.md`
   2. `src = ${CLAUDE_PLUGIN_ROOT}/.claude-template/spec/changes/.template/tracking.yaml`
      `dst = <R>/.spec/changes/.template/tracking.yaml`
   3. `src = ${CLAUDE_PLUGIN_ROOT}/.claude-template/spec/changes/.template/propose.md`
      `dst = <R>/.spec/changes/.template/propose.md`

   For each pair, perform exactly these operations in order:

   1. `Read` the source file via its absolute path (resolves `${CLAUDE_PLUGIN_ROOT}` through the Read tool). This always succeeds — the templates ship with the plugin.
   2. Attempt `Read` of the destination via its absolute path.
   3. **If destination Read returns "file does not exist"** → `Write` the source contents to the destination verbatim. Increment `written`.
   4. **If destination Read returns content** → silent skip. Increment `existing`.

   You MUST attempt all 3 pairs before reporting. Do not return early after pair #1.

   **4b.3. Report.** Final line for `.spec`: `.spec: scaffold complete (written=<written>, existing=<existing> of 3)`.

   Proceed to step 5.

5. **`.spec/` gitignore policy** (only reached on the Yes branch of step 4). `Read` `R/.gitignore`, look for exact line `.spec/`.
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
  .spec: <scaffold complete (written=N, existing=M of 3) | user-skipped>
  .spec gitignore: <committed | added | already ignored | n/a>
  mcp:
    context7: <added | already present | skipped>
    serena:   <added | already present | skipped>
```

Omit the `.spec` / `mcp` lines if they were never relevant on this run. If Serena was added, add a note: `serena requires Python + serena package on PATH`. If any MCP was added, add: `restart the session for new MCP servers to load`. After a fresh `.spec` bootstrap, suggest: `next: populate .spec/standards/*.md (project.md, stack.md, …), then /change "<task text>" to create your first change`.

## Important

- Writes only inside `R/`. Never touches `~/.claude/` or user-scope MCP config.
- The project-scope `settings.json` does NOT contain plugin-management state (`enabledPlugins`, `extraKnownMarketplaces` etc.) — that lives in user-scope. Plain copy is safe.
- `.spec/` and MCP are **opt-in per-project**. The procedure ALWAYS asks about `.spec/` (every run); the scaffold loop is idempotent so re-asking is cheap and safe. MCP is asked only when at least one canonical server is absent.
- `.spec/standards/` is a long-lived freeform directory (stack / architecture / best-practices / anti-patterns / glossary / project context). Edited directly; never archived. Agents read on-demand for relevant context.
- `.spec/changes/.template/` holds the scaffold (`tracking.yaml`, `propose.md`) copied verbatim by `change.sh new` when running `/change "<text>"`. Edit only if you want to change the per-change starter content for THIS project.
- `.mcp.json` is project-scope and conventionally checked in. For private config, the user should use `.mcp.local.json` (gitignored) — mention this when MCP is selected for the first time.
- Idempotent: re-run after `/plugin update` to refresh templates, or anytime to top-up. `.spec/` step always asks and always runs its scaffold loop on Yes (loop is per-file Read+Write — existing files are never overwritten). MCP entries are skipped if already configured.
