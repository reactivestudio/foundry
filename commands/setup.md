---
description: Scaffold .foundry/ in the current project (asks about CLI symlink). For Claude inside a session; terminal equivalent — foundry setup
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/cli:*), AskUserQuestion
---

## Step 1 — ask whether to install the local CLI symlink

Use `AskUserQuestion` with **one** question:

- **question:** "Install local CLI symlink at .foundry/cli? You can then run ./.foundry/cli from this project's terminal."
- **header:** "Install CLI"
- **options:**
  - `Yes` — "Symlink at .foundry/cli points at the plugin's cli. Survives plugin updates."
  - `No` — "Scaffold only. You can still use /foundry:change from Claude Code."

## Step 2 — run setup with the matching flag

If the user picked **Yes**:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/cli --plain setup --install-cli
```

If the user picked **No**:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/cli --plain setup
```

## Step 3 — report

Print the script's output verbatim. Do not embellish — the script's own output is the user-facing message.
