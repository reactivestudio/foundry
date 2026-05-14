---
name: setup
description: "Seed <project>/.claude/ with bushin templates (CLAUDE.md, settings.json) + gitignore the dir. Idempotent. NOT for ~/.claude/."
allowed-tools: Read Write Edit Bash(git rev-parse:*) Bash(mkdir:*) Bash(cmp:*) Bash(diff:*) Bash(grep:*) Bash(cat:*) Bash(echo:*) Bash(test:*) Bash(printf:*) Bash(pwd)
---

Set up bushin plugin templates in the **current project's** `.claude/` directory. This command never touches `~/.claude/` — your global settings remain user-managed.

## What gets installed

- `${CLAUDE_PLUGIN_ROOT}/.claude-template/CLAUDE.md`     → `<project>/.claude/CLAUDE.md`
- `${CLAUDE_PLUGIN_ROOT}/.claude-template/settings.json` → `<project>/.claude/settings.json`
- Entry `.claude/` appended to `<project>/.gitignore` if absent.

Plugin **hooks** (sound on `Stop` etc.) are NOT copied — they live in `bushin/hooks/hooks.json` and Claude Code auto-loads them when the plugin is active in the session. Toggle per-project with `/plugin disable bushin@reactivestudio`.

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

## Final summary

```
bushin:setup complete:
  written: N
  identical: M
  overwritten: K
  kept: L
  gitignore: <added | already present>
```

## Important

- This command writes only inside `<project>/`. It never reads, writes, or backs up `~/.claude/`.
- The project-scope `settings.json` does NOT contain Claude Code's plugin-management state (`extraKnownMarketplaces` etc.) — that state lives in user-scope. So a plain copy is safe; no structured merge needed.
- Idempotent: re-run after `/plugin update` to refresh templates, or anytime to top-up missing files.
