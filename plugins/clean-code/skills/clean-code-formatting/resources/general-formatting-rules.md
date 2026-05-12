# General Formatting Rules

Universal formatting rules adapted from R. Martin's *Clean Code* (Ch. 5 "Formatting"). Rules made obsolete by Kotlin (e.g., Hungarian prefixes, scissors-rule field placement at end of class, manual `private` modifier on every member) are pointed to `kotlin-specific-formatting.md`; framework-specific applications go to `spring-boot-formatting.md`; tooling enforcement goes to `tooling-formatting.md`.

> "When people look under the hood, we want them to be impressed with the neatness, consistency, and attention to detail that they perceive. We want them to perceive that professionals have been at work." — Martin

## How to read this file

Each rule has:
- **Principle** — the one-sentence rule.
- **Bad / Good** — Kotlin snippets adapted from Martin's Java originals.
- **Why** — the failure mode the rule prevents.
- **Exception** — when the rule legitimately bends.
- **Kotlin note** (where applicable) — how Kotlin syntax changes the application.

---

## Rule 1: Vertical Size — Keep Files Small

**Source**: Martin Ch. 5 §"Vertical Formatting"
**Principle**: Aim for ≤ 200 lines per file, with a hard ceiling around 500. Significant systems are built from many small files, not few large ones.

**Why**: A small file is comprehensible at a single scroll. A large file forces the reader to maintain a mental map of where things live — costing eye movement and short-term memory on every read.

**Empirical baseline** (from Ch. 5 Fig. 5-1): mature open-source projects like JUnit and FitNesse averaged 65–200 lines per file. Tomcat and Ant — projects with known maintainability complaints — averaged several hundred and topped multiple thousand. The correlation is not subtle.

**Exception**: A sealed-class hierarchy enumerating 40 domain events, a generated DSL definition, or a long lookup table of constants can legitimately exceed 500 lines. **Test**: ask "does this file have one job?" If yes, length is data; if no, length is a smell.

---

## Rule 2: The Newspaper Metaphor

**Source**: Martin Ch. 5 §"The Newspaper Metaphor"
**Principle**: A source file reads top to bottom like a newspaper article. The class name is the headline. The first few lines give the high-level concept. Detail increases as the reader descends. The reader can stop at any point and have already extracted the gist.

**Bad**: a file where the constructor is at the bottom, helper methods are above the public methods, and the most important method is buried in the middle.

**Good**:
```kotlin
class OrderService(...) {

    // 1. Public API (headline + lead paragraph)
    fun submit(orderId: OrderId): SubmittedOrder { ... }
    fun cancel(orderId: OrderId) { ... }

    // 2. Mid-level orchestrators (body paragraphs)
    private fun chargePaymentAndReserveStock(order: Order) { ... }

    // 3. Low-level mechanics (footnotes)
    private fun computeFee(amount: Money): Money = amount * FEE_RATE
}
```

**Why**: The reader's attention budget is highest in the first 20 lines. Put the most valuable signal there.

---

## Rule 3: Vertical Openness Between Concepts

**Source**: Martin Ch. 5 §"Vertical Openness Between Concepts"
**Principle**: Separate distinct concepts with blank lines. Each blank line is a visual cue: "a new thought starts here."

**Where blank lines belong**:
- After the `package` declaration.
- After the import block.
- Between the class header and the first member.
- Between each member (property/method).
- Between logical sections inside a method (sparingly — see Rule 7).

**Bad**:
```kotlin
package com.example.order
import com.example.shipping.Address
import java.time.Instant
class Order(val id: OrderId, val lines: List<OrderLine>) {
    fun submit(): SubmittedOrder { ... }
    fun cancel() { ... }
}
```

**Good**:
```kotlin
package com.example.order

import com.example.shipping.Address
import java.time.Instant

class Order(
    val id: OrderId,
    val lines: List<OrderLine>,
) {

    fun submit(): SubmittedOrder { ... }

    fun cancel() { ... }
}
```

**Why**: Without blank lines the eye has nothing to lock onto; the structure becomes a wall of text. The blank line is the lowest-cost punctuation in code.

**Exception**: One-line members in a tight cluster (e.g., five short property declarations on a value object) often read better as a tight block — the cluster itself is the concept.

---

## Rule 4: Vertical Density Implies Association

**Source**: Martin Ch. 5 §"Vertical Density"
**Principle**: Lines that are tightly related should appear vertically dense. Anything that breaks them apart (useless comments, blank lines) breaks the association.

**Bad** — KDoc comments on every field break the natural pairing:
```kotlin
class ReporterConfig {
    /**
     * The class name of the reporter listener
     */
    private val className: String

    /**
     * The properties of the reporter listener
     */
    private val properties: MutableList<Property> = mutableListOf()
}
```

