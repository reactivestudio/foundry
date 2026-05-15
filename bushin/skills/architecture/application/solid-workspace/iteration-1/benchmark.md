# SOLID skill — iteration-1 benchmark

3 evals × 2 configs (with_skill vs baseline). Graded against per-eval rubrics in `eval_metadata.json`.

## Summary

| Eval | With skill | Baseline | Δ |
|---|---|---|---|
| 1 — SRP / OrderService split | **5/5 (100%)** | 3/5 (60%) | **+40 pp** |
| 2 — DIP / PostgresClient placement | **5/5 (100%)** | 4.5/5 (90%) | +10 pp |
| 3 — LSP / BoundedCache | **5/5 (100%)** | 4/5 (80%) | +20 pp |
| **Mean pass rate** | **100%** | **76.7%** | **+23.3 pp** |

## Resource cost

| Metric | With skill (mean) | Baseline (mean) | Δ |
|---|---|---|---|
| Tokens | 25,069 | 20,097 | **+25%** |
| Duration (ms) | 39,237 | 31,764 | +24% |
| Tool uses | 5 | 2 | +3 (extra Read calls for SKILL.md + resource) |

Per-eval breakdown:

| Eval | with_skill (tokens / ms) | baseline (tokens / ms) |
|---|---|---|
| 1 | 27,063 / 45,536 | 20,203 / 36,438 |
| 2 | 23,582 / 35,564 | 20,052 / 28,734 |
| 3 | 24,562 / 36,612 | 20,037 / 30,119 |

## Analyst observations

**Baseline is surprisingly strong.** Claude already has SOLID in training; it correctly identified the principle in all 3 cases. The skill's marginal value isn't *teaching* SOLID — it's enforcing Martin's *sharper* formulations and surfacing the failure modes that vanilla advice misses.

**Discriminating rubric points** (consistently differentiated with_skill from baseline):

- **SRP "one actor" framing**. Baseline reverted to the legacy "one reason to change" formulation that Martin himself revised away from. Skill outputs use the actor framing verbatim. *(eval 1)*
- **Facade as SRP-split escape hatch**. Baseline omitted Facade entirely; it kept `OrderService` as an orchestrator (functionally similar but conceptually different from the skill's recommendation). *(eval 1)*
- **"Crossing the curve" terminology + source-deps-vs-control-flow opposition**. Baseline had a similar diagram but didn't name the inversion. *(eval 2)*
- **The `instanceof`/`is` branching smell** as LSP's diagnostic signature. Baseline showed an example that would fail but didn't articulate why call-site type-checks are the canonical LSP polluter. *(eval 3)*

**Non-discriminating rubric points** (both configs got these):

- Naming the principle at issue (Claude already maps these well)
- Proposing a concrete split / placement / fix
- Distinguishing domain-owned interface from infrastructure impl (DIP)
- Ruling out adjacent principles (LSP)

**Cost-benefit:** ~5K extra tokens + 3 extra Read calls per invocation, in exchange for ~23 pp accuracy gain on principled framing and named smells. The extra cost is dominated by reading SKILL.md (~470 tokens) + one resource (~770 tokens). Reasonable trade for advice quality.

**No iteration-2 candidates surfaced.** All 5 rubric points fired correctly on with_skill across all 3 evals. The skill is fit-for-purpose at this scope.

**Caveats** (where this run differs from the canonical skill-creator flow):

- Grading was done by the orchestrator (me), not by the user via the eval viewer. My judgment substitutes for human-in-the-loop feedback. For high-stakes iteration, the user should review outputs in the viewer.
- Only one run per cell — no variance estimate. Re-running would catch flaky pass/fail boundaries.
- `with_skill` was simulated by telling subagents to read SKILL.md, not by genuine plugin activation. Real activation would route resources via the skill loader.
