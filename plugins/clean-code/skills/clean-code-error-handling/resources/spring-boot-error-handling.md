# Spring Boot Error-Handling Patterns

Spring/Spring Boot conventions that implement Feathers' Ch. 7 rules at the framework level — centralised catching at the HTTP boundary, transactional rollback semantics, validation as boundary discipline, and the failure-handling shape of async listeners. These are the *applications* of the rules in `general-error-handling-rules.md`; the language-level mechanics are in `kotlin-specific-error-handling.md`.

> "By the time an exception reaches a controller method, the design is already wrong. Catch at the edge — `@ControllerAdvice` is the edge." — house rule.

## Overview — where exceptions go in a Spring service

```
[ HTTP request ]
       ↓
Controller method                  ← never wraps in try/catch
       ↓
Application service                ← @Transactional boundary; throws domain exceptions
       ↓
Domain                             ← throws domain exceptions; rich messages
       ↓
Adapter / port impl                ← wraps SDK exceptions → port-level exception
       ↓
Third-party SDK / driver           ← throws its own zoo of exceptions
       ↑
       ↓ (on exception, unwind)
[ @RestControllerAdvice catches at the edge ]
       ↓
Produces ProblemDetail (RFC 7807) + correct HTTP status
```

The rule: **business code throws; the edge translates.** Inside controllers, services, and domain classes, no try/catch — except adapter wrappers (Anti-Corruption Layer at the exception level) and `@TransactionalEventListener` handlers that need explicit compensation.

---

## 1. `@RestControllerAdvice` + `@ExceptionHandler` + `ProblemDetail`

The Spring 6 / Boot 3 idiom is **`ProblemDetail`** (RFC 7807) as the standard error response shape, returned from `@ExceptionHandler` methods on a `@RestControllerAdvice` class.

```kotlin
@RestControllerAdvice
class ApiExceptionHandler {

    private val logger = KotlinLogging.logger {}

    @ExceptionHandler(OrderNotFound::class)
    fun handleOrderNotFound(e: OrderNotFound): ProblemDetail =
        problem(HttpStatus.NOT_FOUND, "order-not-found", e.message ?: "order not found")

    @ExceptionHandler(OrderNotSubmittable::class)
    fun handleNotSubmittable(e: OrderNotSubmittable): ProblemDetail =
        problem(HttpStatus.CONFLICT, "order-not-submittable", e.message ?: "order not submittable")

    @ExceptionHandler(PaymentPortFailure::class)
    fun handlePaymentFailure(e: PaymentPortFailure): ProblemDetail {
        logger.warn(e) { "payment port failure" }
        return problem(
            HttpStatus.BAD_GATEWAY,
            "payment-unavailable",
            "We can't process your payment right now. Please try again shortly.",
        )
    }

    @ExceptionHandler(MethodArgumentNotValidException::class)
    fun handleValidation(e: MethodArgumentNotValidException): ProblemDetail =
        problem(HttpStatus.BAD_REQUEST, "validation-failed", "request validation failed")
            .apply {
                setProperty("errors", e.bindingResult.fieldErrors.map { mapOf("field" to it.field, "message" to it.defaultMessage) })
            }

    @ExceptionHandler(Exception::class)
    fun handleUnknown(e: Exception): ProblemDetail {
        val traceId = MDC.get("traceId") ?: UUID.randomUUID().toString()
        logger.error(e) { "unhandled exception (traceId=$traceId)" }
        return problem(
            HttpStatus.INTERNAL_SERVER_ERROR,
            "internal-error",
            "An unexpected error occurred. Reference: $traceId",
        ).apply { setProperty("traceId", traceId) }
    }

    private fun problem(status: HttpStatus, code: String, detail: String): ProblemDetail =
        ProblemDetail.forStatusAndDetail(status, detail).apply {
            type = URI.create("https://errors.example.com/$code")
            title = code
        }
}
```

Key rules:

