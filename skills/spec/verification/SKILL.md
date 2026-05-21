---
name: spec-verification
description: "Verification-stage rules: Q-task taxonomy (tests/exploratory/security/perf), verification-report.md schema. NOT for roadmap syntax."
---

# spec-verification

Knowledge for the verification stage: execute the Q-gates defined in `roadmap.md` and produce `verification-report.md` aggregating their outcomes. Used by the `qa-engineer` agent.

## When to use

- Running Q-gates from `roadmap.md` during verification stage.
- Categorising a Q-gate to pick the right execution approach.
- Writing or reviewing `verification-report.md`.

## Q-task taxonomy

Four canonical categories. Each Q-task in `roadmap.md` should fall into one — the **Acceptance** wording usually makes the category obvious.

| Category | What it verifies | Execution |
|---|---|---|
| **Functional** | FRs pass tests (unit + integration) | run test suite via Bash; capture exit code + counts |
| **Exploratory** | UX flows / end-to-end scenarios | manual — instruct user with explicit step list; capture user's pass/fail report |
| **Security** | NFR-security threats are mitigated (no plaintext secrets, no SSRF, etc.) | combination: automated scans (SAST/dependency-audit) + manual review of threat-model items |
| **Performance** | NFR-perf budgets met (p95 latency, throughput) | run benchmark harness if exists; otherwise instruct user to run + report numbers |

Each Q-task should be **one category**. Multi-category Qs should split (e.g. "functional + security" → `Q3` functional, `Q4` security).

## Execution patterns

For each Q-task, by category:

### Functional Q
1. Read Acceptance — it names a command (`./gradlew test`, `npm test`, `pytest`).
2. Run via `Bash`. Capture stdout/stderr summary, exit code, test counts.
3. Pass = exit 0 + counts match expectation. Fail = anything else.
4. On fail: do NOT iterate-fix-rerun (that's `code-implementor`'s job at impl stage). Report failure; orchestrator routes back.

### Exploratory Q
1. Read Acceptance — it names a scenario.
2. Print to user: numbered manual steps, expected observation at each step.
3. **AskUserQuestion**: "Did the scenario pass?" → Yes / No / Skip (defer).
4. On No: ask user for one-line failure note via Other.

### Security Q
1. Read Acceptance — threat or control to verify.
2. Combine: if automated tool exists in project (Bandit, npm audit, OWASP ZAP) → Bash. Capture findings.
3. Walk the threat model item: cite which design/code element provides the control. Reference `system-design.md` if it covers this.
4. **AskUserQuestion** if subjective ("Does the implementation match the documented control?"): Yes / No / Needs review.

### Performance Q
1. Read Acceptance — target metric + load profile (`p95 ≤ 50ms @ 100 RPS`).
2. If benchmark harness exists: Bash + capture metrics.
3. Else: print manual run instructions (k6 / JMeter / wrk command template). Ask user to report the measurement.
4. Compare reported number to target. Pass / fail.

## `verification-report.md` schema

```
# Verification report: <title>

## Summary
- change: <name>
- Q-gates total: <n>
- pass: <p>  · fail: <f>  · skipped: <s>
- verdict: PASS | FAIL | PARTIAL (with explanation)

## Q-gate results

### Q1 — <title> (<category>)
- Acceptance: <verbatim from roadmap.md>
- Result: PASS | FAIL | SKIPPED
- Evidence: <command + exit code + brief output | user-report citation | benchmark numbers>
- Notes: <free-form if needed; or "none">

### Q2 — …
…

## Outstanding issues (only on FAIL / PARTIAL)
- Q<n> failure: <reason> — recommended action: rework <upstream stage> | re-test after code fix
- …

## NFR coverage cross-check
- NFR-performance: covered by Q<n> → PASS
- NFR-security: covered by Q<n>, Q<m> → PASS
- NFR-observability: covered by Q<n> → PASS
- …
```

## Marking task states during execution

For each Q-task processed:
- Before running: `roadmap.sh set-task-state --task-id Q<n> --state in-progress`.
- On pass: `--state done`.
- On fail: `--state blocked` (so it shows up on next /workflow re-entry; user decides whether to rework or accept partial verification).
- On skipped (user decision): `--state rejected`.

## Quality bar (when to mark `verification: review`)

- Every Q-gate in `roadmap.md` has been processed (state ∈ `done | blocked | rejected`).
- `verification-report.md` covers all Qs with category + result + evidence.
- NFR cross-check section names every NFR from `requirements.md` and cites the covering Q.
- If verdict is FAIL or PARTIAL, recommended actions are concrete (which stage to reopen, what to change).

## When NOT to use

- Defining Q-gates → `spec-decomposition` (during decomposition stage).
- Writing the code under test → `code-implementor` (during implementation).
- Marking change as `done` → that's `tracking.sh derive-status` after all stages settle; verification only marks its own stage `review`.

## Anti-patterns

- **Re-running until green.** If a Q-task fails, surface failure; do NOT silently rerun until it passes. Orchestrator + user decide rework path.
- **Skipping uncomfortable Qs.** "Manual perf test — let's skip." Only acceptable if scope explicitly Out. Otherwise mark rejected with reason.
- **One-line evidence.** "Tests pass." Include the command, exit code, and counts. Future readers must verify without re-running.
- **Inventing Q-gates.** Stick to what's in `roadmap.md`. If you find a missing concern, surface as Outstanding issue + recommend reopening decomposition.
- **Verification as test-writing.** Q-tasks **run** existing tests; they don't author them. If a Q requires writing test code, that's a main task — back to implementation.
