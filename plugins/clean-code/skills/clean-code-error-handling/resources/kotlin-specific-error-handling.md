# Kotlin-Specific Error-Handling Patterns

Kotlin features that change which Clean Code Ch. 7 rules still bite, which become trivial, and which need a new idiom. Each section identifies a Feathers rule, explains what Kotlin does about it, and shows the resulting style.

> "Kotlin's design philosophy is that error handling is a normal part of code, not a bolted-on after-thought. The language makes the common safe path the easy path." — paraphrase of the Kotlin design rationale.

## Quick map — which Kotlin feature attacks which rule

| Feathers rule (Ch. 7) | Kotlin feature | Effect |
|---|---|---|
| §"Use Unchecked Exceptions" | **No checked exceptions** at the language level | Cascade-of-`throws` problem doesn't exist. `@Throws` available for Java interop. |
| §"Don't Return Null" / §"Don't Pass Null" | **Null-safety in the type system** (`T` vs `T?`) | The contract is compile-time-checked. NPE becomes a "you opted in" event. |
| §"Use Exceptions" / §"Normal Flow" | **`Result<T>`** and `runCatching { }` | Bridge between exception and value at a clearly-drawn seam. |
| §"Define Normal Flow" | **Sealed classes / interfaces** for `Outcome` / `Either` | Closed type axes; exhaustive `when` makes branching safe. |
| §"Don't Pass Null" / boundary validation | **`require` / `check` / `error()`** | Standard guard idioms with the correct exception type. |
| §"Write Try First" / resource cleanup | **`use { }`** extension on `AutoCloseable` | try-with-resources without the boilerplate; propagates suppressed exceptions correctly. |
| §"Don't Return Null" — collection case | **`emptyList()` / `emptyMap()` / `emptySet()`** | Built-in zero-allocation empties; no reason to ever return `null` for a collection. |
| §"Provide Context" — null case | **Elvis (`?:`) with throw** | One-liner: `x ?: throw NotFound("...")`. |
| Async / coroutine errors | **Structured concurrency** (`coroutineScope`, `supervisorScope`, `CancellationException` discipline) | Failures propagate up the structured scope; cancellation is a *cooperative* exception you must not swallow. |

---

## 1. No checked exceptions — the cascade is impossible

Java's `throws IOException` viral signature is gone. **Every Kotlin exception is unchecked.** A leaf method that starts throwing a new exception type doesn't force any change to the signatures above it.

```kotlin
// No `throws` clause; all exceptions are runtime.
fun load(path: Path): Document = Files.newInputStream(path).use { stream ->
    parseDocument(stream)         // may throw — caller need not declare
}
```

The price: **you cannot statically see what a method throws.** Mitigations:

- **KDoc the failure modes** on public APIs:
  ```kotlin
  /**
   * Loads and parses a document from disk.
   *
   * @throws DocumentLoadFailure when the file is missing, malformed, or unreadable.
   * @throws AccessDeniedException when the process lacks permission.
   */
  fun load(path: Path): Document
  ```
- **Centralise catching at the edge** (`@RestControllerAdvice`, message-listener error handler, `ApplicationRunner`) so the call sites don't need to know the full set.
- **Use sealed `Outcome` types** when the caller *needs* to branch on a known set of failures — exhaustive `when` over a sealed root gives compile-time guarantees that `throws` used to.

### `@Throws` for Java interop

When a Kotlin function is called from Java, you can re-introduce the checked-exception contract for *that compilation unit*:

```kotlin
@Throws(IOException::class)
fun loadJavaFriendly(path: Path): Document = load(path)
```

A Java caller now sees the checked declaration and must `try/catch` or `throws`. Pure Kotlin callers see no obligation. Use `@Throws` sparingly — it's a *Java compat* shim, not a Kotlin design tool.

---

## 2. Null-safety in the type system — Feathers Rules 7 & 8, free

Kotlin distinguishes **non-nullable `T`** (cannot be null, compile-time-checked) from **nullable `T?`** (may be null; you must handle the absence). This is the language-level enforcement of Feathers' "don't return null / don't pass null".