- **One handler method per "kind of caller-visible error"** — not per cause site. `OrderNotSubmittable` covers many internal reasons but they all map to 409 Conflict externally.
- **Public messages must be safe** to show users / log on the client side. Internal details (SQL state, vendor codes, stack traces) go to server logs with a correlation id.
- **Always include a correlation id** in the response for `5xx`. Without it, support tickets are unanswerable.
- **A final `Exception` handler** is mandatory — it's the safety net. Without one, an unexpected exception leaks the framework's default error response which contains stack details.

### Choosing the HTTP status

| Exception type | HTTP status | Why |
|---|---|---|
| `*NotFound` (domain entity missing) | 404 | The resource truly doesn't exist for this caller |
| `*NotSubmittable` / `*Conflict` (state forbids the operation) | 409 Conflict | Domain rule says "no" — not the request's fault, not server's fault |
| Validation failure (`MethodArgumentNotValidException`, `ConstraintViolationException`) | 400 Bad Request | Caller sent malformed input |
| `*Unauthorized` / Spring Security `AuthenticationException` | 401 | Caller is anonymous, must authenticate |
| `*Forbidden` / Spring Security `AccessDeniedException` | 403 | Caller is authenticated but lacks permission |
| Idempotency conflict (same operation, different payload) | 409 Conflict | Existing resource conflicts with the new request |
| Rate-limit exceeded | 429 | Caller is over the limit |
| External dependency unavailable (port failure) | 502 Bad Gateway / 503 Service Unavailable | The server is up; the dependency isn't |
| Programming errors (`NullPointerException`, `IllegalStateException` that escapes) | 500 Internal Server Error | Server is broken; include trace id |

For the full HTTP error contract (when to use 422 vs 400, when 409 vs 412, Idempotency-Key semantics), see `api-design-principles`.

### `@ResponseStatus` shortcut — use sparingly

```kotlin
@ResponseStatus(HttpStatus.NOT_FOUND)
class OrderNotFound(id: OrderId) : RuntimeException("order $id not found")
```

Spring will return 404 automatically when this exception escapes a controller. **It's a shortcut, not a substitute for `@ExceptionHandler`** — you lose the `ProblemDetail` body, the correlation id, the structured logging, and the explicit mapping. Use `@ResponseStatus` only for very simple internal-tooling services without a public error contract.

---

## 2. The `@Transactional` Kotlin trap

Spring's `@Transactional` annotation **rolls back by default only on `RuntimeException` and `Error`**, not on checked exceptions. In pure Kotlin this is harmless — every exception is a `RuntimeException` — but the moment Java code is involved, surprises appear.

```kotlin
// ✓ Pure Kotlin — all exceptions are RuntimeException, rollback works
@Transactional
fun submitOrder(id: OrderId) {
    val order = repository.findById(id) ?: throw OrderNotFound(id)
    order.submit()                                       // throws OrderNotSubmittable (RuntimeException)
    repository.save(order)
    // If submit() throws, the JPA transaction rolls back. Perfect.
}

// ✗ Trap: a Java-thrown checked exception escapes a transactional Kotlin method
@Transactional
fun importFromCsv(file: Path) {
    csvReader.read(file)                                 // throws IOException (Java, checked) — does NOT trigger rollback
    repository.saveAll(...)
}

// ✓ Mitigation 1: explicit rollback rule
@Transactional(rollbackFor = [Exception::class])
fun importFromCsv(file: Path) { ... }

// ✓ Mitigation 2: catch and translate at the boundary
@Transactional
fun importFromCsv(file: Path) {
    try {
        csvReader.read(file)
    } catch (e: IOException) {
        throw CsvImportFailure("reading $file", e)
    }
    repository.saveAll(...)
}
```

### `noRollbackFor` — for the special case

Some exceptions deliberately *should not* roll back — e.g., a business audit-log entry that must persist even if the surrounding operation fails. Use sparingly:

```kotlin
@Transactional(noRollbackFor = [AuditEntryAlreadyExists::class])
fun recordAudit(entry: AuditEntry) { ... }
```

### Programmatic rollback

