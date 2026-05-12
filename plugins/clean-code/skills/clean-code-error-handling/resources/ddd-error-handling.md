# DDD Error-Handling Patterns

Domain-Driven Design conventions that shape *what* the error names mean, *where* they live in the model, and *how* they cross bounded-context seams. Feathers' Ch. 7 rules tell you to "define exception classes by caller need"; DDD tells you the caller's need *is the domain*, and that the names of failures belong in the ubiquitous language alongside the aggregates that produce them.

> "An exception that doesn't sound like something the business expert would say is leaking the implementation into the contract." — house rule.

## Where do error names live in the model?

In an Onion / Clean Architecture layout (see `architecture-patterns`):

```
domain/
├── order/
│   ├── Order.kt                                ← aggregate; throws domain exceptions
│   ├── OrderId.kt
│   ├── OrderNotSubmittable.kt                  ← domain exception, ubiquitous-language name
│   ├── InsufficientFunds.kt
│   └── SubmitOrderOutcome.kt                   ← sealed outcome (if used)
application/
├── order/
│   ├── SubmitOrder.kt                          ← use case; orchestrates; may translate
│   └── OrderRepository.kt                      ← port; throws *Failure subclass
infrastructure/
├── persistence/
│   ├── JpaOrderRepository.kt                   ← adapter; wraps PersistenceException
│   └── DatabasePortFailure.kt                  ← port-level exception, in this layer
├── payment/
│   ├── StripePaymentAdapter.kt                 ← adapter; wraps StripeException
│   └── PaymentPortFailure.kt
adapters-in/
└── http/
    ├── OrderController.kt                      ← never catches
    └── ApiExceptionHandler.kt                  ← translates everything to ProblemDetail
```

**Domain exceptions** belong in the **domain** package and read like sentences the business expert speaks: `OrderNotSubmittable`, `InsufficientFunds`, `ReservationExpired`. **Infrastructure exceptions** (`DatabasePortFailure`, `PaymentPortFailure`, `EmailDeliveryFailure`) live in the **adapter** layer or in the **port** definition.

A useful test: *if you read the exception's class name out loud, does it sound like the business expert speaking?* If yes, it's a domain exception. If it sounds like "the database is broken" or "the payment gateway timed out", it's an infrastructure exception. The two layers have different audiences (business stakeholder vs ops engineer) and different lifetimes.

---

## 1. Invariant violation vs business-rule violation

Two categories of domain failure, often conflated:

| Category | Definition | Example | Reaction |
|---|---|---|---|
| **Invariant violation** | A statement that must *always* be true about the aggregate, regardless of operations. Reaching this state means the system is broken. | `Money(amount = -1.0)`; an `Order` with zero lines and status SUBMITTED | `IllegalStateException` / `IllegalArgumentException` via `require` / `check`. Reflects "this can never happen". |
| **Business-rule violation** | A statement about what operations are *legal* given current state. Reaching this state means the request is wrong. | Submitting an Order in CANCELLED state; charging an expired card | Domain-named exception (`OrderNotSubmittable`, `CardExpired`). Reflects "the request asks for something the domain forbids". |

```kotlin
class Money(val amount: BigDecimal, val currency: Currency) {
    init {
        require(amount.scale() <= currency.defaultFractionDigits) {
            "amount $amount has more fractional digits than $currency permits"   // INVARIANT
        }
        require(amount >= BigDecimal.ZERO) {
            "amount must be non-negative, was $amount"                            // INVARIANT
        }
    }
}

class Order(
    val id: OrderId,
    private val lines: MutableList<OrderLine>,
    private var status: OrderStatus,
) {
    init {
        require(lines.isNotEmpty()) { "order must have at least one line" }       // INVARIANT
    }

    fun submit() {
        check(status == OrderStatus.DRAFT) {                                       // (could also be a business-rule
            "cannot submit order $id: status is $status, expected DRAFT"           //  exception; see below)
        }
        require(lines.all { it.isAvailable }) {                                    // BUSINESS RULE — better as
            throw SomeItemsUnavailable(lines.filterNot { it.isAvailable }.map { it.sku })
        }
        status = OrderStatus.SUBMITTED
    }
}

class OrderNotSubmittable(val orderId: OrderId, message: String) : RuntimeException(message)
class SomeItemsUnavailable(val items: List<Sku>) : RuntimeException("items unavailable: $items")
```