```kotlin
fun findById(id: UserId): User?       // explicit absence — caller must handle
fun load(id: UserId): User            // non-null — caller can rely on it (or it throws)

// caller — the language forces the check
val user = repository.findById(id)
    ?: throw UserNotFound(id)         // Elvis → throw at the seam

// or — at the seam where absence is normal flow
val user = repository.findById(id) ?: AnonymousUser
```

### The four legitimate "absence" shapes

| Shape | When to use |
|---|---|
| `T` (non-nullable) | The default — most parameters, most returns. |
| `T?` (nullable) | Query where "not found" is a normal answer. *The caller must handle it.* |
| Empty collection (`emptyList<T>()`) | "No matching rows"; `List<T>` is the correct type, never `List<T>?`. |
| Sealed / Special Case (`PerDiemMeals`) | Absence has *its own behaviour*. |

`Optional<T>` from `java.util` is a fifth, used only at the **Spring Data JPA boundary** because the repository returns it:

```kotlin
interface UserRepository : JpaRepository<UserEntity, UUID>

// translate at the boundary
fun findById(id: UserId): User? =
    jpaRepository.findById(id.value).getOrNull()?.toDomain()
```

`Optional<T>` should never appear in application/domain code; convert at the persistence-adapter seam.

### Guards at the platform boundary

Code arriving from Java, JSON deserialisation, JPA result mapping, or `Environment` lookups carries **platform types** (`T!`) — the compiler doesn't know nullability. Guard at the boundary:

```kotlin
@PostMapping("/webhook")
fun handle(@RequestBody body: WebhookPayload?) {
    val payload = requireNotNull(body) { "webhook body was null" }
    // from here on, the type system carries non-null
    service.process(payload)
}

// or, lifted into Jackson configuration — required Kotlin fields fail to deserialise
data class WebhookPayload(
    val event: EventId,        // non-nullable → Jackson rejects missing/null
    val occurredAt: Instant,
    val payload: JsonNode,
)
```

`requireNotNull(x) { "..." }` throws `IllegalArgumentException` if `x` is null and returns the non-null value. It's the standard Kotlin **boundary guard** — pair it with a descriptive lambda message.

### Elvis + throw — the seam idiom

```kotlin
val order = repository.findById(id)
    ?: throw OrderNotFound(id)

val email = user.email
    ?: throw IllegalStateException("user ${user.id} has no email")
```

One-liner; reads naturally; preserves the type-system non-null after the throw.

### Don't reintroduce nulls with `!!`

The bang-bang operator (`x!!`) converts a nullable to non-nullable and throws NPE if it was null. It's *strictly worse* than `requireNotNull(x) { "..." }`:

- No descriptive message.
- The `NullPointerException` says nothing about which operation failed.
- It looks like a casual cast; reviewers miss it.

```kotlin
// ✗ Silent landmine
val pl = body!!.payload

// ✓ Explicit, with context
val pl = requireNotNull(body) { "webhook body was null" }.payload
```

Detekt's `UnsafeCallOnNullableType` lints `!!` on every line. Turn it on.

---

## 3. `require`, `check`, `error()` — the three guard idioms

Kotlin's standard library provides three guards, each with a distinct *exception type* that documents intent:

| Idiom | Throws | Use for |
|---|---|---|
| `require(cond) { msg }` | `IllegalArgumentException` | **Argument** preconditions ("amount must be > 0") |
| `requireNotNull(x) { msg }` | `IllegalArgumentException` | Argument is non-null at the boundary |
| `check(cond) { msg }` | `IllegalStateException` | **Internal state** preconditions ("order is not in DRAFT") |
| `checkNotNull(x) { msg }` | `IllegalStateException` | Internal state value is non-null |
| `error(msg)` | `IllegalStateException` | Unreachable branch ("should never happen") |

