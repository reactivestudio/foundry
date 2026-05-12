---
name: clean-code-formatting
description: "Code formatting discipline for Kotlin/Spring code — opinionated rules for vertical formatting (file size ≤ 500 lines, newspaper top-down ordering, blank-line openness, dependent-function locality, stepdown reading) and horizontal formatting (line width ≤ 120, whitespace around low-precedence operators, no manual column alignment, indentation never collapsed). Adapted from R. Martin's Clean Code Ch. 5 'Formatting', filtered for what Kotlin already solves (expression bodies, single-expression functions, trailing commas, primary-constructor properties, multi-line string `trimIndent`) and extended with Spring conventions (thin controllers, transactional boundaries as natural vertical separators, Given-When-Then test layout, `application.yml` structure) and the tooling that enforces it (ktlint, ktfmt, Spotless, detekt, EditorConfig, pre-commit hooks, CI gates). Use when setting up a new project's formatting profile, picking between ktlint and ktfmt, configuring `.editorconfig` for a Kotlin/Spring repo, reviewing a file that 'feels off' visually, fixing a 1000-line god class with the wrong vertical structure, refactoring a class whose dependent methods are scattered, adding pre-commit / CI formatting gates, reviewing a PR with broken stepdown ordering or mixed levels of abstraction, deciding when expression bodies / scope functions improve density vs. when they hide intent, choosing alignment for `when` arrows / variable declarations, or auditing a Spring service for layout consistency before merging."
risk: safe
source: "Adapted from R. Martin, Clean Code (2008), ch. 5 'Formatting', filtered for Kotlin/Spring + house rules + modern tooling"
date_added: "2026-05-12"
---

# Clean Code: Formatting

> "Code formatting is about communication, and communication is the professional developer's first order of business." — R. Martin
>
> "The functionality you create today has a good chance of changing in the next release, but the readability of your code will have a profound effect on all the changes that will ever be made." — R. Martin

Formatting is the only attribute of code that survives every refactor. The names change, the structure changes, the algorithm changes — but the *shape* a reader's eye traces down the file is set by precedent and rarely reset. A team that gets formatting right buys decades of compounding readability; a team that doesn't pays a tax on every read.

This skill is the opinionated catalog: Martin's Ch. 5 rules adapted for Kotlin's syntax (expression bodies, trailing commas, primary constructors, multi-line strings, scope functions) and Spring's idioms (thin controllers, transactional boundaries, Given-When-Then tests, `application.yml` layout), plus the **tooling layer** Martin didn't have — ktlint, ktfmt, Spotless, detekt, EditorConfig, pre-commit, CI gates — because in 2026 the team rules are encoded in a file, not in a wiki page.

## Use this skill when
- Setting up a new Kotlin/Spring project — picking the formatter (ktlint vs. ktfmt), writing `.editorconfig`, wiring pre-commit + CI gate.
- A reviewer says "this file is hard to read" but can't point at a specific bug — formatting is usually the answer.
- A 1000-line god class needs to be triaged — the first cut is "what does the vertical structure tell us about responsibilities?".
- Refactoring a class whose dependent functions are scattered up and down the file — applying stepdown.
- Reviewing a PR with a `when` block, a multi-line lambda, or a long argument list and deciding what shape is canonical.
- Auditing a Spring service for layout: where do `@Transactional` boundaries sit, are controllers thin, are tests Given-When-Then.
- Choosing whether expression bodies (`fun x() = ...`) help density or hide a complex computation.
- A team is bikeshedding tabs vs. spaces, alignment, line width — encoding the decision in `.editorconfig` once and for all.
- Migrating a Java codebase to Kotlin and deciding which Java-style habits to drop (column alignment, `m_` prefixes, getters above fields).

## Do not use this skill when
- The task is naming, function size, or class structure — use `clean-code-naming`, `clean-code-functions`, or `clean-code-classes` instead. Formatting is the **layer** of those skills, not their content.
- The codebase has an established and automated formatter (ktlint/ktfmt with strict CI gate) — conform to it; don't litigate. Open a separate discussion if you want to change the team standard.
- The file is generated (`build/generated/`, MapStruct, kapt, protobuf) — its shape is not yours to set.
- The task is architecture, persistence, or testing strategy — use the relevant sibling skill.

## Core principles (the ten)