### When to use which

- **Invariants** are best enforced in **constructors** via `init { require(...) }` or in private factory functions. The aggregate cannot exist in a violating state.
- **Business rules** are enforced in **operation methods** (`submit`, `cancel`, `applyDiscount`) and throw **domain-named exceptions** the caller might *handle* (e.g., the application layer renders a 409 with a specific message).
- `check { ... }` blurs the line — it's stricter than `require` (suggests "state was wrong, not arguments") but still a generic exception type. For things callers might branch on, prefer a named exception.

### Don't use exceptions for normal-flow validation

A user trying to submit an empty cart isn't a *failure* — it's *normal flow*. Validate at the controller boundary (Bean Validation, `@Valid`) or in a sealed `Outcome`:

```kotlin
// Validation at the boundary — empty cart caught before the aggregate exists
data class SubmitCartRequest(
    @field:Size(min = 1, max = 50) val items: List<CartItemRequest>,
)

// Or: sealed outcome — "empty" is part of the result
sealed interface SubmitCartOutcome {
    data class Submitted(val orderId: OrderId) : SubmitCartOutcome
    object Empty : SubmitCartOutcome
    data class OutOfStock(val items: List<Sku>) : SubmitCartOutcome
}
```

Save domain exceptions for *unexpected* domain failures inside the aggregate.

---

## 2. Sealed `Outcome` as part of the ubiquitous language

When the failure modes are *expected, finite, and the caller will branch on them*, the **outcome itself** is part of the domain — model it as a sealed hierarchy:

```kotlin
sealed interface ReserveSeatOutcome {
    data class Reserved(val reservationId: ReservationId, val expiresAt: Instant) : ReserveSeatOutcome
    object AlreadyReservedByCaller : ReserveSeatOutcome
    data class TakenByAnotherPassenger(val by: PassengerId) : ReserveSeatOutcome
    object ShowSoldOut : ReserveSeatOutcome
}

class Show(...) {
    fun reserveSeat(seat: SeatId, passenger: PassengerId, idempotencyKey: IdempotencyKey): ReserveSeatOutcome {
        val existing = reservations.find { it.idempotencyKey == idempotencyKey }
        if (existing != null) return ReserveSeatOutcome.AlreadyReservedByCaller

        val current = reservations.find { it.seatId == seat && it.isActive }
        return when {
            current != null && current.passengerId == passenger -> ReserveSeatOutcome.AlreadyReservedByCaller
            current != null                                     -> ReserveSeatOutcome.TakenByAnotherPassenger(current.passengerId)
            isSoldOut                                            -> ReserveSeatOutcome.ShowSoldOut
            else                                                 -> {
                val reservation = Reservation.create(seat, passenger, idempotencyKey, clock.now() + reservationTtl)
                reservations += reservation
                ReserveSeatOutcome.Reserved(reservation.id, reservation.expiresAt)
            }
        }
    }
}
```

The outcome is named in the **ubiquitous language**: `AlreadyReservedByCaller`, `TakenByAnotherPassenger`, `ShowSoldOut` are things a domain expert recognises. Compare with exception-shaped equivalents:

| Sealed outcome | Exception alternative | Why outcome wins here |
|---|---|---|
| `Reserved(id, expiresAt)` | (void return, throws on failure) | Carries reservation id + expiry without an extra query |
| `AlreadyReservedByCaller` | `IdempotentDuplicateException` | This *isn't an error* — it's an expected success state for retried requests |
| `TakenByAnotherPassenger(by)` | `SeatAlreadyReservedException` | Carries the conflicting passenger id; useful for the UI |
| `ShowSoldOut` | `ShowSoldOutException` | The caller will render the same page state as `TakenByAnother`; sealed `when` lets exhaustive handling at the boundary |

### When NOT to reach for sealed `Outcome`

- **Open-ended failure modes** (infrastructure unavailable, JSON parse error). The variants would multiply; exception with `cause` is honest.
- **Single-failure-mode operations.** `LoadProfile` either finds the profile or it doesn't. `Profile?` + Elvis is enough; a sealed `LoadProfileOutcome { Found, NotFound }` is bureaucracy.
- **Inside transactional methods**, when failure means "roll back". Throwing is what `@Transactional` understands; `Outcome.Failure` requires `setRollbackOnly()`.
- **When the caller will only `.fold` with the same handling for all failures.** That's a single catch block in disguise.

