---
name: spec-lint
description: Catalogue of foundry's enforcement scripts (M8 substrate). Use when a stage gate needs to validate an artifact.
---

# Enforcement substrate

Foundry's discipline isn't in prompts — it's in **scripts that fail** when an artifact violates a rule from the talks. Phase 2 ships two trustable (deterministic, no heuristic) scripts. Phase 3+ producer-agents wire them into stage gates.

## Scripts

### `scripts/cli/spec/lint/line-count.sh <file> <max>`

**Enforces:** [CRISPY §4](../../../roadmap/CRISPY.md) (design ≤220), [§5](../../../roadmap/CRISPY.md) (structure outline ≤100), [NO-VIBES §6](../../../roadmap/NO-VIBES.md) (sub-agent response ≤30).

Counts content lines (non-blank, non-comment-only, non-separator). `--raw` disables filtering for absolute count.

```
$ line-count.sh design.md 220
line-count PASS: design.md = 187 / 220
$ line-count.sh design.md 100
line-count FAIL: design.md has 187 content lines (max 100)
# exit 1
```

### `scripts/cli/spec/lint/opinion-words.sh <file>`

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

## Phase-by-phase plug-in plan

| Phase | Producer | Wires up |
|---|---|---|
| 3 | researcher | `opinion-words.sh research.md` + `line-count.sh research.md 30` (per sub-agent return) |
| 4 | designer | `line-count.sh design.md 220` |
| 5 | outliner | `line-count.sh structure.md 100` |
| 6 | implementor | build/test wrappers — to be written in Phase 6 (see below) |
| 7 | verifier | same wrappers as part of verification report |

## What's intentionally NOT here

- **build-check.sh / test-check.sh wrappers** — removed 2026-07-06. Ran gradle build/test and returned compact `PASS`/`FAIL + last N error lines` (12-FACTOR §7). Dropped as premature: gradle-specific, no consumer until Phase 6 implementor. Recreate at Phase 6 for the target project's build tool.
- **trajectory-counter hook** — removed 2026-07-06. Logged every tool call to `.foundry/.trajectory.log` for the Phase 6 «≥2 consecutive errors → new context» heuristic; dropped as premature tooling (noisy stderr-based error detection, jq dependency, no consumer until Phase 6). Trajectory protection stays engineer's discipline; revisit at Phase 6 if a real need shows up.
- **instruction-count.sh** — deferred. CRISPY §1 caps ≤40 instructions per agent prompt, but doesn't define «instruction» precisely. Wait for first real agent.md in Phase 3 to calibrate the counting heuristic on actual content.
- **horizontal-pattern.sh** — deferred. CRISPY §6 describes horizontal plans by example, not by regex signature. Wait for first structure outline in Phase 5.
- **Smart Zone (≤35% context fill) auto-check** — explicitly **not** enforced. See ROADMAP §«Что фреймворк НЕ enforce'ит»: token count mid-session unreliable, threshold fuzzy ([CRISPY Q&A](../../../roadmap/CRISPY.md): Dex regularly goes to 60%), Goodhart. Use Claude Code's built-in `/context` + discipline.

## Hard rule for producer-agents

When you receive a stage-completion gate, **always** invoke the matching lint script(s) and fail the gate on nonzero exit. Never paraphrase the lint message — print stderr verbatim. The script is the source of truth.
