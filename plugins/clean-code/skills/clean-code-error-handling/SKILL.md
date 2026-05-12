---
name: clean-code-error-handling
description: "Error-handling discipline for Kotlin/Spring code — opinionated rules for exceptions vs return codes, writing the try-catch-finally first as a transaction scope, unchecked-by-default, providing operation context with every exception, defining exception classes by caller need (not source), wrapping third-party APIs into a single domain exception type (ACL), the Special Case Pattern for normal-flow control, and a hard ban on returning or passing null. Adapted from R. Martin / M. Feathers, Clean Code Ch. 7 'Error Handling', filtered for what Kotlin already solves (no checked exceptions at all, null-safety in the type system, `Result<T>` / `runCatching` / sealed `Either`, `require` / `check`, `use { }` for AutoCloseable) and extended with Spring conventions (`@RestControllerAdvice` + `@ExceptionHandler` + `ProblemDetail` RFC 7807, `@Transactional` rollback rules, Bean Validation at the boundary, Resilience4j fallback as Special Case, message-listener retry/DLQ, application-event error compensation). Use when writing a method that can fail and you're deciding between exception, `Result<T>`, or sealed `Outcome`; designing a new exception hierarchy; wrapping a third-party SDK (Feign, RestTemplate, AWS, payment gateway); reviewing a PR with try/catch in business code or null returns; refactoring nested `if (x != null)` ladders into proper null-safety; designing a `@RestControllerAdvice` and the public error contract; placing `@Transactional(rollbackFor = ...)` correctly; choosing between throwing and returning `Optional` / nullable; auditing a service for error-handling consistency before merging; or hardening a listener / consumer against poison messages and infrastructure outages."
risk: safe
source: "Adapted from R. Martin / M. Feathers, Clean Code (2008), ch. 7 'Error Handling', filtered for Kotlin/Spring + house rules"
date_added: "2026-05-12"
---

# Clean Code: Error Handling

> "Error handling is important, but if it obscures logic, it's wrong." — M. Feathers
>
> "Throw at the seam, catch at the edge, translate at the boundary." — house rule.

Most code bases aren't dominated by what they *do* — they're dominated by what they *do when something goes wrong*. Scattered try/catch, null-checks at every level, error codes that callers forget to inspect, third-party exceptions leaking up through five layers — these are the things that make a 200-line method out of 40 lines of actual business logic. Error handling is a separate concern; it should *read* as a separate concern.

This skill is the opinionated catalog of error-handling discipline: Feathers' Ch. 7 rules, adapted for Kotlin's machinery (no checked exceptions, null-safety, `Result<T>`, sealed types) and Spring's idioms (centralised `@ExceptionHandler`, `ProblemDetail`, transactional rollback rules, validation at the boundary, retry/DLQ in listeners). The goal: code where the happy path is one straight line and the failure handling lives in one place — the edge of the program.

## Use this skill when
- Writing a method that can fail and the question is *exception, `Result<T>`, or sealed `Outcome`*.
- Designing a new exception hierarchy or auditing an existing one.
- Wrapping a third-party SDK / Feign client / payment gateway / S3 SDK so its exceptions don't leak into your domain.
- Reviewing a PR with `try/catch` inside business code, or `if (x != null)` ladders.
- Refactoring a method that returns `null` for "not found" and the caller has stopped checking.
- Designing the `@RestControllerAdvice` for a service and the public error contract (HTTP status + `ProblemDetail`).
- Placing `@Transactional(rollbackFor = ...)` — particularly when Kotlin and Java code mix.
- Hardening a message listener against poison messages, retrying without losing data, or wiring DLQ.
- Auditing a module for error-handling consistency before merging a structural change.

## Do not use this skill when
- The error path is dictated by an external contract you don't own (JPA `EntityManager` semantics, JDBC `SQLException`, a vendor SDK callback) — adapt to the contract, don't rewrite it.
- The "error" is a debugger / observability concern — use `debugging-systematic` for finding *why* something fails, this skill is about *how to express* failure.
- The problem is architectural — circuit-breaker policy, service-mesh failure injection, retry budgets across services — use `microservices-patterns-deep` for cross-service resilience.
- You're picking the HTTP error format / status code contract — use `api-design-principles` for that; this skill assumes the contract and shows how to satisfy it.

## Core principles (the eight)

