# General Error-Handling Rules

Universal error-handling rules adapted from R. Martin / M. Feathers, *Clean Code* (Ch. 7 "Error Handling"). Rules where Kotlin already changes the game (unchecked-only language, null-safety in the type system, `Result<T>` / `runCatching`, `use { }` for AutoCloseable) are *summarised here* and *deepened in* `kotlin-specific-error-handling.md`. Framework applications (`@RestControllerAdvice`, transactional rollback rules, listener retry/DLQ) live in `spring-boot-error-handling.md`. Domain-level applications (domain exception hierarchy, sealed `Outcome`, invariant vs business-rule) live in `ddd-error-handling.md`.

> "Error handling is just one of those things that we all have to do when we program… Error handling is important, but if it obscures logic, it's wrong." — Feathers
>
> "Clean code is readable, but it must also be robust. These are not conflicting goals." — Feathers

## How to read this file

Each rule has:
- **Source** — the chapter section.
- **Principle** — the one-sentence rule.
- **Bad / Good** — Kotlin snippets adapted from Feathers' Java originals.
- **Why** — the failure mode the rule prevents.
- **Exception** — when the rule legitimately bends.
- **House extension** (where applicable) — Kotlin/Spring-specific add-ons.

Rules appear in the order Feathers presents them — roughly outer-to-inner: how do callers *see* errors, how do you *write* the error-handling block, how do you *classify* errors, how do you *avoid producing them in the first place*.

---

## Rule 1: Use exceptions rather than return codes

**Source**: Ch. 7 §"Use Exceptions Rather Than Return Codes"
**Principle**: When an operation can fail, throw an exception. Don't return a status code, an error flag, or a sentinel value — callers will eventually forget to check, and forgotten checks become silent corruption.

**Bad** (caller must remember to check every return; logic and error handling tangled):
```kotlin
fun sendShutDown() {
    val handle = getHandle(DEV1)
    if (handle != DeviceHandle.INVALID) {
        retrieveDeviceRecord(handle)
        if (record.status != DEVICE_SUSPENDED) {
            pauseDevice(handle)
            clearDeviceWorkQueue(handle)
            closeDevice(handle)
        } else {
            logger.log("Device suspended. Unable to shut down")
        }
    } else {
        logger.log("Invalid handle for: $DEV1")
    }
}
```

**Good** (try defines the failure scope; happy path is linear):
```kotlin
fun sendShutDown() {
    try {
        tryToShutDown()
    } catch (e: DeviceShutDownError) {
        logger.log(e)
    }
}

private fun tryToShutDown() {
    val handle = getHandle(DEV1)           // throws DeviceShutDownError on INVALID
    val record = retrieveDeviceRecord(handle)
    pauseDevice(handle)
    clearDeviceWorkQueue(handle)
    closeDevice(handle)
}

private fun getHandle(id: DeviceId): DeviceHandle =
    rawGetHandle(id).takeIf { it != DeviceHandle.INVALID }
        ?: throw DeviceShutDownError("Invalid handle for: $id")
```

**Why**: Return codes create a single coupling between every caller and the producer — every line of code is now a node in an error-handling graph. Exceptions decouple. The producer says "I failed"; the catcher (often a single one, near the edge) decides what to do. The happy path reads as the sequence of steps it actually is.

**Exception**: Public-API boundaries where the caller is in another language (Java, C ABI, network protocol). HTTP status codes, gRPC statuses, AMQP message rejection are *external* return-code protocols — translate at the boundary, don't carry them inward.

**House extension (Kotlin/Spring)**:
- Inside the JVM, exceptions are the default. Across HTTP, the boundary translates the exception into `ProblemDetail` + status code via `@RestControllerAdvice` (see `spring-boot-error-handling.md`).
- For *expected and finite* failure modes at an internal seam where the caller will branch on the outcome, a sealed `Outcome` / `Result<T, E>` is the better tool — see `kotlin-specific-error-handling.md` §"`Result<T>` and `runCatching`".

---

## Rule 2: Write your try-catch-finally statement first

**Source**: Ch. 7 §"Write Your Try-Catch-Finally Statement First"
**Principle**: When writing code that can throw, *first* write the `try-catch-finally`. The `try` block is a transaction scope — within it, execution can abort at any point and resume in `catch`. Define the scope, then write a test that forces the exception, then fill in the body.

