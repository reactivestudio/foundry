---
name: debugging-systematic
description: "Root-cause debugging methodology for bugs, test failures, exceptions, crashes, performance regressions, integration issues, and unexpected behaviour. Enforces a 4-phase investigation (investigate → pattern → hypothesis → fix) and a 3-fix tripwire that escalates to architectural reconsideration if multiple fixes fail. Use BEFORE proposing any fix, especially when under time pressure, when a previous fix didn't work, when symptoms are deep in a call stack, or when a multi-component system is failing in unclear ways. Use when test failures, exceptions, mysterious behaviour, performance regressions, build failures, or any 'something is wrong but I don't know why' situation appears."
risk: safe
source: "obra/superpowers (MIT) — adapted"
date_added: "2026-05-12"
---

# Systematic Debugging

> "The fix you apply without understanding the root cause is the next bug you'll have to fix."

Random fixes feel fast, but they cost more than they save: each guess that doesn't work moves the bug somewhere else, and the next fix has to undo the previous one. Systematic debugging is not slower — it converges faster, because each phase rules out a class of explanations instead of guessing one at a time.

## Use this skill when
- A test is failing, a deploy is breaking, a request is throwing, a process is crashing, a metric is regressing.
- A previous fix didn't work, or "fixed it" but the symptom moved.
- The system has multiple components (CI → build → signing, API → service → DB → cache, etc.) and you can't tell where it breaks.
- Performance regression appeared and the cause isn't obvious from the diff.
- Under time pressure — *especially* then; pressure is when guessing feels rational.
- The user says "this is broken" without further explanation.

## Do not use this skill when
- The task is purely **planning, designing, or refactoring working code** — there's no symptom to root-cause.
- The task is **read-only investigation / answering "how does this work"** — that's exploration, not debugging.
- The error message already tells you the exact fix (e.g. a typo in a config key, an obvious null check) AND the fix is local and verifiable — overhead exceeds value.
- You're producing **status reports or progress updates** with no claim of "fixed" attached.

## The 4-phase methodology

Each phase rules out a class of explanations. Skipping ahead is the #1 cause of fix-and-revert cycles — not because of a rule, but because the next phase's hypothesis is only as good as the previous phase's evidence.

### Phase 1 — Investigate
Goal: understand **what** is broken and **what changed**, before forming any hypothesis.

1. **Read the error completely.** Stack trace, error codes, line numbers. Errors often contain the literal answer.
2. **Reproduce reliably.** Exact steps. Does it happen every time, or sometimes? If you can't reproduce, gather more data — don't guess.
3. **Check recent changes.** `git log`, recent commits, dependency bumps, config changes, environmental differences. The fix is usually adjacent to the change that introduced the bug.
4. **In multi-component systems, instrument boundaries.** Log what enters/leaves each component. This reveals *where* it breaks before you investigate *why*. → `resources/multi-component-diagnostics.md` for the pattern.
5. **Trace data flow up.** When an error is deep in a stack, find where the bad value originated, not where it surfaced. Fix at the source.

### Phase 2 — Pattern
Goal: locate working examples that resemble the broken one. Differences between working and broken are the suspect set.

1. **Find working examples** of similar code in the same codebase. Something *works*; learn from it.
2. **Read references completely.** If you're implementing a pattern from a library or doc, read every line — don't skim. Partial understanding causes specific bugs.
3. **List every difference** between working and broken. Even ones that "can't matter." Especially those.
4. **Understand the dependencies and assumptions** that the working code relies on — config, ordering, environment, lifecycle.

### Phase 3 — Hypothesis
Goal: form a *single* testable theory and prove it cheaply.

1. **State one hypothesis explicitly.** "I think X is the root cause because Y." Write it down. Vague hypotheses produce vague tests.
2. **Test minimally.** Smallest possible change that would confirm or refute. One variable at a time. Don't bundle "while I'm here" changes.
3. **Verify before continuing.**
   - Confirmed → Phase 4.
   - Refuted → form a *new* hypothesis. Don't pile fixes on top of the failed one.
4. **Admit ignorance honestly.** "I don't understand X" is not a failure — it's a signal to research or ask. Pretending to understand produces the worst fixes.

### Phase 4 — Fix
Goal: change the root cause, prove the bug is gone, prove nothing else broke.

1. **Write a failing test first** that reproduces the symptom — even a one-off script. Without it you cannot prove the fix worked.
2. **Apply one change.** Address the root cause from Phase 3. No "while I'm here" cleanup, no bundled refactors — surgical only. (See `karpathy-guidelines` §3.)
3. **Verify the fix.** Test passes, no other tests broke. Use `methodology-verification` to enforce evidence-before-claim.
4. **If the fix doesn't work, count.** If you've tried < 3 fixes, return to Phase 1 with what you learned. If ≥ 3 fixes have failed, **stop and question the architecture** (next section).

