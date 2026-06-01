---
description: Scaffold .foundry/ in the current project + install local CLI symlink
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/bin/foundry:*)
---

Run the foundry CLI in plain mode. `--install-cli` puts a symlink at `.foundry/bin/foundry` so the user can call the CLI from their terminal in this project:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/foundry --plain setup --install-cli
```

Report exactly what the script printed. Do not embellish — the script's own output is the user-facing message.