**Bad** (body written first; exception path is an afterthought, often broken):
```kotlin
fun retrieveSection(sectionName: String): List<RecordedGrip> {
    val stream = FileInputStream(sectionName)
    val grips = decode(stream)            // may throw; what happens to the stream?
    stream.close()
    return grips
}
```

**Good** (scope first → test for missing file → body fills in):
```kotlin
// 1. test that drives the design
@Test
fun `retrieveSection throws StorageException on invalid file name`() {
    assertThrows<StorageException> { sectionStore.retrieveSection("invalid - file") }
}

// 2. scope first — body is a stub
fun retrieveSection(sectionName: String): List<RecordedGrip> =
    try {
        FileInputStream(sectionName).use { stream ->
            decode(stream)
        }
    } catch (e: FileNotFoundException) {
        throw StorageException("retrieval error: $sectionName", cause = e)
    }
```

**Why**: Exceptions define behavioural contracts — "if X happens, the caller is left in state Y". Designing that contract *before* writing the happy path forces you to think about resource cleanup, partial-state recovery, and what the caller actually wants when something fails. Bolted-on `catch` after the fact misses cleanup (`finally` / `use`) and rethrows opaquely.

**Exception**: Trivial transformations with no resources and no caller-visible side effect (`fun toUpper(s: String) = s.uppercase()`) don't need a try first — there's nothing to scope.

**House extension (Kotlin)**:
- `use { }` replaces `try { ... } finally { x.close() }` for any `AutoCloseable` — and it propagates exceptions correctly, including suppressed exceptions from `close()` itself. Always prefer `use`.
- `runCatching { ... }.fold(onSuccess, onFailure)` is the "try-catch as an expression" idiom — useful when the result must be a value (e.g., mapping to HTTP). Don't reach for it inside controllers or services unless the *value* really needs to be there; throws + advice is cleaner.

---

## Rule 3: Use unchecked exceptions

**Source**: Ch. 7 §"Use Unchecked Exceptions"
**Principle**: Don't use checked exceptions. Every `throws` clause in a method signature *forces* its callers to either catch or also declare — that cascade breaks encapsulation: a low-level change reshapes signatures three layers up.

**Bad** (Java; checked exception cascades through five layers):
```java
class DocumentLoader {
    public Document load(URL u) throws IOException, ParserConfigurationException, SAXException { ... }
}
class ReportBuilder {
    public Report build(URL u) throws IOException, ParserConfigurationException, SAXException { /* throws cascade */ }
}
class ReportController {
    public ResponseEntity<Report> report(...) throws IOException, ParserConfigurationException, SAXException { /* and again */ }
}
```

**Good** (Kotlin — no checked exceptions; the cascade is impossible):
```kotlin
class DocumentLoader {
    fun load(u: URL): Document = try {
        parse(u)
    } catch (e: IOException)                  { throw DocumentLoadFailure("loading $u", e) }
      catch (e: ParserConfigurationException) { throw DocumentLoadFailure("loading $u", e) }
      catch (e: SAXException)                 { throw DocumentLoadFailure("loading $u", e) }
}

class DocumentLoadFailure(message: String, cause: Throwable) : RuntimeException(message, cause)
```

The hierarchy is **`RuntimeException` + your domain exception**; nothing propagates a checked obligation.

**Why**: Feathers calls this an Open/Closed Principle violation — to add a new failure mode to a leaf method, you must edit every method between it and the catching site. The change radius of a low-level fact is the entire call tree, and *each modified module must be re-built and redeployed*. Languages that don't have checked exceptions (Kotlin, C#, Python, Ruby) produce robust software anyway; the proof of concept has been running for two decades.

**Exception**: When you're writing a Kotlin library consumed from Java and the Java caller *should* be forced to handle a particular failure (a `Closeable.close()` operation that genuinely can fail), use `@Throws(IOException::class)` on the Kotlin side so the Java compiler enforces it.

**House extension (Kotlin/Spring)**:
- Build your exception tree under `RuntimeException` with a small set of well-named subclasses (`OrderNotFound`, `PaymentPortFailure`, `EmailDeliveryError`). Don't extend `Exception` directly — you'd reintroduce checked semantics for Java callers.
- `@Transactional` rolls back by default *only* on `RuntimeException` and `Error`. Throwing a checked exception out of a transactional method does *not* trigger rollback unless you set `rollbackFor`. In Kotlin this almost never bites because all exceptions are unchecked at compile time, but a Java-thrown checked exception leaking into Kotlin code can. See `spring-boot-error-handling.md` §"The `@Transactional` Kotlin trap".

