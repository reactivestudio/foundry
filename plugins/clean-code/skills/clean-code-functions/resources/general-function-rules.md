# General Function Rules

Universal function-writing rules adapted from R. Martin's *Clean Code* (Ch. 3 "Functions"). Rules where Kotlin already changes the game (named/default args replacing argument-object cheats, `when` + sealed replacing the switch pattern, scope functions replacing trivial helpers, expression bodies, `Result<T>`) are *summarised here* and *deepened in* `kotlin-specific-functions.md`. Framework applications (transactional boundaries, `@ExceptionHandler`, CQS at the service layer) live in `spring-boot-functions.md`. Aggregate/repository/specification function shape lives in `ddd-functions.md`.

> "Functions should do one thing. They should do it well. They should do it only." — Martin
>
> "Functions are the verbs of [the language we design while we write a system], and classes are the nouns." — Martin

## How to read this file

Each rule has:
- **Principle** — the one-sentence rule.
- **Bad / Good** — Kotlin snippets adapted from Martin's Java originals.
- **Why** — the failure mode the rule prevents.
- **Exception** — when the rule legitimately bends.
- **House extension** (where applicable) — Kotlin/Spring-specific add-ons.

The rules are presented in the order Martin presents them — which is roughly the order a reader notices them when opening an unfamiliar function.

---

## Rule 1: Small

**Source**: Martin Ch. 3 §"Small!" and §"Blocks and Indenting"
**Principle**: Functions should be small. Then they should be smaller than that. **Target: ≤ 20 lines, ≤ 2 levels of indent.** Each block inside `if` / `else` / `while` / `for` should be **one line** — typically a call to a function whose name documents the block.

**Bad** (mixed levels, deep nesting, ~50 lines):
```kotlin
fun testableHtml(pageData: PageData, includeSuiteSetup: Boolean): String {
    val wikiPage = pageData.wikiPage
    val buffer = StringBuilder()
    if (pageData.hasAttribute("Test")) {
        if (includeSuiteSetup) {
            val suiteSetup = PageCrawlerImpl.getInheritedPage(SUITE_SETUP_NAME, wikiPage)
            if (suiteSetup != null) {
                val pagePath = suiteSetup.pageCrawler.getFullPath(suiteSetup)
                val pagePathName = PathParser.render(pagePath)
                buffer.append("!include -setup .").append(pagePathName).append("\n")
            }
        }
        // ...30 more lines of mixed-abstraction work
    }
    pageData.content = buffer.toString()
    return pageData.html
}
```

**Good** (small, single-level, top-level intent):
```kotlin
fun renderPageWithSetupsAndTeardowns(pageData: PageData, isSuite: Boolean): String {
    if (pageData.isTestPage()) {
        includeSetupAndTeardownPages(pageData, isSuite)
    }
    return pageData.html
}
```

The inner functions (`includeSetupAndTeardownPages`, `includeSetupPages`, ...) sit just below this one in the file, each at one level of abstraction.

**Why**: The eye should not have to scroll, the brain should not have to push state onto a mental stack to follow a function. Small functions are individually obvious. They compose into stories.

**Exception**: A single `when` over many sealed cases can produce a 30-line function that is *more* readable than any split. A pure data pipeline (`return rows.map { ... }.filter { ... }.groupBy { ... }`) may legitimately be 15 lines and require no extraction.

**House extension (Kotlin)**:
- Single-expression functions are how Kotlin makes "small" the default — `fun isAdmin() = role == ADMIN`. Use them aggressively for one-liner getters/predicates.
- The "one line per block" rule fits the body of `let` / `run` / `also` / `apply` chains *when the chain is the function*. If you're nesting scope functions to keep the line count down, you've cheated — extract.

---

## Rule 2: Do One Thing

**Source**: Martin Ch. 3 §"Do One Thing"
**Principle**: A function should do only the steps **one level of abstraction below its name**. Equivalently: if you can extract another function from it with a name that is *not* merely a paraphrase of the body, the original was doing more than one thing.

