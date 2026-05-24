---
name: workflow-enforcement
description: Catalogue of foundry's enforcement scripts (M4 + M8 + M5 substrate). Use when a stage gate needs to validate an artifact, when wrapping a build/test command for an agent, or when reading the trajectory log to decide on a context restart.
---

# Enforcement substrate

Foundry's discipline isn't in prompts — it's in **scripts that fail** when an artifact or trajectory violates a rule from the talks. Phase 2 ships five trustable (deterministic, no heuristic) scripts. Phase 3+ producer-agents wire them into stage gates.

## Scripts

### `scripts/lint/line-count.sh <file> <max>`

**Enforces:** [CRISPY §4](../../../roadmap/CRISPY.md) (design ≤220), [§5](../../../roadmap/CRISPY.md) (structure outline ≤100), [NO-VIBES §6](../../../roadmap/NO-VIBES.md) (sub-agent response ≤30).

Counts content lines (non-blank, non-comment-only, non-separator). `--raw` disables filtering for absolute count.

```
$ line-count.sh design.md 220
line-count PASS: design.md = 187 / 220
$ line-count.sh design.md 100
line-count FAIL: design.md has 187 content lines (max 100)
# exit 1
```

### `scripts/lint/opinion-words.sh <file>`

**Enforces:** [CRISPY §3](../../../roadmap/CRISPY.md): «research = facts only, no opinions». Greps for banned words (case-insensitive):

- EN: `recommend`, `suggest`, `should`, `ought`, `better`, `prefer`, `propose`, `advise`, `ideally`, `preferable`
- RU: `следует`, `рекомендую`, `рекомендуется`, `лучше`, `предлагаю`, `предпочтительно`, `желательно`

**Skips fenced code blocks** (` ```...``` `) — opinion words inside quoted snippets are fine.

```
$ opinion-words.sh research.md
opinion-words FAIL: research.md
  research.md:12:I recommend using Bucket4j
# exit 1
```

### `scripts/wrap/build-check.sh`

**Enforces:** [12-FACTOR §7](../../../roadmap/12-FACTOR.md): «Compact errors in context. Don't dump full gradle output».

Runs `./gradlew build` (auto-detects wrapper / system gradle). On success: `PASS` + duration. On failure: `FAIL` + last 20 lines filtered for `FAILURE:`, `BUILD FAILED`, `What went wrong`, kotlin `e:`/`w:` prefixes, exceptions, stack frames.

Override line cap with `BUILD_CHECK_MAX_LINES` env var.

### `scripts/wrap/test-check.sh`

**Enforces:** same compaction principle for `./gradlew test`. Filters for `FAILED`, `Tests run`, `Caused by`, stack frames, gradle task lines. Cap via `TEST_CHECK_MAX_LINES`.

### `hooks/trajectory-counter.sh`

**Enforces:** [NO-VIBES §4](../../../roadmap/NO-VIBES.md) observability. Registered as `PostToolUse` hook in `hooks/hooks.json`. After every tool call, appends one TSV line to `<project>/.foundry/.trajectory.log`:

```
<ISO-8601>\t<tool_name>\t<ok|error>\t<excerpt>
```

Detects error via `tool_response.is_error == true`, non-empty `stderr`, or top-level `error` field. **Never blocks.** Silently no-ops if `.foundry/` missing or `jq` unavailable.

## Reading the trajectory log (counting consecutive errors)

Phase 6 implementor pattern — count consecutive errors at log tail:

```bash
n=0
while IFS=$'\t' read -r ts tool res excerpt; do
  if [[ "$res" == "error" ]]; then n=$((n+1)); else break; fi
done < <(tail -r .foundry/.trajectory.log 2>/dev/null || tac .foundry/.trajectory.log)
echo "$n"
```

When `n >= 2` → propose `/foundry:change` to restart context with the existing artifact (per NO-VIBES §4: «at first sign of bad trajectory → new context»).

## Phase-by-phase plug-in plan

| Phase | Producer | Wires up |
|---|---|---|
| 3 | researcher | `opinion-words.sh research.md` + `line-count.sh research.md 30` (per sub-agent return) |
| 4 | designer | `line-count.sh design.md 220` |
| 5 | outliner | `line-count.sh structure.md 100` |
| 6 | implementor | `build-check.sh` + `test-check.sh` after each step; trajectory-counter read for restart decision |
| 7 | verifier | `build-check.sh` + `test-check.sh` as part of verification report |

## What's intentionally NOT here

- **instruction-count.sh** — deferred. CRISPY §1 caps ≤40 instructions per agent prompt, but doesn't define «instruction» precisely. Wait for first real agent.md in Phase 3 to calibrate the counting heuristic on actual content.
- **horizontal-pattern.sh** — deferred. CRISPY §6 describes horizontal plans by example, not by regex signature. Wait for first structure outline in Phase 5.
- **Smart Zone (≤35% context fill) auto-check** — explicitly **not** enforced. See ROADMAP §«Что фреймворк НЕ enforce'ит»: token count mid-session unreliable, threshold fuzzy ([CRISPY Q&A](../../../roadmap/CRISPY.md): Dex regularly goes to 60%), Goodhart. Use Claude Code's built-in `/context` + discipline.

## Hard rule for producer-agents

When you receive a stage-completion gate, **always** invoke the matching lint script(s) and fail the gate on nonzero exit. Never paraphrase the lint message — print stderr verbatim. The script is the source of truth.
