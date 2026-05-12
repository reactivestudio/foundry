---
name: methodology-verification
description: "Discipline for making completion claims only after running verification and reading the output — evidence before assertions. Use BEFORE saying anything is fixed, done, passing, working, ready to commit, or ready to PR. Catches the moment between 'change is made' and 'change is verified' where false positives are introduced. Requires running the proving command (test, build, lint, smoke check) in the current session and confirming the output, not citing a previous run or a 'should pass' intuition."
risk: safe
source: "obra/superpowers (MIT) — adapted"
date_added: "2026-05-12"
---

# Verification Before Completion

> "Completion claims without verification produce false positives that cost more to fix than they save up front."

A change is two distinct things: a *modification* and a *verified outcome*. Forgetting that distinction is the single most common source of "but I tested it" regressions — the test wasn't run, or wasn't run after the last change, or was run on a stale build. This skill is the gate that keeps the two events bound together.

## Use this skill when
- About to say "fixed", "done", "passing", "working", "ready", "✅", or any equivalent.
- About to commit, push, open a PR, mark a task complete, or move to the next task.
- About to claim an agent / subagent succeeded based on its own report.
- A subjectively-confident moment ("this is right") is about to become an objective claim.
- Reviewing a fix that was made earlier in the session and is now being concluded.

## Do not use this skill when
- The work is **read-only investigation** (answering "how does X work", reading a file, summarizing a codebase). There is no completion claim to verify.
- The output is an **intermediate progress update** ("I'm partway through", "still working on this"). Verification applies to *conclusions*, not narration.
- The output is a **status-of-the-world report** ("here's what I see in the diff", "the test suite has 3 failures"). Reporting state is not claiming completion.
- The task is **producing a plan or design** that doesn't need execution. The plan is the deliverable; no verification needed.
- The change is **so trivial it has no failure mode** (e.g. fixing a typo in a comment, renaming a local variable). Apply judgment — the discipline serves you.

## The gate

Before any claim of completion or success, work through these five steps in order. If any step fails, the claim must be revised to match the actual state.

1. **Identify** — what specific command would prove this claim? (`./gradlew check`, `npm test`, `pytest tests/foo.py`, a manual smoke check with declared pass criteria.)
2. **Run** — execute the full command, fresh, in this session. Not a previous run. Not a partial run.
3. **Read** — full output. Check the exit code. Count failures explicitly if the output is long.
4. **Verify** — does the output confirm the claim? If no, state actual status with evidence. If yes, state the claim *with* the evidence.
5. **Then** — make the claim, paired with the proof.

If a step is skipped, the resulting claim is unsupported — not necessarily wrong, but unverified, and "unverified" is the honest label.

## Common false-positive shapes

These are the recurring shapes where "looks done" diverges from "is done":

| Claim | What actually proves it | Common shortcut that fails |
|---|---|---|
| Tests pass | Test command in this session: `0 failures` in output, exit 0. | "Previous run was green", "they should pass now." |
| Linter clean | Linter output: `0 errors / 0 warnings` for the changed scope. | "Linter passed earlier", or extrapolating from a partial check. |
| Build succeeds | Build command: exit 0. | "Linter passed" (linter ≠ compiler), "looks like it compiles." |
| Bug fixed | The original failing test / repro now passes (and previously failed). | "Code changed in the right place, assumed fixed." |
| Regression test works | TDD red-green-revert verified: test fails without the fix, passes with it. | "I wrote a regression test" (without confirming it actually catches the bug). |
| Subagent completed | VCS diff shows the expected changes; spot-check at least one. | Trusting the agent's "success" report verbatim. |
| Requirements met | Line-by-line walkthrough of the original ask, gaps named explicitly. | "Tests pass, so the feature is done." |
| Migration applied | Schema check OR `flyway info` shows the migration in `Success` state. | "Migration file exists." |

## Red flags — your own language

If you catch yourself writing or thinking these *before* running the verification:

- "Should pass now."
- "Probably works."
- "Seems to."
- "Looks correct."
- "Great!" / "Perfect!" / "Done!" / "✅"
- "Just one more thing and we're done."
- Composing a commit message before the test has finished.

…that's the moment to stop and run the proving command. The cost of confirming is small; the cost of an unverified completion claim that turns out wrong is large — you've now misled the user, and the next message has to walk it back.

## TDD red-green-revert pattern

The regression-test case deserves its own callout. A test that "passes now" doesn't prove it would have caught the bug — it might pass for unrelated reasons. The honest sequence:

1. Write the test.
2. Run it on the current (fixed) code → passes.
3. Revert the fix → run it again → **must fail** (otherwise the test doesn't actually probe the bug).
4. Restore the fix → run it → passes.
5. Now the test is proven to catch this specific regression.

Without step 3, you have a passing test of unknown value. Confidence in the test is proportional to having seen it red.

## Stack-specific verification commands (Kotlin/Spring)

| Claim | Command |
|---|---|
| All tests pass | `./gradlew check` (full) or `./gradlew :module:<name>:test` (scoped). |
| Module compiles | `./gradlew :module:<name>:compileKotlin`. |
| Lint clean | `./gradlew lintKotlin`. |
| Format applied | `./gradlew formatKotlin` (then `lintKotlin` to confirm). |
| App boots | `./gradlew :app:bootRun`, then `curl /actuator/health` returns `UP`. |
| Migrations apply | `./gradlew :app:flywayMigrate`. |
| Image builds | `make dev-image`. |

These are the exact commands; cite them as evidence, not paraphrases. ("I ran the tests" is weaker than "`./gradlew check` exit 0".)

## Why this matters

Trust between a contributor and the rest of the team is broken more by false completion claims than by honest mistakes. A bug that ships because nobody ran the test is reproducible; a bug that ships because someone *said* they ran the test, but didn't, erodes the assumption that words mean what they say. Slow truth costs less than fast falsity — every time.

## Related skills

| Skill | Role |
|---|---|
| `karpathy-guidelines` | §4 Goal-Driven Execution defines what counts as success at planning time. This skill enforces actually checking the criteria at completion time. |
| `debugging-systematic` | Phase 4 step 3 explicitly delegates to this skill — fixes need evidence, not just code changes. |
| `clean-code` | Pre-merge cadence rules when refactoring (one smell / one fix / one commit); works hand-in-hand with this skill at PR time. |
| `testing-strategy-kotlin-spring` | Designs what the verification *is*; this skill enforces actually running it. |

## Limitations
- Verification is only as good as what's being verified. A passing test for the wrong scenario is still a false positive — pair the verification run with a question of whether the test actually probes the claim (`testing-strategy-kotlin-spring` helps design that probe).
- Some claims cannot be verified by a single command (UI behaviour, third-party integrations, production behaviour). Decompose them into the smallest verifiable parts and verify each; declare the rest as "checked manually under conditions X" with the conditions named.
- Stop and ask if the proving command is unclear, or if the success criteria for the task were never declared — completion has no meaning without criteria.