1. **Exceptions over return codes.** Return codes force every caller to remember to check; one forgotten `if` and the system runs on stale state. Exceptions separate happy-path logic from failure handling, and the compiler / runtime guarantees no caller silently ignores them.
2. **Write the `try` first — it's a transaction scope.** A `try` block defines "from here, execution can abort; the `catch`/`finally` must leave the world consistent". When writing failure-capable code, start with the try-catch-finally skeleton, then a test that forces the exception, then the body. The scope is the design, not an afterthought.
3. **Unchecked by default.** Checked exceptions are an Open/Closed Principle violation — a low-level change cascades through every `throws` clause above it. Kotlin doesn't have checked exceptions at all; in Spring code, throw `RuntimeException` subclasses and let `@ExceptionHandler` translate them at the edge.
4. **Provide operation context.** Stack traces tell you *where*, not *what was being attempted*. Every thrown exception should name the operation (`"submitting order ${order.id}"`) and the relevant inputs. The `cause` carries the underlying failure; the message carries the intent.
5. **Define exception classes by caller need, not by source.** If three different SDK exceptions all lead to the same `catch` block (log, retry, give up), they should be one exception in *your* code. Wrap the third-party API and translate its zoo into one (or a few) of your types. This is the Anti-Corruption Layer at the exception level.
6. **Define the normal flow — Special Case Pattern.** Not every "absent" or "unusual" state is exceptional. If "no meal expenses" naturally maps to "per-diem amount", return a `PerDiemMealExpenses` object, not a `MealExpensesNotFound` exception. Exceptions are for *abnormal* events; predictable absences are normal flow expressed via sealed types or special-case objects.
7. **Don't return null.** A nullable return at a domain seam is a contract that says "the caller must handle the absence". In Kotlin the *type system* enforces that — but the culture still matters: prefer `Optional`/nullable for *absence* in queries, an empty collection for "no rows", a Special Case object for "neutral element", an exception for *failure*. Mixing all four under `null` is the smell.
8. **Don't pass null.** Passing `null` as a parameter is worse — the receiver can't tell whether you mean "no value", "default", or "you forgot". Forbid it via the type system (non-nullable parameter types), and at runtime via `require(x != null) { "..." }` for arguments that arrive from Java or deserialisation.

## Quick reference — what to do when

| Situation | Default move | Anti-pattern |
|---|---|---|
| Domain rule violated inside an aggregate | `throw DomainException` (subclass of `RuntimeException`) with operation context | Returning `false` from `submit()` and hoping the caller checks |
| Use-case orchestrator may fail multiple ways and the caller is *another internal layer* | Sealed `Outcome` / `Result<T, E>` at the seam, mapped to HTTP at the edge | Letting raw `RuntimeException` bubble; mixing `Result` and exceptions in the same layer |
| Third-party SDK throws its own exception | Wrap the adapter in `try` → throw your `*PortFailure` with `cause` | Letting `FeignException` / `AmazonClientException` reach your controllers |
| Resource needs closing | Kotlin `use { }` (or Java try-with-resources) | Manual `finally { close() }` boilerplate |
| Invariant guard at function start | `require(arg.isPositive()) { "amount must be > 0, was $arg" }` | Silent fail / returning a sentinel value |
| State precondition (not a caller mistake) | `check(state == Submitted) { "cannot pay an order in $state" }` | Conflating with `require` — wrong exception type |
| HTTP boundary | `@RestControllerAdvice` → `ProblemDetail` (RFC 7807) per exception | `try/catch` in controllers; `return ResponseEntity.status(500)...` ad hoc |
| Predictable "not found" in query | Nullable return / `Optional` / empty collection | Throwing `EntityNotFoundException` from a read path |
| Predictable "absent meals → per-diem" | Special Case object (sealed subtype) | Catching `NotFound` and computing the default in the `catch` |
| Async listener fails | Retry policy + idempotent handler + DLQ on poison | `try { ... } catch (Exception e) { logger.error(...) }` swallowing |

## House defaults — the four-rule decision

