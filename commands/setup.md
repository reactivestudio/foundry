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

Optional (asked only when absent — silent skip on re-run):

- `<project>/.spec/` — 4-bucket change workflow with per-stage `tracking.yaml`. Scaffolded **locally** from `${CLAUDE_PLUGIN_ROOT}/.claude-template/spec/`. Bash-only file ops; no external deps. Includes `standards/` for long-lived project rules and `changes/.template/` (used by `change.sh new`).
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
- **Probe existence via `Read`, not Bash.** To check whether `<abs>/.spec/...` exists, attempt `Read` of a canonical marker file in that subtree. If `Read` returns "file does not exist" → treat as absent. If it returns content → treat as present. This avoids any interpretation of bash exit codes.
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

4. **`.spec/` (optional, project-scope).** No Bash probes — `Read` is the existence test.

   **4a. Probe via marker file.** Attempt `Read` of `R/.spec/changes/.template/tracking.yaml` (canonical marker — it's always present in a complete scaffold and absent in everything else).
   - `Read` returns "file does not exist" → `.spec` is absent OR severely incomplete. Treat as absent. Go to 4b.
   - `Read` returns file contents → `.spec` is at least partially populated. Go to 4d (top-up).

   **4b. Ask to bootstrap (only when 4a says absent).**

   AskUserQuestion: **"Bootstrap `.spec/` (4-bucket change workflow) in this project?"**
   - **Yes, bootstrap** — `description: "Scaffolds <project>/.spec/ with standards/README.md (long-lived rules), 4 bucket dirs (backlog/in-progress/done/declined), and changes/.template/ used by /change. No external deps."`
   - **No, skip** — `description: "Don't bootstrap. You can re-run /setup later to add it."`

   On No → record `.spec: skipped`, jump to step 6 (skip 5 too — no `.spec/` to gitignore).
   On Yes → continue to 4c.

   **4c. Bootstrap (full scaffold).**

   1. `Bash`: `mkdir -p <R>/.spec/changes/backlog <R>/.spec/changes/in-progress <R>/.spec/changes/done <R>/.spec/changes/declined <R>/.spec/changes/.template <R>/.spec/standards` (substitute `<R>` with the resolved absolute path).
   2. For each `(src, dst)` triple:
      - `${CLAUDE_PLUGIN_ROOT}/.claude-template/spec/standards/README.md`              → `<R>/.spec/standards/README.md`
      - `${CLAUDE_PLUGIN_ROOT}/.claude-template/spec/changes/.template/tracking.yaml`  → `<R>/.spec/changes/.template/tracking.yaml`
      - `${CLAUDE_PLUGIN_ROOT}/.claude-template/spec/changes/.template/propose.md`     → `<R>/.spec/changes/.template/propose.md`

      `Read` source via its absolute path. `Write` destination verbatim. (No cp — Write is more reliable; only 3 files.)

   Record `.spec: bootstrapped (3 files written)`. Proceed to step 5.

   **4d. Top-up (only when 4a says present).** Same files as 4c, but only `Write` the ones whose destination `Read` returns "file does not exist". Never overwrite existing content.

   For each of the 3 target files:
   - Attempt `Read <R>/.spec/<dst>`.
   - If "file does not exist" → `Read` plugin-side source and `Write` dst.
   - Otherwise → silent skip.

   Also run the `mkdir -p` Bash call once at the start of 4d (idempotent — covers the case where some bucket directory got deleted by the user).

   Record either `.spec: already present (complete)` (zero writes) or `.spec: topped up (<n> files written)`.

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
  .spec: <bootstrapped (3 files written) | topped up: N files | already present (complete) | skipped>
  .spec gitignore: <committed | added | already ignored | n/a>
  mcp:
    context7: <added | already present | skipped>
    serena:   <added | already present | skipped>
```

Omit the `.spec` / `mcp` lines if they were never relevant on this run. If Serena was added, add a note: `serena requires Python + serena package on PATH`. If any MCP was added, add: `restart the session for new MCP servers to load`. After a fresh `.spec` bootstrap, suggest: `next: populate .spec/standards/*.md (project.md, stack.md, …), then /change "<task text>" to create your first change`.

## Important

- Writes only inside `R/`. Never touches `~/.claude/` or user-scope MCP config.
- The project-scope `settings.json` does NOT contain plugin-management state (`enabledPlugins`, `extraKnownMarketplaces` etc.) — that lives in user-scope. Plain copy is safe.
- `.spec/` and MCP are **opt-in per-project**. Always ask before installing, and only when absent.
- `.spec/standards/` is a long-lived freeform directory (stack / architecture / best-practices / anti-patterns / glossary / project context). Edited directly; never archived. Agents read on-demand for relevant context.
- `.spec/changes/.template/` holds the scaffold (`tracking.yaml`, `propose.md`) copied verbatim by `change.sh new` when running `/change "<text>"`. Edit only if you want to change the per-change starter content for THIS project.
- `.mcp.json` is project-scope and conventionally checked in. For private config, the user should use `.mcp.local.json` (gitignored) — mention this when MCP is selected for the first time.
- Idempotent: re-run after `/plugin update` to refresh templates, or anytime to top-up. Already-present `.spec/` / MCP entries are skipped silently.