## The 3-fix tripwire

If three fixes have failed, the pattern under repair is almost certainly wrong — not just the line of code. Symptoms of this:
- Each fix reveals a new problem in a different place (whack-a-mole).
- The "right" fix would require "massive refactoring" of nearby code.
- Each fix creates a new symptom.

At this point, the issue is architectural, not local. Pause and ask:
- Is this pattern fundamentally sound for what we're doing?
- Are we sticking with it through inertia rather than fit?
- Should we step back and reshape the design instead of continuing to patch?

Discuss with the user before attempting fix #4. Escalate to `architect-review` (audit) or `architecture` (re-decide) as appropriate. **This is not a failed hypothesis — it's a wrong shape.**

## Red flags — stop and return to Phase 1

If you catch any of these in your own thinking, the methodology is being skipped:

- "Quick fix for now, investigate later."
- "Just try changing X and see if it works."
- "Multiple changes at once, run tests."
- "I'll skip the test, manually verify."
- "It's probably X — let me fix that." (no evidence yet)
- "I don't fully understand, but this might work."
- "Reference says X, but I'll adapt it differently."
- Proposing solutions before tracing data flow.
- "One more fix attempt" (when 2+ have already failed).

The user often signals the same thing: "*Stop guessing*", "*Is that not happening?*", "*Will it show us...?*", "*We're stuck?*" — those are redirections back to evidence.

## Common rationalizations (full table in `resources/rationalizations.md`)

The shortest version: every excuse for skipping the methodology is an artifact of the same mistake — confusing **certainty** with **evidence**. Two of the most common:

| Excuse | What's actually true |
|---|---|
| "Emergency, no time for process." | Systematic debugging is faster than guess-and-check thrashing. The clock is the reason to be rigorous, not to skip. |
| "Issue is simple, I see the problem." | Seeing the symptom isn't understanding the cause. Simple bugs have root causes too — usually they're cheap to confirm. |

Full catalog of recurring excuses in `resources/rationalizations.md`.

## When investigation finds no root cause

Occasionally a real issue is environmental, timing-dependent, or external — flaky network, a race condition in an upstream service, a kernel bug. Sequence:

1. Document what you investigated and ruled out.
2. Implement appropriate handling: retry with backoff, timeout, circuit breaker, idempotency, clear error to the user.
3. Add monitoring / logging so the *next* occurrence has the evidence this one didn't.

But: ~95% of "no root cause" verdicts are incomplete investigation. Spend more time before settling.

## Selective reading rule

| File | When to read |
|---|---|
| `resources/multi-component-diagnostics.md` | Phase 1, step 4 — the cross-boundary instrumentation pattern with Kotlin/Spring + shell examples. Used when a system spans CI → build → deploy or service → service → DB. |
| `resources/rationalizations.md` | When you catch yourself reaching for a shortcut — the table of common excuses and what each one actually means. |

## Related skills

| Skill | Role |
|---|---|
| `methodology-verification` | Phase 4 step 3 — produce the evidence that proves the fix landed. |
| `karpathy-guidelines` | §1 think before coding, §3 surgical changes. Aligns with "one change at a time" in Phase 4. |
| `methodology-clarifying-questions` | When the symptom report is too vague to start Phase 1, ask instead of guessing. |
| `architect-review` | When the 3-fix tripwire fires — audit the current design. |
| `architecture` | When `architect-review` confirms the shape is wrong — re-decide. |
| `jvm-performance` | When the symptom is latency / GC / OOM, the methodology is the same but the tools are specialized. |
| `clean-code` | Smell catalog — sometimes Phase 2's "find working examples" points at a known smell pattern. |

## Why the methodology converges faster than guessing

The intuition that "just trying things" is faster than investigation is the most expensive intuition in debugging. A random fix has roughly three outcomes:

1. It works — but you don't know *why*, so the next similar bug returns.
2. It doesn't work — and now you have one more variable in the system, complicating the next attempt.
3. It "works" by side effect — the bug moves somewhere else, surfaces later, and the fix has to be unwound under more pressure.

Systematic debugging trades a few minutes of evidence-gathering for the elimination of outcomes 2 and 3. The single metric worth caring about is the last one: random fixes don't just take longer, they leave the codebase worse than they found it.

## Limitations
- The methodology assumes you have access to the system, logs, and the ability to instrument. When debugging from a screenshot alone, Phase 1 is partially blind — surface that.
- A 4-phase walk is overhead for genuinely trivial bugs (typo in a string, obvious null). Apply judgment; the methodology serves you, not the reverse.
- Stop and ask if symptoms are unclear, reproduction is impossible, or scope is ambiguous — Phase 1 cannot start without something to investigate.
