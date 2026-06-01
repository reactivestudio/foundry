---
description: Browse / create / drill into a change in .foundry/
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/bin/foundry:*), AskUserQuestion
---

Argument: `$ARGUMENTS`

First read the lifecycle and conventions skills so your slug and action choices match the framework:
- `${CLAUDE_PLUGIN_ROOT}/skills/workflow/lifecycle/SKILL.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/workflow/conventions/SKILL.md`

All foundry calls below MUST use `--plain` — Claude is not a TTY and the interactive UI relies on a real terminal.

Classify the argument into exactly one of three intents:

## (a) No argument → **list**

```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/foundry --plain list
```

Show the output verbatim. Stop — user can re-invoke with a slug to drill.

## (b) Argument looks like a free-form title (multi-word, contains space, or quoted) → **new**

1. Generate a kebab-case slug from the title following [conventions/SKILL.md](${CLAUDE_PLUGIN_ROOT}/skills/workflow/conventions/SKILL.md): lowercase, `[a-z0-9-]` only, ≤40 chars, **semantic** (not first-N-words). Examples: `"Rate limiting for /api/orders"` → `add-rate-limiting`; `"Fix flaky kafka consumer test"` → `fix-flaky-kafka-test`.
2. Pass the slug to foundry via env so it overrides the default ASCII-fold:
   ```bash
   FOUNDRY_SLUG=<your-slug> bash ${CLAUDE_PLUGIN_ROOT}/bin/foundry --plain new "<title>"
   ```
3. Report the created slug verbatim. Mention: user should edit `proposal.md` next, then `/foundry:change <slug>` to drill.

## (c) Argument is a single kebab-case token → **drill**

1. Show the change:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/bin/foundry --plain show <slug>
   ```
2. Read the `status:` field from the output. Based on it, present a single `AskUserQuestion` with valid next actions from [lifecycle/SKILL.md](${CLAUDE_PLUGIN_ROOT}/skills/workflow/lifecycle/SKILL.md):
   - `backlog` → Start (move to in-progress), Decline, Cancel
   - `in-progress` → Finish (move to done), Pause (revert to backlog), Decline, Cancel
   - `done` → Cancel (terminal — no mutations)
   - `declined` → Revive (back to backlog), Cancel
3. If user picks Decline, ask a second question for the reason (free text).
4. Execute via foundry:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/bin/foundry --plain move <slug> --to=<bucket> [--reason=<reason>]
   ```
5. Report the script's output verbatim.

## Hard rules

- Always use `--plain`. Never invoke `foundry` without it from Claude Code.
- Never edit `.foundry/changes/**` files directly — always go through `bin/foundry` or `scripts/change.sh`.
- Never invent a transition not listed in lifecycle/SKILL.md.
- If a command exits non-zero, report stderr verbatim and stop. Do not retry with a different transition to "make it work".
