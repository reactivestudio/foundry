---
name: methodology
description: "Entry point and router for the methodology-* family — process discipline (how you work) that wraps every coding task in any language or stack. Owns the always-on coding cadence: think before touching code, surface assumptions, make surgical changes, define verifiable success, verify before claiming done, ask clarifying questions when genuinely ambiguous. Use BEFORE any non-trivial coding work — writing, editing, refactoring, code review where you propose changes — and whenever about to say 'done', 'fixed', 'passing', or 'ready'. Methodology lives on top of every domain skill (clean-code-*, ddd-*, spring-*, test-*) — it decides HOW you work; those decide WHAT you produce. Routes to: karpathy-guidelines (always-on coding discipline), methodology-clarifying-questions (when underspecified), methodology-verification (before any completion claim)."
---

# Methodology

Process discipline for coding work — **how** you work, not **what** you produce.

Domain skills (`clean-code-*`, `ddd-*`, `spring-*`, `test-*`) tell you what good code looks like. The `methodology-*` family tells you how to arrive at it without overcomplicating, overcorrecting, or false-claiming "done".

## When to use

- **Any non-trivial coding task.** Writing, editing, refactoring, code-review where you propose changes — invoke at the start.
- **Ambiguous request.** Multiple plausible interpretations, missing scope, unstated acceptance criteria, unclear environment or constraints — invoke before guessing.
- **About to claim 'done'.** "Fixed", "passing", "working", "ready to merge", "ready to PR" — invoke before saying it. This is the most-skipped methodology step.
- **Unfamiliar with the methodology-\* family.** Use this entry as the map.

## When NOT to use

- Pure read-only exploration ("how does X work?") — no completion claim, no code change.
- Documentation-only edits (Markdown content, comment-only fixes) — no logic to verify.
- Configuration changes with no logic — same.
- Trivial reversible operations (typo in a comment, renaming a local variable in a single function) — apply judgment.

## The family

| Skill | When it applies | Frequency |
|---|---|---|
| `karpathy-guidelines` | Before writing/editing/refactoring code in any language | **Always** (when coding) |
| `methodology-clarifying-questions` | Request is genuinely underspecified and a discovery read won't resolve it | Conditional |
| `methodology-verification` | Before any completion claim — "fixed", "done", "passing", "ready" | Almost-always (at end of task) |

## The cadence

A full coding task moves through four phases. Methodology touches three of them.

```
1. Receive task        ───► if ambiguous: methodology-clarifying-questions
                            else: proceed
2. Plan + code         ───► karpathy-guidelines (always)
                            • surface assumptions
                            • minimum change, nothing speculative
                            • surgical: every line traces to the request
                            • define verifiable success criteria up front
3. Make the change     ───► keep karpathy principles live while editing
4. Claim 'done'        ───► methodology-verification
                            • identify the proving command
                            • run it in this session
                            • read the output, check exit code
                            • only then claim, with evidence
```

Skipping step 4 is the most common failure mode — `methodology-verification` exists precisely because "looks done" diverges from "is done" far more often than feels true.

## Routing decision

| Symptom | Skill |
|---|---|
| "Multiple plausible interpretations, can't tell which" | `methodology-clarifying-questions` |
| "About to write code, no methodology loaded yet" | `karpathy-guidelines` |
| "Tempted to refactor adjacent code while fixing a bug" | `karpathy-guidelines` §3 (Surgical) |
| "Wrote 200 lines, gut says it could be 50" | `karpathy-guidelines` §2 (Simplicity) |
| "About to say 'tests pass' / 'should work now'" | `methodology-verification` |
| "Subagent reported success — should I trust the report?" | `methodology-verification` (verify the diff) |
| "Wrote a regression test that passes — done?" | `methodology-verification` (red-green-revert) |

## Pair with domain skills

`methodology-*` sits above domain skills, not in their place.

- Designing a class hierarchy? `methodology` for process; `solid-principles` / `grasp-patterns` for substance.
- Debugging a flaky test? `methodology` for process; `debugging-systematic` for substance.
- Reviewing a PR? `methodology` for process; `clean-code-*` for smell vocabulary.
- Picking a test layer? `methodology` for process; `test-strategy` / `testing-strategy-kotlin-spring` for substance.

Same in reverse: domain skills assume good methodology. `clean-code-functions` doesn't re-teach "verify before claim" — it leans on `methodology-verification` to enforce it.

## Family-level anti-patterns

- **Ceremony over substance.** Invoking methodology skills and then reciting their structure back at the user is misuse. The principles are internal scaffolding; they should change your *actions*, not pad your *output*.
- **Skipping verification because the change feels safe.** That feeling is exactly the moment `methodology-verification` exists to catch. Run the proving command anyway — the cost is small; the cost of an unverified false-positive is large.
- **Clarifying questions as a stalling tactic.** If you find yourself asking questions to defer hard work, do the work instead. `methodology-clarifying-questions` has its own NOT-use list — respect it.
- **Treating methodology as optional for "small" changes.** Surgical (§3) and verification apply *especially* to small changes — those are where assumptions go uninspected and "trivial" silently turns into a 200-line diff.

## Related (non-methodology) skills

| Skill | Why it pairs |
|---|---|
| `debugging-systematic` | Process discipline for *bugs specifically*. Its Phase 4 delegates to `methodology-verification`. |
| `simplify` | Applies karpathy §2 (Simplicity First) over an existing diff. |
| `clean-code` | Smell vocabulary and refactoring cadence — methodology owns the meta-cadence above it. |
