---
name: clean-code
description: "Code review/refactor: naming, functions, classes, comments, errors, boundaries. NOT for SOLID."
---

# Clean Code

Router and cross-cutting rules for refactoring and code review. Topic-specific procedures live in `resources/<topic>.md` — load only what the task needs.

## When to use

- Reviewing a function, class, or module for design smells.
- Refactoring existing code that "feels off".
- Planning a cleanup pass before adding a feature.
- Auditing a module before merging structural changes.

## When NOT to use

- SOLID at principle scope → `architecture/application/solid/`.
- New code from scratch → `methodology/karpathy` (think, simplify, surgical).
- Framework-shaped types (`@Entity`, gRPC stub, DTO) — accept the shape, isolate it.

## Output template — when reviewing code

Structure the review response as:

1. **Smell named.** Use the vocabulary in the smell lookup below (or `resources/smells-catalog.md` for full diagnosis). Vague code isn't a smell — "long method mixing two levels of abstraction" is.
2. **Diagnosis.** Why it's a smell *here* (not just "looks long"). Cite the relevant threshold or rule.
3. **Action plan.** Numbered, execution order. **One smell, one fix, one commit.**
4. **Cadence reminder.** Characterisation tests first if behaviour is at risk; never change behaviour and structure in the same step.

If the code is clean, say so. Don't invent smells.

## Refactoring cadence — the rules Claude won't enforce by default

1. **Identify the smell first.** "Cleanup" without a named smell drifts in scope. Name it; you know what done looks like.
2. **One smell, one fix, one commit.** Don't bundle rename + extract + interface introduction. Bisect-friendly.
3. **Characterisation tests stay green at every step.** If the code has no tests, write tests that pin *current* behaviour (warts and all) *before* refactoring. The tests are the safety net.
4. **Preserve behaviour.** Refactoring ≠ bug fix ≠ feature. If you find a bug mid-refactor, finish the refactor commit first, then fix the bug as its own commit.
5. **Never change behaviour and structure in the same step.** One or the other per commit.
6. **Stop when good enough.** Clean Code is a direction, not a destination. A 90%-clean module shipping beats 100%-clean in PR.

## Smell vocabulary — quick router

When you see this smell, read the linked resource for procedures and bad/best examples.

| Smell | Resource |
|---|---|
| `*Manager`/`*Helper`/`*Util`/`*Dto`/`*Impl` suffix, vague abstract names (`Item`, `Data`, `Info`), comment-instead-of-name, inconsistent vocabulary | `resources/naming.md` (+ `naming-practices.md`) |
| Long method, deep nesting, flag arguments, `when` on type, side effects, CQS violations | `resources/functions.md` |
| God class, weasel suffix (`*Manager`/`*Helper`/`*Util`), 25-word test failure, low cohesion | `resources/classes.md` (+ `classes-practices.md` for examples) |
| Comment-as-failed-name, redundant KDoc, commented-out code, mumbling TODO | `resources/comments.md` |
| Wrong file size, broken stepdown, manual column alignment, line > 120 | `resources/formatting.md` |
| Hybrid class (data + behaviour), train wreck `a.b().c().d()`, anemic domain, JPA entity-as-aggregate | `resources/objects-and-data.md` |
| Catch-and-log everywhere, null returns/passes, third-party exceptions leaking up | `resources/error-handling.md` |
| Vendor types in domain code, `Map<String,Any?>` in public APIs, no Adapter for SDK | `resources/boundaries.md` |
| Service-locator usage, field injection (`@Autowired var`), framework imports in domain, inline cross-cutting | `resources/systems.md` |
| Don't know what to call it | `resources/smells-catalog.md` — 15 actionable smells with Symptom → Diagnosis → Fix |

## Anti-patterns in refactoring itself

- **Don't refactor code you're not changing.** Surgical rule — open a separate PR if cleanup elsewhere matters.
- **Don't refactor for refactoring's sake.** Every cleanup should make the *next* feature commit easier. If you can't name that future commit, defer.
- **Don't apply line-count rules religiously.** "≤ 20-line function" is a *review-attention* heuristic, not a build constraint. A 25-line linear function doing one thing is fine.
- **Don't extract function-per-line.** Splitting `return a + b` into a helper adds indirection without revealing intent.
- **Don't introduce abstractions speculatively.** Strategy pattern for one concrete type = dead code with extra steps. Refactor *toward* the abstraction when the second case appears.
- **Don't trust "it compiles" as verification.** Compilers don't preserve behaviour; tests do.

## Source

R. C. Martin, *Clean Code* (2008), chapters 2–8, 10–11, 17. SOLID at principle scope is in `architecture/application/solid/`. Stack-specific idioms (Kotlin / Spring / JPA / DDD) live in their own categories.
