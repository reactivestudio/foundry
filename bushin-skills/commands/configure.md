---
name: configure
description: "Interactive editor for ~/.claude/settings.json: model, permissions allow/deny, env, hooks. JSON validated before write."
---

Interactive editor for `~/.claude/settings.json`. Drives edits via AskUserQuestion + Read/Write/Bash; never writes invalid JSON.

## Sub-flows

Ask the user which area to edit (multi-select via AskUserQuestion):

1. **model** — default model for sessions (`claude-sonnet-4-6`, `claude-opus-4-7`, `claude-haiku-4-5`, or custom).
2. **permissions.allow** — add or remove allow patterns (tools, bash command prefixes).
3. **permissions.deny** — add or remove deny patterns.
4. **env** — add/remove environment variables (e.g. `BASH_MAX_OUTPUT_LENGTH`).
5. **hooks** — add/remove hooks for `Stop`, `SubagentStop`, `Notification`, `SessionEnd`, etc.

For each chosen area, run the corresponding sub-flow below.

## Procedure (per sub-flow)

1. **Read** the current `~/.claude/settings.json`. If it doesn't exist, error out and suggest `/setup-global-settings` first.
2. Use `jq` to extract the current value of the chosen section.
3. Show the current value to the user.
4. Ask via AskUserQuestion what to change (concrete options depend on the section — see below).
5. Build the new value as a JSON snippet.
6. Apply via `jq` to produce the new full settings.json content.
7. **Validate** with `jq . <newcontent>` (or write to a temp file and `jq . tmpfile`). If invalid, abort and report the error.
8. Backup the current file to `~/.claude/.bak/<UTC>/settings.json` (create directory once).
9. Write the new content to `~/.claude/settings.json`.

## Sub-flow specifics

### model
AskUserQuestion with options: `claude-sonnet-4-6`, `claude-opus-4-7`, `claude-haiku-4-5`. (User can pick "Other" for custom.) Set `.model = <chosen>`.

### permissions.allow / permissions.deny
Show current array, numbered. Ask:
- **Add pattern** — prompt for free text (e.g. `Bash(npm test:*)`).
- **Remove pattern** — list current entries with numbers; user picks index to remove.
- **Done**.

Repeat until user picks Done. Apply changes with `jq '.permissions.allow += [...]'` / `del(.permissions.allow[N])`.

### env
Show current `env` object. Ask:
- **Add/update key** — prompt for `KEY=VALUE`.
- **Remove key**.
- **Done**.

### hooks
Show current `hooks` object (event → array of hook configs). Ask:
- **Add hook** — choose event (`Stop`, `SubagentStop`, `Notification`, `SessionEnd`), then prompt for a shell command. Wrap in the standard `{type: "command", command: "..."}` structure.
- **Remove hook** — list current hooks numbered; pick to remove.
- **Done**.

## Important

- Never write a settings.json that fails `jq .` validation.
- Always backup before write (`~/.claude/.bak/<UTC>/settings.json`).
- After write, print the diff summary: which keys changed.
- If the user picked multiple areas to edit in step "which area", run sub-flows sequentially, but only **write the file once at the very end**, after collecting all changes.