1. **Formatting is communication.** Choose rules that minimise reader friction; once chosen, apply them mechanically via tooling. Religion is for things people argue about; this is for things a tool decides.
2. **Vertical structure tells a story.** A file reads top to bottom like a newspaper article: name = headline, top = high-level intent, bottom = mechanical detail. The reader can stop reading at any line and have already gotten the gist.
3. **Files stay small.** Target ≤ 200 lines, ceiling 500. Significant systems are built from many small files, not few large ones. A 2,000-line file is almost always two missing classes.
4. **Blank lines are punctuation.** Use them between concepts (package / imports / class header / each method). Within a method, blank lines separate sections that — if you wrote a comment — would each get one.
5. **Closely related things stay close.** Dependent function below caller. Instance variables in one well-known place. Variable declarations next to their use. Conceptual cousins (`assertTrue`/`assertFalse`) shoulder to shoulder.
6. **Stepdown reading direction.** Calls point downward. Read top-down to descend levels of abstraction; you should never have to scroll up to understand what comes next.
7. **Lines stay under 120.** 80 is a relic, 200 is careless. Long lines push the reader to scroll horizontally — and horizontal scroll breaks pattern recognition. Break long expressions on operators or argument boundaries.
8. **Horizontal whitespace separates by precedence.** Spaces around `=`, around low-precedence operators (`+`, `-`), no spaces between high-precedence factors (`a*b`), no space between function name and `(`. Spaces after commas. **Don't column-align** — alignment emphasises the wrong axis and breaks under reformat.
9. **Indentation is sacred.** Never collapse `if`/`while`/short function bodies to one line. Indent encodes the scope hierarchy; collapsing it costs the reader a mental indent reconstruction every time.
10. **Team rules > personal preferences.** Encode them in `.editorconfig` + ktlint/ktfmt + a CI gate. A consistent style applied by everyone (even one you mildly dislike) beats a mix of personal styles.

## Quick targets

| Metric | Target | Action when exceeded |
|---|---|---|
| File length | ≤ 200 lines, max ~500 | Split the class. The shape is telling you two responsibilities live here. |
| Class length | ≤ ~150 lines | Same. Look for an emergent collaborator or a "secondary" concept. |
| Function length | ≤ 20 lines | Use `clean-code-functions` — extract sub-functions. |
| Line width | ≤ 120 chars | Break on operators, named arguments, or extract a local variable. |
| Indent depth | ≤ 3 levels | Guard clauses + extract method. |
| Blank lines between methods | exactly 1 | Tooling auto-fixes. Two blank lines = signal the editor is asleep. |
| Blank lines inside a method | 0 or 1 to separate sections | If you need 2+, the function is doing 2+ things — split. |

## Vertical formatting — cheatsheet

### The newspaper metaphor

```
┌── ClassName.kt ────────────────────────────────────┐
│ package com.example.order                          │  ← name + location
│                                                    │
│ import ...                                         │  ← context
│                                                    │
│ class OrderService(                                │  ← headline: what this file is
│     private val orderRepository: OrderRepository,  │  ← collaborators
│     private val paymentGateway: PaymentGateway,    │
│ ) {                                                │
│                                                    │
│     fun submit(orderId: OrderId): Order { ... }    │  ← high-level intent (public API)
│                                                    │
│     fun cancel(orderId: OrderId) { ... }           │
│                                                    │
│     private fun chargePayment(...) { ... }         │  ← one level down: helper for submit
│                                                    │
│     private fun reserveStock(...) { ... }          │  ← same level: helper for submit
│                                                    │
│     private fun computeFee(...): Money { ... }     │  ← lowest level: pure mechanic
│ }                                                  │
└────────────────────────────────────────────────────┘
```

### Vertical openness — where blank lines go

```kotlin
package com.example.order            // ← package on its own
                                     // ← blank
import com.example.shipping.Address  // ← imports as a block
import java.time.Instant
                                     // ← blank
class Order(                         // ← class header
    val id: OrderId,
    val lines: List<OrderLine>,
) {
                                     // ← blank
    fun submit(): SubmittedOrder { ... }
                                     // ← blank between methods
    fun cancel() { ... }
}
```

Inside a method body, a blank line marks a logical section — if you'd write a comment like `// validate`, leave a blank line instead and let the next line's name carry the meaning.

