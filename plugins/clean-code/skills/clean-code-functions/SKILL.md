---
name: clean-code-functions
description: "Function-writing discipline for Kotlin/Spring code — opinionated rules for size (≤ 20 lines, indent ≤ 2), single responsibility (\"do one thing\"), one level of abstraction, the stepdown rule, descriptive names, low arity (0–2 args, flag arguments forbidden), no side effects, command-query separation, exceptions over error codes, and DRY. Adapted from R. Martin's Clean Code Ch. 3 'Functions', filtered for what Kotlin already solves (named/default arguments, sealed `when`, scope functions, extension receivers, Result<T>, expression bodies) and extended with Spring/JPA conventions (transactional boundaries, @ExceptionHandler over try/catch, CQS at the service layer). Use when writing a new function or method, refactoring a long method, reviewing function-level smells in a PR, deciding whether to split a function, replacing a switch/when with polymorphism, taming a 4+ argument signature, eliminating flag arguments or hidden side effects, untangling a function that both queries and commands, or auditing a module for function-level hygiene."
risk: safe
source: "Adapted from R. Martin, Clean Code (2008), ch. 3 'Functions', filtered for Kotlin/Spring + house rules"
date_added: "2026-05-12"
---

# Clean Code: Functions

> "The first rule of functions is that they should be small. The second rule of functions is that they should be smaller than that." — R. Martin
>
> "Master programmers think of systems as stories to be told rather than programs to be written." — R. Martin

Functions are the verbs of the language a programmer designs while writing a system. Every function is a paragraph in that story — and a paragraph that doesn't fit on a screen, mixes three thoughts, or hides side effects in its margin, breaks the narrative for every reader that comes after. Most of what makes code unreadable lives at the function level: long bodies, mixed levels of abstraction, flag arguments, and side effects masquerading as queries.

This skill is the opinionated catalog of function-level discipline: classical rules from Martin's Ch. 3, adapted for Kotlin's machinery (named/default arguments, `when` over sealed hierarchies, scope functions, `Result<T>`) and Spring's idioms (transactional boundaries, `@ExceptionHandler`, ProblemDetail, command/query separation at the service layer).

## Use this skill when
- Writing a new function or method — before the first line of the body.
- Refactoring a function that crossed 20 lines, three levels of indent, or three arguments.
- Reviewing a PR and you see a function you have to read twice to understand.
- Deciding whether to split a function — *one thing* and *one level of abstraction* are the two tests.
- Replacing a `switch` / `when (type)` with polymorphism (sealed hierarchies + factory).
- Taming a function that takes a boolean flag, an output parameter, or four positional args.
- A function's name says "check X" but it also writes — separating command and query.
- Choosing between exceptions and a `Result<T>` / sealed `Either` at a layer boundary.
- Auditing a module's "average function" before merging a structural change.

## Do not use this skill when
- Naming the function or its parameters — use `clean-code-naming` for that (the two skills work together: this skill assumes names follow `clean-code-naming` rules).
- The function is generated (e.g., `@Generated` JPA criteria, Mapstruct), or strictly mirrors an external contract — shape is not yours to set.
- The "function" is a one-line property accessor or a pure data class member — the rules don't fight there.
- The task is architecture-level (module boundaries, persistence pattern) — use `architect-review` or `architecture-patterns`.

## Core principles (the ten)

