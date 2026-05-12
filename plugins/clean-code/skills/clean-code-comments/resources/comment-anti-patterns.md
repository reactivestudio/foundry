# Comment Anti-Patterns

The 18 anti-patterns from Martin Ch. 4 plus house additions specific to Kotlin/Spring/modern tooling. For legitimate categories see `when-comments-earn-their-keep.md`.

> "Inaccurate comments are far worse than no comments at all. They delude and mislead." — Martin

Each anti-pattern has:
- **Signal** — how to recognise it
- **Bad** — example
- **Fix** — what to do instead

---

## B1: Mumbling

**Signal**: A comment that makes sense to the author at the moment of writing but is incomplete or context-dependent for anyone else.

**Bad**:
```kotlin
fun loadProperties() {
    try {
        val stream = FileInputStream("$location/$PROPERTIES_FILE")
        loadedProperties.load(stream)
    } catch (e: IOException) {
        // No properties files means all defaults are loaded
    }
}
```

Who loads the defaults? Where? Was this a reminder to come back later? A justification for the empty catch? Pure mumbling.

**Fix**:
```kotlin
fun loadProperties() {
    val file = File(location, PROPERTIES_FILE)
    if (!file.exists()) return   // defaults already loaded by the bean's @PostConstruct
    file.inputStream().use { loadedProperties.load(it) }
}
```

The code now narrates itself. The empty `catch` is gone, and the "no file → use defaults" semantics are explicit.

---

## B2: Redundant Comments

**Signal**: The comment takes longer to read than the code and conveys less precise information.

**Bad**:
```kotlin
/**
 * Utility method that returns when this.closed is true.
 * Throws an exception if the timeout is reached.
 */
@Synchronized
fun waitForClose(timeoutMillis: Long) {
    if (!closed) {
        (this as Object).wait(timeoutMillis)
        if (!closed) throw IllegalStateException("MockResponseSender could not be closed")
    }
}
```

The signature + body already say all of this — and more accurately (the comment misleadingly suggests the method waits *until* closed, when it actually waits for a fixed timeout).

**Fix**: Delete the KDoc.

---

## B3: Misleading Comments

**Signal**: The comment claims something the code doesn't actually do.

**Bad**:
```kotlin
/** Returns when this.closed is true. */
fun waitForClose(timeoutMillis: Long) { ... }   // actually waits a fixed time, then throws
```

The caller will trust the comment, call this in a loop, and write a bug.

**Fix**: Delete or rewrite to match the actual behaviour:
```kotlin
/** Waits up to [timeoutMillis] for the resource to close; throws if still open. */
fun waitForClose(timeoutMillis: Long) { ... }
```

Better — rename so the method name no longer needs the KDoc:
```kotlin
fun waitForCloseOrThrow(timeoutMillis: Long) { ... }
```

---

## B4: Mandated Comments

**Signal**: Every function / property has KDoc because policy requires it. Most of the KDoc is empty or restates the signature.

**Bad**:
```kotlin
/**
 * @param title The title of the CD
 * @param author The author of the CD
 * @param tracks The number of tracks on the CD
 * @param durationInMinutes The duration of the CD in minutes
 */
fun addCD(title: String, author: String, tracks: Int, durationInMinutes: Int) {
    cdList.add(CD(title, author, tracks, durationInMinutes))
}
```

Every `@param` restates the parameter name. Zero added value.

**Fix**: Drop the policy of mandatory KDoc. Apply the visibility gate from `when-comments-earn-their-keep.md` §8 — KDoc only on `public` API boundaries.

**House extension**: If you control the team's KDoc policy, set it to **"KDoc on public-API only, no mandatory KDoc on internal/private"**. Mandatory KDoc is the most reliable producer of comment debt.

---

## B5: Journal Comments

**Signal**: A list of dated change entries at the top of a file.

**Bad**:
```kotlin
/*
 * Changes (from 11-Oct-2001)
 * --------------------------
 * 11-Oct-2001 : Re-organised and moved to new package (DG)
 * 05-Nov-2001 : Added getDescription(), removed NotableDate (DG)
 * 12-Nov-2001 : IBD requires setDescription() now that NotableDate is gone (DG)
 * 27-Aug-2002 : Fixed bug in addMonths(), thanks to N. Petr (DG)
 * 13-Mar-2003 : Implemented Serializable (DG)
 */
class SerialDate { ... }
```

