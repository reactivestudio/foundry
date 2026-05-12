---
name: clean-code
description: "Entry point and router for the clean-code-* family — Kotlin/Spring code-smell diagnostic vocabulary plus refactoring cadence rules. Use when refactoring existing code, identifying smells in a PR or code review, planning a cleanup pass before adding a feature, or migrating Java-style Kotlin into idiomatic Kotlin. Owns two things the per-topic siblings don't: the smell vocabulary (Rigidity, Fragility, Train wreck, Primitive obsession, Feature envy, God class, …) for naming what's wrong before fixing it, and the cadence rules (one smell / one fix / one commit; characterization tests first; preserve behaviour; stop when good enough) for applying fixes safely. Routes to the right clean-code-* sibling (-naming, -functions, -classes, -error-handling, -objects-and-data, …) for the deep dive on each smell. Does NOT auto-trigger on greenfield code — for new code use karpathy-guidelines."
risk: safe
source: "custom — Martin's Clean Code design-smell taxonomy + refactoring cadence rules, filtered for Kotlin/Spring"
date_added: "2026-05-12"
---

# Clean Code

> "The goal of refactoring is to change the shape of code without changing what it does."

The **entry point and router** for the clean-code-* family. It owns two things that the per-topic siblings don't: the **smell vocabulary** (so you can name what's wrong before fixing it) and the **cadence rules** (so the fix doesn't drag unrelated changes along with it). For the deep dive on any single smell, follow the cross-reference in the vocabulary table to the owning sibling.

## When to use this skill

- Refactoring an existing function/class/module ("this is messy, clean it up").
- Identifying smells in a file or in a PR review.
- Planning a cleanup pass before adding a feature.
- Migrating Java-style Kotlin into idiomatic Kotlin.
- Picking *which* clean-code-* sibling actually applies to the messy code in front of you.

## When NOT to use this skill

- **Writing new code from scratch.** That's `karpathy-guidelines` — minimum code, surface assumptions, surgical changes. This skill is for cleaning, not creating.
- **Picking an architecture pattern** (Onion vs Clean vs Layered). That's `architecture-patterns`.
- **The deep dive on one specific smell.** Once the smell is named via the vocabulary below, jump to the sibling that owns it (Long method → `clean-code-functions`, Train wreck → `clean-code-objects-and-data`, `!!` everywhere → `clean-code-error-handling`, …).

## Selective Reading Rule

| File | When to read |
|------|--------------|
| `resources/smells-catalog.md` | When you need the Symptom → Diagnosis → Fix sketch → When-NOT-to-fix view of a specific smell, with a pointer to the sibling skill that owns the full Kotlin before/after. |

## Smell vocabulary

Use these terms when diagnosing. "Bad code" isn't a smell — "long method with deep nesting mixing two levels of abstraction" is. Naming the smell turns "ugh, this is rough" into a concrete refactor.

### Design smells (Martin's taxonomy)

These describe how a *module* feels from the outside.

| Smell | What it means |
|---|---|
| **Rigidity** | Hard to change. One small modification cascades into many files. |
| **Fragility** | Changes in one place break unrelated things. |
| **Immobility** | Can't lift code out for reuse without dragging half the module with it. |
| **Viscosity** | Doing the right thing is harder than the wrong thing (tests slow, build clunky, conventions painful). |
| **Opacity** | Hard to read; reader has to reconstruct intent from implementation. |
| **Needless complexity** | Premature abstraction, options not used, "what if we need…". |
| **Needless repetition** | Same logic in three places. |
| **Dead code** | Unreached branches, unused parameters, commented-out blocks. |

### Local code smells (with owner skill for the deep dive)

These describe what's wrong at the function / class / file level.

| Smell | Owner sibling |
|---|---|
| Long method / deep nesting | `clean-code-functions` |
| Long parameter list / flag arguments | `clean-code-functions` |
| `when` / `if` chains on type | `clean-code-functions` (polymorphism via sealed) |
| Primitive obsession (`String` for `Email`, `Long` for `Cents`) | `clean-code-objects-and-data` (value objects); `clean-code-naming` (value-class naming) |
| Train wreck (`a.b().c().d()` — Demeter violation) | `clean-code-objects-and-data` |
| Feature envy (method in A uses B's data more than its own) | `clean-code-objects-and-data` |
| Anemic domain / hybrid class | `clean-code-objects-and-data` |
| God class / fat service | `clean-code-classes` |
| Premature abstraction (interface with one impl, strategy with one variant) | `clean-code-classes` (OCP misuse); `clean-code-systems` (DI overuse) |
| Comment-as-failed-name | `clean-code-comments`; `clean-code-naming` |
| Inconsistent / mumbled / abbreviation-heavy names | `clean-code-naming` |
| Vendor types leaking into domain code | `clean-code-boundaries` |
| God test / mocked-everything test / train-wreck assertions | `clean-code-unit-tests` |
| `!!` everywhere / null-as-error-code | `clean-code-error-handling` |
| Field injection (`@Autowired var`) | `clean-code-systems` |
| Inline `@Value` config instead of `@ConfigurationProperties` | `clean-code-systems` |
| Manual `try/catch` for return codes; `try` ladders in business code | `clean-code-error-handling` |
| `data class` for a JPA `@Entity` | `clean-code-objects-and-data` |
| Mutable state where immutable would do (`var` everywhere, `MutableList` exposed) | `clean-code-objects-and-data`; `clean-code-classes` |

For the Symptom / Diagnosis / Fix sketch / When-NOT-to-fix view of each one — see `resources/smells-catalog.md`. For the full Kotlin before/after with edge cases — follow the **owner** column.

## The refactoring loop

The cadence rules that keep a refactor from turning into a yak shave.

1. **Identify the smell first** in the vocabulary above. Skipping this step is how refactors balloon — without a name, "this needs cleanup" is shapeless. With a name, you know what done looks like *and* which sibling skill to consult.

2. **One smell, one fix, one commit.** Don't bundle a rename with an extract-method with a value-class introduction. If anything regresses, you want the bisect to point at one change. If you spot a second smell mid-refactor, write it down on a sticky note and finish the first one.

3. **Characterization tests stay green at every step.** If the code you're touching has no tests, write a characterization test that pins down the *current* behaviour (warts and all) before refactoring. Then refactor with the test as the safety net. Then — if behaviour change was actually the goal — change behaviour in a separate commit. The shape of the characterization test is owned by `clean-code-unit-tests`.

4. **Preserve behaviour.** Refactoring ≠ adding features ≠ fixing bugs. If you find a bug mid-refactor, either (a) stop, fix the bug as its own commit, then resume, or (b) note the bug and finish the refactor first, then fix it. Mixing structural and behavioural change makes both reviews harder and bisects useless.

5. **Stop when good enough.** Clean Code is a direction, not a destination. Aggressive cleanup of code that's about to be deleted is waste. A 90%-clean module that ships beats a 100%-clean module still in PR.

## Anti-patterns in refactoring itself

- **Don't refactor code you're not changing.** `karpathy-guidelines` §3 — surgical. If the change is to `UserService.create`, don't also rename methods in `UserController` that the change doesn't touch. Open a separate "cleanup of UserController" PR if it really matters.

- **Don't refactor for refactoring's sake.** Every cleanup commit should make the *next* feature commit easier or safer. If you can't name that future commit, the cleanup is speculative — defer it.

- **Don't religiously apply line-count rules.** "≤ 20-line function" is a heuristic for *review attention*, not a build-failing constraint. A 25-line linear function doing one thing is fine; a 12-line function doing three things is not.

- **Don't extract function-per-line.** Splitting `return a + b` into a helper adds indirection without revealing intent. Three lines doing one thing stays inline; twenty lines doing five things gets split.

- **Don't introduce abstractions speculatively.** Strategy pattern for the one concrete type you'll ever have is dead code with extra steps. Refactor *toward* the abstraction when the second concrete case appears, not before.

- **Don't trust "it compiles" or "the IDE moved it" as verification.** Compilers don't preserve behaviour; tests do. See `methodology-verification`.

## Related skills

- `karpathy-guidelines` — for writing **new** code (always-on, mandatory before coding). This skill is its mirror for *existing* code.
- `clean-code-naming` / `-functions` / `-comments` / `-formatting` / `-objects-and-data` / `-error-handling` / `-boundaries` / `-unit-tests` / `-classes` / `-systems` — once you've named the smell, the sibling owns the deep dive on the fix.
- `methodology-verification` — refactoring is exactly the situation where "I think it still works" needs to be "I ran the tests and read the output."
- `simplify` — Anthropic's built-in "review changed code and fix issues" command. Broader scope; this skill is narrower (Kotlin/Spring-specific, smell-vocabulary-led).

## Limitations

- The vocabulary is a heuristic, not a checklist. A piece of code can have three named smells and still be the right shape for its context — don't fix a smell just because you spotted it.
- "Characterization test first" assumes the code is testable. If it isn't, that's its own refactor — extract a seam first; see `clean-code-boundaries` and `clean-code-classes`.
- Stop and ask if the messy-code target, the cleanup scope, or what "done" looks like are unclear.