1. **Small.** Default size is **≤ 20 lines**, indent depth **≤ 2**. Blocks inside `if` / `while` / `for` should be **one line** — typically a call to a well-named function that documents the block. If a body needs scrolling, the function is doing too much.
2. **Do one thing.** A function does only the steps **one level of abstraction below its name**. The test: if you can extract another function whose name is *not* just a paraphrase of its body, the original was doing more than one thing.
3. **One level of abstraction per function.** Don't mix `pageData.getHtml()` (high) with `.append("\n")` (low). High intent and low mechanics belong in different functions.
4. **Stepdown rule.** Code reads top-down: every function is followed by those it calls, each one level lower. The reader descends through the file the way they descend through a TO-paragraph narrative.
5. **Descriptive names.** A long descriptive name beats a short cryptic one, and beats a comment explaining the cryptic one. Consistency matters: siblings share vocabulary (`includeSetupPage`, `includeSuiteSetupPage`, `includeTeardownPage`) so reading one name predicts the others.
6. **Few arguments.** **0 is best, 1 is good, 2 needs reason, 3 needs justification, 4+ is a missing object.** Kotlin's named arguments soften the ordering problem but not the cognitive load — fewer is still better.
7. **No flag arguments.** `render(isSuite = true)` advertises that the function does two things. Split into `renderForSuite()` / `renderForSingleTest()`, or model the discriminator as a sealed type.
8. **No side effects.** A function named `checkPassword` that also initialises the session is a lie. Either remove the side effect, or rename to expose it (`checkPasswordAndInitialiseSession`) — and use the awkward name as the prompt to redesign.
9. **Command–Query Separation.** A function **either** changes state (returns `Unit` / id / acknowledgement) **or** answers a question (returns a value). Not both. `if (set("user", "bob"))` is the smell.
10. **Exceptions, not error codes.** Error codes spawn nested `if` chains and an `Error` enum that everyone depends on (a dependency magnet). Exceptions (or `Result<T>` at a clearly drawn seam) flatten the happy path and stay open for extension.

## Size & shape — quick targets

| Metric | Target | Action when exceeded |
|---|---|---|
| Function length | ≤ 20 lines | Extract sub-functions; each `if`/`while` block becomes a named call. |
| Indent depth | ≤ 2 levels | Early-return guard clauses; extract the inner block. |
| Cyclomatic complexity | ≤ 5 | Replace conditional with polymorphism (sealed `when`) or strategy. |
| Argument count | ≤ 2 | Argument object (data class / inline value class); receiver via extension. |
| Body branches | 0 or 1 | A second branch usually means "doing two things" — split. |

## Argument count — what each level means

| Arity | Form | Notes |
|---|---|---|
| 0 (niladic) | `render()` | Best. Everything needed is on the receiver. |
| 1 (monadic) | `render(page)` — query / transform / event | Use a verb-noun pair. Distinguish *query* (`fileExists(path)`), *transform* (`open(path): InputStream`), *event* (`onPasswordFailed(attempts)`). |
| 2 (dyadic) | `Point(x, y)` | OK when arguments are **two ordered parts of one concept** (coordinates, range). Otherwise convert one to a receiver or member. |
| 3 (triadic) | rare | Needs strong reason (e.g., `assertEquals(1.0, amount, .001)`). |
| 4+ (polyadic) | almost never | A missing class. Group related parameters into a data class. |

## Flag arguments — always split or sealed-out

```kotlin
// ✗ Flag — the function does two things on the same name
fun render(pageData: PageData, isSuite: Boolean): String

// ✓ Two functions — name carries the variant
fun renderForSuite(pageData: PageData): String
fun renderForSingleTest(pageData: PageData): String

// ✓ Or a sealed type — when there are 3+ variants or the flag is part of a domain enum
sealed interface RenderMode { object Suite; object SingleTest; object SetupOnly }
fun render(pageData: PageData, mode: RenderMode): String
```

`when` over a sealed hierarchy is fine — it's polymorphism in disguise. A boolean isn't.

## Switch / `when` on type → polymorphism

A `when (entity.type)` block that returns different behaviours per type is a `switch` in Martin's sense. It violates SRP (changes for every new type) and OCP (must be edited to extend).

```kotlin
// ✗ when on type — repeats for every operation (calculatePay, isPayDay, deliverPay, ...)
fun calculatePay(e: Employee): Money = when (e.type) {
    COMMISSIONED -> calculateCommissionedPay(e)
    HOURLY       -> calculateHourlyPay(e)
    SALARIED     -> calculateSalariedPay(e)
}

// ✓ Sealed hierarchy + behaviour on each subtype; factory hides the only remaining `when`
sealed class Employee {
    abstract fun calculatePay(): Money
    abstract fun isPayDay(today: LocalDate): Boolean
    abstract fun deliverPay(pay: Money)
}
class Commissioned(...) : Employee() { ... }
class Hourly(...)       : Employee() { ... }
class Salaried(...)     : Employee() { ... }

class EmployeeFactory {
    fun create(record: EmployeeRecord): Employee = when (record.type) {  // ← the one tolerated when
        COMMISSIONED -> Commissioned(record)
        HOURLY       -> Hourly(record)
        SALARIED     -> Salaried(record)
    }
}
```