### Vertical density — kill the noise that breaks tight pairs

```kotlin
// ✗ Useless KDoc breaks the natural pair of related fields
class ReporterConfig {
    /** The class name of the reporter listener */
    private val className: String

    /** The properties of the reporter listener */
    private val properties: MutableList<Property> = mutableListOf()
}

// ✓ Pair is visually tight; meaning is in the names
class ReporterConfig {
    private val className: String
    private val properties: MutableList<Property> = mutableListOf()
}
```

If a comment really adds value, it goes *above* the field with a blank line above it — not in between the two related fields.

### Vertical distance — five rules

| Rule | What it means |
|---|---|
| **Local variables near use** | Declare at top of small function, or just before the first use. Don't hoist all declarations to the top of a 50-line method. |
| **Instance variables at top** | Kotlin's primary constructor solves this — properties declared in the constructor live there. For `class { val/var ... ; fun ... }` style, properties go above methods. |
| **Caller above callee** | Public API on top, private helpers below. Reading the file is descending the call tree. |
| **Conceptual affinity** | Sibling methods (`assertTrue`/`assertFalse`, `findById`/`findByName`) stay adjacent even if they don't call each other. Shared vocabulary → adjacency. |
| **Vertical ordering** | Most important concepts first. A reader should learn the highest-value thing in the first 20 lines of a file. |

### Caller-above-callee — stepdown reading

```kotlin
// ✓ Stepdown — reading top to bottom is reading levels of abstraction
class WikiPageResponder(...) {

    fun makeResponse(context: Context, request: Request): Response {
        val pageName = getPageNameOrDefault(request, "FrontPage")
        loadPage(pageName, context)
        return if (page == null) notFoundResponse(context, request)
               else makePageResponse(context)
    }

    private fun getPageNameOrDefault(request: Request, default: String): String { ... }

    private fun loadPage(resource: String, context: Context) { ... }

    private fun notFoundResponse(...) { ... }

    private fun makePageResponse(...) { ... }
}
```

The eye traverses the file the way it traverses an outline: each function defines the next.

## Horizontal formatting — cheatsheet

### Whitespace around operators

```kotlin
// ✓ Space around assignment + low-precedence ops; tight on high-precedence factors
val determinant = b * b - 4 * a * c
val root1 = (-b + sqrt(determinant)) / (2 * a)

fun measureLine(line: String) {
    lineCount++
    val lineSize = line.length
    totalChars += lineSize
    lineWidthHistogram.addLine(lineSize, lineCount)   // ← no space between fn and (
    recordWidestLine(lineSize)
}
```

| Where | Spaces? | Why |
|---|---|---|
| Around `=` (assignment / default param) | yes | Two distinct sides; spacing signals it. |
| Around `+`, `-`, `==`, `&&`, `\|\|` | yes | Low precedence — accentuate. |
| Around `*`, `/`, `%` | no (often) | High precedence factor; tight binding. |
| Between function name and `(` | **no** | Name and parens are one unit. |
| After `,` | yes | Argument separator. |
| Around `->` in lambdas | yes | Same as `=`. |

Most of this is enforced by ktlint/ktfmt automatically. The rule matters for explaining *why* the tool chose what it chose.

### Line width

- **120 is the cap**, 100 is a kinder default for side-by-side diffs.
- Break on argument boundaries, on operators, or by extracting a local with a meaningful name. Don't break mid-identifier.
- Long argument list → trailing-comma multi-line layout (Kotlin 1.4+).

```kotlin
// ✓ Trailing-comma multi-line — every arg on its own line, adds-a-line diffs are 1 line
fun createOrder(
    customer: CustomerId,
    lines: List<OrderLine>,
    shipping: Address,
    billing: Address,
    placedAt: Instant,
): Order { ... }
```

### Indentation — never collapse

```kotlin
// ✗ Collapsed scopes hide structure
class CommentWidget(parent: ParentWidget, text: String) : TextWidget(parent, text) {
    companion object { const val REGEXP = "^#[^\r\n]*(?:(?:\r\n)|\n|\r)?" }
    override fun render() = ""
}

// ✓ Expanded — short, but the structure is still visible at a glance
class CommentWidget(parent: ParentWidget, text: String) : TextWidget(parent, text) {

    companion object {
        const val REGEXP = "^#[^\r\n]*(?:(?:\r\n)|\n|\r)?"
    }

    override fun render(): String = ""
}
```