1. **Inside the domain (aggregates, value objects, domain services):** **throw** unchecked domain exceptions. Domain code shouldn't carry result-wrapper types — invariants are absolute and exceptions reflect "this isn't allowed". Build a small, *caller-shaped* exception hierarchy (`OrderNotSubmittable`, `InsufficientFunds`), not a class per cause.
2. **At a use-case / port seam (application service ↔ adapter):** **wrap and translate**. Adapters catch SDK / driver exceptions and throw your port-level exception with `cause`. The application service sees one well-named failure type per port (`PaymentPortFailure`, `InventoryPortFailure`), not the SDK zoo.
3. **At a between-modules seam (Modulith application module ↔ application module, or use-case ↔ use-case):** **sealed `Outcome` / `Result<T, E>`** when the failure modes are *expected and finite* and the caller will branch on them (`Submitted | OutOfStock | DuplicateRequest`). Otherwise stay with exceptions — `Result` types that you only ever `.getOrThrow()` add noise without value.
4. **At the HTTP / async-message boundary:** **translate to the transport's idiom** — `ProblemDetail` for HTTP, structured error payload for AMQP, gRPC `Status`. Centralise translation in `@RestControllerAdvice` / `ErrorHandler` / interceptor; never write transport-shaped code inside business logic.

**Don't propagate one layer's idiom into the next.** A controller seeing `Result<Order, PaymentError>` instead of a thrown exception is fine; a JPA repository returning `Result<Order, DatabaseError>` is bureaucracy.

## The unchecked-by-default rule

Kotlin has no checked exceptions. Every `Throwable` is unchecked. This is a feature.

```kotlin
// ✓ Kotlin idiom — no `throws` clause, no compile-time obligation
fun submitOrder(id: OrderId): Order {
    val order = repository.findById(id) ?: throw OrderNotFound(id)
    order.submit()                       // may throw OrderNotSubmittable
    return repository.save(order)
}
```

`throws` propagation chains are gone. The cost: you cannot statically tell whether a method can throw. The mitigation: KDoc the failure modes on public APIs, name exceptions descriptively, and centralise catching at the edge.

When **calling Kotlin code from Java**, mark thrown exceptions with `@Throws` so Java code can compile-time-check them:

```kotlin
@Throws(OrderNotFound::class, OrderNotSubmittable::class)
fun submitOrder(id: OrderId): Order = /* ... */
```

See `resources/kotlin-specific-error-handling.md` for the full set of Kotlin-specific moves.

## Provide context — the message format

```kotlin
// ✗ Stack trace alone — tells you where, not what
throw IllegalStateException()

// ✗ Message restates the type — adds nothing
throw IllegalStateException("Illegal state")

// ✓ Operation + relevant inputs + (where helpful) the offending value
throw OrderNotSubmittable(
    "Cannot submit order ${order.id}: status is ${order.status}, expected DRAFT",
)
```

Rules:
- **Name the operation.** "submitting", "fetching", "applying discount".
- **Name the principal.** Aggregate id, user id, request id.
- **Name the conflict.** Expected vs actual; the rule that fired.
- **Preserve cause** with `cause = e` whenever you wrap.
- **Don't put PII in the message.** Email, full name, card number — these will end up in logs and bug-tracker tickets. Use IDs, or a redaction.

## Wrapping third-party APIs — ACL at the exception level

```kotlin
// Port — what your application service depends on
interface PaymentPort {
    fun charge(card: CardToken, amount: Money): PaymentReceipt
}

class PaymentPortFailure(message: String, cause: Throwable) : RuntimeException(message, cause)

// Adapter — wraps Stripe SDK; one exception type out
@Component
class StripePaymentAdapter(private val stripe: StripeClient) : PaymentPort {
    override fun charge(card: CardToken, amount: Money): PaymentReceipt =
        try {
            val charge = stripe.charges().create(card.value, amount.cents)
            PaymentReceipt(charge.id, charge.amount.toMoney())
        } catch (e: StripeException) {
            throw PaymentPortFailure(
                "charging $amount with $card via Stripe failed: ${e.code}",
                cause = e,
            )
        }
}
```

The application service catches `PaymentPortFailure` — not `StripeException`, not `CardDeclinedException`, not `ApiConnectionException`. The day you migrate to Adyen, only `StripePaymentAdapter` changes.

## Special Case Pattern — pull normal-flow out of `catch`

```kotlin
// ✗ Exception drives the happy path — "no meals" is normal, not a failure
val total = try {
    expenseReportDao.getMeals(employee.id).total
} catch (e: MealExpensesNotFound) {
    mealPerDiem(employee)
}

// ✓ Sealed hierarchy — "absent" is just another case
sealed interface MealExpenses { val total: Money }
data class ReportedMeals(override val total: Money) : MealExpenses
data class PerDiemMeals(override val total: Money) : MealExpenses
class PerDiemMealsPolicy(private val rates: PerDiemRates) {
    fun forDay(employee: Employee, day: LocalDate): PerDiemMeals = PerDiemMeals(rates.lookup(employee.region, day))
}

// caller is now linear
val meals = expenseReportService.mealsFor(employee, day)
val total = meals.total
```

