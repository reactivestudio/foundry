# Functions — size, arity, command-query, polymorphism

For the cadence rules, see `../SKILL.md`.

## Output template — when reviewing a function

1. **Size verdict.** Lines / indent depth / argument count vs thresholds.
2. **Smells found.** From the lookup below.
3. **Action plan.** Extract / split / replace flag with sealed type / lift try-catch to advice.

## MUST-check before closing the review

Pass through this list explicitly — short methods get buried under long ones, and these are the smells that hide in tiny `handle()` / `get*()` bodies.

- [ ] No `when (x: Any)` or open-hierarchy `when` without a `sealed` root? (else-branch hides every new variant you forget to handle)
- [ ] Every `get*` is a pure query — no cache mutation, no DB connection opening, no counter increments? (CQS)
- [ ] No method that **both** answers a question **and** changes state? (split into `existsX` + `setX`)
- [ ] No method exceeding **3** arguments? (4+ = missing argument object)
- [ ] No `Boolean` flag parameter switching behaviour? (split into two methods, or sealed mode)
- [ ] No nesting deeper than **2** indent levels? (guard clauses; lift inner block)

## Size thresholds

| Metric | Target | Action when exceeded |
|---|---|---|
| Function length | ≤ 20 lines | Extract each block as a named sub-function. |
| Indent depth | ≤ 2 levels | Guard clauses; lift the inner block into a function. |
| Cyclomatic complexity | ≤ 5 | Sealed hierarchy + `when` per subtype, or Strategy. |
| Argument count | ≤ 2 | Argument object (data class / value class); receiver via extension. |
| `try` body | only statement in the function | `try` is the whole body — caller has its own function around it. |

## Arity rules

- **0 args (niladic):** Best. Everything needed is on the receiver.
- **1 arg (monadic):** Verb-noun pair. Distinguish *query* (`exists(path)`), *transform* (`open(path)`), *event* (`onFailed(attempts)`).
- **2 args (dyadic):** Only if the two are **ordered parts of one concept** (`Point(x, y)`). Otherwise convert one to a receiver.
- **3+:** Almost never. Group into a data class. The 4-argument function is a missing class.

## Hard rules

**No flag arguments.** A `Boolean` parameter that switches the function's behaviour means the function does two things.

```kotlin
// ✗ render(pageData, isSuite = true)
// ✓ renderForSuite(pageData)  +  renderForSingleTest(pageData)
// ✓ or sealed RenderMode { Suite, SingleTest, SetupOnly } if 3+ variants
```

**Command-Query Separation.** A function **either** mutates (returns `Unit` / id) **or** answers (returns a value). Not both.

```kotlin
// ✗ if (set("user", "bob")) { ... }      — does it ask or set?
// ✓ if (attributeExists("user")) setAttribute("user", "bob")
```

**No side effects under a query name.** A `checkPassword` that also initialises the session lies. Either remove the side effect or rename to expose it (`checkPasswordAndInitialise`) — and use the awkward name as the prompt to redesign.

**One `try` per function, and it's the whole body.** If a function contains `try`, the `try` should be the first non-trivial statement and nothing else should follow the `catch` / `finally`. Lift business logic out, leave: `try { doTheThing() } catch (e: ...) { handle(e) }`.

## Switch / `when` on type → polymorphism

A `when (entity.type)` that returns different behaviours per type is a god-function in slow motion: every new variant edits the same site.

```kotlin
// ✗ Repeated for every operation (calculatePay, isPayDay, deliverPay, …)
fun calculatePay(e: Employee): Money = when (e.type) {
    COMMISSIONED -> calculateCommissionedPay(e)
    HOURLY       -> calculateHourlyPay(e)
    SALARIED     -> calculateSalariedPay(e)
}

// ✓ Sealed hierarchy + behaviour on each subtype
sealed class Employee {
    abstract fun calculatePay(): Money
    abstract fun isPayDay(today: LocalDate): Boolean
}
class Commissioned(...) : Employee() { ... }
class Hourly(...)       : Employee() { ... }
class Salaried(...)     : Employee() { ... }
```

Tolerated `when` on type: **once, inside a factory**, buried behind the sealed root. Anywhere else, it's the smell.

## Smell → fix lookup

| Smell | Fix |
|---|---|
| Function > 20 lines | Extract each block as a named sub-function. |
| Indent > 2 | Guard-clause early returns; lift inner block. |
| Sections separated by blank line + comment (`// validate`, `// dispatch`) | Each section is a function. |
| Mixed levels of abstraction (`page.getHtml()` + `.append("\n")`) | Extract the low-level part. |
| Boolean flag argument | Split into two functions, or use a sealed type. |
| Output argument (`appendFooter(buffer)`) | Make it a receiver method (`buffer.appendFooter()`) or return a value. |
| Function that reads *and* writes (`set(...): Boolean`) | Split into `existsX()` + `setX()`. |
| Returns error code | Throw, or return `Result<T>` at a clearly defined seam. |
| `try/catch` mixed with business logic | Extract try-body into its own function; lift catch to `@RestControllerAdvice` if Spring. |
| Repeated `when (entity.type)` returning behaviour | Sealed hierarchy with behaviour per subtype. |
| 4+ arguments | Argument object (data class) or value class for a single field. |
