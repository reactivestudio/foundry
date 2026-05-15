---
name: naming
description: "Variable/function/class naming: intent-revealing, no noise, no puns. NOT for docs/UX copy."
---

# Naming

Names are how code talks to the next reader — often you, three months later. A name that needs a comment to be understood has already failed.

## When to use

- Creating a new variable / function / class / file.
- Reviewing or refactoring existing names.
- Renaming during a refactor.

## Core rules

1. **Reveal intent.** A name answers *why it exists, what it does, how it's used*. If you'd need a comment to explain it, the name failed. `d` → `elapsedTimeInDays`.

2. **No disinformation.** Don't claim a type the value doesn't have — `accountList` that isn't a `List` should be `accounts`. Avoid abbreviations already owned by something else (`hp`, `aix`, `sco`). Ban `l` and `O` as identifiers — they look like `1` and `0`. Two names differing by one inner word (`...HandlingOfStrings` vs `...StorageOfStrings`) will hide bugs in autocomplete.

3. **Make meaningful distinctions.** No number series (`a1`, `a2`). No noise suffixes — `Info`, `Data`, `Object`, `Variable`; if removing them changes nothing, they don't belong. `getActiveAccount()` / `getActiveAccounts()` / `getActiveAccountInfo()` is a trap — the caller can't choose.

4. **Pronounceable.** Programming is a social activity — names get said aloud in reviews. `genymdhms` → `generationTimestamp`. If you'd sound silly pronouncing it, rename.

5. **Searchable. Length tracks scope.** Wide-scope variables and constants must be greppable: `7` → `MAX_CLASSES_PER_STUDENT`. Single letters and bare magic numbers are tolerated only inside a tight loop body.

6. **No encodings.** No Hungarian (`phoneString` for a `PhoneNumber`). No field prefixes (`m_dsc`, `_field`). Leave interfaces unadorned (`ShapeFactory`, not `IShapeFactory`); if you must encode anything, mark the implementation (`ShapeFactoryImpl`).

7. **No mental mapping.** The reader shouldn't translate `r` into "lowercased URL without host or scheme." Single-letter counters (`i`, `j`, `k`) are tolerated only as loop tradition. Clarity beats cleverness.

## Classes & methods

- **Classes are nouns.** `Customer`, `WikiPage`, `Account`. Avoid `Manager`, `Processor`, `Data`, `Info` — vague containers that hide the real responsibility.
- **Methods are verbs.** `postPayment`, `deletePage`, `save`. Accessors: `get` / `set` / `is`.
- **Overloaded constructors → static factories with intent.** `Complex.fromRealNumber(23.0)` reads better than `Complex(23.0)`. Make the constructor private to enforce it.
- **Don't be cute.** `HolyHandGrenade` is a joke for one team for one week — rename to `deleteItems`. No slang (`whack()` → `kill()`), no culture-bound puns (`eatMyShorts()` → `abort()`).

## Consistency

- **One word per concept.** Pick `get` *or* `fetch` *or* `retrieve` across the codebase — not all three. Same for `controller` / `manager` / `driver`.
- **Don't pun.** Reusing one word for two operations misleads. `add` for arithmetic and `add` for "append to a collection" — second one should be `insert` or `append`.

## Domain

- **Solution domain when available.** Your readers are programmers — `Visitor`, `Queue`, `EventBus`, `Adapter` carry precise meaning.
- **Problem domain otherwise.** When no programmer-eese exists, use the business term so a maintainer can ask a domain expert.

## Context

- **Group related variables into a class.** Standalone `state` is opaque; bundle `firstName`, `lastName`, `street`, `state` into an `Address` — the compiler then carries the context for you.
- **Prefixes only as fallback.** `addrState` works if a class isn't justified, but a class is almost always better.
- **No gratuitous prefix-spam.** Don't tag every class with `GSD…`. Differentiate only when types actually collide: `PostalAddress`, `MacAddress`, `WebAddress`.

## Examples

### Implicit context → intent-revealing

```kotlin
// Bad — what are these numbers? what is in theList?
fun getThem(): List<IntArray> {
    val list1 = mutableListOf<IntArray>()
    for (x in theList) if (x[0] == 4) list1.add(x)
    return list1
}

// Good
fun getFlaggedCells(): List<Cell> {
    val flaggedCells = mutableListOf<Cell>()
    for (cell in gameBoard) if (cell.isFlagged()) flaggedCells.add(cell)
    return flaggedCells
}
```

### Magic numbers → named constants

```kotlin
// Bad
for (j in 0..33) s += t[j] * 4 / 5

// Good
for (j in 0 until NUMBER_OF_TASKS) {
    val realTaskDays = taskEstimate[j] * realDaysPerIdealDay
    val realTaskWeeks = realTaskDays / workDaysPerWeek
    sum += realTaskWeeks
}
```

### Noise-word triplet → distinct verbs

```kotlin
// Bad — caller can't tell which to call
fun getActiveAccount(): Account
fun getActiveAccounts(): List<Account>
fun getActiveAccountInfo(): AccountInfo

// Good — verb encodes intent
fun findActiveAccount(id: Long): Account
fun listActiveAccounts(): List<Account>
fun activeAccountSummary(id: Long): AccountSummary
```

### Cryptic / Hungarian → clean

```kotlin
// Bad
class DtaRcrd102 {
    private val genymdhms: Date = Date()
    private val modymdhms: Date = Date()
    private val pszqint: String = "102"
}

// Good
class Customer {
    val generationTimestamp: Date = Date()
    val modificationTimestamp: Date = Date()
    val recordId: String = "102"
}
```

## When NOT to use

- Breaking-change renames of public API — handle as a migration, not naming.
- Stack-specific idioms (Kotlin, Spring, JPA) — defer to the matching reference skill.
- Documentation prose, UX copy, git branch names, commit messages.
- Style nits in review when the existing name is already clear.

## Source

Adapted from R. C. Martin, *Clean Code*, ch. 2 "Meaningful Names" (Tim Ottinger).