When a method returns a `Result<T>` / sealed `Outcome` instead of throwing, Spring doesn't know to roll back. Mark the transaction explicitly:

```kotlin
@Transactional
fun submitOrder(cmd: SubmitOrderCommand): SubmitOrderOutcome {
    val order = repository.findById(cmd.id) ?: return SubmitOrderOutcome.NotFound
    val outcome = order.submit()
    if (outcome is SubmitOrderOutcome.OutOfStock) {
        TransactionAspectSupport.currentTransactionStatus().setRollbackOnly()
    }
    repository.save(order)
    return outcome
}
```

This is **noisy** — it's another reason exceptions are usually the better fit inside transactional methods. Reserve sealed-`Outcome` returns for *non-transactional* seams (validation, idempotency checks before persistence) or accept the overhead.

### `@Transactional` on `private` / `internal` methods

Spring AOP wraps `public` methods on Spring-managed beans. `@Transactional` on `private` or `internal` methods is silently ignored. Detekt's `SpringJavaInjectionPointsAutowiringInspection` and similar lints catch this. Also: self-invocation (calling another `@Transactional` method on `this`) bypasses the proxy — extract the call into another bean.

---

## 3. Validation as boundary discipline

Feathers' "Don't Pass Null" + "Don't Return Null" generalise to "validate at the boundary, then trust your types". Spring Boot's Bean Validation integration is the canonical implementation.

```kotlin
data class CreateOrderRequest(
    @field:NotNull val customerId: UUID?,                  // wire format may legitimately omit
    @field:Size(min = 1, max = 50) val lines: List<OrderLineRequest> = emptyList(),
    @field:Email val notificationEmail: String? = null,
)

data class OrderLineRequest(
    @field:NotBlank val sku: String?,
    @field:Min(1) val quantity: Int?,
)

@RestController
class OrderController(private val submitOrder: SubmitOrder) {

    @PostMapping("/orders")
    fun create(@Valid @RequestBody request: CreateOrderRequest): OrderResponse {
        // Validation has already happened. From here, types are trustworthy.
        val command = SubmitOrderCommand(
            customerId = CustomerId(request.customerId!!),  // safe — @NotNull validated above
            lines = request.lines.map { it.toDraft() },
        )
        val order = submitOrder(command)
        return OrderResponse.of(order)
    }
}
```

Failed validation throws `MethodArgumentNotValidException`; your `@RestControllerAdvice` formats it into 400 + per-field error list.

### Method-level validation

For services and components, `@Validated` enables Bean Validation on method parameters:

```kotlin
@Service
@Validated
class OrderQueryService {
    fun findById(@NotNull id: OrderId): Order? = /* ... */
}
```

Calling with `null` throws `ConstraintViolationException`. Useful as a belt-and-braces at internal seams, but **type-level non-null is the primary defence** — the `@NotNull` annotation is for cases where Kotlin's type system can't reach (Java callers, reflective invocation).

### Validation vs domain invariants — where does each live?

| Layer | Concern | Tool |
|---|---|---|
| Controller / DTO | "Is the wire format syntactically valid?" — required fields, format constraints, lengths | Bean Validation (`@Valid`, `@NotBlank`, `@Email`) |
| Application service | "Does the operation make sense in current state?" — e.g., "this customer doesn't exist" | Throw domain exception after query (`CustomerNotFound`) |
| Domain | "Is the invariant preserved?" — e.g., "an order has at least one line" | `init { require(...) }` in value objects / aggregates |

Don't put Bean Validation annotations on domain entities — they're framework-coupling that bleeds into the model. Validate at the DTO; trust types in the domain.

---

## 4. Listener error handling — retry, DLQ, idempotency

Async message listeners are the place where Feathers' rules meet *infrastructure*. The same "wrap and translate" principle applies, but the **destination** of unhandled exceptions is different — the broker, not an HTTP client.

### RabbitMQ (`@RabbitListener`)

