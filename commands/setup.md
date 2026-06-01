---
description: Scaffold .foundry/ in the current project (asks about CLI symlink)
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/bin/foundry:*), AskUserQuestion
---

## Step 1 — ask whether to install the local CLI symlink

Use `AskUserQuestion` with **one** question:

- **question:** "Install local CLI symlink at .foundry/bin/foundry? You can then run ./.foundry/bin/foundry from this project's terminal (or add .foundry/bin to PATH)."
- **header:** "Install CLI"
- **options:**
  - `Yes` — "Symlink will point at the plugin's bin/foundry. Survives plugin updates."
  - `No` — "Scaffold only. You can still use /foundry:change from Claude Code."

## Step 2 — run setup with the matching flag

If the user picked **Yes**:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/foundry --plain setup --install-cli
```

If the user picked **No**:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/foundry --plain setup
```

## Step 3 — report

Print the script's output verbatim. Do not embellish — the script's own output is the user-facing message.