Tolerated `when` on type: **once**, **inside a factory**, **buried behind the sealed root**. Anywhere else, it's the smell.

## Command–Query Separation

```kotlin
// ✗ Both commands and answers — ambiguous, breaks reasoning
fun set(attribute: String, value: String): Boolean

if (set("username", "unclebob")) { ... }   // does it ask whether it was set, or set-and-check?

// ✓ Split — one verb, one purpose
fun attributeExists(name: String): Boolean
fun setAttribute(name: String, value: String)
```

At the Spring service layer the same rule shows up as the **command-vs-query method split**: methods that mutate return `Unit` / an id; methods that read return DTOs. See `resources/spring-boot-functions.md` for the layered version.

## Exceptions over error codes — flatten the happy path

```kotlin
// ✗ Error codes → nested if chain; happy and sad path are tangled
if (deletePage(page) == OK) {
    if (registry.deleteReference(page.name) == OK) {
        if (configKeys.deleteKey(page.name.toKey()) == OK) logger.info("page deleted")
        else logger.error("configKey not deleted")
    } else logger.error("deleteReference failed")
} else logger.error("delete failed")

// ✓ Exceptions → happy path is linear; error handling is one place
try {
    deletePageAndAllReferences(page)
} catch (e: Exception) {
    logger.error(e.message, e)
}

private fun deletePageAndAllReferences(page: Page) {
    deletePage(page)
    registry.deleteReference(page.name)
    configKeys.deleteKey(page.name.toKey())
}
```

**Error handling is one thing.** If a function contains `try`, the `try` should be the first non-trivial statement and nothing else should follow the `catch` / `finally`. In Spring, lift try/catch out of business code entirely with `@ExceptionHandler` / `@ControllerAdvice` — see `resources/spring-boot-functions.md`.

For domain-level errors at module seams, **`Result<T>` or a sealed `Either`** is a reasonable choice — but pick one boundary, stay on it, and don't let result-wrappers leak through every layer.

## Smell → fix quick reference

| Smell | Fix |
|---|---|
| Function > 20 lines | Extract each block as a named sub-function — `extract method`. |
| Indent > 2 | Guard-clause early returns; lift the inner block into a function. |
| Function with sections (comment "// initialization", "// processing") | Each section is a function. The comment is naming the function for you. |
| Mixed levels of abstraction | High-level call + low-level mechanic in same body → extract the mechanic. |
| Boolean flag argument | Split into two functions, or use a sealed type. |
| Output argument (`appendFooter(buffer)`) | Make it a receiver method (`buffer.appendFooter()`) or return a new value. |
| Function that both reads and writes (`set(...): Boolean`) | Split into `existsX()` + `setX()`. |
| Returns error code | Throw, or return `Result<T>` at a clearly defined seam. |
| `try/catch` mixed with business logic | Extract try-body into its own function; lift catch into `@ExceptionHandler` if Spring. |
| `when (entity.type)` returning behaviour | Sealed hierarchy with behaviour per subtype; one `when` in a factory. |
| 4+ arguments | Argument object (data class or `@JvmInline value class` for a single field). |
| Repeated code across functions | Extract; in Kotlin, often an extension function or default-argument variant. |

## Selective Reading Rule