```kotlin
@Component
class OrderEventListener(private val service: OrderProcessing) {

    @RabbitListener(queues = ["orders.submitted"])
    fun onSubmitted(@Payload event: OrderSubmittedEvent, @Header("idempotency-key") key: String) {
        if (idempotencyStore.alreadyProcessed(key)) return       // Feathers' "normal flow" — duplicate is not an error
        try {
            service.handleSubmission(event)
            idempotencyStore.markProcessed(key)
        } catch (e: TransientFailure) {
            throw e                                              // → retry policy kicks in
        } catch (e: PoisonMessage) {
            logger.error(e) { "poison message ${event.id}: ${e.reason}" }
            throw AmqpRejectAndDontRequeueException("poison", e) // → DLQ
        }
    }
}
```

Configure retry + DLQ globally (or per-queue):

```kotlin
@Bean
fun rabbitListenerContainerFactory(connectionFactory: ConnectionFactory): SimpleRabbitListenerContainerFactory =
    SimpleRabbitListenerContainerFactory().apply {
        setConnectionFactory(connectionFactory)
        setAdviceChain(
            RetryInterceptorBuilder.stateless()
                .maxAttempts(5)
                .backOffOptions(/* initial */ 200, /* multiplier */ 2.0, /* max */ 10_000)
                .recoverer(RejectAndDontRequeueRecoverer()) // → DLQ exchange binding
                .build()
        )
    }
```

Three categories of failure:

| Category | Example | Strategy |
|---|---|---|
| **Transient** (network, lock contention, downstream 503) | `PaymentPortFailure(cause = ResourceAccessException)` | Throw → retry with backoff |
| **Poison** (malformed payload, business invariant permanently violated, missing reference data) | `OrderEventPayloadInvalid` | `AmqpRejectAndDontRequeueException` → DLQ |
| **Idempotent duplicate** (re-delivery of an already-processed message) | check `idempotency-key` | Return normally, do nothing |

See `messaging-rabbitmq-spring` for the full set of broker-level reliability patterns.

### Kafka (`@KafkaListener`)

Default Spring Kafka behaviour: on exception, the consumer **retries the same message indefinitely** unless you configure a `DefaultErrorHandler` with `DeadLetterPublishingRecoverer`. Configure:

```kotlin
@Bean
fun errorHandler(template: KafkaTemplate<String, Any>): DefaultErrorHandler =
    DefaultErrorHandler(
        DeadLetterPublishingRecoverer(template) { record, _ -> TopicPartition("${record.topic()}.DLT", record.partition()) },
        FixedBackOff(/* interval */ 1000, /* maxAttempts */ 4),
    ).apply {
        addNotRetryableExceptions(PoisonMessage::class.java)   // these go straight to DLT
    }
```

---

## 5. `@TransactionalEventListener` and async error compensation

Spring's `@TransactionalEventListener` runs *after* the publishing transaction commits — perfect for cross-aggregate / cross-module effects. But it introduces a subtlety: **the listener exception cannot roll back the publisher's transaction; it's already committed.**

```kotlin
// Publisher — transaction commits, event fires AFTER_COMMIT
@Transactional
fun submitOrder(cmd: SubmitOrderCommand): Order {
    val order = repository.findById(cmd.id) ?: throw OrderNotFound(cmd.id)
    order.submit()
    repository.save(order)
    eventPublisher.publishEvent(OrderSubmittedEvent(order.id, order.total))
    return order
}

// Listener — fires AFTER the publishing transaction commits
@Component
class EmailNotifier(private val mailer: Mailer) {
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    fun onSubmitted(e: OrderSubmittedEvent) {
        try {
            mailer.sendOrderConfirmation(e.orderId)
        } catch (failure: MailerFailure) {
            // ❗ Can't roll back the order — it's already committed.
            //    Either retry, or schedule for later via outbox / dead-letter.
            outbox.scheduleRetry(e, failure)
        }
    }
}
```

