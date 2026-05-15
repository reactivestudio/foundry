# SOLID skill — iteration-2 benchmark

4 new evals targeting hypotheses added in the recent edits (anemic abstraction, speculative SRP, LSP precondition naming, DI-hell-is-SRP). 4 evals × 2 configs (with_skill vs baseline). Strict grading: rubric points require canonical terminology, not just adjacent meaning.

## Summary

| Eval | With skill | Baseline | Δ |
|---|---|---|---|
| 4 — Anemic interface (DIP overkill) | **5/5 (100%)** | 4/5 (80%) | +20 pp |
| 5 — Speculative SRP (don't split) | **5/5 (100%)** | 4/5 (80%) | +20 pp |
| 6 — LSP precondition strengthening | 5/5 (100%) | 5/5 (100%) | 0 |
| 7 — DI hell as SRP smell | 5/5 (100%) | 5/5 (100%) | 0 |
| **Mean pass rate** | **100%** | **90%** | **+10 pp** |

## Resource cost

| Metric | With skill (mean) | Baseline (mean) | Δ |
|---|---|---|---|
| Tokens | 21,541 | 18,197 | +18.4% |
| Duration (ms) | 36,545 | 33,823 | +8.1% |
| Tool uses | 4 | 1 | +3 (Read calls for SKILL.md + resource) |

## Comparison with iteration-1

| Iteration | Evals | with_skill | baseline | Δ pp |
|---|---|---|---|---|
| 1 (original 3 evals) | 3 | 100% | 76.7% | **+23.3** |
| 2 (4 new evals on recent edits) | 4 | 100% | 90% | **+10** |

**Lift is roughly half iteration-1's.** The new hypotheses give a thinner signal than the original SRP/DIP/LSP framing did. Two of four (preconditions, DI-hell) don't discriminate at all — baseline already produces the canonical answer.

## Analyst observations

**Where the skill still lifts (eval 4, eval 5):**

- *"Anemic abstraction"* as a named pattern. Baseline reached the same conclusion ("ceremony, not inversion") but didn't use the term. The skill's explicit naming gives a hook for code review comments.
- *"Speculative SRP"* as a named anti-pattern. Baseline called it "SRP-theater" and "needless decomposition driven by a misreading of SRP" — same idea, no shared vocabulary across reviewers.

These are terminology wins. They matter for shared review language; they don't add insight the model didn't already have.

**Where the skill does NOT lift (eval 6, eval 7):**

- *Strengthening preconditions / weakening postconditions* — baseline produced the term verbatim and cited Liskov's full rule set unprompted. Adding this to lsp.md was redundant: the model already knows it.
- *DI hell as an SRP smell* — baseline framed it correctly without help: "A 9-arg constructor is not a DI-ergonomics problem... violating SRP." Adding this to srp.md was also redundant.

**Implication:** the lsp.md "Two mechanisms of violation" section and the srp.md "DI hell is an SRP smell" section can likely be cut without quality regression. They're cargo content — they look load-bearing but the model already produces the same output without them.

**Hypotheses not tested in this iteration:**

- *Hierarchy of protection* (OCP — level = distance from I/O, not generality)
- *Interlock chain* (SKILL.md — SRP→DIP, OCP needs DIP, LSP underwrites OCP, ISP = SRP for interfaces)
- *Humble Object* (LSP — framework-forced violations)
- *Header vs role interface* (ISP — Fowler)
- *Accidental duplication* (SRP — survived iteration-1 grading; not re-tested here)

A future iteration could target each with a focused prompt; the cost is another ~100K subagent tokens.

## Caveats

- Same as iteration-1: single run per cell (no variance), orchestrator grading (not human-in-the-loop), simulated activation via subagents reading the skill files.
- Strict grading required the canonical term to fire the rubric point. A laxer grading (idea-present, term-absent = pass) would zero out the delta entirely — baseline gets there, just in different words.
- Iteration-1 and iteration-2 evals are different sets. Mean comparison is between *different prompts*, not the same prompts re-run; mixing them gives a 7-eval mean of with=100%, baseline=82.9%, Δ=+17.1pp — a closer-to-honest figure.

## Verdict

The skill's empirical value is concentrated in:
1. **Sharper formulations the model otherwise misquotes** (actor framing, Facade, crossing the curve, instanceof-smell) — iteration-1 evidence.
2. **Decision rules the model doesn't volunteer** (when interface is overkill, when not to split) — iteration-2 evidence.

The skill's empirical value is **NOT** in:
1. Restating concepts the model already produces unprompted (precondition rules, DI-hell-SRP).

Recommendation: trim cargo from lsp.md and srp.md; keep dip.md "anemic abstraction" and srp.md "when not to split" — both surfaced unique lift.