---

## Rule 4: Provide context with exceptions

**Source**: Ch. 7 §"Provide Context with Exceptions"
**Principle**: A stack trace tells you *where* the error occurred; it doesn't tell you *what was being attempted*. Every exception message should carry the operation name, the principal id, and the relevant inputs — enough for a triage engineer to understand the failure from the log alone.

**Bad** (no operation, no principal, no value — the log entry is mute):
```kotlin
if (status != OrderStatus.DRAFT) throw IllegalStateException()
```

**Better but still thin** (says *what* but not *why*):
```kotlin
if (status != OrderStatus.DRAFT) throw IllegalStateException("not draft")
```

**Good** (operation + principal + expected vs actual; cause preserved when wrapping):
```kotlin
if (status != OrderStatus.DRAFT) {
    throw OrderNotSubmittable(
        "Cannot submit order ${order.id}: status is $status, expected DRAFT",
    )
}

// When wrapping, always carry the cause
try { gateway.charge(card, amount) }
catch (e: SdkException) {
    throw PaymentPortFailure(
        "charging $amount on card ${card.last4} via gateway failed: ${e.code}",
        cause = e,
    )
}
```

**Why**: The triage engineer who sees the exception is rarely the same person who wrote the throw. The log line might be all they have — Sentry / Kibana / Splunk drop most context except `message` and `stack`. A message that names the operation ("submitting order"), the principal (`order.id`), and the conflict ("status was X, expected Y") turns a 30-minute investigation into a 30-second one.

**Exception**: Don't include personally identifiable information (PII) or secrets in the message — email addresses, full names, full card numbers, JWT bodies. The message will end up in logs that are far less protected than your database. Use IDs or last-N-digits redactions.

**House extension (Kotlin/Spring)**:
- Pair every thrown exception with **structured logging context**: `MDC.put("orderId", order.id)` before the throw, or use the `kotlin-logging` `logger.atError().addKeyValue("orderId", order.id)`. The exception carries the human-readable story; MDC carries the queryable fields.
- For HTTP responses, the *external* message should be sanitised — include a correlation id (`traceId`) and a generic "We couldn't submit your order, contact support with id …" — but keep the rich internal message in logs. `ProblemDetail.detail` is your public message; the exception's internal `message` is for ops. See `spring-boot-error-handling.md`.

---

## Rule 5: Define exception classes in terms of a caller's needs

**Source**: Ch. 7 §"Define Exception Classes in Terms of a Caller's Needs"
**Principle**: Classify exceptions by **how they will be caught**, not by where they originated. If three different SDK exceptions all end up in the same `catch` block doing the same work, they should be one exception in your code.

**Bad** (one catch block per SDK exception type, doing the same work):
```kotlin
val port = ACMEPort(12)
try {
    port.open()
} catch (e: DeviceResponseException) {
    reportPortError(e); logger.log("Device response exception", e)
} catch (e: ATM1212UnlockedException) {
    reportPortError(e); logger.log("Unlock exception", e)
} catch (e: GMXError) {
    reportPortError(e); logger.log("Device response exception")
}
```

**Good** (wrap the SDK; one exception type, one catch block):
```kotlin
class LocalPort(portNumber: Int) {                  // adapter — your code owns it
    private val inner = ACMEPort(portNumber)

    fun open() = try {
        inner.open()
    } catch (e: DeviceResponseException) { throw PortDeviceFailure("opening port", e) }
      catch (e: ATM1212UnlockedException) { throw PortDeviceFailure("opening port", e) }
      catch (e: GMXError)                 { throw PortDeviceFailure("opening port", e) }
}

class PortDeviceFailure(message: String, cause: Throwable) : RuntimeException(message, cause)

// caller — clean and decoupled from the SDK
val port = LocalPort(12)
try {
    port.open()
} catch (e: PortDeviceFailure) {
    reportError(e); logger.log(e.message, e)
}
```

