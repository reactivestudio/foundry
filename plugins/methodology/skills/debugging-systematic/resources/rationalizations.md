# Common Rationalizations

> Every excuse for skipping the methodology comes from the same place: confusing **certainty** with **evidence**. Below is the catalog of recurring excuses and what each one actually means in practice.

Read this when you catch yourself reaching for a shortcut. It's not a rebuke — it's a checklist for whether the shortcut is justified or whether it's about to cost an hour you can't see yet.

## The catalog

| Excuse you're telling yourself | What it actually means |
|---|---|
| **"Issue is simple, don't need the process."** | Simple bugs have root causes too. The process is fast for simple bugs (you find the cause in 30 seconds) and only feels slow when you're trying to skip it. Run it; it's cheap. |
| **"Emergency, no time for the process."** | The clock is the reason to be rigorous, not to skip. Random fixes under pressure produce two-hour thrashing sessions; systematic debugging produces a 15-minute fix. The methodology *is* the fast path. |
| **"Just try this first, then investigate."** | The first fix sets the pattern for the session. If it doesn't land, you're now debugging *with* a half-applied speculative change in the codebase. Do it right from the start; the speculative-fix has negative time-value. |
| **"I'll write the test after confirming the fix works."** | Untested fixes don't stick — they pass manually once and then regress when something adjacent changes. Test first, fix second, prove the test fails without the fix. Cheaper than discovering the regression in two weeks. |
| **"Multiple fixes at once saves time."** | If multiple changes succeed together, you don't know which one mattered. If they fail together, you don't know which one broke. Cannot diagnose, cannot revert cleanly. Net cost is higher, not lower. |
| **"Reference is too long, I'll adapt the pattern."** | Partial understanding produces specific, hard-to-spot bugs. The skipped paragraph usually contains the constraint you would have violated. Read the reference completely the first time; you only have to do it once. |
| **"I see the problem, let me fix it."** | Seeing the symptom is not understanding the cause. The visible bad value almost always originates somewhere else — fix it at the symptom and the root reappears as a different symptom next week. |
| **"One more fix attempt."** (after 2+ have already failed) | The 3-fix tripwire exists because the pattern of fixes-not-working past three attempts is overwhelmingly the architecture, not the bug. The expected value of fix #4 in this state is negative — it usually produces more code to revert. |
| **"It's probably X."** | "Probably" is a hypothesis, not evidence. The hypothesis is fine — Phase 3 is designed to test it cheaply. Skipping the test and jumping to the fix means you're not testing the hypothesis; you're acting on faith. |
| **"I don't fully understand but this might work."** | "Might work" fixes that work-by-accident are the worst kind: they pass review, ship, and produce a recurring incident that's nobody's clear responsibility. Stop and ask. |
| **"The user wants it fixed NOW."** | Users want *the bug gone*, not *a fix attempted*. A failed fix doesn't address their request — it converts an existing pain into "still painful, plus we did something." Spend the 5 minutes on Phase 1; tell them you're investigating, not stalling. |
| **"I already know this codebase."** | Knowledge of the codebase tells you where to *look*, not what is wrong. Two minutes of grep and stack-reading is faster than the time you'll spend if your familiarity-based guess is wrong. |
| **"The error message is wrong."** | Almost always, the error message is right and your *interpretation* is wrong. Read it again, completely, including the underlying cause if there's a chain. The error has been formed by a system that doesn't lie about itself. |
| **"It's flaky / environmental / not really a bug."** | This verdict belongs at the *end* of investigation, not at the beginning. ~95% of "it's flaky" cases are incomplete investigation. Only conclude flakiness after Phase 1 has actually been walked. |
| **"Pattern says X but I'll adapt it differently."** | Patterns work because of their constraints. "Adapting" usually means dropping the constraint you didn't fully understand — which is also the one that prevents the failure mode the pattern was designed for. |
| **"I'll skip Phase 1 because I already know what changed."** | Knowing what changed is half of Phase 1; the other half is verifying that's what's actually breaking. The change you noticed and the change that broke things aren't always the same change. |

## Why these patterns recur

Each excuse is a way of skipping the step that would have *cost* the least and *prevented* the most. The cognitive shape is the same every time:

1. Pattern-match a quick fix → 2. Feel certainty → 3. Treat certainty as evidence → 4. Skip the cheap verification → 5. Either get lucky (no learning) or get unlucky (twice the work).

The methodology exists to **break step 3**: certainty and evidence are different things, and the cost of verifying is almost always less than the cost of being wrong.

## The honest test

When you catch yourself reaching for one of the excuses above, ask one question:

> If I run the verification right now (the test, the log, the repro, the read-the-reference) — what's the worst case?

The worst case is almost always "I lose two minutes and confirm what I already thought." That's the *worst* case. The best case is you catch the mistake before it costs an hour. The expected value of verifying is positive in nearly every situation that produced the excuse.

## When the excuse is actually justified

A few cases where shortcutting is genuinely fine, so the catalog doesn't sound like an absolute:

- **Typo-class bugs** with an error pointing at the exact line. The "investigation" took 5 seconds — you've already done Phase 1.
- **Compile errors** with a clear message and a single-file fix. The compiler is doing Phase 1 for you.
- **Throwaway prototypes** that won't be merged. The cost-benefit of rigor is different in throwaway code.
- **You've encountered this exact bug recently** and the fix is well-known. (But: verify it's actually the same bug — pattern-match is often wrong here.)

In every other case, the methodology pays for itself.