| File | When to read |
|---|---|
| `resources/general-function-rules.md` | Martin Ch. 3 rules as a foundation — Small, Do One Thing, Stepdown, Switch, Arguments (monad/dyad/triad), Side Effects, Output Args, CQS, Exceptions, Extract Try/Catch, Error.java magnet, DRY, Structured Programming. Read first. |
| `resources/kotlin-specific-functions.md` | What Kotlin solves *out of the box*: named & default args (kill most triads), expression bodies, scope functions (`let`/`run`/`apply`/`also`/`with`) and where they help vs. hide intent, `when` + sealed classes vs. switch, extension functions to move dyads to monads, `Result<T>` & `runCatching`, `inline`/`crossinline`, `suspend` functions, single-expression patterns. |
| `resources/spring-boot-functions.md` | Spring/Spring Boot applications: controller methods as thin orchestrators, `@Transactional` boundaries (one transaction per use case), `@ExceptionHandler` & `@ControllerAdvice` to lift try/catch, `ProblemDetail` (RFC 7807), CQS at the service layer (`Command` returns id, `Query` returns DTO), `@EventListener` / `@TransactionalEventListener` / `@ApplicationModuleListener` handler shape, `@Async`, validation as boundary, method-level security. |
| `resources/ddd-functions.md` | Domain-level applications: behaviour methods on aggregates (`order.submit()`), factory methods replacing switch on type, specifications as composable query-only functions, repositories with one verb per query, domain service vs. aggregate method, ACL translation functions. |

## Anti-patterns in function refactoring work itself

- **Refactoring without tests.** Martin's refactor in Listing 3-7 worked because tests existed. Without tests, every "I shrank this function" carries silent regression risk. **Add the characterization test first; refactor second.**
- **Extract-method spree on unrelated code.** Surgical rule from `karpathy-guidelines` — don't refactor functions you weren't asked to touch. Open a follow-up PR.
- **Naming the extracted function as a restatement.** `validateOrder()` calling `validateOrderInternal()` adds depth without abstraction. Either the extraction is meaningful and the name reflects a new concept, or don't extract.
- **Over-decomposing into one-liners.** A 3-line function extracted into three 1-line functions across a file forces the reader to chase. Small is the rule, not microscopic.
- **Premature polymorphism for a `when` with two cases.** Two cases is a `when`, not a sealed hierarchy. Polymorphism pays off at three+ variants or repeated dispatch.
- **Replacing all error codes with exceptions at a network boundary.** External protocols (HTTP, gRPC, AMQP) speak status codes — `Result`/`Either` at that seam can be clearer than mapping every IO error to a custom exception.
- **Treating "function" as "method on a class".** Top-level functions and extension functions are functions too — same rules apply, and they're often the right tool over a Helper class.
- **Splitting a function only to satisfy line count.** If two halves share so much state that one passes 5 arguments to the other, the original was cohesive — find a different cut.

## Related skills

| Skill | This not that |
|---|---|
| `clean-code-naming` | Names of functions, parameters, variables; this skill is function **shape & responsibility**. The two are paired — apply both. |
| `clean-code` | Smell vocabulary and refactoring cadence at module level; this skill is the deep dive on functions specifically. |
| `solid-principles` | SRP / OCP at class scope; this skill is SRP applied to a single function ("do one thing"). |
| `ddd-tactical-patterns` | Aggregate/VO/Repository structure; this skill is the verb-level discipline inside each. |
| `cqrs-implementation` | Architectural CQRS; this skill is the smaller, function-level command/query separation. |
| `karpathy-guidelines` | §1 surgical changes — don't refactor what you weren't asked to. §6 verify before claim — re-run tests after every extract. |
| `architect-review` | Long-method / god-method smells during a structural audit; this skill provides the criteria the review applies. |
| `methodology-verification` | After any refactor: re-run the proving command before claiming the function is "cleaner". |

## Limitations

- **Numbers are heuristics, not laws.** "≤ 20 lines" is a strong default; a well-named single-expression function returning a `when` over 15 sealed cases can be 30 lines and clearer than any extraction. Apply judgement.
- **Domain shape can override.** A pure data-transformation pipeline may legitimately be a single function with internal `let` chains; cutting it into named pieces can scatter what reads naturally top-to-bottom.
- **External contracts win.** Framework callbacks, JPA criteria builders, gRPC service handlers, Servlet API methods are shaped by the framework — fit Martin's rules where you can, accept the shape where you can't.
- **Performance hot spots are a small carve-out.** Inlining for allocation reasons, manual loop unrolling, or branch-prediction-aware code can make a function "uglier" by Clean Code standards but faster. Measure first; comment why; isolate the ugliness to the smallest function possible.
- **Team consistency is non-negotiable.** If the codebase uses `Result<T>` at every layer, conform; if it throws everywhere, conform. A single function written against the grain is worse than one that follows a flawed-but-consistent style.
