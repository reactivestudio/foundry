---
description: Scaffold .foundry/ structure in the current project (idempotent)
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/bin/foundry:*)
---

Run the foundry CLI in plain mode (deterministic output, no TTY prompts):

```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/foundry --plain setup
```

Report exactly what the script printed. Do not embellish — the script's own output is the user-facing message.