**Fix**: Delete. Git captures every byte of this history with author + timestamp + diff.

---

## B6: Noise Comments

**Signal**: A comment that restates the obvious or labels the trivially clear.

**Bad**:
```kotlin
/** Default constructor. */
class AnnualDateRule()

/** The day of the month. */
private val dayOfMonth: Int

/**
 * Returns the day of the month.
 * @return the day of the month.
 */
fun getDayOfMonth(): Int = dayOfMonth
```

Readers' eyes glaze; the comments become background static; eventually the code drifts and they're not just useless but wrong.

**Fix**: Delete all of them.

---

## B7: Scary Noise (cut-paste KDoc)

**Signal**: A cluster of nearly-identical KDoc blocks copy-pasted onto fields, with a cut-paste error revealing nobody actually reads them.

**Bad**:
```kotlin
/** The name. */
private val name: String

/** The version. */
private val version: String

/** The licenceName. */
private val licenceName: String

/** The version. */                  // ← cut-paste error: this is "info", not "version"
private val info: String
```

If authors aren't paying attention when writing them, readers won't either.

**Fix**: Delete the whole cluster. The field names already say everything.

---

## B8: Comment Instead of a Function or Variable

**Signal**: A comment explains what the next 1–3 lines do, when a named extraction would say the same thing without commentary.

**Bad**:
```kotlin
// Check to see if the employee is eligible for full benefits
if (employee.flags and HOURLY_FLAG != 0 && employee.age > 65) {
    ...
}
```

**Fix**:
```kotlin
if (employee.isEligibleForFullBenefits()) {
    ...
}

// in Employee:
fun isEligibleForFullBenefits(): Boolean =
    (flags and HOURLY_FLAG != 0) && age > 65
```

Comment vanishes; intent moves into a name the call site can read.

**Another example**:
```kotlin
// does the module from the global list depend on the subsystem we are part of?
if (sModule.dependSubsystems.contains(subSysMod.subSystem)) { ... }
```

**Fix** (named locals):
```kotlin
val moduleDependees = sModule.dependSubsystems
val ourSubSystem = subSysMod.subSystem
if (moduleDependees.contains(ourSubSystem)) { ... }
```

Or, better still, an extension or method:
```kotlin
if (sModule.dependsOn(subSysMod.subSystem)) { ... }
```

This is the most common comment anti-pattern. Most "explanation" comments in code are really missing function names.

---

## B9: Position Markers

**Signal**: ASCII banners marking sections of a file.

**Bad**:
```kotlin
class OrderService {
    //////////// FIELDS ////////////
    private val repo: OrderRepository

    //////////// METHODS ////////////
    fun submit(...) { ... }

    //////////// PRIVATE HELPERS ////////////
    private fun validate(...) { ... }
}
```

**Fix**: Banners signal "this file is too big to navigate without them" — split the file. In Kotlin, prefer:
- Different files for different responsibilities.
- `private` helpers at the bottom of the file (stepdown rule from `clean-code-functions`).
- Top-level private functions in `OrderHelpers.kt` if the helpers are reusable.

**Kotlin-specific gotcha**: IntelliJ supports `// region ... // endregion` folding markers. Same anti-pattern as ASCII banners — they signal the class needs splitting. See `kotlin-spring-comments.md` §"// region folding".

---

## B10: Closing-Brace Comments

**Signal**: Comments on closing braces identifying which block is ending.

**Bad**:
```kotlin
try {
    while (...) {
        ...
    } // while
    println(wordCount)
} // try
catch (e: IOException) {
    ...
} // catch
```

**Fix**: The function is too long. Split it. A function short enough to fit on one screen never needs closing-brace comments.

---

## B11: Attributions and Bylines

**Signal**: `/* Added by Rick */` or `// Refactored by DB on 2003-04-15`.

**Bad**:
```kotlin
/* Added by Rick */
fun unfinishedFeature(): Unit = TODO()
```

**Fix**: Delete. `git blame` shows the author and date for every line, accurately, forever.

---

## B12: Commented-Out Code

**Signal**: Blocks of `//` or `/* */` containing real code, disabled but kept "just in case".

**Bad**:
```kotlin
val response = InputStreamResponse()
response.setBody(formatter.resultStream, formatter.byteCount)
// val resultsStream = formatter.resultStream
// val reader = StreamReader(resultsStream)
// response.setContent(reader.read(formatter.byteCount))
```

Future readers won't have the courage to delete it — they'll assume it's there for a reason.