**Kotlin exception**: a true **single-expression function** (`fun x() = ...`) is *not* collapsed indentation — it's a different syntactic form. Single-expression is fine when the expression fits one line and reads naturally; if you find yourself wanting to add a comment or break across lines, switch to a block body.

### Column alignment — don't

```kotlin
// ✗ Alignment lies — the eye reads down a column without crossing types/values
class FitNesseExpediter(...) {
    private val socket                  : Socket
    private val input                   : InputStream
    private val output                  : OutputStream
    private val request                 : Request
    protected var requestParsingTimeLimit: Long
    private var requestProgress         : Long
}

// ✓ Unaligned — and the length of the list now visibly screams "split this class"
class FitNesseExpediter(...) {
    private val socket: Socket
    private val input: InputStream
    private val output: OutputStream
    private val request: Request
    protected var requestParsingTimeLimit: Long
    private var requestProgress: Long
}
```

The alignment rule generalises: **manual column alignment hides the real signal.** If the list is long enough that alignment would help, the list is the smell.

## Smell → fix quick reference

| Smell | Fix |
|---|---|
| File > 500 lines | Split. The classes inside are different responsibilities. |
| All private helpers above the public method | Reverse to stepdown order — public on top. |
| Caller and callee in opposite ends of the file | Move callee just below caller. |
| Instance vars scattered through the class body | Move all properties to the top (or into the primary constructor). |
| Local variable declared at top of long method, used 30 lines later | Move declaration next to first use, or extract that block to a method. |
| Two unrelated public methods with no blank line between | Insert blank line. |
| Two halves of a method separated by blank line + section comment | Each half is a function — extract. |
| Line > 120 chars | Break on argument boundaries / operators. |
| `if (cond) doX()` on one line | Expand to block body. |
| Multi-line method without any blank lines inside | If method does more than one thing, split by section with blank lines; better, extract. |
| Inconsistent style between files | Run formatter on the whole repo as one commit; lock it in CI. |
| `${field?.value ?: default}` chained 4 levels deep on one line | Extract a `val` with a meaningful name. |
| Manual column alignment of `=`, `:`, `->` | Remove. Trust the formatter. |
| `}` and method signature on same line | Always separate. |
| Useless comments between paired fields | Delete. The pairing speaks. |

## Selective Reading Rule

| File | When to read |
|---|---|
| `resources/general-formatting-rules.md` | Martin Ch. 5 rules as the foundation — Newspaper Metaphor, Vertical Openness, Vertical Density, Vertical Distance (Variable Declarations, Dependent Functions, Conceptual Affinity), Vertical Ordering, Line Width, Horizontal Openness/Density, Alignment, Indentation, Dummy Scopes, Team Rules. With before/after examples ported from Java to Kotlin. Read first when starting on this skill. |
| `resources/kotlin-specific-formatting.md` | Kotlin-only formatting decisions: Kotlin official style guide deltas from Java, primary-constructor property layout, trailing commas, expression bodies vs. block bodies, scope functions and their vertical-density risk, `when` block layout (and why not to align arrows), multi-line lambdas, multi-line strings + `trimIndent` / `trimMargin`, extension function placement, top-level declarations vs. companion objects, package layout. |
| `resources/spring-boot-formatting.md` | Spring/Spring Boot applications: controller method shape (thin, one transaction per use case), `@Transactional` as a natural vertical separator, `@RestController` annotation stacking, `application.yml` / `application.properties` structure and sectioning, `@ConfigurationProperties` layout, JPA `@Entity` field ordering, REST controller method ordering (HTTP-verb stepdown), Given-When-Then test layout with blank lines, AssertJ chain layout, Spring Security DSL layout. |
| `resources/tooling-formatting.md` | The formatting toolchain — pick your formatter (**ktlint** for Kotlin official style + plugin-light vs. **ktfmt** for Facebook/Google strict-deterministic vs. **diktat** for opinionated checks), Spotless as the Gradle wrapper, detekt's formatting ruleset, **EditorConfig** as the cross-tool source of truth, IntelliJ IDEA `.editorconfig` integration, pre-commit hooks (Husky / lefthook / pre-commit), CI gate (Gradle task in GitHub Actions / GitLab), strategy for the first migration (one big-bang reformat commit), git-blame-ignore-revs to keep history readable. |