**Bad** (three different things at three abstraction levels):
```kotlin
fun emailReceipt(order: Order) {
    val pdf = PdfGenerator()
    pdf.addLine("Order #${order.id}")
    order.lines.forEach { line ->
        pdf.addLine("${line.name}  ${line.quantity}  ${line.price}")
    }
    pdf.addLine("Total: ${order.total}")
    val bytes = pdf.render()
    val message = MimeMessage()
    message.setSubject("Your receipt")
    message.setRecipient(order.customer.email)
    message.attach(bytes, "receipt.pdf")
    smtp.send(message)
}
```

**Good**:
```kotlin
fun emailReceipt(order: Order) {
    val receipt = renderReceipt(order)
    sendReceiptEmail(order.customer.email, receipt)
}

private fun renderReceipt(order: Order): ByteArray { ... }
private fun sendReceiptEmail(to: Email, attachment: ByteArray) { ... }
```

`emailReceipt` now describes two steps at one level below its name — *render* and *send*. Each sub-function is internally cohesive.

**Why**: A function that does three things has three reasons to change, three failure modes to test, and three contexts a reader must hold simultaneously. Splitting decouples them in time and in the reader's mind.

**Exception**: "One thing" is **not** "one statement". A `validateAndNormalise` step at the right level of abstraction is one thing — *prepare the input* — even though it bundles several checks.

