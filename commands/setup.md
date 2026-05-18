---
name: setup
description: "Init <project>/.claude/ for foundry: templates, gitignore, optional openspec + MCP servers. Idempotent. NOT for ~/.claude/."
allowed-tools: Read Write Edit Bash(git rev-parse:*) Bash(mkdir:*) Bash(cmp:*) Bash(diff:*) Bash(grep:*) Bash(cat:*) Bash(echo:*) Bash(test:*) Bash(printf:*) Bash(pwd) Bash(command:*) Bash(npx:*)
---

Set up foundry in the **current project**. Templates land in `<project>/.claude/`; optional integrations (openspec, MCP) land in the project root. This command never touches `~/.claude/` or user-scope MCP config — your global settings remain user-managed.

## What gets installed

Always (mandatory, with diff-prompt on conflict):

- `${CLAUDE_PLUGIN_ROOT}/.claude-template/CLAUDE.md`     → `<project>/.claude/CLAUDE.md`
- `${CLAUDE_PLUGIN_ROOT}/.claude-template/settings.json` → `<project>/.claude/settings.json`
- Entry `.claude/` appended to `<project>/.gitignore` if absent.

Optional (asked only when absent — silent skip on re-run if already in place):

- `<project>/openspec/` via `npx -y @fission-ai/openspec@latest init --tools claude --force` — **project-scope only**, never global. The npm package is `@fission-ai/openspec` (the bare name `openspec` on npm is an unrelated empty placeholder).
- `<project>/.mcp.json` entries for any subset of: `context7`, `serena` — **project-scope** MCP servers.

Plugin **hooks** (sound on `Stop` etc.) are NOT copied — they live in `hooks/hooks.json` at the plugin root and Claude Code auto-loads them when the plugin is active in the session. Toggle per-project with `/plugin disable foundry@reactivestudio`.

## Procedure

1. Resolve the project root: use the closest enclosing `.git/` directory as anchor (`git rev-parse --show-toplevel`). If not inside a git repo, ask the user via AskUserQuestion whether to use the current working directory.

2. Ensure `<project>/.claude/` exists (`mkdir -p`).

3. For each (source, target) pair:
   - **Target absent** → write the source contents. Record as `written`.
   - **Target identical** (`cmp -s` → 0) → skip silently. Record as `identical`.
   - **Target differs** → run `diff -u source target | head -n 60` and show the output. Ask via AskUserQuestion:
     - **Overwrite**
     - **Keep existing**
     - **Show full diff**

     On *Show full diff* → print full `diff -u`, then re-ask. On *Overwrite* → write source over target, record as `overwritten`. On *Keep* → record as `kept`.

   No backups: `.claude/` is gitignored, files are personal-local, the worst case of an overwrite is a 30-second re-edit. The diff-prompt is the safeguard.

4. For `<project>/.gitignore`:
   - If it doesn't exist, create with a single line `.claude/`.
   - If it exists but no exact-match line `.claude/` (use `grep -Fx '.claude/' .gitignore`), append `.claude/` as a new line. Record as `gitignore: added`.
   - If already present, record `gitignore: already present`.

5. **openspec (optional, project-scope).** Check `test -d <project>/openspec`:
   - Already present → record `openspec: already present`. Do NOT prompt, do NOT re-run init.
   - Absent → AskUserQuestion: **Install openspec into this project?** [Yes / No]. The user decides per-project; never install globally.
     - On Yes: verify `command -v node` (record `openspec: failed (node not found)` and continue if missing — don't abort the whole setup). Then run `npx -y @fission-ai/openspec@latest init --tools claude --force` from the project root. Stream output. Record `openspec: installed` or `openspec: failed: <stderr tail>`. NOTE: the npm package is `@fission-ai/openspec` — the bare-name `openspec` package is an unrelated empty placeholder, do not use it.
     - On No: record `openspec: skipped`.

6. **MCP servers (optional, project-scope).** Read `<project>/.mcp.json` if it exists, else start with `{"mcpServers":{}}`. Determine which canonical servers (`context7`, `serena`) are already registered — collect their names into `present`.
   - If `present` covers both canonical servers → record `mcp: already configured (context7, serena)`. Do NOT prompt.
   - Else AskUserQuestion (multiSelect, exclude already-present entries from the options): **Register MCP servers in this project's `.mcp.json`?** Options: any of `Context7`, `Serena`, plus `None`. The user picks zero or more; selecting None (or no options) skips the step.
     - For each selected server, add the canonical entry:
       - `context7` → `{"command":"npx","args":["-y","@context7/mcp@latest"]}`
       - `serena` → `{"command":"python","args":["-m","serena.mcp"],"env":{"SERENA_PROJECT_DIR":"."}}`. Note: requires Python + the `serena` package on PATH — surface this in the summary notes.
     - Write `<project>/.mcp.json` back with 2-space indent. Preserve any pre-existing keys untouched. Record per-server: `added` or `already present`.
   - If the user picks None, record `mcp: skipped`.

## Final summary

```
foundry:setup complete:
  templates:
    written: N
    identical: M
    overwritten: K
    kept: L
  gitignore: <added | already present>
  openspec: <installed | already present | skipped | failed: …>
  mcp:
    context7: <added | already present | skipped>
    serena:   <added | already present | skipped>
  notes:
    - serena requires `pip install serena` + Python on PATH (only shown if serena was added)
    - restart the Claude Code session for new MCP servers to load (only shown if any were added)
```

Omit `openspec` / `mcp` lines from the summary if the user was never prompted (i.e., both already present and silently skipped) — keeps re-runs quiet.

## Important

- This command writes only inside `<project>/`. It never reads, writes, or backs up `~/.claude/` or user-scope MCP config.
- The project-scope `settings.json` does NOT contain Claude Code's plugin-management state (`extraKnownMarketplaces` etc.) — that state lives in user-scope. So a plain copy is safe; no structured merge needed.
- openspec and MCP are **opt-in per-project**. Don't assume the user wants them just because they ran `/setup`. Always ask before installing, and only when absent.
- `.mcp.json` is project-scope and conventionally checked in. If the user prefers a private/local-only config, they should use `.mcp.local.json` (gitignored) instead — mention this in the prompt when MCP is selected for the first time.
- Idempotent: re-run after `/plugin update` to refresh templates, or anytime to top-up missing files. Already-present openspec/MCP entries are skipped silently — no re-prompting.