---

## 3. Aggregate-level exception hierarchy

For business-rule violations *within* an aggregate, build a small hierarchy *rooted at the aggregate*. The catch site can be specific or general:

```kotlin
sealed class OrderException(message: String, cause: Throwable? = null) : RuntimeException(message, cause)

class OrderNotFound(id: OrderId) : OrderException("order $id not found")
class OrderNotSubmittable(id: OrderId, reason: String) : OrderException("order $id cannot be submitted: $reason")
class OrderAlreadyCancelled(id: OrderId) : OrderException("order $id is already cancelled")
class CannotCancelShippedOrder(id: OrderId) : OrderException("order $id has shipped; cancellation requires refund flow")

// Catch broad — for one handler in @ControllerAdvice
@ExceptionHandler(OrderException::class)
fun handleOrderException(e: OrderException): ProblemDetail =
    when (e) {
        is OrderNotFound              -> problem(NOT_FOUND, "order-not-found", e.message)
        is OrderNotSubmittable        -> problem(CONFLICT, "order-not-submittable", e.message)
        is OrderAlreadyCancelled      -> problem(CONFLICT, "order-already-cancelled", e.message)
        is CannotCancelShippedOrder   -> problem(UNPROCESSABLE_ENTITY, "cannot-cancel-shipped", e.message)
    }
```

Benefits:
- The catch site has a stable contract ("anything from the Order context") — adding `OrderRefundFailed` requires editing one `when`.
- Sealed root makes the `when` exhaustive — the compiler catches forgotten cases.
- Each subclass carries typed data (the id, the reason) — no string parsing.

**One root per aggregate** is the natural unit. Cross-aggregate compositions (saga orchestrators) get their own root.

---

## 4. ACL at the exception level — bounded-context translation

When two bounded contexts integrate, the **Anti-Corruption Layer** (`ddd-context-mapping`) protects each from the other's vocabulary. Exceptions are part of the vocabulary:

```kotlin
// Customer context (the dependency)
package customer.api
class CustomerNotFoundException(id: String) : RuntimeException("customer $id not found")
class CustomerSuspendedException(id: String, reason: String) : RuntimeException("$id suspended: $reason")

// Order context (the consumer) — its own port + translation
package order.application
class OrderCustomerLookupFailure(val customerId: CustomerId, val reason: Reason, cause: Throwable) : RuntimeException("...") {
    enum class Reason { Unknown, Suspended, Network }
}

interface CustomerPort {
    fun findById(id: CustomerId): CustomerSnapshot                // throws OrderCustomerLookupFailure
}

// Adapter — translates upstream context's exceptions to ours
@Component
class CustomerHttpAdapter(private val client: CustomerApiClient) : CustomerPort {
    override fun findById(id: CustomerId): CustomerSnapshot = try {
        client.getCustomer(id.value).toSnapshot()
    } catch (e: CustomerNotFoundException) {
        throw OrderCustomerLookupFailure(id, Reason.Unknown, e)
    } catch (e: CustomerSuspendedException) {
        throw OrderCustomerLookupFailure(id, Reason.Suspended, e)
    } catch (e: ResourceAccessException) {                              // Spring RestTemplate / WebClient
        throw OrderCustomerLookupFailure(id, Reason.Network, e)
    }
}
```

The Order context never imports `customer.api.*`. Its dependency on the Customer context is a thin port with a port-shaped exception. The day the Customer team renames `CustomerSuspendedException` to `AccountFrozenException`, only the adapter changes.

### Where the translation belongs