The two reactions:
1. **Retry** the listener (Spring Modulith's `@ApplicationModuleListener` integrates with the `event_publication` table for this — failed events stay there and can be retried).
2. **Compensate** the original action (issue a refund, post a reversal entry, send an apology email).

Don't `throw` out of an `AFTER_COMMIT` listener and assume the framework "does something" — it logs and moves on. Make the failure visible (alert, DLQ, retry mechanism) explicitly.

**Use `@ApplicationModuleListener`** (Spring Modulith) over plain `@TransactionalEventListener` when you want event-publication tracking and automatic retry — see `spring-boot-mastery` §"Spring Modulith deep".

---

## 6. Resilience4j fallback — Special Case Pattern for dependencies

Feathers' Special Case Pattern at the *dependency* level: when an external service is unavailable, return a sensible default instead of propagating the exception.

```kotlin
@Component
class CatalogClient(private val webClient: WebClient) {

    @CircuitBreaker(name = "catalog", fallbackMethod = "fallbackForProduct")
    @TimeLimiter(name = "catalog")
    @Retry(name = "catalog")
    fun product(sku: Sku): CompletableFuture<Product> =
        webClient.get().uri("/products/{sku}", sku.value)
            .retrieve().bodyToMono(Product::class.java)
            .toFuture()

    @Suppress("unused") // referenced by Resilience4j fallbackMethod
    fun fallbackForProduct(sku: Sku, cause: Throwable): CompletableFuture<Product> {
        logger.warn(cause) { "catalog unavailable for $sku, serving cached" }
        return cache.get(sku)?.let { CompletableFuture.completedFuture(it) }
            ?: CompletableFuture.failedFuture(CatalogPortFailure("catalog unavailable for $sku", cause))
    }
}
```

The fallback can:
- Return a cached / stale value (Special Case object).
- Return a degraded result (empty list of recommendations is better than 502 for a sidebar widget).
- Throw a **port-level** exception so the caller sees a consistent failure type (not the raw circuit-breaker `CallNotPermittedException`).

The right choice depends on **the caller's tolerance for staleness**. A pricing page can't show stale data; a "recently viewed" sidebar can. Decide per-port; don't fall back blindly.

See `microservices-patterns-deep` for the broader resilience picture (timeouts, bulkheads, retry budgets).

---

## 7. Startup failures — `ApplicationRunner`, `@PostConstruct`, smart initialisation

A failure during application startup is *categorically different* from a failure during request handling. The right behaviour: **fail fast and loud**. Don't catch and continue — a partially-initialised application is a debugging nightmare.

```kotlin
// ✓ Loud failure on missing config
@Component
class ConfigVerifier(@Value("\${critical.api.token}") private val token: String) {
    @PostConstruct
    fun verify() {
        require(token.isNotBlank()) { "critical.api.token must be set; refusing to start" }
    }
}

// ✓ ApplicationRunner — runs once after context is up; failure prevents readiness
@Component
class DatabaseMigrationCheck(private val flyway: Flyway) : ApplicationRunner {
    override fun run(args: ApplicationArguments) {
        val info = flyway.info()
        check(info.pending().isEmpty()) {
            "pending migrations: ${info.pending().joinToString { it.version.toString() }}; refusing to start"
        }
    }
}
```

`SpringApplication.run(...)` will throw, the JVM will exit non-zero, and your orchestrator (Kubernetes, ECS, systemd) restarts or alerts. That's the desired behaviour.

**Don't** swallow startup failures with a `try/catch` and a warn log. A service that lies about being ready is the worst class of bug.

---

## 8. Spring Security — auth exceptions

Spring Security throws specific exception types for auth failures, handled by `AuthenticationEntryPoint` / `AccessDeniedHandler` *before* the request reaches your `@RestControllerAdvice`. The default mapping is correct for most services:

| Exception | HTTP | When |
|---|---|---|
| `AuthenticationException` (and subclasses) | 401 | No credentials, expired token, invalid JWT |
| `AccessDeniedException` | 403 | Authenticated, but missing role/permission |
| `BadCredentialsException` | 401 | Username/password mismatch |
| `LockedException` | 401 / 423 | Account locked |
| `DisabledException` | 401 / 403 | Account disabled |

For a custom `ProblemDetail`-shaped 401 / 403, register your own `AuthenticationEntryPoint` / `AccessDeniedHandler` in the security filter chain — not in `@RestControllerAdvice`, because the exceptions never reach the advice layer. See `spring-security-and-auth`.

---

## 9. Error-response logging — what goes where

```
┌──────────────────────┬─────────────────────────────────────────────────────┐
│ Where                │ What                                                │
├──────────────────────┼─────────────────────────────────────────────────────┤
│ Exception message    │ Operation + principal + expected vs actual (rich)   │
│ ProblemDetail.detail │ Safe-for-public message; no PII, no stack            │
│ Server logs          │ Full exception incl. cause, stack, MDC context       │
│ MDC                  │ traceId, requestId, userId, tenantId, orderId        │
│ Metrics              │ Counter per `error.type` + status code               │
│ Distributed trace    │ Error span attribute set to the exception type        │
└──────────────────────┴─────────────────────────────────────────────────────┘
```

The discipline: **the public payload is the absolute minimum needed for the caller; the server log has everything**. Connecting the two is the correlation id (`traceId`) which appears in *both*.

---

## 10. The `@Transactional(readOnly = true)` rule

Query / read methods should be `@Transactional(readOnly = true)`. This is unrelated to error handling on the surface, but it interacts with the rollback rules: a read-only transaction that triggers a state change throws `TransactionSystemException` at flush time — which is *good*, it catches accidental writes during reads. Don't disable this; treat the exception as a real bug.

---

## Cross-rule summary — Spring application of Feathers' rules

| Feathers rule | Spring application |
|---|---|
| Use Exceptions, not codes | Throw domain exceptions from services; `@RestControllerAdvice` translates |
| Write try first | Adapter wrapping; `try { sdk.call() } catch(e) { throw PortFailure(...) }` |
| Use unchecked | All Kotlin exceptions are unchecked; `@Transactional` rolls back automatically |
| Provide context | Exception message + MDC + traceId in `ProblemDetail` |
| Define exception classes by caller | One handler per "kind of caller-visible error" in `@ControllerAdvice` |
| Define the normal flow | Resilience4j fallback for dependency outages; idempotency-key checks in listeners |
| Don't return null | Spring Data Optional → translate at the repository boundary |
| Don't pass null | Bean Validation at controller; non-null types inside |

## Anti-patterns specific to Spring

- **`try/catch` inside controllers.** The advice exists for this.
- **`@Transactional` on a `private` method.** Silently ignored — AOP wraps `public` methods only.
- **Self-invocation of `@Transactional`** (calling another `@Transactional` method on `this`). Bypasses the proxy; the inner annotation does nothing.
- **`@Transactional` returning `Result<T>` without explicit rollback.** Spring doesn't know to roll back when you return a `Result.failure`. Use `setRollbackOnly()` or throw.
- **Catching `Exception` in a controller method "for safety".** You just hid the bug from the advice layer. Let it propagate.
- **Swallowing exceptions in `@TransactionalEventListener`** without a retry / compensation plan. The committing transaction is gone; silent failure is *data loss*.
- **No final `Exception` handler in `@RestControllerAdvice`.** The framework's default error page leaks stack details. Always add one.
- **`@ResponseStatus(500)` on a custom exception.** 500 means "the server is broken". If you're throwing it deliberately, the situation is *not* "the server is broken" — pick the right status.
- **Validating in the service layer with `if (input.foo == null) throw`.** Bean Validation at the controller is the canonical home; the service should trust its inputs.
- **`@ExceptionHandler` on a controller class** (not `@ControllerAdvice`). Scopes the handler to that controller only — usually not what you want; cross-cutting handlers belong on the advice.
- **Returning a `ResponseEntity<Map<String, Any>>` ad-hoc from a controller.** Use `ProblemDetail` — it's the standard, OpenAPI generators know it, error-reporting tools expect it.