## Anti-patterns in formatting work itself

- **Reformatting a file you're touching for a bugfix.** Surgical rule from `karpathy-guidelines` — the diff should show the fix, not a 200-line reformat noise. Open a separate "reformat" PR; commit it via `.git-blame-ignore-revs` so `git blame` stays useful.
- **Adopting Clean Code's Java conventions verbatim in Kotlin.** Martin's "instance vars at top of class" is shaped by Java field declarations. Kotlin's primary constructor *is* the place — don't duplicate fields in the body just to honour the rule literally.
- **Litigating style in PR review when the team has a formatter.** If `./gradlew spotlessCheck` passes, the formatting is correct *by definition*. Code review focuses on intent, not whitespace.
- **Configuring the formatter to match each developer's IDE settings.** The opposite — encode rules in `.editorconfig` + ktlint/ktfmt, IDE auto-imports from there. One source of truth.
- **Mixing formatter changes with semantic changes in one commit.** Even with `.git-blame-ignore-revs`, mixed commits make code review impossible. Reformat commits do one thing.
- **Skipping the CI gate "just for this PR".** If the gate is optional, it doesn't exist. The gate is what makes the rules survive turnover.
- **Manually aligning `when` arrows or variable types.** The formatter doesn't preserve it; you'll fight the tool every reformat. Pick alignment-off and move on.
- **Treating expression bodies as a goal.** `fun x() = if (a) compute(b) else fallback(c, d).also { log(it) }.let { transform(it) }` is shorter but unreadable. Single-expression form is a *reward* for a function that genuinely is one expression — not a target.
- **Reformatting a file that has an active feature branch.** Conflicts will be 100% of the diff. Merge or rebase first, then reformat.

## Related skills

| Skill | This not that |
|---|---|
| `clean-code-naming` | Names of classes, methods, variables; this skill is the **layout** those names live in. |
| `clean-code-functions` | Function size and responsibility; this skill is the visual presentation of those functions on the page. Stepdown reading is the bridge between them. |
| `clean-code` | Smell vocabulary and refactoring cadence — names smells like long methods, deep nesting, primitive obsession; this skill is the typographic layer. |
| `solid-principles` | SRP / OCP at class scope; SRP at file scope is one expression of "small files". |
| `architecture-patterns` | Package layout and module boundaries; this skill assumes the package exists and shapes the file inside it. |
| `testing-strategy-kotlin-spring` | What to test and at which slice; this skill is the visual layout of the test (Given-When-Then blocks, AssertJ chain). |
| `karpathy-guidelines` | §1 surgical changes — don't reformat code you weren't asked to touch. §6 verify — re-run the formatter check before claiming a fix is ready. |
| `methodology-verification` | After any formatting change: `./gradlew spotlessCheck` (or equivalent) must pass before claiming the work is done. |

## Limitations

- **Numbers are heuristics, not laws.** "≤ 200 lines per file" is a strong default; a generated DSL definition or a Kotlin sealed-class hierarchy enumerating 50 domain events can legitimately be 400 lines and still readable.
- **External shape can override.** Framework-generated files (kapt, MapStruct, protobuf, Avro-generated POJOs) and DSL builders (Gradle Kotlin DSL, Spring Security DSL) have their own conventions — let them be.
- **Vertical-distance rules trade off with file-size rules.** Keeping a callee just below its caller can grow a file past 500 lines; at some point, splitting wins. The trade-off is judgement, not mechanics.
- **Team consistency is non-negotiable.** If the codebase aligns `when` arrows, conform; if it doesn't, conform. A single file written against the grain is worse than one that follows a flawed-but-consistent style.
- **Tooling can mask design problems.** A perfectly ktlint-clean 2,000-line class is still a 2,000-line class. Formatting is the *layer*, not the *cure* — pair this skill with `clean-code-functions` / `clean-code` for the deeper smells.
- **`.editorconfig` precedence varies across IDEs/CLIs.** When ktlint, IntelliJ, and `.editorconfig` disagree, ktlint wins on CI, IntelliJ wins locally, and `.editorconfig` is supposed to be authoritative for both. Pin versions and audit periodically.