```kotlin
class Money(val amount: BigDecimal, val currency: Currency) {
    init {
        require(amount.scale() <= currency.defaultFractionDigits) {
            "amount $amount has more fraction digits than $currency permits"
        }
        require(amount >= BigDecimal.ZERO) { "amount must be non-negative, was $amount" }
    }
}

class Order(...) {
    fun submit() {
        check(status == DRAFT) { "cannot submit order $id: status is $status, expected DRAFT" }
        // ...
    }
}

fun describe(e: Employee): String = when (e) {
    is Hourly       -> "hourly: ${e.rate}/h"
    is Salaried     -> "salaried: ${e.salary}"
    is Commissioned -> "commissioned: ${e.base} + ${e.rate}%"
    // ❗ exhaustive `when` over sealed makes this unnecessary, but if needed:
    // else -> error("unknown employee type: ${e::class}")
}
```

**Why the distinction matters**: catching `IllegalArgumentException` to handle bad caller input is a sensible reaction; catching `IllegalStateException` for the same purpose is wrong (the *system* is misbehaving, not the caller). Using the right idiom communicates this to readers and to global `@ExceptionHandler` handlers that route by type.

---

## 4. `use { }` — try-with-resources, idiomatic

The `use` extension on `AutoCloseable` is Kotlin's try-with-resources. **Always prefer it over manual `try { } finally { x.close() }`.**

```kotlin
// ✗ Manual — easy to forget, easy to swallow secondary exceptions
val stream = FileInputStream(path)
try {
    return decode(stream)
} finally {
    stream.close()                       // may itself throw — what happens to the original exception?
}

// ✓ use — handles suppressed exceptions correctly
return FileInputStream(path).use { stream ->
    decode(stream)
}
```

`use` does three things correctly:
1. Runs `close()` even on exception.
2. If `close()` itself throws, attaches the close exception as **suppressed** to the original (via `addSuppressed`) — no exception is lost.
3. If only `close()` throws, propagates it normally.

Chained resources:

```kotlin
FileInputStream(path).use { input ->
    GZIPInputStream(input).use { gz ->
        BufferedReader(InputStreamReader(gz, UTF_8)).use { reader ->
            reader.readLines()
        }
    }
}
```

For JDBC, JPA EntityManager, S3 streams, Kafka producers, HTTP clients — anything that implements `Closeable` / `AutoCloseable` — `use` is the right tool. If a library type *doesn't* implement `AutoCloseable`, add an inline extension:

```kotlin
inline fun <T : Cluster, R> T.use(block: (T) -> R): R = try { block(this) } finally { close() }
```

---

## 5. `Result<T>` and `runCatching` — exception ↔ value at a seam

Kotlin's `Result<T>` is a sealed value type that holds either a value or a `Throwable`. `runCatching { block }` runs `block` and catches *any* exception except `CancellationException` (see §7), wrapping success/failure in a `Result`.

```kotlin
// ✓ Useful — at a clearly-drawn seam where the value form is genuinely needed
fun loadConfig(path: Path): Result<Config> = runCatching {
    Files.newInputStream(path).use { parseConfig(it) }
}

val config = loadConfig(path).getOrElse {
    logger.warn("falling back to defaults: ${it.message}")
    Config.defaults()
}
```

### When `Result<T>` earns its keep

- A **boundary between two layers** where the caller will *branch* on success/failure (e.g., use case ↔ another use case in a saga).
- A **parser / decoder** that consumes a stream and may produce a half-completed result you want to inspect.
- **Functional pipelines** where exceptions would break the chain: `list.map { fetch(it) }.mapCatching { decode(it) }.fold(...)`.

### When `Result<T>` is over-engineering

- **Inside business logic** that already throws domain exceptions. Wrapping every call in `runCatching` and `getOrThrow`-ing two lines later is noise.
- **At the controller boundary.** Throw domain exceptions; let `@RestControllerAdvice` translate. Don't return `Result<OrderId>` from a controller — the framework already does this job.
- **As a way to "force callers to handle errors".** That's what KDoc and a small exception hierarchy do; `Result` doesn't make callers handle the error, it makes them `.getOrThrow()`.

### Combinators

```kotlin
Result.success(42)
    .map { it * 2 }                                      // Result<Int>
    .mapCatching { riskyTransform(it) }                  // catches throws inside the block
    .recover { e -> -1 }                                 // produces a value from a failure
    .recoverCatching { e -> if (e is Recoverable) 0 else throw e }
    .onSuccess { logger.info("got $it") }
    .onFailure { logger.warn("failed", it) }
    .fold(onSuccess = { it.toString() }, onFailure = { "error: ${it.message}" })
```

