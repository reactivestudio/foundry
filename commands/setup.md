---
name: setup
description: "Init <project>/.claude/ for foundry: templates, gitignore, optional .spec/ + MCP servers. Idempotent. NOT for ~/.claude/."
allowed-tools: Read Write Edit Bash(git rev-parse:*) Bash(test:*) Bash(command:*) Bash(mkdir:*) Bash(pwd)
---

Set up foundry in the **current project**. Templates land in `<project>/.claude/`; optional integrations (`.spec/` spec-driven workflow, MCP servers) land in the project root. Never touches `~/.claude/` or user-scope MCP config.

## What gets installed

Always (mandatory, with diff-prompt on conflict):

- `${CLAUDE_PLUGIN_ROOT}/.claude-template/CLAUDE.md`     → `<project>/.claude/CLAUDE.md`
- `${CLAUDE_PLUGIN_ROOT}/.claude-template/settings.json` → `<project>/.claude/settings.json`
- Entry `.claude/` appended to `<project>/.gitignore` if absent.

Optional (asked only when absent — silent skip on re-run):

- `<project>/.spec/` — scaffolded **locally** from `${CLAUDE_PLUGIN_ROOT}/.claude-template/spec/`. Bash-only file ops; no `npx`, no external dependencies. The 10 `/spec-*` commands (propose / new / continue / apply / sync / archive / list / show / status / validate) operate on this directory. Includes a `standards/` folder for long-lived project rules (stack, architecture, anti-patterns…).
- `<project>/.mcp.json` with any subset of `context7`, `serena`.

Plugin hooks live in `hooks/hooks.json` and auto-load when foundry is active. Toggle per-project with `/plugin disable foundry@reactivestudio`.

## Hard rules for the writer

**The user must NOT see raw shell diagnostics.** These rules are non-negotiable:

- **Use `Read` / `Write` / `Edit` for everything you can.** Comparing files? `Read` both, compare in your head. Checking if `.gitignore` has an entry? `Read` it, look at the lines. Writing templates? `Write`. Appending to `.gitignore`? `Edit`. **Never** use `cmp`, `diff`, `grep`, `cat`, `cp`, `printf >>`, or `echo >>` from Bash for these.
- **Bash is allowed only for these four operations** — nothing else:
  1. `git rev-parse --show-toplevel` (resolve project root, once).
  2. `test -d <abs-path>/.spec` (existence probe for .spec dir).
  3. `mkdir -p <abs-path>/.spec/specs <abs-path>/.spec/changes <abs-path>/.spec/changes/archive` (create scaffold dirs).
  4. `pwd` (fallback when not in a git repo).
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

4. **`.spec/` (optional, project-scope).** One Bash call to probe: `test -d R/.spec`.
   - Exit 0 (present) → record `.spec: already present`. Proceed to step 5 (gitignore policy) only if `.gitignore` lacks any opinion about `.spec/`.
   - Exit non-zero (absent) → AskUserQuestion: **"Bootstrap `.spec/` (local spec-driven workflow) in this project?"**
     - **Yes, bootstrap** — `description: "Scaffolds <project>/.spec/ with project.md, config.yaml, standards/ (long-lived rules), and empty specs/, changes/ folders. The 10 /spec-* commands operate here. No external deps."`
     - **No, skip** — `description: "Don't bootstrap. You can re-run /setup later to add it."`
     - On Yes:
       - One Bash call: `mkdir -p R/.spec/specs R/.spec/changes R/.spec/changes/archive R/.spec/standards`.
       - For each `(src, dst)`:
         - `${CLAUDE_PLUGIN_ROOT}/.claude-template/spec/project.md`             → `R/.spec/project.md`
         - `${CLAUDE_PLUGIN_ROOT}/.claude-template/spec/config.yaml`            → `R/.spec/config.yaml`
         - `${CLAUDE_PLUGIN_ROOT}/.claude-template/spec/standards/README.md`    → `R/.spec/standards/README.md`
         `Read` source, `Write` destination verbatim.
       - Record `.spec: bootstrapped (3 files + standards/README.md)`.
     - On No: record `.spec: skipped`. Skip step 5.

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
  .spec: <bootstrapped | already present | skipped>
  .spec gitignore: <committed | added | already ignored | n/a>
  mcp:
    context7: <added | already present | skipped>
    serena:   <added | already present | skipped>
```

Omit the `.spec` / `mcp` lines if they were never relevant on this run (both already present and silently skipped). If Serena was added, add a note: `serena requires Python + serena package on PATH`. If any MCP was added, add: `restart the session for new MCP servers to load`. After a fresh `.spec` bootstrap, suggest: `next: fill in .spec/project.md and any .spec/standards/*.md, then /spec-propose "<description>"`.

## Important

- Writes only inside `R/`. Never touches `~/.claude/` or user-scope MCP config.
- The project-scope `settings.json` does NOT contain plugin-management state (`enabledPlugins`, `extraKnownMarketplaces` etc.) — that lives in user-scope. Plain copy is safe.
- `.spec/` and MCP are **opt-in per-project**. Always ask before installing, and only when absent.
- `.spec/standards/` is a long-lived freeform directory (stack / architecture / best-practices / anti-patterns / glossary). Edited directly; never archived. The 10 `/spec-*` commands read every `.spec/standards/*.md` when loading context.
- `.mcp.json` is project-scope and conventionally checked in. For private config, the user should use `.mcp.local.json` (gitignored) — mention this when MCP is selected for the first time.
- Idempotent: re-run after `/plugin update` to refresh templates, or anytime to top-up. Already-present `.spec/` / MCP entries are skipped silently.
