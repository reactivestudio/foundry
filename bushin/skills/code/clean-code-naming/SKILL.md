---
name: clean-code-naming
description: "Name or rename variables/functions/classes: intent over comment. NOT for docs/UX/branches/commits."
---

# Clean Code — Naming

Names are how code talks to the next reader — often you, three months later. A name that needs a comment to be understood has already failed.

## When to use

- Creating a name for a variable, argument, function, class, file, package, or directory.
- Reviewing or refactoring existing names in PR or pre-commit.
- Renaming during a refactor.

## When NOT to use

- Breaking-change renames of public API — handle as a migration.
- Stack-specific idioms (Kotlin, Spring, JPA, DDD) — defer to the matching reference skill in `kotlin/`, `framework/`, `ddd/`.
- Documentation prose, UX copy, git branch names, commit messages.
- Style nits in review when the existing name is already clear.

## House defaults

The biggest naming smell is reaching wider than needed.

- **One word, then two.** Default to a single domain noun (`Order`, `Reservation`, `Payment`). A second word must add domain meaning, not synonym noise — `PurchaseOrder` vs `SalesOrder` is legitimate when both exist; `OrderEntity` is not. Three+ words is almost always a smell.
- **No negated booleans.** `isEnabled`, not `isNotDisabled`. Double-negation in conditionals (`if (!isNotDisabled)`) is unforgivable.
- **No conjunctions in class names.** `OrderAndPaymentValidator` splits into two classes, or finds a higher-level concept (`CheckoutValidator`).
- **Conversion methods come in pairs.** `toDomain` ↔ `fromRow`, never `toDomain` + `mapBack`. Symmetry signals the inverse.
- **Side effects belong in the name.** A `get*` that opens a socket or constructs lies — make it `getOrCreate*` or restructure (lazy property, explicit factory).
- **Length tracks scope.** `i` in a tight loop is fine; a class field with the same name is not.

## Red list — words that promise nothing

Replace with a concrete domain term every time.

| Forbidden | What it really says | Replace with |
|---|---|---|
| `Item` | "I didn't think about what this is" | `OrderLine`, `Reservation`, `MenuEntry` |
| `Data` / `Info` / `Object` / `Thing` | empty noun, tautology | concrete domain word |
| `Detail` / `Details` | usually = Info | `ShippingAddress`, not `ShippingDetails` |
| `Element` | XML flashback | `Node`, `OrderLine` |
| `Manager` / `Handler` / `Processor` | verb is hidden inside | `*er` from the verb: `Submitter`, `Reconciler`, `Approver` |
| `Helper` / `Util` / `Utils` | bag of unrelated functions | extension functions or the missing class |
| `Common` / `Base*` | dumping ground / inheritance for its own sake | distribute by topic; prefer composition |

## Stack-noise suffixes (modern Hungarian)

Encode layer or container type — not intent.

| Suffix | Default action | Tolerated when |
|---|---|---|
| `*Entity` | remove | persistence row — prefer `*Row` |
| `*Dto` | remove | pre-existing project-wide convention |
| `*Model` / `*Bean` / `*Object` / `*Data` / `*Info` | always remove | — |
| `*Impl` | remove | two valid implementations; mark by specificity (`JpaOrderRepository`, not `OrderRepositoryImpl`) |
| `*Service` | not as a default | genuine application-layer orchestrator (load → call → save) |

## Core principles

Sixteen from ch.2 plus N7 / N2 from ch.17, condensed. Full WHY in `resources/theory.md`.

1. **Reveal intent.** If a comment is needed, the name failed.
2. **No disinformation.** No `accountList` for a `Set`. No `l`/`O` identifiers.
3. **Make meaningful distinctions.** No number series, no noise suffixes, no `klass`-tricks.
4. **Pronounceable.** `genymdhms` → `generationTimestamp`.
5. **Searchable. Length tracks scope.** `e` is the worst single letter — greps against every comment.
6. **No encodings.** No Hungarian, no `m_`, no `I*` on interfaces.
7. **No mental mapping.** Reader shouldn't translate `r` → "URL minus host/scheme".
8. **Side effects in the name** (N7). `get*` that constructs is a lie.
9. **Match level of abstraction** (N2). `connect(locator)` outlives `dial(phone)`.
10. **Classes nouns; methods verbs.** Static factories with intent: `Complex.fromRealNumber(23.0)`.
11. **Don't be cute.** `whack()` → `kill()`.
12. **One word per concept.** Pick `find` *or* `fetch` *or* `get` — not all three.
13. **Don't pun.** `add` for arithmetic ≠ `add` for "append".
14. **Solution domain when applicable, problem domain otherwise.**
15. **Add context via class extraction.** `state` alone is opaque → bundle into `Address`.
16. **Don't add gratuitous context.** No `GSDFooBar`.

## Renaming

Don't fear it. Tooling makes the change cheap and atomic. A rename surprises someone exactly the way any improvement does — pay that cost and move on.

## Practices

`resources/practices.md` — bad/best example catalog organised by topic (intent, magic numbers, noise words, side effects, level of abstraction, Hungarian, conjunctions, conversion pairs, one-word default).

## Source

Adapted from R. C. Martin, *Clean Code*, ch. 2 "Meaningful Names" (Tim Ottinger) and ch. 17 §N1–N7. Stack-specific naming (Kotlin / Spring / JPA / DDD) deferred to skills in those categories.