- **Adapter package** in the consumer context (Order's `infrastructure/customer/`). Not in the upstream context's library.
- **One translation point per bounded-context boundary.** Don't duplicate the translation across services that share an integration.
- **The port-level exception is part of the Order context's vocabulary** — its name reads as something an Order-context developer recognises, not as a passthrough of the upstream name.

---

## 5. Idempotent outcomes — "already done" is success

For idempotent operations, the second invocation with the same key is *not* an error. The outcome should make this explicit:

```kotlin
sealed interface ChargeOutcome {
    data class Created(val chargeId: ChargeId, val amount: Money) : ChargeOutcome
    data class AlreadyExisted(val chargeId: ChargeId, val originalAmount: Money) : ChargeOutcome
    data class Declined(val reason: DeclineReason) : ChargeOutcome
}

class Charge private constructor(...) {
    companion object {
        fun create(idempotencyKey: IdempotencyKey, amount: Money, card: CardToken, existingByKey: Charge?): ChargeOutcome {
            if (existingByKey != null) {
                return if (existingByKey.amount == amount && existingByKey.card == card)
                    ChargeOutcome.AlreadyExisted(existingByKey.id, existingByKey.amount)
                else
                    throw IdempotencyKeyConflict(idempotencyKey, "amount or card differs from original")
            }
            // ... create new charge ...
        }
    }
}
```

Two distinct cases:

- **Same key, same payload** → `AlreadyExisted` (success).
- **Same key, different payload** → `IdempotencyKeyConflict` (genuine error — usually 409 Conflict; the caller has a bug).

Don't return `Created` for both — that misleads the caller into thinking a new charge happened. Don't throw `AlreadyExisted` — that misleads the caller into thinking it failed.

See `cqrs-implementation` for command-side idempotency patterns and `api-design-principles` §"Idempotency-Key" for the HTTP-level contract.

---

## 6. Domain events and error compensation

When an aggregate raises a domain event, downstream listeners may fail. The publishing transaction has already committed (see `spring-boot-error-handling` §7). The recovery strategies — all variations of Feathers' Special Case Pattern applied to *time*:

### a) Retry — transient failures

The listener throws; an outbox / retry mechanism (Spring Modulith `@ApplicationModuleListener`, RabbitMQ retry interceptor) re-delivers later. Idempotent handlers are mandatory: the second delivery must produce the same effect as the first.

### b) Compensate — when retry won't fix it

A downstream context permanently rejects the event (the customer was deleted between the order being placed and the loyalty-points award). The publishing aggregate must *react* — either issue a refund, cancel the order, or trigger a saga step that compensates.

```kotlin
@Component
class LoyaltyPointsAwardCompensator(private val orderService: OrderService) {
    @ApplicationModuleListener
    fun on(failure: LoyaltyAwardFailed) {
        when (failure.reason) {
            LoyaltyAwardFailed.Reason.CustomerNotFound ->
                orderService.flagForReview(failure.orderId, "loyalty award failed: customer missing")
            LoyaltyAwardFailed.Reason.AccountClosed    ->
                orderService.flagForReview(failure.orderId, "loyalty award failed: account closed")
        }
    }
}
```

The compensator is a *listener for failure events*, structurally identical to a listener for success events. It belongs in the same context as the action it compensates.

### c) Saga — multi-step distributed transaction

For multi-step flows (place order → reserve inventory → charge card → ship), each step has a compensating step that undoes the previous. This is a full architectural concern — see `cqrs-implementation` and `microservices-patterns-deep`.

---

## 7. Specifications and the "no match" case

A Specification (`ddd-tactical-patterns`) is a pure query — it returns true/false for an entity. The "no match" case is **never an error**:

```kotlin
class CreditworthyCustomerSpecification(private val rules: CreditRules) {
    fun isSatisfiedBy(customer: Customer): Boolean = rules.evaluate(customer)
}

// Use — no exception in sight
val eligible = customers.filter(creditworthySpec::isSatisfiedBy)
```

When the application service then *uses* the result and finds zero matches, that's a normal-flow case — handle with an empty result, a sealed `Outcome`, or a domain-named exception if the absence is genuinely an error in that context.

---

## 8. Repository contract — find vs get vs require

A canonical naming convention for the three repository read shapes:

```kotlin
interface OrderRepository {
    fun findById(id: OrderId): Order?                    // returns null when absent — normal flow
    fun getById(id: OrderId): Order = findById(id) ?: throw OrderNotFound(id)   // convenience; throws
}
```

- `findById` returns nullable — the caller decides what absence means.
- `getById` throws — for code paths where absence is genuinely an error in context.

The repository never returns `Optional<Order>` to application/domain code; that's `kotlin-specific-error-handling.md` §2 territory (translate at the JPA boundary).

**Don't have both** with subtly different semantics scattered across repositories — pick one convention per codebase. The two-method `find`/`get` pattern is one good default; another is `findById` only, with the caller always doing `?: throw`. Be consistent.

---

## 9. Error contract as part of the published-language contract

When a bounded context exposes an API (HTTP, gRPC, event stream) for other contexts to consume, **its errors are part of the published language**. Treat them like any other contract:

- **Stable error types and codes.** Renaming `OrderNotSubmittable` to `OrderInvalidState` is a breaking change — consumers may have switch/when over the code.
- **Versioning.** New error types in a minor version are tolerable if consumers handle "unknown error" gracefully; removing an error type is breaking.
- **Documented in the spec.** OpenAPI / Protobuf must describe possible errors per operation. Don't let the error contract drift from the impl.
- **`ProblemDetail.type` URIs are stable identifiers** — `https://errors.example.com/order-not-submittable` is the contract; the human-readable `title` and `detail` can evolve.

See `api-design-principles` for the wire-level shape; this skill is concerned with the *domain* names that fill the contract.

---

## Cross-rule summary — DDD application of Feathers' rules

| Feathers rule | DDD application |
|---|---|
| Use Exceptions, not codes | Domain throws domain exceptions; outcome types when the caller will branch finitely |
| Define exception classes by caller | One root per aggregate; sealed hierarchy for in-aggregate failures |
| Provide context | Exception name + carried data in ubiquitous language; no SDK internals |
| Define the normal flow | Sealed `Outcome` for known finite cases; idempotent "already done" outcomes |
| Don't return null | `findById` returns `T?`; `getById` throws; both belong on the repository |
| Don't pass null | Value objects validate in `init`; aggregates trust their inputs |
| Use unchecked exceptions | All domain exceptions extend `RuntimeException` (Kotlin enforces this implicitly) |
| Define classes around catcher's needs | Distinct exception types only when the catcher will branch on them — otherwise message-only |

## Anti-patterns specific to DDD

- **`*Exception` names that read like database errors** (`OrderRowMissingException`, `JpaConstraintViolationOrder`) inside the domain. The domain doesn't know about rows — wrap and translate at the adapter.
- **Vendor exception types in a port interface** (`fun findById(id): Order throws SQLException`). The port belongs to the *consumer's* vocabulary.
- **One exception class per failure cause within an aggregate** when callers don't branch. `OrderNotSubmittableBecauseEmpty`, `OrderNotSubmittableBecauseAlreadyCancelled`, ... is one class with three messages — unless callers really do `when (e)`.
- **Throwing from a Specification's `isSatisfiedBy`.** Specs are queries — they return true/false. Throwing breaks composition (`spec1.and(spec2)`).
- **Domain events that carry exceptions.** Events describe *what happened in the past*; "the database failed" is not a domain event. Compensation events (`LoyaltyAwardFailed`) carry **business reasons**, not SDK exceptions.
- **Sealed `Outcome` returned from a `@Transactional` method without `setRollbackOnly()`.** A "failure" outcome that doesn't roll back is a data-integrity bug waiting to happen.
- **Re-using infrastructure exceptions inside the domain** because "they already exist". `EntityNotFoundException` (JPA) leaking into a domain method makes the domain depend on Hibernate.
- **A god-class `BusinessException` with an enum of all causes.** This is the classical "Error.java magnet" (`clean-code-functions` §"Error.java"). Each cause becomes a dependency; every code that branches on the enum is coupled to *every* code site that throws it.
- **Domain exceptions thrown for things that should be validated at the boundary.** "Empty cart" is a controller-side `@Size(min=1)`, not a `CartIsEmptyException` from the aggregate.
- **An "internal" domain exception that escapes the use case.** If a private helper throws `InvalidInternalState`, either the use case should catch and translate it, or the helper's contract is wrong.

## Where to go next

- **`ddd-tactical-patterns`** for the broader aggregate / value-object / repository design that this skill assumes.
- **`ddd-context-mapping`** for the bounded-context boundary itself — the ACL pattern that this skill applies at the exception level.
- **`ddd-strategic-design`** for how the ubiquitous language gets built — *that* is the source of good exception names.
- **`cqrs-implementation`** for command-side idempotency, projection error handling, and the `event_publication` outbox pattern.
- **`api-design-principles`** for the published-language contract over the wire — how domain exceptions surface as HTTP / gRPC errors.