**Good** — pair is visually tight; meaning is in the names:
```kotlin
class ReporterConfig {
    private val className: String
    private val properties: MutableList<Property> = mutableListOf()
}
```

**Why**: If the names already say what the comment says, the comment costs you density without adding information. If the name *doesn't* say it, fix the name before adding a comment.

**House extension**: comments worth keeping go *above* the construct they document, separated by a blank line from what's above, **not** in between paired declarations.

---

## Rule 5: Vertical Distance — Related Concepts Stay Close

**Source**: Martin Ch. 5 §"Vertical Distance"
**Principle**: Closely related concepts should be vertically close. The reader should not have to scroll up and down to assemble understanding.

This rule has four sub-cases — Rules 5a–5d.

### Rule 5a: Variable Declarations Near Use

**Bad**:
```kotlin
fun readPreferences() {
    val inputStream: InputStream
    val preferencesFile: File
    val properties: Properties
    // ... 40 lines later ...
    inputStream = FileInputStream(preferencesFile)
}
```

**Good** — Kotlin version, short function so local vars on top is fine:
```kotlin
private fun readPreferences() {
    val inputStream = FileInputStream(preferencesFile())
    val properties = Properties(currentPreferences())
    try {
        properties.load(inputStream)
        setPreferences(properties)
    } finally {
        inputStream.close()
    }
}
```

For longer functions, declare just before first use. In `for` loops, declare the control variable inline:
```kotlin
// ✓ Kotlin makes this trivial
fun countTestCases(): Int = tests.sumOf { it.countTestCases() }
```

### Rule 5b: Instance Variables in One Place

**Bad** — Java-style scattering, with private fields buried mid-class:
```kotlin
class TestSuite : Test {
    fun createTest(theClass: Class<out TestCase>, name: String): Test { ... }

    fun getTestConstructor(theClass: Class<out TestCase>): Constructor<*> { ... }

    private val fName: String           // ← buried — reader has to stumble onto this
    private val fTests: MutableList<Test> = mutableListOf()

    constructor() { ... }
    constructor(theClass: Class<out TestCase>) { ... }
}
```

**Good** — Kotlin idiom: primary constructor or properties at top:
```kotlin
class TestSuite(
    private val name: String,
) : Test {

    private val tests: MutableList<Test> = mutableListOf()

    constructor() : this("")
    constructor(theClass: Class<out TestCase>) : this(theClass.simpleName)

    fun createTest(theClass: Class<out TestCase>, name: String): Test { ... }
    fun getTestConstructor(theClass: Class<out TestCase>): Constructor<*> { ... }
}
```

**Kotlin note**: prefer **primary constructor properties** — that's the canonical location. The C++ "scissors rule" (fields at the bottom) is a legacy convention; Java/Kotlin convention is "fields at top" and the primary constructor formalises it.

### Rule 5c: Dependent Functions — Caller Above Callee

**Source**: Martin Ch. 5 §"Dependent Functions"
**Principle**: If function A calls function B, A should be above B. This creates a downward call flow and lets the reader trust that they can descend through the file.

**Bad** — helpers above public API:
```kotlin
class WikiPageResponder {
    private fun getPageNameOrDefault(...): String { ... }
    private fun loadPage(...) { ... }
    private fun notFoundResponse(...): Response { ... }

    fun makeResponse(context: Context, request: Request): Response {
        val pageName = getPageNameOrDefault(request, "FrontPage")
        loadPage(pageName, context)
        return if (page == null) notFoundResponse(context, request)
               else makePageResponse(context)
    }
}
```

**Good** — stepdown order, public API at top:
```kotlin
class WikiPageResponder {

    fun makeResponse(context: Context, request: Request): Response {
        val pageName = getPageNameOrDefault(request, "FrontPage")
        loadPage(pageName, context)
        return if (page == null) notFoundResponse(context, request)
               else makePageResponse(context)
    }

    private fun getPageNameOrDefault(request: Request, default: String): String { ... }

    private fun loadPage(resource: String, context: Context) { ... }

    private fun notFoundResponse(context: Context, request: Request): Response { ... }

    private fun makePageResponse(context: Context): Response { ... }
}
```

**Why**: The reader descends through the file the way they descend through an outline. They never have to scroll up to find what's been called.

**Note**: Kotlin (like Java) does not require forward declaration, so this is a *convention*, not a compiler constraint. The convention is the value.

### Rule 5d: Conceptual Affinity

**Source**: Martin Ch. 5 §"Conceptual Affinity"
**Principle**: Methods that share a vocabulary or perform variations of the same task should sit adjacent — even if they don't call each other.

