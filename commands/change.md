---
description: Browse / create / drill into a change in .foundry/
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/change.sh:*), AskUserQuestion
---

Argument: `$ARGUMENTS`

First read the lifecycle and conventions skills so your slug generation and mutation choices match the framework:
- `${CLAUDE_PLUGIN_ROOT}/skills/workflow/lifecycle/SKILL.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/workflow/conventions/SKILL.md`

Then classify the argument into exactly one of three intents:

## (a) No argument → **list**

Run and show output verbatim:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/change.sh list
```

Stop. No follow-up question — user can re-invoke with a slug to drill.

## (b) Argument looks like a free-form title (multi-word, contains space, or quoted) → **new**

1. Generate a kebab-case slug from the title following [conventions/SKILL.md](${CLAUDE_PLUGIN_ROOT}/skills/workflow/conventions/SKILL.md): lowercase, `[a-z0-9-]` only, ≤40 chars, semantic (not just first-N-words). Examples: `"Rate limiting for /api/orders"` → `add-rate-limiting`; `"Fix flaky kafka consumer test"` → `fix-flaky-kafka-test`.
2. Run:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/change.sh new <slug> "<title>"
   ```
3. Report the created path. Mention: user should edit `proposal.md` next, then re-invoke `/foundry:change <slug>` to drill.

## (c) Argument is a single kebab-case token → **drill**

1. Run:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/change.sh show <slug>
   ```
2. Based on current bucket, present a single `AskUserQuestion` with valid next actions. Use the transition matrix from [lifecycle/SKILL.md](${CLAUDE_PLUGIN_ROOT}/skills/workflow/lifecycle/SKILL.md):
   - `backlog` → Start (move to in-progress), Decline, Edit title, Cancel
   - `in-progress` → Finish (move to done), Pause (revert to backlog), Decline, Cancel
   - `done` → Cancel (terminal — no mutations)
   - `declined` → Revive (back to backlog), Cancel
3. If user picks Decline, ask a second question for the reason (free text).
4. Execute the corresponding `change.sh move <slug> <to> [reason]`. Report the script's output verbatim.

## Hard rules

- Never edit `.foundry/changes/**` files directly — always go through `change.sh`.
- Never invent a transition not listed in lifecycle/SKILL.md.
- If the script exits non-zero, report stderr verbatim and stop. Do not retry with a different transition to "make it work".