**Trap**: `runCatching` swallows `CancellationException`, breaking coroutine cancellation. Inside `suspend` functions, prefer `try/catch` with explicit `CancellationException` rethrow — see §7.

---

## 6. Sealed `Outcome` / `Either` — when failures are part of the type

When the failure modes are **expected, finite, and the caller will branch on them**, a sealed hierarchy is better than `Result<T>` or exceptions:

```kotlin
sealed interface SubmitOrderOutcome {
    data class Submitted(val orderId: OrderId) : SubmitOrderOutcome
    data class OutOfStock(val items: List<Sku>) : SubmitOrderOutcome
    data class DuplicateRequest(val existingOrderId: OrderId) : SubmitOrderOutcome
    object PaymentDeclined : SubmitOrderOutcome
}

class SubmitOrder(...) {
    operator fun invoke(cmd: SubmitOrderCommand): SubmitOrderOutcome {
        // ... pure domain logic, no try/catch ...
    }
}

// caller — exhaustive `when` is a compile-time guarantee
when (val outcome = submitOrder(cmd)) {
    is Submitted        -> /* ... */
    is OutOfStock       -> notify(outcome.items)
    is DuplicateRequest -> /* ... */
    PaymentDeclined     -> /* ... */
}
```

**Advantages over exceptions** for this case:
- Compile-time exhaustiveness — `when` over sealed must handle every case.
- Each case can carry **typed data** (the list of out-of-stock items, the duplicate id).
- No stack-trace allocation cost when failure is part of normal flow.
- The function signature *documents* the outcomes in the return type.

**When to prefer exceptions over sealed `Outcome`**:
- The failure modes are open-ended (third-party SDK can fail in dozens of ways).
- The caller cannot meaningfully recover from any of them (just bubbles up to `@ControllerAdvice`).
- The failure is a *bug* (programming error), not a business outcome.

**Don't propagate `Outcome` across many layers.** It's a seam tool, not a default return shape. If five layers all `.fold` it onward, the noise overwhelms the benefit.

For richer "Either" semantics, Arrow's `Either<L, R>` is widely used; but **don't pull in Arrow just for `Either`** — sealed-class `Outcome` is half a screen of Kotlin and has zero dependency cost.

---

## 7. Coroutines — `CancellationException` discipline

Inside a coroutine, **cancellation is signalled by `CancellationException`**. The coroutine framework relies on this exception propagating *out* of the suspending function so that structured concurrency can unwind cleanly.

```kotlin
// ✗ Silent cancellation swallow — the coroutine refuses to die
suspend fun fetchAll(urls: List<URL>): List<String> = coroutineScope {
    urls.map { url ->
        async {
            try {
                client.fetch(url)
            } catch (e: Exception) {       // ❗ catches CancellationException too
                ""
            }
        }
    }.awaitAll()
}

// ✓ Rethrow cancellation explicitly
suspend fun fetchAll(urls: List<URL>): List<String> = coroutineScope {
    urls.map { url ->
        async {
            try {
                client.fetch(url)
            } catch (e: CancellationException) {
                throw e                     // never swallow
            } catch (e: Exception) {
                ""
            }
        }
    }.awaitAll()
}
```

**Rule**: in suspending code, `catch (e: Exception)` and `catch (e: Throwable)` are footguns. Either catch a specific type, or rethrow `CancellationException`:

```kotlin
try { /* ... */ }
catch (e: CancellationException) { throw e }
catch (e: SomeBusinessException) { /* handle */ }
```

The same caveat applies to `runCatching` — it swallows `CancellationException`. There's a [discussion-stage](https://github.com/Kotlin/kotlinx.coroutines/issues/1814) extension `coRunCatching` in some codebases; or use plain try/catch with explicit rethrow.

### Structured concurrency — failures propagate up the scope