**Good**:
```kotlin
object Assert {
    fun assertTrue(message: String?, condition: Boolean) {
        if (!condition) fail(message)
    }

    fun assertTrue(condition: Boolean) = assertTrue(null, condition)

    fun assertFalse(message: String?, condition: Boolean) = assertTrue(message, !condition)

    fun assertFalse(condition: Boolean) = assertFalse(null, condition)
}
```

These four methods would sit together even with zero coupling — the naming family says they belong.

**Why**: A reader scanning for `assertFalse` finds it instantly if `assertTrue` is right above. Distance between conceptual cousins forces search.

---

## Rule 6: Vertical Ordering — High-Level First

**Source**: Martin Ch. 5 §"Vertical Ordering"
**Principle**: Function calls should point downward. Most important / most abstract first; least important / most mechanical last.

**Why**: Newspapers, Wikipedia articles, technical specs — all readable hierarchies put the abstract summary first and the details last. Code is a hierarchy; honour it.

**Test**: a fresh reader should grasp the file's purpose from the first non-import 20 lines, without scrolling.

---

## Rule 7: Horizontal Line Width

**Source**: Martin Ch. 5 §"Horizontal Formatting"
**Principle**: Keep lines ≤ 120 characters. Martin's preference was 120; the Kotlin official style guide says 100; both are defensible.

**Why**:
- Long lines break side-by-side diff viewing and code review.
- The eye scans short lines faster.
- Empirical data from Ch. 5 Fig. 5-2: programmers overwhelmingly write lines under 80; long lines are rare on purpose.

**How to break a long line**:
1. Extract a local with a meaningful name.
2. Break on argument boundaries (with trailing comma).
3. Break on operators (operator goes at the start of the new line — keeps the operator visible in the indent column).

```kotlin
// ✗ One long line
fun createOrder(customer: CustomerId, lines: List<OrderLine>, shipping: Address, billing: Address, placedAt: Instant): Order { ... }

// ✓ Trailing-comma multi-line
fun createOrder(
    customer: CustomerId,
    lines: List<OrderLine>,
    shipping: Address,
    billing: Address,
    placedAt: Instant,
): Order { ... }
```

**Exception**: SQL string literals, regex patterns, and URL templates often need to live unbroken — splitting them harms readability more than the width does. Keep them on one line and accept the overflow.

---

## Rule 8: Horizontal Openness and Density

**Source**: Martin Ch. 5 §"Horizontal Openness and Density"
**Principle**: Whitespace **associates** what belongs together and **disassociates** what doesn't. Use it to reflect precedence and grouping.

```kotlin
// ✓ Whitespace around assignment + low-precedence ops; tight on high-precedence
fun measureLine(line: String) {
    lineCount++
    val lineSize = line.length          // ← space around =
    totalChars += lineSize              // ← space around +=
    lineWidthHistogram.addLine(lineSize, lineCount)   // ← no space after method name; space after comma
    recordWidestLine(lineSize)
}

// ✓ Precedence visible via density
val determinant = b * b - 4 * a * c                   // ← unfortunately most formatters force `b * b`; live with it
val root1 = (-b + sqrt(determinant)) / (2 * a)
```

**Why**: Operator precedence is encoded in the language but invisible at a glance. Whitespace makes it visible.

**Caveat**: Kotlin formatters (ktlint, ktfmt) normalise spacing aggressively and *don't* preserve precedence-based density. Don't fight the tool — let it normalise, and rely on operator parentheses for clarity instead.

---

## Rule 9: No Horizontal Column Alignment

**Source**: Martin Ch. 5 §"Horizontal Alignment"
**Principle**: Don't manually align fields, types, or values in columns. Alignment emphasises the wrong axis and is destroyed by every reformat.

**Bad**:
```kotlin
class FitNesseExpediter(...) {
    private val socket                   : Socket
    private val input                    : InputStream
    private val output                   : OutputStream
    private val request                  : Request
    private val response                 : Response
    private val context                  : FitNesseContext
    protected var requestParsingTimeLimit: Long
    private var requestProgress          : Long
    private var requestParsingDeadline   : Long
    private var hasError                 : Boolean
}
```

**Good**:
```kotlin
class FitNesseExpediter(...) {
    private val socket: Socket
    private val input: InputStream
    private val output: OutputStream
    private val request: Request
    private val response: Response
    private val context: FitNesseContext
    protected var requestParsingTimeLimit: Long
    private var requestProgress: Long
    private var requestParsingDeadline: Long
    private var hasError: Boolean
}
```