**Why**: Distinct exception classes are only useful *when the caller branches on them*. If every distinct class leads to the same handling, the distinctions are noise — and they're noise that comes from the *vendor*, not from your domain. Wrapping the third-party API gives you four things at once:
1. One exception type in your code → less duplication.
2. Decoupling from the SDK → swap the vendor without touching callers.
3. Easier testing → mock your port, not the SDK.
4. Domain-shaped error contract → "PortDeviceFailure" reads as a domain concern, not a Stripe / AMQP / S3 implementation detail.

When the caller *will* genuinely take different action per cause, use a **sealed hierarchy of reasons** — not a flat set of classes:
```kotlin
sealed class PaymentFailure(message: String, cause: Throwable? = null) : RuntimeException(message, cause) {
    class CardDeclined(reason: String, cause: Throwable? = null) : PaymentFailure("declined: $reason", cause)
    class Network(cause: Throwable) : PaymentFailure("payment gateway unreachable", cause)
    class Configuration(cause: Throwable) : PaymentFailure("misconfigured", cause)
}
// catch can pattern-match
when (val e = caught) {
    is PaymentFailure.CardDeclined -> notifyUser(e.message)
    is PaymentFailure.Network      -> retryLater()
    is PaymentFailure.Configuration -> alertOncall(e)
}
```

**Exception**: Sometimes the SDK's exceptions *are* your domain — a thin gateway around a small vendor protocol may legitimately let the vendor types through if they're already shaped like your domain. Don't wrap for the sake of wrapping; wrap when the SDK's exception shape doesn't match the caller's branching shape.

**House extension (Kotlin/Spring)**:
- The wrapping adapter belongs in the **infrastructure / adapter package**; the port interface lives in **application** or **domain**. The application service only knows the port's exceptions.
- This is the Anti-Corruption Layer at the exception level — see `ddd-context-mapping`. Pair with `ddd-error-handling.md` for the strategic version.

---

## Rule 6: Define the normal flow (Special Case Pattern)

**Source**: Ch. 7 §"Define the Normal Flow"
**Principle**: Don't use exceptions to drive predictable absences. If "no X exists" is a *normal* state of the domain, model it as a value (sealed type, Special Case object, nullable), not as a thrown exception that the caller must catch to fall back to the default behaviour.

**Bad** (exception drives the "default" branch — happy path forks through a catch):
```kotlin
val total: Money = try {
    expenseReportDao.getMeals(employee.id).total
} catch (e: MealExpensesNotFound) {
    mealPerDiem(employee)
}
```

**Good** (Special Case Pattern — absence is a kind of expense, not an exception):
```kotlin
sealed interface MealExpenses { val total: Money }
data class ReportedMeals(override val total: Money) : MealExpenses
data class PerDiemMeals(override val total: Money) : MealExpenses

class ExpenseReportService(
    private val dao: ExpenseReportDao,
    private val perDiem: PerDiemRates,
) {
    fun mealsFor(employee: Employee, day: LocalDate): MealExpenses =
        dao.findMeals(employee.id, day)
            ?.let { ReportedMeals(it.total) }
            ?: PerDiemMeals(perDiem.lookup(employee.region, day))
}

// caller — one path, no fork
val total = expenseReportService.mealsFor(employee, day).total
```

**Why**: Exceptions are a tool for *abnormal* events. The "abnormal" classifier is what makes them readable: a reader sees `throw` and assumes "something went wrong". If you throw on a routine, expected, in-spec case, every subsequent reader has to learn that "MealExpensesNotFound" is *not* a problem. That tax compounds — every team member, every grep, every code review.

Special Case (Fowler) replaces the absence with a polymorphic stand-in: the caller treats `PerDiemMeals` the same way as `ReportedMeals`, just calls `.total`. No branching, no special handling.

**Exception**: When the "normal" answer is truly **nothing** — the right move is often a nullable / empty collection / `Optional`, not a synthetic Special Case object. `findUserById` returning `User?` is honest; inventing a `NullUser` to "avoid null" is over-engineering. Save Special Case for absences that have **behaviour** (`PerDiemMeals.total` is non-zero; `NullUser` has nothing meaningful to return).

**House extension (Kotlin)**:
- Kotlin's nullable types `T?` are the small, lightweight version of "absence" — pair them with `?:` to express defaults inline. `findUserById(id) ?: throw UserNotFound(id)` or `findUserById(id) ?: AnonymousUser`.
- Sealed hierarchies are the heavier version, used when the absence has its own behaviour or multiple varieties exist. `dao.findMeals(...)?.let { ... } ?: PerDiemMeals(...)`.
- This connects to **CQRS** at the read side: queries return projections; "not found" is a projection state, not an exception. See `cqrs-implementation`.