```kotlin
// coroutineScope: any child failure cancels siblings AND the scope itself
suspend fun loadDashboard(userId: UserId): Dashboard = coroutineScope {
    val profile  = async { profileService.load(userId) }
    val orders   = async { orderService.recent(userId) }
    val balance  = async { paymentService.balance(userId) }
    Dashboard(profile.await(), orders.await(), balance.await())
    // If profile fails, orders & balance are cancelled; the exception bubbles up.
}

// supervisorScope: child failures DON'T cancel siblings
suspend fun loadDashboardLenient(userId: UserId): Dashboard = supervisorScope {
    val profile  = async { profileService.load(userId) }
    val orders   = async { runCatching { orderService.recent(userId) }.getOrDefault(emptyList()) }
    val balance  = async { runCatching { paymentService.balance(userId) }.getOrDefault(Money.ZERO) }
    Dashboard(profile.await(), orders.await(), balance.await())
}
```

Pick `coroutineScope` when all children must succeed (the dashboard is meaningless without the profile). Pick `supervisorScope` when partial results are valuable.

---

## 8. Exception types as sealed hierarchies of reasons

When the caller *will* take different action per failure cause, a sealed hierarchy of exceptions is the typed alternative to "if (e.code == X)":

```kotlin
sealed class PaymentFailure(message: String, cause: Throwable? = null) : RuntimeException(message, cause) {
    class CardDeclined(reason: String, cause: Throwable? = null) : PaymentFailure("declined: $reason", cause)
    class Network(cause: Throwable) : PaymentFailure("payment gateway unreachable", cause)
    class Configuration(cause: Throwable) : PaymentFailure("misconfigured", cause)
    object RateLimited : PaymentFailure("rate limited")
}

// catch site can pattern-match
try {
    payment.charge(card, amount)
} catch (e: PaymentFailure) {
    when (e) {
        is PaymentFailure.CardDeclined   -> notifyUser(e.message)
        is PaymentFailure.Network        -> retryLater()
        is PaymentFailure.Configuration  -> alertOncall(e)
        PaymentFailure.RateLimited       -> backoffAndRetry()
    }
}
```

**Advantages**: one catch clause, exhaustive `when` for branching, typed data per cause. **Cost**: exception construction is still allocating; if you're in a hot path, prefer sealed `Outcome` (no Throwable, no stack trace).

---

## 9. Validation idioms — `require` chains, `validate { }`, Arrow `Validated`

For a single guard, `require` is the answer:

```kotlin
data class CreateOrderCommand(val customerId: CustomerId, val items: List<OrderLineDraft>) {
    init {
        require(items.isNotEmpty()) { "order must have at least one item" }
        require(items.all { it.quantity > 0 }) { "all line quantities must be positive" }
    }
}
```

For **collecting multiple validation errors** (e.g., a form with three bad fields), `require` is wrong — it short-circuits on the first failure. Options:

1. **Sealed `ValidationFailure` + accumulation**:
   ```kotlin
   sealed class ValidationError {
       data class TooShort(val field: String, val min: Int) : ValidationError()
       data class Invalid(val field: String, val message: String) : ValidationError()
   }
   fun validate(req: CreateOrderRequest): List<ValidationError> {
       val errors = mutableListOf<ValidationError>()
       if (req.email.isBlank()) errors += ValidationError.TooShort("email", 1)
       if (req.items.isEmpty()) errors += ValidationError.TooShort("items", 1)
       return errors
   }
   ```
2. **Bean Validation** at the controller boundary (`@Valid` + JSR-380 annotations) — Spring framework does the accumulation; see `spring-boot-error-handling.md`.
3. **Arrow `Either.Validated`** — when you're already using Arrow. Don't add Arrow for this alone.

Pick one style for the codebase; mixing them inside one service produces "which kind of validation does this layer do?" reviews.

---

## 10. Java interop — bridges between checked and unchecked

When **calling Java code that throws checked exceptions** from Kotlin, you can catch them by class — the checked obligation doesn't exist in Kotlin, but the exception still propagates at runtime:

```kotlin
// Java method: void load() throws IOException
fun load(): String = try {
    javaLoader.load()                      // no `throws` declaration needed
} catch (e: IOException) {                  // catch by class — works fine
    throw DocumentLoadFailure("loading", e)
}
```