**Why**:
1. Aligned columns lead the eye down the names *without crossing the types* — the type information is decoupled from the name.
2. Auto-formatters destroy the alignment, so it doesn't survive a single CI run.
3. If you needed alignment to read the list, the list is too long — that's the actual smell. Note how the unaligned version makes the length more obvious: this class is doing too much.

**Same rule applies to**:
- `when` arrows (`→`).
- `val` types and initialisers.
- Comments at end of declarations.

---

## Rule 10: Indentation

**Source**: Martin Ch. 5 §"Indentation"
**Principle**: Indent to show scope hierarchy. Class members one level in, method bodies one further, blocks within blocks one further. Always.

**Why**: Indentation is the most important visual cue for control flow. Programmers don't read code linearly — they scan the left margin to find structure, then drill into specific blocks. Strip indentation and code becomes unreadable.

**Demonstration** — same code, two layouts:

```kotlin
class FitNesseServer(private val context: FitNesseContext): SocketServer { fun serve(s: Socket) { serve(s, 10000) } fun serve(s: Socket, requestTimeout: Long) { try { val sender = FitNesseExpediter(s, context); sender.requestParsingTimeLimit = requestTimeout; sender.start() } catch (e: Exception) { e.printStackTrace() } } }
```

```kotlin
class FitNesseServer(
    private val context: FitNesseContext,
) : SocketServer {

    fun serve(s: Socket) = serve(s, 10000)

    fun serve(s: Socket, requestTimeout: Long) {
        try {
            val sender = FitNesseExpediter(s, context)
            sender.requestParsingTimeLimit = requestTimeout
            sender.start()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
```

The first form is the same code. Nobody reads it.

### Rule 10a: Don't Collapse Short Scopes

**Source**: Martin Ch. 5 §"Breaking Indentation"
**Principle**: Even short `if` / `while` / function bodies expand to indented blocks. Don't write `if (cond) doX()` on one line.

**Bad**:
```kotlin
class CommentWidget(parent: ParentWidget, text: String) : TextWidget(parent, text) {
    companion object { const val REGEXP = "..." }
    override fun render() = ""
}
```

**Good**:
```kotlin
class CommentWidget(parent: ParentWidget, text: String) : TextWidget(parent, text) {

    companion object {
        const val REGEXP = "..."
    }

    override fun render(): String = ""
}
```

**Kotlin exception**: A **single-expression function** (`fun x() = expr`) is not collapsed indentation — it's a different syntactic form, and idiomatic. The rule applies to *block bodies* squashed onto one line, not to expression bodies.

---

## Rule 11: Dummy Scopes

**Source**: Martin Ch. 5 §"Dummy Scopes"
**Principle**: Avoid `while(...);` and similar empty-body loops. If you must use one, the body and its `{}` go on a separate, indented line.

**Bad**:
```kotlin
while (input.read(buf, 0, readBufferSize) != -1);
```

The trailing semicolon hides on the same line — easy to miss, easy to introduce a bug by adding a statement after.

**Good** — in Kotlin, `while` doesn't have an empty body shortcut; rewrite as:
```kotlin
do {
    val read = input.read(buf, 0, readBufferSize)
} while (read != -1)
```

Or, better: use a higher-level idiom (`forEachLine`, `useLines`, `bufferedReader().lineSequence()`).

**Why**: Empty loops are an anti-pattern. Either there's a side effect inside `read()` (then make it explicit) or the iteration is doing nothing (then remove it). Either way the construct is suspicious.

---

## Rule 12: Team Rules > Personal Preferences

**Source**: Martin Ch. 5 §"Team Rules"
**Principle**: A team agrees on a single formatting style and applies it consistently. Personal preferences yield to the team standard.

**House extension**: Encode the team rules in a *file*, not a wiki page:
- `.editorconfig` for cross-IDE/cross-tool baseline.
- ktlint or ktfmt config for Kotlin specifics.
- Spotless Gradle task to apply formatting.
- Pre-commit hook to catch local drift.
- CI gate (`./gradlew spotlessCheck`) that fails the build on violation.

**Why**: Wiki rules drift; file rules don't. The first PR after a "we decided X" wiki note will violate it. The first PR with a CI gate either passes or fails on the spot.

---

## Cross-references

| Need | File |
|---|---|
| Kotlin-specific layout (expression bodies, trailing commas, `when`, scope fns, multiline strings) | `kotlin-specific-formatting.md` |
| Spring application layout (controllers, `application.yml`, JPA entities, test layout) | `spring-boot-formatting.md` |
| Toolchain (ktlint vs. ktfmt, Spotless, EditorConfig, pre-commit, CI gate) | `tooling-formatting.md` |
| Function size / responsibility | sibling skill `clean-code-functions` |
| Class naming / member naming | sibling skill `clean-code-naming` |