The cost of the exception version: one path through the code reads as a try/catch, another as a method call. The reader has to know that "MealExpensesNotFound" is not actually a *failure*. The Special Case version makes the absence a first-class concept in the domain.

## Don't return / pass null — and what to do instead

```kotlin
// ✗ Java-shaped — returns null, lets the caller forget to check
fun findEmployees(): List<Employee>? = if (...) null else dao.list()

// ✓ Empty collection for "no rows"
fun findEmployees(): List<Employee> = dao.list()         // may be empty; never null

// ✓ Nullable for "absence" in queries — Kotlin's type system enforces the check
fun findById(id: EmployeeId): Employee? = dao.findOrNull(id)

// ✓ Exception for "failure to access the store"
fun findById(id: EmployeeId): Employee =
    dao.findOrNull(id) ?: throw EmployeeNotFound(id)     // caller's choice: throw, or use findById?

// ✗ Null-passing — invites bugs the type system was designed to prevent
fun project(p1: Point?, p2: Point?): Double
calculator.project(null, Point(12, 13))                   // boom

// ✓ Non-nullable parameters — `null` doesn't compile
fun project(p1: Point, p2: Point): Double

// ✓ When forced (Java interop, JSON), guard at the boundary
fun receive(payload: WebhookPayload?) {
    val pl = requireNotNull(payload) { "webhook payload was null" }
    process(pl)
}
```

The four legitimate "absence" forms in Kotlin:

| Form | Use for |
|---|---|
| Non-nullable type `T` | The default. Most parameters and returns. |
| Nullable type `T?` | A query may legitimately not find a row. *Absence is a normal answer.* |
| Empty collection | "No rows matched"; never use `null` for an empty list. |
| Sealed `Outcome` / Special Case | When absence has *its own behaviour* (`PerDiemMeals` above). |

`Optional<T>` from `java.util` is a fifth, used only because Spring Data JPA returns it — convert at the repository boundary: `repository.findById(id).orElse(null)` or `getOrNull()`.

## Selective Reading Rule

| File | When to read |
|---|---|
| `resources/general-error-handling-rules.md` | The eight Feathers/Martin rules in *Source / Principle / Bad / Good / Why / Exception / House extension* form, Kotlin snippets. Read first when starting on this skill. |
| `resources/kotlin-specific-error-handling.md` | Kotlin-only mechanics: no checked exceptions, null-safety, `Result<T>` / `runCatching`, sealed `Either`-style hierarchies, `require` / `check` / `error()`, `use { }` for AutoCloseable, `@Throws` for Java interop, coroutine cancellation discipline, `runBlocking` pitfalls. |
| `resources/spring-boot-error-handling.md` | Spring: `@RestControllerAdvice` + `@ExceptionHandler` + `ProblemDetail` (RFC 7807), `@Transactional` rollback rules (the Kotlin trap), Bean Validation at the boundary (`@Valid`, `MethodArgumentNotValidException`), Resilience4j fallback, `@RabbitListener` / `@KafkaListener` retry & DLQ, `@TransactionalEventListener` & async error compensation, `ApplicationRunner` startup failures. |
| `resources/ddd-error-handling.md` | DDD: domain exception hierarchy in ubiquitous language, invariant vs business-rule violation, sealed `Outcome` as part of the model, idempotent outcomes (`Created` / `AlreadyExisted`), ACL-level exception translation between bounded contexts, where domain events and error compensation meet (saga-style flows). |

## Anti-patterns in error-handling work itself