When **Java calls Kotlin** that throws, the Java compiler is unaware of the throws unless `@Throws(...)` is declared:

```kotlin
@Throws(IOException::class)
fun loadForJava(path: Path): Document = load(path)
```

Without `@Throws`, the Java caller has no compile-time obligation; it'll discover the exception only at runtime. For libraries consumed by Java, this matters; for pure Kotlin codebases, skip.

**Trap**: `@Transactional` rollback rules. Spring rolls back by default *only* on `RuntimeException` / `Error`. A Java-thrown checked exception leaking into Kotlin code does **not** trigger rollback — see `spring-boot-error-handling.md` §"The `@Transactional` Kotlin trap".

---

## 11. `Nothing` — the type of "this throws"

`Nothing` is a Kotlin type that has no instances. A function returning `Nothing` either throws or loops forever. This lets the compiler reason about flow:

```kotlin
fun fail(reason: String): Nothing = throw IllegalStateException(reason)

val name: String = user.name ?: fail("user has no name")   // type system knows fail() never returns,
                                                            // so `name` is non-null below this line.
```

`Nothing` is the return type of `throw`, of `error(...)`, of `TODO()`, and of any function whose body is purely a throw. Use it when:

- Building a domain-specific failure helper (`fun orderNotFound(id: OrderId): Nothing = throw OrderNotFound(id)`).
- Smart-cast support across an Elvis: `val x: T = nullable ?: fail("missing")`.

Don't use it to "force" callers to handle errors — that's KDoc + a small exception hierarchy's job.

---

## 12. The `TODO()` function vs `// TODO` comment

Kotlin's standard library has `TODO(reason: String)`, which throws `NotImplementedError`:

```kotlin
fun complicated(input: Foo): Bar = TODO("implement decoding for Foo v3 — JIRA-1234")
```

This is **strictly better than `// TODO`** for unimplemented code paths:
- Calling code that hits it fails immediately, not silently with a wrong default.
- The reason is preserved in the exception message.
- It's discoverable via "find usages of `TODO`" rather than text search.

For "I plan to clean this up later" (where the code *runs* but isn't ideal), the comment form is fine; for "this is not implemented", always `TODO()`.

---

## Cross-rule summary — Kotlin idioms per Feathers rule

| Feathers rule | Kotlin tool |
|---|---|
| Use Exceptions, not codes | Default; `Result<T>` at a clear seam |
| Write try first | `use { }`; `try` as an expression |
| Use unchecked | All exceptions unchecked; `@Throws` only for Java interop |
| Provide context | Elvis + throw with rich message; `MDC` for structured logs |
| Define exception classes by caller | Sealed hierarchy of reasons; one `catch (e: PaymentFailure)` + `when` |
| Define the normal flow | Sealed `Outcome` / Special Case object; nullable + Elvis |
| Don't return null | Non-nullable type by default; `T?` for absence; empty collection for "no rows"; Special Case for behavioural absence |
| Don't pass null | Non-nullable parameter type; `requireNotNull` only at platform boundary |

## Pitfalls — Kotlin-specific things to watch

- **`!!` everywhere.** Detekt rule; lint to zero. The only acceptable `!!` is one a reviewer can defend in code review.
- **`runCatching` inside `suspend` blocks.** Swallows `CancellationException`. Use explicit try/catch.
- **`Result<T>` propagated through five layers.** It's a seam tool, not a return-type default.
- **`@Throws` on internal Kotlin APIs.** Pointless unless Java calls them.
- **`catch (e: Exception)` at random places.** This is the most common smell — it catches `NullPointerException`, `IllegalStateException`, and `CancellationException` indiscriminately. Catch specific types.
- **Lateinit vars for "I'll initialise later".** `lateinit` throws `UninitializedPropertyAccessException` on read-before-init — that's a runtime failure for what should be a compile-time guarantee. Prefer constructor injection or `lazy { }`.
- **`Optional<T>` propagating from JPA into application code.** Translate at the repository boundary.
- **JPA entities with non-nullable fields and no default constructor.** JPA needs a no-arg constructor; Hibernate-Kotlin handles it, but make sure `kotlin-jpa` plugin is in the build to avoid surprises.