---

## Rule 7: Don't return null

**Source**: Ch. 7 §"Don't Return Null"
**Principle**: Every `null` return is a contract that demands a null-check at every call site. One missed check produces a `NullPointerException` somewhere downstream — usually in a wrapping method that has no idea the null came from a query three layers below. Prefer empty collections, Special Case objects, or thrown exceptions to "absence" expressed as `null`.

**Bad** (Java-style; cascade of null-checks; one missed → NPE):
```kotlin
fun registerItem(item: Item?) {
    if (item != null) {
        val registry = persistentStore.itemRegistry        // could also be null
        if (registry != null) {
            val existing = registry.getItem(item.id)        // could be null
            if (existing.billingPeriod.hasRetailOwner()) {  // NPE if existing is null
                existing.register(item)
            }
        }
    }
}
```

**Good** (Kotlin null-safety + Special Case + empty collection for "no rows"):
```kotlin
fun registerItem(item: Item) {                          // non-null parameter — caller can't pass null
    val existing = registry.findItem(item.id) ?: return // explicit absence handling
    if (existing.billingPeriod.hasRetailOwner()) {
        existing.register(item)
    }
}

// And on the producer side
fun getEmployees(): List<Employee> = dao.list()         // empty list, never null

// not
fun getEmployees(): List<Employee>? = if (...) null else dao.list()
```

**Why**: Null is the **billion-dollar mistake** (Tony Hoare). A function whose return type is `T?` honestly tells the caller "you must handle absence" — in Kotlin the type system enforces this at the call site. A function whose return type is `T` but actually returns null is dishonest, and one forgotten check is a runtime crash that may not surface for weeks.

Empty collections are the special case for "no rows" — `Collections.emptyList()` is referentially safe, doesn't allocate, and lets the caller iterate without checking. A `null` collection is *always* wrong: the caller has no reason to distinguish "no rows" from "the query never ran".

**Exception**: When interoperating with Java APIs that legitimately return null (`HashMap.get(key)`, `Spring Data findById().orElse(null)`), translate at the boundary — never let the platform-level null leak.

**House extension (Kotlin)**:
- The four legitimate "absence" forms:

  | Form | Use for |
  |---|---|
  | Non-nullable `T` | Default. Most parameters and returns. |
  | Nullable `T?` | Query may legitimately not find a row. *Absence is a normal answer.* |
  | Empty collection | "No matching rows"; never `null` for an empty list. |
  | Sealed / Special Case | Absence has its own *behaviour* (per-diem meals, anonymous user). |

- `Optional<T>` from `java.util` is the **fifth** form, used at the JPA boundary because Spring Data returns it. Convert at the repository: `repository.findById(id).getOrNull()` or `.orElse(null)`. Don't propagate `Optional` into application or domain code.
- `requireNotNull` and `checkNotNull` are the two standard guard idioms at *boundaries* (deserialised JSON, Java interop): `requireNotNull(payload.email) { "payload.email was null" }`.

---

## Rule 8: Don't pass null

**Source**: Ch. 7 §"Don't Pass Null"
**Principle**: Passing `null` as a parameter is worse than returning it — the receiver cannot tell the intent. Was it "no value", "default", "you forgot"? Forbid it at the type system. Don't try to "handle" it with assertions or invalid-argument exceptions; remove the possibility instead.

**Bad** (any of these — they each fail the test "what does the caller actually mean by null?"):
```kotlin
fun xProjection(p1: Point?, p2: Point?): Double {
    if (p1 == null || p2 == null) throw InvalidArgumentException("...")
    return (p2.x - p1.x) * 1.5
}

// or assertions — good documentation, still a runtime bomb
fun xProjection(p1: Point?, p2: Point?): Double {
    assert(p1 != null) { "p1 should not be null" }
    assert(p2 != null) { "p2 should not be null" }
    return (p2!!.x - p1!!.x) * 1.5
}
```

