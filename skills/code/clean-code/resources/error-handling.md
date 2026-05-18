# Error Handling — throw at the seam, catch at the edge, translate at the boundary

The discipline: a happy path that reads as a straight line, and failure handling that lives in one place — the edge of the program.

## Output template — when reviewing error handling

1. **Layer identification.** Domain / port / inter-module / boundary.
2. **What's the right idiom here?** Apply the 4-rule decision below.
3. **Smells found.** Catch-and-log, null returns, third-party leakage, `try` mid-method.
4. **Action plan.** Translate at the right seam; lift try/catch out of business code; provide operation context.

## The 4-rule decision — what to do at each layer

1. **Inside the domain (aggregates, value objects, domain services): throw unchecked domain exceptions.** Invariants are absolute; exceptions reflect "this isn't allowed". Build a small, caller-shaped hierarchy (`OrderNotSubmittable`, `InsufficientFunds`), not a class per cause.

2. **At a use-case / port seam (application service ↔ adapter): wrap and translate.** Adapters catch SDK exceptions and throw your port-level exception with `cause`. The application service sees one well-named failure type per port (`PaymentPortFailure`), not the SDK zoo.

3. **At a between-modules seam: sealed `Outcome` / `Result<T, E>`** — *only* when the failure modes are expected, finite, and the caller will branch on them (`Submitted | OutOfStock | DuplicateRequest`). Otherwise, stay with exceptions. `Result` types you only ever `.getOrThrow()` add noise without value.

4. **At the HTTP / async-message boundary: translate to the transport's idiom.** `ProblemDetail` (RFC 7807) for HTTP, structured error payload for AMQP, gRPC `Status`. Centralise in `@RestControllerAdvice` / interceptor; never write transport-shaped code inside business logic.

**Don't propagate one layer's idiom into the next.** Controller seeing `Result<Order, PaymentError>` is fine; a JPA repository returning `Result<Order, DatabaseError>` is bureaucracy.

## Write the `try` first — it's a transaction scope

A `try` block defines "from here, execution can abort; the catch/finally must leave the world consistent." Start with the skeleton:

```kotlin
try {
    // (1) write the test that forces this exception first
    doTheThing()                  // (2) then the body
} catch (e: SpecificException) {
    // (3) what does consistency look like here?
}
```

The scope is the *design*, not an afterthought.

## Provide operation context with every exception

```kotlin
// ✗ Stack trace alone — tells you where, not what
throw IllegalStateException()

// ✗ Message restates the type
throw IllegalStateException("Illegal state")

// ✓ Operation + principal + the conflict
throw OrderNotSubmittable(
    "Cannot submit order ${order.id}: status is ${order.status}, expected DRAFT",
    cause = e,
)
```

Rules:
- **Name the operation** ("submitting", "fetching", "applying discount").
- **Name the principal** — aggregate id, user id, request id.
- **Name the conflict** — expected vs actual; the rule that fired.
- **Preserve `cause`** whenever wrapping.
- **No PII in messages** — emails, names, card numbers end up in logs and tickets. Use IDs or redaction.

## Wrap third-party APIs — ACL at the exception level

```kotlin
// Port — what the application service depends on
interface PaymentPort {
    fun charge(card: CardToken, amount: Money): PaymentReceipt
}

class PaymentPortFailure(message: String, cause: Throwable) : RuntimeException(message, cause)

// Adapter — wraps the SDK; one exception type out
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

Application service catches `PaymentPortFailure` — never `StripeException`, never `CardDeclinedException`. Migrate to Adyen → only the adapter changes.

## Special Case Pattern — pull normal flow out of `catch`

If "absent" or "unusual" maps naturally to a value, return that value — don't throw.

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

val meals = expenseReportService.mealsFor(employee, day)
val total = meals.total
```

## Don't return null, don't pass null — and what to do instead

The four legitimate "absence" forms:

| Form | Use for |
|---|---|
| Non-nullable type `T` | The default. Most parameters and returns. |
| Nullable type `T?` | A query may legitimately not find a row. Absence is a normal answer. |
| Empty collection | "No rows matched". Never `null` for an empty list. |
| Sealed `Outcome` / Special Case | When absence has its own behaviour (`PerDiemMeals`). |

Mixing all four under `null` is the smell.

## Smell → fix lookup

| Smell | Fix |
|---|---|
| `catch (Exception e) { logger.error(...) }` swallowing the exception | Either rethrow, or have a Special Case path that genuinely handles the absence. |
| `catch (Throwable t)` | Don't. JVM handles `OutOfMemoryError` / `StackOverflowError`. |
| Empty `catch` | If truly safe to ignore, `catch (_: X) { /* reason */ }`. Otherwise re-throw. |
| Catching `NullPointerException` to "handle" a null | The NPE is a symptom; the bug is the null reaching that line. |
| Rethrowing without `cause` | Always `throw MyException(msg, cause = e)`. |
| One exception class per cause site (`OrderNotSubmittableBecauseAlreadyShipped`) | Same exception, different message — or sealed hierarchy of reasons if caller branches on them. |
| `try/catch` covering most of a method body | Extract the body; the try-catch becomes one line. |
| Mixing exceptions and `Result<T>` in the same layer | Pick one style per layer. |
| `@Transactional` on a method returning `Result<T>` | Spring rolls back on thrown unchecked exceptions, **not** on returned `Result.failure`. Either throw, or `setRollbackOnly()` explicitly. |
| `@ControllerAdvice` returning 500 for everything | Map status code per exception type; let unknowns produce 500 *with a correlation id*. |
| Exception-as-control-flow in hot loops | Throw is ~100× slower than a `when` on sealed types. Model as a value. |