**Test (Martin's rule)**: if you can extract another function whose name is more than a restatement of the body, the function was doing more than one thing. `includeSetupsAndTeardownsIfTestPage` extracted from a one-`if` body is just a restatement — that's the line.

---

## Rule 3: One Level of Abstraction per Function

**Source**: Martin Ch. 3 §"One Level of Abstraction per Function"
**Principle**: All statements in a function should sit at the same conceptual altitude.

**Bad** (high-level `getHtml()` next to low-level `.append("\n")`):
```kotlin
fun render(page: Page): String {
    val html = page.getHtml()                // high
    val buf = StringBuilder(html)
    buf.append("\n")                          // low
    buf.append("<!-- end -->")                // low
    return buf.toString()
}
```

**Good**:
```kotlin
fun render(page: Page): String =
    page.getHtml()
        .withFooter("<!-- end -->")           // one consistent level: "rendered html with footer"

private fun String.withFooter(footer: String) = "$this\n$footer"
```

**Why**: Mixing levels of abstraction obscures intent. A reader sees `getHtml()` and assumes "we're working with rendered output" — then sees `.append("\n")` and realises they're working with raw character mechanics. They have to revise their model and re-read.

**Symptom**: a comment "// now do the buffer stuff" inside a function that started with "// render the page". Each comment is naming a section — each section wants to be a function.

**Exception**: An assertion or short guard clause at the top of a function (`require(amount > 0)`) is a different micro-level but is **structurally** outside the body proper. That's fine.

---

## Rule 4: Reading Code Top to Bottom — the Stepdown Rule

**Source**: Martin Ch. 3 §"Reading Code from Top to Bottom: The Stepdown Rule"
**Principle**: Code should read like a top-down narrative. Each function is followed in the file by the functions it calls, each at the next level of abstraction down. "TO render the page, we render setups, then content, then teardowns. TO render setups, we render the suite setup if it's a suite, then the regular setup. TO render the suite setup, we..."

**Bad** (private helpers scattered alphabetically or by accident of edit order):
```
class PageRenderer {
    fun render(page) { ... calls a(), b() ... }
    private fun z() { ... }
    private fun a() { ... calls b() ... }
    private fun m() { ... }
    private fun b() { ... }
}
```

**Good**:
```
class PageRenderer {
    fun render(page) { ... calls a(), b() ... }
    private fun a() { ... calls b() ... }
    private fun b() { ... }
    private fun m() { ... }
    private fun z() { ... }
}
```

The reader who opens the file at the top can descend through the call graph by reading down, never scrolling back up.

**Why**: Code is read far more than written. The reader who has to jump around to follow control flow is paying a tax on every read. Ordering for narrative pays it once at edit time.

**Exception**: Cross-cutting helpers used by many functions in the file may go at the bottom (private utility section), once the main narrative is over.

**House extension**: In Kotlin, top-level private functions in the same file follow the same rule — the file is the narrative unit, not the class. Extension functions defined at the file top also fit this — order them after the function that uses them most.

---

## Rule 5: Use Descriptive Names

**Source**: Martin Ch. 3 §"Use Descriptive Names"
**Principle**: Don't be afraid of long descriptive names. A long descriptive name beats a short cryptic name; a long descriptive name beats a long descriptive *comment*. Pick consistent vocabulary across sibling functions so the names tell a story when read together.

**Bad**:
```kotlin
fun proc(x: Order) { ... }
fun handle(x: Order) { ... }
fun doWork(x: Order) { ... }
```

**Good**:
```kotlin
fun renderPageWithSetupsAndTeardowns(page: Page, isSuite: Boolean): String
private fun isTestPage(page: Page): Boolean
private fun includeSetupAndTeardownPages(page: Page, isSuite: Boolean)
private fun includeSetupPages(page: Page, isSuite: Boolean)
private fun includeSuiteSetupPage(page: Page)
private fun includeSetupPage(page: Page)
private fun includeTeardownPage(page: Page)
private fun includeSuiteTeardownPage(page: Page)
```

Reading those names in order, the structure is obvious. If `includeSuiteSetupPage` exists, you expect `includeSuiteTeardownPage` to exist, and it does.

**Why**: Names are the cheapest form of documentation that doesn't drift. A consistent naming scheme across siblings creates a tiny domain-specific language inside the module — and a reader who learns one verb can predict the rest.

**Exception**: Inside a 5-line scope, `i`, `it`, or a short lambda parameter is fine. The longer the scope, the longer the name should be.

**Cross-link**: See `clean-code-naming` for the deep dive — this skill assumes those rules are applied at the level of *what* the function is called; this rule is just the function-shape consequence.

---

## Rule 6: Function Arguments

**Source**: Martin Ch. 3 §"Function Arguments"
**Principle**: The ideal number of arguments is **zero** (niladic). Then **one** (monadic). Then **two** (dyadic). **Three** needs justification. **Four or more** is a missing object.

### Common monadic forms

There are three legitimate shapes for a one-argument function:

1. **Query** — ask about the argument: `fun fileExists(path: Path): Boolean`.
2. **Transform** — take the argument and return something derived: `fun open(path: Path): InputStream`.
3. **Event** — argument is the event data; no return value: `fun onPasswordAttemptFailed(attempts: Int)`.

```kotlin
// ✗ Monadic without one of the three forms — confusing
fun includeSetupPageInto(buffer: StringBuilder)   // is it a transform? an event?

// ✓ Transform: returns the result
fun renderSetupPage(): String

// ✓ Method on the receiver: the buffer is the receiver, the argument tells what to do
buffer.appendSetupPage()
```

### Dyads

A function with two arguments takes more thought than monadic — the reader has to learn the order. Acceptable when the two arguments are **two ordered parts of one concept**:

```kotlin
val origin = Point(0, 0)        // x, y — ordered components of a single value
val range = Range(start, end)
```

Less acceptable when the two arguments have no natural ordering:

```kotlin
// ✗ writeField — which goes first?
writeField(outputStream, name)

// ✓ Move the OutputStream to a receiver
outputStream.writeField(name)
```

### Triads

Three arguments **significantly** harder. Most triads should be reduced to monads or dyads via:
- **Argument object** — group related arguments into a data class.
- **Receiver** — move one to the function's owning class.
- **Default arguments** — when one is rarely varied.

```kotlin
// ✗ Triad with ambiguous ordering
fun assertEquals(message: String, expected: T, actual: T)

// ✓ One reasonable triad — three values of one *concept* (floating-point comparison)
fun assertEquals(expected: Double, actual: Double, delta: Double)
```

### Polyadic (4+)

Almost always a missing class. Group related arguments into a data class.

```kotlin
// ✗ Polyad
fun makeCircle(x: Double, y: Double, radius: Double, colour: Colour, label: String): Circle

// ✓ Argument object
data class Circle(val centre: Point, val radius: Double, val style: Style)
data class Style(val colour: Colour, val label: String)
```

**Why**: Every additional argument is something the reader must look up, the caller must order correctly, and the tester must exercise. Argument count grows the call-site combinatorics multiplicatively.

**House extension (Kotlin)**: Named arguments at call sites mitigate but do not eliminate the cost — see `kotlin-specific-functions.md`.

---

## Rule 7: Flag Arguments

**Source**: Martin Ch. 3 §"Flag Arguments"
**Principle**: A boolean argument that toggles behaviour advertises that the function does two things. Split it.

**Bad**:
```kotlin
fun render(pageData: PageData, isSuite: Boolean): String
// caller:
render(pageData, true)   // what is `true`?
```

**Good (split)**:
```kotlin
fun renderForSuite(pageData: PageData): String
fun renderForSingleTest(pageData: PageData): String
```

**Good (sealed mode when ≥ 3 variants)**:
```kotlin
sealed interface RenderMode {
    object Suite : RenderMode
    object SingleTest : RenderMode
    object SetupOnly : RenderMode
}

fun render(pageData: PageData, mode: RenderMode): String =
    when (mode) {
        Suite      -> ...
        SingleTest -> ...
        SetupOnly  -> ...
    }
```

**Why**: A flag passes the *decision* into the function. The decision belongs at the call site. A `Boolean` parameter is the worst form because the call site `f(true)` reveals nothing.

**Exception**: A genuinely orthogonal modifier — `findAll(includeDeleted = false)` — where the two behaviours are the same operation with one toggle. Named-only invocation makes this readable. Even then, two functions are clearer if the count is two.

---

## Rule 8: Have No Side Effects

**Source**: Martin Ch. 3 §"Have No Side Effects" / §"Output Arguments"
**Principle**: A function's name promises what it does. A function that does more than its name promises lies to the reader. Side effects (mutating fields, system globals, parameters) are the most common lie.

**Bad**:
```kotlin
class UserValidator(private val crypto: Cryptographer) {
    fun checkPassword(userName: String, password: String): Boolean {
        val user = UserGateway.findByName(userName) ?: return false
        val phrase = crypto.decrypt(user.encryptedPhrase, password)
        if (phrase == "Valid Password") {
            Session.initialise()                  // ← side effect, name says nothing
            return true
        }
        return false
    }
}
```

**Good** (separate the side effect):
```kotlin
class UserValidator(private val crypto: Cryptographer) {
    fun checkPassword(userName: String, password: String): Boolean {
        val user = UserGateway.findByName(userName) ?: return false
        val phrase = crypto.decrypt(user.encryptedPhrase, password)
        return phrase == "Valid Password"
    }
}

// Caller decides when to initialise the session
if (validator.checkPassword(name, password)) {
    Session.initialise()
}
```

**Why**: Side effects create **temporal coupling** — the function can only be called when calling it is safe (in this case, when erasing the session is OK). Hidden coupling is the source of bugs that only show up in production.

**Exception**: If the function's *purpose* is the side effect — `logger.error(message)` — the side effect is the contract and the name reflects it.

**House extension**: If you must keep the coupling, **name it**: `authenticateAndInitialiseSession`. Then use the awkward name as the smell that pushes you to redesign.

---

## Rule 9: Output Arguments

**Source**: Martin Ch. 3 §"Output Arguments"
**Principle**: Arguments are read as inputs. An argument that the function mutates breaks that contract.

**Bad**:
```kotlin
fun appendFooter(buffer: StringBuilder) {
    buffer.append("\n<!-- end -->")
}

// caller has to read the signature to know what happens
appendFooter(report)
```

**Good** (extension / method on the owning object):
```kotlin
fun StringBuilder.appendFooter() {
    append("\n<!-- end -->")
}

// caller reads naturally — the receiver is mutated, the argument is the "what"
report.appendFooter()
```

**Or** return a new value:
```kotlin
fun withFooter(report: String): String = "$report\n<!-- end -->"

val finished = withFooter(report)
```

**Why**: Output arguments cause a double-take. In OO languages, `this` is the natural output channel — use it. In Kotlin, extension functions add a second receiver-style output channel.

**Exception**: A builder receiving a builder as input (`Spec.from(builder).build()`) — the type makes the mutation obvious.

---

## Rule 10: Command–Query Separation

**Source**: Martin Ch. 3 §"Command Query Separation" (originally B. Meyer)
**Principle**: Functions should either **do** something (commands) or **answer** something (queries) — not both.

**Bad**:
```kotlin
fun set(attribute: String, value: String): Boolean   // returns "did it work?"

if (set("username", "unclebob")) { ... }
// Does this ask "was it set?" or "set it, and check the result"?
```

**Good**:
```kotlin
fun attributeExists(name: String): Boolean
fun setAttribute(name: String, value: String)

if (attributeExists("username")) {
    setAttribute("username", "unclebob")
}
```

**Why**: When a function both reads and writes, every call site must reason about both effects. CQS gives reads zero side effects (safe to call from any context) and writes zero return (safe to ignore the return value).

**Exception**: Append-and-return-the-result on builders (`builder.append("x").append("y")`) is the fluent-builder idiom — the "return" is the same builder, intentionally chainable. Not a query/command violation, a different pattern.

**Cross-link**: This is the same rule that, at the architectural level, becomes CQRS. See `cqrs-implementation`. At the Spring service layer, see `spring-boot-functions.md`.

---

## Rule 11: Prefer Exceptions to Returning Error Codes

**Source**: Martin Ch. 3 §"Prefer Exceptions to Returning Error Codes"
**Principle**: Returning error codes forces the caller to check after every call and nests the happy path deeper and deeper. Exceptions flatten the happy path.

**Bad** (nested error checks):
```kotlin
if (deletePage(page) == OK) {
    if (registry.deleteReference(page.name) == OK) {
        if (configKeys.deleteKey(page.name.toKey()) == OK) {
            logger.info("page deleted")
        } else {
            logger.error("configKey not deleted")
        }
    } else {
        logger.error("deleteReference failed")
    }
} else {
    logger.error("delete failed")
}
```

**Good** (linear happy path, one error sink):
```kotlin
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

**Why**: Happy path stays readable. Error processing is one *cohesive* block, not interleaved with logic.

**Exception**: At a network/RPC seam, status codes *are* the contract. There, `Result<T>` or a sealed `Either` may be clearer than mapping every status code to an exception type.

---

## Rule 12: Extract Try/Catch Blocks

**Source**: Martin Ch. 3 §"Extract Try/Catch Blocks"
**Principle**: `try` / `catch` blocks confuse the structure of code. Extract their bodies into named functions.

**Bad**:
```kotlin
fun delete(page: Page) {
    try {
        deletePage(page)
        registry.deleteReference(page.name)
        configKeys.deleteKey(page.name.toKey())
    } catch (e: Exception) {
        logger.error(e.message, e)
    }
}
```

**Good**:
```kotlin
fun delete(page: Page) {
    try {
        deletePageAndAllReferences(page)
    } catch (e: Exception) {
        logError(e)
    }
}

private fun deletePageAndAllReferences(page: Page) {
    deletePage(page)
    registry.deleteReference(page.name)
    configKeys.deleteKey(page.name.toKey())
}

private fun logError(e: Exception) {
    logger.error(e.message, e)
}
```

**Why**: `delete` is now *about* error processing — easy to understand and easy to ignore when reading the happy path. `deletePageAndAllReferences` is about the work, with no error concern in sight.

---

## Rule 13: Error Handling Is One Thing

**Source**: Martin Ch. 3 §"Error Handling Is One Thing"
**Principle**: A function that contains `try` should contain *only* `try`. The `try` should be the function's first non-trivial statement, and nothing of substance should follow the `catch` / `finally`.

**Why**: Error handling itself is one thing. Mixing it with business logic violates "do one thing".

**House extension**: In Spring, lift try/catch out of business code entirely with `@ExceptionHandler` / `@ControllerAdvice` and `ProblemDetail`. See `spring-boot-functions.md`.

---

## Rule 14: The Error.java Dependency Magnet

**Source**: Martin Ch. 3 §"Error.java Dependency Magnet"
**Principle**: A single `enum class Error { ... }` that everyone imports is a dependency magnet — adding a code recompiles every caller. Exceptions (derived from a base type) do not couple consumers to additions.

**Bad**:
```kotlin
enum class ErrorCode { OK, INVALID, NO_SUCH, LOCKED, OUT_OF_RESOURCES, ... }

// Every callsite imports ErrorCode and switches over it
```

**Good** (Kotlin):
```kotlin
sealed class DomainError(message: String) : Exception(message)
class InvalidArgument(field: String)       : DomainError("$field is invalid")
class NotFound(entity: String, id: Any)    : DomainError("$entity $id not found")
class Conflict(entity: String, reason: String) : DomainError("$entity: $reason")
```

A new `NotFound` subtype doesn't touch consumers that only handle `DomainError` generically.

**House extension**: For wire-level errors at the API boundary, see `api-design-principles` for `ProblemDetail` / RFC 7807; for module-level errors, sealed `DomainError` hierarchy is the Kotlin-idiomatic shape.

---

## Rule 15: Don't Repeat Yourself (DRY)

**Source**: Martin Ch. 3 §"Don't Repeat Yourself"
**Principle**: Duplication is the root of most evil in software. It multiplies the cost of any change by the number of copies and creates opportunities for divergence.

**Bad** (the same path-building / include-directive code repeated four times for setup / suite-setup / teardown / suite-teardown).

**Good** (one `include(pageName, arg)` function called from four sites).

**Why**: Reduction of duplication is one of the few changes that is almost always positive: less code, fewer bugs, one place to change.

**Caveat**: **Don't over-DRY**. Two pieces of code that *look* similar but represent different domain concepts may diverge later — extracting them coupes the concepts artificially. The rule is "the same *thing* expressed twice is duplication"; the rule is *not* "any two functions with similar shapes are duplication."

**House extension (Kotlin)**: Common Kotlin extraction targets that reduce duplication without coupling concepts:
- Extension function on the receiver type.
- Default argument variant of an existing function.
- Inline higher-order function (`inline fun <T> Iterable<T>.partitionBy(predicate: (T) -> Boolean)`).

---

## Rule 16: Structured Programming — single entry/exit

**Source**: Martin Ch. 3 §"Structured Programming"
**Principle**: Dijkstra's "single return per function, no break/continue" rule was about large functions. In small functions, multiple returns and early `continue`/`break` are often clearer than the contortions needed to satisfy single-exit.

**Bad** (forced single-exit in a 5-line function):
```kotlin
fun findUser(id: UserId): User? {
    var result: User? = null
    if (cache.contains(id)) {
        result = cache.get(id)
    } else if (repo.exists(id)) {
        result = repo.findById(id)
    }
    return result
}
```

**Good** (early returns are fine in a small function):
```kotlin
fun findUser(id: UserId): User? {
    cache.get(id)?.let { return it }
    return repo.findById(id)
}
```

**Why**: Multiple return is readable when the function is small. Forced single-exit invents flag variables to carry early decisions to the bottom.

**Exception**: `goto` — never; Kotlin doesn't have it anyway.

---

## Rule 17: Switch / `when (type)` is a smell — bury it in a factory

**Source**: Martin Ch. 3 §"Switch Statements"
**Principle**: A `switch` (or Kotlin `when (entity.type)`) returning per-type behaviour repeats once for every operation (calculatePay, isPayDay, deliverPay, ...) and changes for every new type. Use polymorphism via a sealed hierarchy; the one tolerated `when` is in the factory.

**Bad**:
```kotlin
enum class EmployeeType { COMMISSIONED, HOURLY, SALARIED }

class Payroll {
    fun calculatePay(e: Employee): Money = when (e.type) {
        COMMISSIONED -> calculateCommissionedPay(e)
        HOURLY       -> calculateHourlyPay(e)
        SALARIED     -> calculateSalariedPay(e)
    }
    fun isPayDay(e: Employee, today: LocalDate): Boolean = when (e.type) { ... }
    fun deliverPay(e: Employee, pay: Money) = when (e.type) { ... }
}
```

**Good** (sealed hierarchy; factory holds the lone `when`):
```kotlin
sealed class Employee {
    abstract fun calculatePay(): Money
    abstract fun isPayDay(today: LocalDate): Boolean
    abstract fun deliverPay(pay: Money)
}

class Commissioned(private val rate: BigDecimal, private val sales: BigDecimal) : Employee() {
    override fun calculatePay(): Money = Money(rate * sales)
    override fun isPayDay(today: LocalDate): Boolean = today.dayOfMonth == 15
    override fun deliverPay(pay: Money) { /* ... */ }
}
class Hourly(...) : Employee() { ... }
class Salaried(...) : Employee() { ... }

class EmployeeFactory {
    fun create(record: EmployeeRecord): Employee = when (record.type) {
        EmployeeType.COMMISSIONED -> Commissioned(record.rate, record.sales)
        EmployeeType.HOURLY       -> Hourly(record.rate, record.hours)
        EmployeeType.SALARIED     -> Salaried(record.salary)
    }
}
```

**Why**: Adding a new employee type now touches one place (the factory and a new subclass), not every operation. SRP and OCP at function scope.

**Exception**: A `when` over a closed set of *values* (`HttpStatus`, `OrderState` transitions) that returns derived data — not behaviour — is fine; that's not polymorphism territory.

**Cross-link**: `solid-principles` covers SRP / OCP at the class level. `gof-patterns` covers which GoF patterns Kotlin's sealed/data classes have already absorbed.

---

## Rule 18: How Do You Write Functions Like This?

**Source**: Martin Ch. 3 §"How Do You Write Functions Like This?"
**Principle**: You don't write clean functions on the first try. You write a clumsy first draft with tests, then refactor: split, rename, eliminate duplication, level the abstractions. Tests are what make the refactor safe.

**Process**:
1. Get the behaviour working — long, messy, but covered by tests.
2. Split out functions whose names you can defend.
3. Rename to descriptive.
4. Push side effects out / up.
5. Convert flag arguments to two functions.
6. Re-run tests at every step.

**Why**: Software writing is like prose writing — first draft is for *getting it down*; cleanup is a separate pass. Trying to write the final form first is what produces overly clever, brittle one-liners.

**Cross-link**: `karpathy-guidelines` §6 (verify before claiming done) and `methodology-verification` enforce the test-first / test-after discipline.

---

## A worked example — the FitNesse `testableHtml` refactor

Martin's original:

```kotlin
// 50+ lines, deep nesting, mixed levels, duplication, flag argument
fun testableHtml(pageData: PageData, includeSuiteSetup: Boolean): String { ... }
```

After applying the rules:

```kotlin
class SetupTeardownIncluder private constructor(private val pageData: PageData) {
    private var isSuite: Boolean = false
    private val testPage: WikiPage = pageData.wikiPage
    private val pageCrawler: PageCrawler = testPage.pageCrawler
    private val newPageContent: StringBuilder = StringBuilder()

    companion object {
        fun render(pageData: PageData, isSuite: Boolean = false): String =
            SetupTeardownIncluder(pageData).render(isSuite)
    }

    private fun render(isSuite: Boolean): String {
        this.isSuite = isSuite
        if (isTestPage()) {
            includeSetupAndTeardownPages()
        }
        return pageData.html
    }

    private fun isTestPage(): Boolean = pageData.hasAttribute("Test")

    private fun includeSetupAndTeardownPages() {
        includeSetupPages()
        includePageContent()
        includeTeardownPages()
        updatePageContent()
    }

    private fun includeSetupPages() {
        if (isSuite) includeSuiteSetupPage()
        includeSetupPage()
    }

    private fun includeSuiteSetupPage() = include(SUITE_SETUP_NAME, "-setup")
    private fun includeSetupPage()      = include("SetUp", "-setup")

    private fun includePageContent() { newPageContent.append(pageData.content) }

    private fun includeTeardownPages() {
        includeTeardownPage()
        if (isSuite) includeSuiteTeardownPage()
    }

    private fun includeTeardownPage()      = include("TearDown", "-teardown")
    private fun includeSuiteTeardownPage() = include(SUITE_TEARDOWN_NAME, "-teardown")

    private fun updatePageContent() { pageData.content = newPageContent.toString() }

    private fun include(pageName: String, arg: String) {
        val inherited = findInheritedPage(pageName) ?: return
        val pathName = getPathNameForPage(inherited)
        buildIncludeDirective(pathName, arg)
    }

    private fun findInheritedPage(name: String): WikiPage? =
        PageCrawlerImpl.getInheritedPage(name, testPage)

    private fun getPathNameForPage(page: WikiPage): String =
        PathParser.render(pageCrawler.getFullPath(page))

    private fun buildIncludeDirective(pathName: String, arg: String) {
        newPageContent.append("\n!include $arg .$pathName\n")
    }
}
```

Every function is short, single-level, and reads like prose. The `render(boolean)` flag is still tolerated *only* because it's the public-API contract — internally there's no flag-driven branching, just a recorded mode used by the `if (isSuite)` guards.

That last point is the lesson: **Clean Code is a destination reached through editing**, not a posture struck in the first draft.

---

## Summary table — rules at a glance

| # | Rule | One-line test |
|---|---|---|
| 1 | Small | Function fits on a screen with room to spare. |
| 2 | Do one thing | Can't extract a sub-function with a non-paraphrase name. |
| 3 | One level of abstraction | No `getHtml()` next to `.append("\n")`. |
| 4 | Stepdown rule | File reads top-down, no upward scrolling to follow calls. |
| 5 | Descriptive names | Sibling functions share vocabulary. |
| 6 | Few arguments | ≤ 2; 3 needs justification; 4+ = missing object. |
| 7 | No flag arguments | No `Boolean` toggling behaviour. |
| 8 | No side effects | Name covers everything the function does. |
| 9 | No output arguments | Mutate `this` or return a new value. |
| 10 | CQS | Function either commands or queries. |
| 11 | Exceptions, not codes | Happy path is linear. |
| 12 | Extract try/catch | `try` body is its own function. |
| 13 | Error handling is one thing | `try` is the first statement; nothing meaningful after `catch`. |
| 14 | No Error enum magnet | Sealed `DomainError` hierarchy. |
| 15 | DRY (with judgement) | Same *thing* twice is duplication; same *shape* twice may not be. |
| 16 | Structured programming, lightly | Multi-return is fine in small functions. |
| 17 | Switch → polymorphism | One `when (type)` allowed, in a factory. |
| 18 | Iterative drafting | First draft is for getting it down; clean it on a pass. |