**Good** (the type system carries the rule; null doesn't compile):
```kotlin
fun xProjection(p1: Point, p2: Point): Double = (p2.x - p1.x) * 1.5
```

At the boundary where data arrives from outside (Jackson, JPA result mapping, Java caller), validate once:
```kotlin
// Jackson — use non-nullable Kotlin types and the kotlin-jackson module; missing required fields fail to deserialise
data class WebhookPayload(val event: EventId, val occurredAt: Instant, val payload: JsonNode)

// Defensive guard at the controller seam when the wire format may genuinely omit the field
@PostMapping("/webhook")
fun handle(@RequestBody body: WebhookPayload?) {
    val pl = requireNotNull(body) { "webhook body was null" }
    process(pl)
}
```

**Why**: A `null` parameter is a wordless message. The author writing the function has no way to know what to do with it; the caller has no way to remember when they're allowed to pass it. Languages that let `null` flow freely create maintenance disasters. Kotlin's non-nullable parameter type is a compile-time enforcement of Feathers' rule — *use it*.

Assertions and `InvalidArgumentException` *document* the rule but don't *prevent* the violation; the production system still crashes at runtime when the caller is wrong. The compile-time guard is strictly better.

**Exception**: Java interop. When a Kotlin function is called from Java, the parameter is implicitly `T!` (platform type); a Java caller can pass `null` regardless of your declaration. Annotate parameters that *must* be non-null:
```kotlin
fun xProjection(p1: Point, p2: Point): Double {
    requireNotNull(p1) { "p1 must not be null" }     // for Java callers
    requireNotNull(p2) { "p2 must not be null" }
    return (p2.x - p1.x) * 1.5
}
```
The `requireNotNull` calls are belt-and-braces for Java callers; pure Kotlin callers cannot trigger them.

**House extension (Kotlin/Spring)**:
- **Constructor validation** for value objects: use `init { require(...) }` to forbid invalid values at construction. A `Money(amount = -1.0)` should not exist; a non-empty `Email("...")` should not exist.
- **`@JvmInline value class` for typed primitives**: `value class CustomerId(val value: UUID)` makes "pass a customer id" a compile-time-distinct concept from "pass an order id" — preventing the most common parameter-confusion bug at zero allocation cost.
- **Bean Validation at the controller boundary**: `@Valid @RequestBody CreateOrderRequest` triggers JSR-380 annotations (`@NotNull`, `@NotBlank`, `@Email`). The boundary enforces input shape; inside, Kotlin's type system carries it. See `spring-boot-error-handling.md` §"Validation as boundary discipline".

---

## Cross-rule summary

| Smell | Rule violated | Fix |
|---|---|---|
| Caller checks an integer error code | 1 | Throw an exception, catch at the edge |
| Method body grew around a late-added `try` | 2 | Extract body into a separate function; wrap the call in `try` first |
| `throws IOException` cascading through five Kotlin methods | 3 | (Shouldn't compile in pure Kotlin; if it's there, it's wrapper around a Java callee — catch + wrap inside the wrapper) |
| Exception with no message or `IllegalStateException()` | 4 | Add operation + principal + expected vs actual to the message |
| Three SDK exceptions caught individually doing the same work | 5 | Wrap the SDK; one exception type |
| `catch (NotFound) { return default }` for a routine "absent" case | 6 | Special Case / sealed `Outcome`; pull the default into normal flow |
| `if (x != null)` ladders | 7 | Make the producer return non-null (empty list / nullable / Special Case) |
| `assert(arg != null)` inside the body | 8 | Make the parameter non-nullable; `requireNotNull` only at Java/JSON boundaries |
| `try/catch` swallowing `Exception` with a log line | (multiple) | Either rethrow with context, or have a real Special Case path that handles the absence |
| Single exception class with multiple distinct branching behaviours | 5 | Sealed hierarchy of reasons; the caller pattern-matches |

## Where to go next

- **`kotlin-specific-error-handling.md`** — how Kotlin's features (no checked, null-safety, `Result`, `runCatching`, `use`, sealed types, `@Throws`) implement these rules at the language level.
- **`spring-boot-error-handling.md`** — how Spring centralises catching at the boundary (`@RestControllerAdvice` + `ProblemDetail`), the `@Transactional` rollback rules, validation as boundary, listener retry/DLQ.
- **`ddd-error-handling.md`** — how to design the domain exception hierarchy so its names belong in the ubiquitous language, when to reach for sealed `Outcome` over throwing, and how the ACL translates third-party errors at bounded-context seams.