- **`catch (Exception e) { logger.error(...) }` at every layer.** Logging an exception and continuing is silent corruption — the caller proceeds as if the operation succeeded. Either rethrow, or have a Special Case path that genuinely handles the absence.
- **`catch (Throwable t)`.** Catches `OutOfMemoryError`, `StackOverflowError`, and `ThreadDeath`. The JVM is the one designed to handle those — don't.
- **Empty catch blocks.** "We'll come back to this." We won't. If it's truly safe to ignore, `catch (_: SpecificException) { /* irrelevant: documented reason */ }` with the reason.
- **Catching `NullPointerException` to "handle" a null.** The NPE is a *symptom*; the bug is the null reaching that line. Use the type system or a `requireNotNull` at the boundary.
- **Exception-as-control-flow inside hot loops.** Throw is roughly 100× slower than a `when` branch on a sealed type. If the failure is expected and frequent, model it as a value (sealed `Outcome`) — not because exceptions are "wrong", but because they're the wrong shape for the loop.
- **Rethrowing without preserving cause.** `throw MyException("wrapped")` discards the original stack trace. Always pass `cause = e`.
- **One exception class per cause site.** `OrderNotSubmittableBecauseAlreadyShipped`, `OrderNotSubmittableBecauseEmptyLines`, `OrderNotSubmittableBecausePaymentMissing` is the same exception with a different message. One class, three messages; or — if the caller *will branch on the reason* — a sealed hierarchy of reasons.
- **`try/catch` covering most of a method body.** The `try` should be a small, well-named function called from the catching scope. Extract the body first; the try-catch becomes a one-line shape: `try { doTheThing() } catch (e: ...) { handle(e) }`.
- **Mixing exceptions and `Result<T>` in the same layer.** Picking one style per layer is cheaper than reading two error idioms in one file. `Result` at the seam between two clearly-drawn layers is fine; everywhere is noise.
- **`@Transactional` on a method that returns `Result<T>`.** Spring rolls back on thrown unchecked exceptions, not on a returned `Result.failure`. Either throw inside the transaction, or explicitly mark the transaction for rollback (`TransactionAspectSupport.currentTransactionStatus().setRollbackOnly()`).
- **Catching everything in `@ControllerAdvice` and returning `500 Internal Server Error`.** Reach for the right status code per exception type; let true unknowns produce 500 *with a correlation id* so support can trace them.

## Related skills

| Skill | This not that |
|---|---|
| `clean-code-functions` | "Exceptions over error codes" and "extract try/catch" at the function level; this skill is the full discipline (hierarchy, wrapping, boundaries). |
| `clean-code-objects-and-data` | Special Case Pattern for "no behaviour" cases; this skill is its application to *errors* specifically. |
| `clean-code-naming` | Names of exception classes (no `*ExceptionImpl`, no `*Error` for things that recover); this skill is when/why to introduce one. |
| `api-design-principles` | What the HTTP error contract looks like (`ProblemDetail` shape, status code per case); this skill is how the service produces it. |
| `spring-security-and-auth` | 401 vs 403 mapping, AuthN / AuthZ exceptions; this skill is the general translation pipeline, that skill is the security-specific decisions. |
| `messaging-rabbitmq-spring` | Listener-level retry / DLQ / poison message handling; this skill is the general error model around it. |
| `microservices-patterns-deep` | Circuit-breaker / retry budget across services; this skill is single-service exception handling. |
| `debugging-systematic` | Finding why something failed; this skill is how to *express* failure in code. |
| `ddd-tactical-patterns` | Aggregate invariants throw domain exceptions; this skill is what those exceptions look like. |
| `solid-principles` | The OCP justification for unchecked exceptions and Special Case Pattern; this skill applies them to errors. |
| `karpathy-guidelines` | §2 don't add error handling for impossible cases — over-defensive `catch` blocks for things the type system already rules out. |

## Limitations

- **One project, one style.** A repo that throws exceptions in some services and returns `Result<T>` in others reads as two codebases. Pick a default at the org level and conform; an isolated "improvement" in one service is worse than uniform "wrong-ish" everywhere.
- **Performance hot spots exempt.** In a parser, a serializer, or a tight loop where the failure rate is non-trivial, exceptions are expensive. Model failure as a value there — measure first, comment why, isolate to the smallest function.
- **External contracts win.** JDBC throws `SQLException`; JPA throws `PersistenceException`; Spring Web throws `MethodArgumentNotValidException`. You adapt to those at the boundary — Feathers' rules apply to *your* code, not to framework code you can't change.
- **Domain errors aren't always exceptions.** A `password mismatch` on login is a normal, expected, security-sensitive outcome; modelling it as a `BadCredentialsException` and translating to a 401 in advice is fine, but a sealed `AuthOutcome` is equally fine. Pick once; document the choice.
- **Tests for failure paths are easy to forget.** If a `catch` block exists, a test should force it to execute. An untested `catch` is an untested code path; expect it to be wrong the first time it fires.