**Fix**: **Delete.** Git remembers. Promise.

If you want to keep a reference for the next iteration:
- Commit to a branch with a meaningful name.
- Open an issue with a link to the commit.
- Write a test that captures the intent of the old code.

**House rule**: Commented-out code is the single most common comment smell in real codebases. **Always delete on sight.** The bar to keep is "I will uncomment within today's session." Anything older = delete.

---

## B13: HTML in Comments

**Signal**: HTML tags (`<pre>`, `<p>`, `&lt;`, `&gt;`) inside comments meant for human readers.

**Bad** (Java-era Javadoc dragged into Kotlin):
```kotlin
/**
 * Task to run fit tests.
 * <p/>
 * <pre>
 * Usage:
 *   &lt;taskdef name=&quot;execute-tests&quot;
 *     classpathref=&quot;classpath&quot; /&gt;
 * </pre>
 */
class FitnesseTestTask { ... }
```

**Fix**: Kotlin's KDoc uses **Markdown**, not HTML.

```kotlin
/**
 * Task to run fit tests.
 *
 * Usage:
 * ```xml
 * <taskdef name="execute-tests" classpathref="classpath" />
 * ```
 */
class FitnesseTestTask { ... }
```

**House rule**: KDoc supports Markdown code fences, links (`[ClassName]`), and `**bold**`/`*italic*`. Don't HTML-ify it; the rendered Dokka output handles formatting.

---

## B14: Nonlocal Information

**Signal**: A method-level comment talks about a config value, default, or invariant that lives elsewhere in the system.

**Bad**:
```kotlin
/**
 * Port on which the service runs. Defaults to **8082**.
 */
fun setFitnessePort(port: Int) {
    this.port = port
}
```

The default (8082) lives in a config class elsewhere; this comment will be wrong the moment that default changes.

**Fix**: Delete the nonlocal claim. If the default genuinely matters at the call site, make it visible at the source:
```kotlin
@ConfigurationProperties("fitnesse")
data class FitnesseProperties(val port: Int = 8082)
```

Now `8082` lives in exactly one place, and the type system enforces it.

---

## B15: Too Much Information

**Signal**: A comment includes RFC text, a wall of history, or a tutorial on the underlying domain.

**Bad**:
```kotlin
/*
 * RFC 2045 — Multipurpose Internet Mail Extensions (MIME)
 * Part One: Format of Internet Message Bodies
 * Section 6.8. Base64 Content-Transfer-Encoding
 *
 * The encoding process represents 24-bit groups of input bits as
 * output strings of 4 encoded characters. Proceeding from left to right,
 * a 24-bit input group is formed by concatenating 3 8-bit input groups.
 * ... [40 more lines]
 */
fun base64Encode(input: ByteArray): String = ...
```

**Fix**:
```kotlin
/** Base64-encodes the input per RFC 2045 §6.8. */
fun base64Encode(input: ByteArray): String = ...
```

Link to the standard; don't paste it.

---

## B16: Inobvious Connection

**Signal**: A comment is correct, but its relationship to the adjacent code isn't clear.

**Bad**:
```kotlin
/*
 * start with an array that is big enough to hold all the pixels
 * (plus filter bytes), and an extra 200 bytes for header info
 */
pngBytes = ByteArray((width + 1) * height * 3 + 200)
```

What's a filter byte? Is it the `+1`? The `*3`? Why 200? The comment needs its own comment.

**Fix**: Extract the magic numbers into named constants:
```kotlin
private const val BYTES_PER_PIXEL = 3
private const val PNG_HEADER_BYTES = 200
private const val FILTER_BYTE_PER_ROW = 1

pngBytes = ByteArray(
    (width + FILTER_BYTE_PER_ROW) * height * BYTES_PER_PIXEL + PNG_HEADER_BYTES
)
```

The comment becomes unnecessary; the constants self-document.

---

## B17: Function Headers on Short Functions

**Signal**: A small function (3–5 lines) carrying a many-line KDoc.

**Bad**:
```kotlin
/**
 * Determines if a customer is active.
 *
 * @return true if the customer has logged in within the last 30 days
 */
fun isActive(): Boolean = lastLogin > Instant.now().minus(30, DAYS)
```

**Fix**: Either rename to carry the meaning or drop the redundant block:
```kotlin
fun isActive(): Boolean = lastLogin > Instant.now().minus(30, DAYS)

// or — if "active" has a domain meaning the project documents:
fun isActiveByLastLoginPolicy(): Boolean = lastLogin > Instant.now().minus(30, DAYS)
```

