# SOLID skill — iteration-3 benchmark

4 evals targeting the 4 unverified hypotheses from recent edits: OCP hierarchy of protection, OCP/SOLID interlock chain, Humble Object (LSP), header vs role interfaces (ISP).

## Summary

| Eval | With skill | Baseline | Δ |
|---|---|---|---|
| 8 — OCP hierarchy of protection | 5/5 (100%) | **5/5 (100%)** | 0 |
| 9 — OCP/SOLID interlock chain | 5/5 (100%) | **5/5 (100%)** | 0 |
| 10 — Humble Object | 5/5 (100%) | **5/5 (100%)** | 0 |
| 11 — Header vs role interfaces | 5/5 (100%) | **5/5 (100%)** | 0 |
| **Mean pass rate** | **100%** | **100%** | **0 pp** |

**Baseline takes everything.** Zero discrimination on the 4 hypotheses tested here.

## Resource cost

| Metric | With skill (mean) | Baseline (mean) | Δ |
|---|---|---|---|
| Tokens | 21,038 | 18,585 | +13.2% |
| Duration (ms) | 37,677 | 40,492 | -7.0% |

## What baseline produced unaided

- **eval-8**: Cited Martin verbatim ("level = distance from I/O"), distinguished from SAP (stability), gave a detailed expense-reimbursement worked example, even recommended ArchUnit enforcement.
- **eval-9**: Produced an ASCII dependency graph `SRP → ISP → DIP → LSP → OCP`, framed OCP as "emergent property," and translated to four concrete moves. Indistinguishable from the with_skill output.
- **eval-10**: Named *Humble Object* by name, cited *Meszaros* and the *GOOS book* unprompted, and produced a more code-complete refactor than the with_skill version.
- **eval-11**: Used Fowler's "role interfaces vs header interfaces" terminology verbatim, produced canonical implementations, and identified the latent SRP smell.

## Implication

All four edits made in the second improvement round are **cargo content** — they restate things baseline-Claude already knows and produces unprompted, often with the same canonical terminology and citations.

The skill file additions to be considered for removal:
- `lsp.md` — "Two mechanisms of violation" section (iteration-2 also showed this is cargo)
- `lsp.md` — "Humble Object" section (iteration-3 cargo)
- `srp.md` — "DI hell is an SRP smell" section (iteration-2 cargo)
- `srp.md` — "+5 collaborators" red flag (iteration-2 cargo)
- `isp.md` — "Header interface vs role interface" section (iteration-3 cargo)
- `ocp.md` — Counter-intuitive level-from-I/O paragraph (iteration-3 cargo)
- `SKILL.md` — "How the principles interlock" section (iteration-3 cargo)

What survives empirically (iteration-2 + idea that wasn't tested but felt unique):
- `dip.md` — "When an interface is overkill" (criterion: boundary OR volatile, "anemic abstraction") — terminology win, +20 pp
- `srp.md` — "When NOT to split" / speculative SRP — terminology win, +20 pp
- `srp.md` — "Accidental vs honest duplication" — survived iteration-1 grading

## Combined across all iterations (11 evals)

| Iteration | n | with_skill | baseline | Δ |
|---|---|---|---|---|
| 1 | 3 | 100% | 76.7% | **+23.3 pp** |
| 2 | 4 | 100% | 90% | **+10 pp** |
| 3 | 4 | 100% | 100% | **0 pp** |
| **All** | 11 | **100%** | **88.2%** | **+11.8 pp** |

The lift trend points downward as the questions move from sharp Martinisms (iteration-1) → named decisions (iteration-2) → broader SOLID interlocks (iteration-3). The further the question gets from "things only Martin's specific framing nails," the less the skill discriminates.

## Caveats

Same as prior iterations: single run per cell, orchestrator grading, simulated activation via subagent file reads. Strict grading (term-required) was applied throughout; with looser grading (idea-present, terms-not-required) iteration-2's delta would also collapse to near zero.