---

## B18: KDoc on Nonpublic Code

**Signal**: KDoc blocks on `private` / `internal` classes and functions that no consumer outside the module sees.

**Bad**:
```kotlin
/**
 * Helper to load order rows from the database.
 *
 * @param id the order id
 * @return the order row
 */
private fun loadRow(id: OrderId): OrderRow = ...
```

The signature already says everything; nobody outside this file ever reads the KDoc.

**Fix**: Delete the KDoc. Internal/private code stands or falls on its signature and small size.

**House rule**: Default — **no KDoc on `internal` / `private`**. Exceptions: a complex invariant future maintainers must understand (then write an *intent* comment, see `when-comments-earn-their-keep.md` §3), or a class with deliberately subtle behaviour worth a paragraph.

---

## House additions beyond Martin

### H1: TODO without owner or issue ID

**Signal**: `// TODO fix this later`, `// TODO ?`

**Bad**:
```kotlin
// TODO refactor
fun submitOrder(...) { ... }
```

**Fix**: Add ownership or delete:
```kotlin
// TODO(DEV-1234): refactor for batch processing — target Q3
fun submitOrder(...) { ... }
```

Orphan TODOs that have aged through a release cycle without movement = delete; if it mattered, it would be in the tracker.

---

### H2: KDoc that paraphrases the signature

**Signal**: Every `@param` repeats the parameter name; `@return` repeats the type.

**Bad**:
```kotlin
/**
 * Submits the order.
 *
 * @param order the order to submit
 * @return the submitted order
 * @throws OrderException if the order is invalid
 */
fun submit(order: Order): Order
```

Each line restates the signature. Delete the whole block — the signature is the documentation.

**Fix**: Either drop the KDoc, or rewrite it to carry the *why*:
```kotlin
/**
 * Submits a draft order, locking inventory and producing an [OrderSubmitted] event.
 *
 * Submission is idempotent — submitting an already-submitted order is a no-op.
 *
 * @throws OrderException if the order is in a non-draft state
 */
fun submit(order: Order): Order
```

---

### H3: Comment-translating-a-name

**Signal**: A comment explains what a variable or parameter is named for.

**Bad**:
```kotlin
val r: String = url.lowercase().removeHostAndScheme()  // r is the path portion
```

**Fix**: Rename and delete the comment:
```kotlin
val urlPath: String = url.lowercase().removeHostAndScheme()
```

Cross-references `clean-code-naming` Rule 7 (Avoid Mental Mapping).

---

### H4: Logging as commentary

**Signal**: `log.info("...")` calls placed where a comment would otherwise sit — narrating the *static* code path rather than recording a *runtime* event.

**Bad**:
```kotlin
fun submitOrder(order: Order) {
    log.info("Validating order")            // ← describes the code, not an event
    validate(order)
    log.info("Calculating total")           // ← same
    val total = calculateTotal(order)
    log.info("Persisting")                  // ← same
    save(order)
}
```

These log lines are commentary masquerading as observability — they will flood production logs without adding diagnostic value.

**Fix**: Use logs for **events that matter to operators** (lifecycle transitions, errors, decisions), not for narrating each statement.
```kotlin
fun submitOrder(order: Order) {
    validate(order)
    val total = calculateTotal(order)
    save(order)
    log.info("Order submitted: id={} total={}", order.id, total)
}
```

One log line at the meaningful boundary. The intermediate "comments" disappear because the code reads itself.

---

## Quick sweep — when reviewing a diff

Run through the comments in a PR with these signals:

- [ ] Any commented-out code? → delete
- [ ] Any TODOs without owner / issue ID? → fix or delete
- [ ] Any KDoc that paraphrases the signature? → delete
- [ ] Any "did X on YYYY-MM-DD" journal entries? → delete (Git knows)
- [ ] Any closing-brace `// while` / `// if`? → function too long, split
- [ ] Any `////// SECTION //////` banners or `// region` folding? → file too long, split
- [ ] Any HTML tags in KDoc? → convert to Markdown
- [ ] Any walls of RFC text / tutorials? → link out instead
- [ ] Any comment explaining what a name means? → rename, delete comment
- [ ] Any `log.info` narrating each step? → keep one at boundary, delete rest
- [ ] What remains — does it explain *why*? If not, delete.
