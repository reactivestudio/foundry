# Spring Boot Function Patterns

Clean Code Ch. 3 rules applied at function level in Spring Boot / Kotlin services. The framework provides infrastructure (request mapping, transactions, exception translation, validation, event dispatch) that lets business functions stay small, single-purpose, and free of cross-cutting noise — *if* you use those affordances correctly.

> "Error handling is one thing." — Martin. Spring's `@ExceptionHandler` makes that one thing happen in **one place per service**, not in every method.

## Quick map — Spring affordance per Martin rule

| Rule | Spring affordance | What it lets you avoid |
|---|---|---|
| §"Have No Side Effects" | `@Transactional` boundary at the use-case method | Commit/rollback logic inside business code. |
| §"Error Handling Is One Thing" | `@ExceptionHandler` / `@ControllerAdvice` + `ProblemDetail` | try/catch inside controllers and services. |
| §"Exceptions over codes" | Domain exceptions → `ProblemDetail` per RFC 7807 | Error code enums; HTTP-coupling inside business logic. |
| §"CQS" | Method naming on services: `createOrder()` vs `findOrder()` | Read methods that mutate as a side effect. |
| §"Few arguments" | `@Valid @RequestBody` + DTOs | Long parameter lists in controllers. |
| §"Do One Thing" | `@EventListener` / `@TransactionalEventListener` / `@ApplicationModuleListener` | A use-case method that also emails, audits, projects. |
| §"Flag arguments" | `@PreAuthorize`, distinct endpoint paths | Boolean toggles deciding behaviour inside one method. |
| §"Stepdown rule" | Controller → application service → domain → infrastructure | One body holding logic from multiple layers. |

---

## 1. Controller methods are thin orchestrators — one HTTP concern each

A controller method maps HTTP → domain → HTTP. It does not contain business rules. Target: **5–10 lines**, **one application-service call**, no try/catch (handled globally).

```kotlin
@RestController
@RequestMapping("/api/v1/orders")
class OrderController(private val orders: OrderApplicationService) {

    // ✓ Thin: bind, delegate, respond. Errors handled by @ControllerAdvice.
    @PostMapping
    fun submit(@Valid @RequestBody command: SubmitOrderRequest): ResponseEntity<OrderView> {
        val view = orders.submit(command.toCommand())
        return ResponseEntity
            .created(URI("/api/v1/orders/${view.id}"))
            .body(view)
    }

    @GetMapping("/{id}")
    fun byId(@PathVariable id: OrderId): OrderView = orders.byId(id)
}
```

**Anti-pattern** — fat controller:
```kotlin
// ✗ Validation, persistence, mapping, and error translation all in the controller
@PostMapping
fun submit(@RequestBody req: SubmitOrderRequest): ResponseEntity<*> {
    if (req.customerId == null) return ResponseEntity.badRequest().body("...")
    try {
        val order = Order(...)                       // domain construction in controller
        orderRepo.save(order)                        // repository call from controller
        return ResponseEntity.ok(OrderResponse(...)) // mapping in controller
    } catch (e: IllegalStateException) {
        return ResponseEntity.status(409).body(...)  // try/catch in controller
    }
}
```

Three rules violated: do one thing, no side effects (mixing layers), error handling is one thing.

---

## 2. `@Transactional` boundary — one transaction per use case, at the application-service method

Place `@Transactional` on the **application-service method** that represents a use case, **not** on repository methods, **not** on domain methods, **not** on controller methods.

```kotlin
@Service
@Transactional(readOnly = true)                       // default: read
class OrderApplicationService(
    private val orders: OrderRepository,
    private val publisher: ApplicationEventPublisher,
) {
    @Transactional                                    // write: one TX for the whole use case
    fun submit(command: SubmitOrder): OrderView {
        val order = Order.submit(command)
        orders.save(order)
        publisher.publishEvent(order.events())        // outbox / Modulith
        return OrderView.from(order)
    }

    fun byId(id: OrderId): OrderView =
        orders.findByIdOrThrow(id).let(OrderView::from)
}
```

**Why function-level**:
- The transaction is the use-case's **atomic unit**. Mixing two transactional methods inside one creates **nested-transaction surprises** (Propagation rules) — readers can't infer behaviour from the function body.
- Read-default + write-override **flips the safety bias** correctly: forgetting to annotate a query is harmless; forgetting to annotate a write is loud (read-only TX fails on flush).

**Anti-patterns**:
| Anti-pattern | Why bad |
|---|---|
| `@Transactional` on every repository method | Per-call transactions; calling two repos = two TXs, no atomicity. |
| `@Transactional` on a controller method | Layer leak: controllers should not know about TX. |
| `@Transactional` inside an `@Async` method | Suspended TX boundaries; threading + TX is a footgun. |
| Self-invocation of `@Transactional` method | Spring proxies don't intercept self-calls — TX absent. |

---

## 3. `@ExceptionHandler` + `ProblemDetail` — try/catch lifted out of business code

Martin's "Error handling is one thing" becomes: **zero try/catch in controllers and services for HTTP-translatable errors**. Throw a domain exception; let `@ControllerAdvice` map it.

```kotlin
// Domain exceptions — sealed hierarchy, no HTTP knowledge
sealed class DomainError(message: String) : RuntimeException(message)
class NotFound(entity: String, id: Any)            : DomainError("$entity $id not found")
class Conflict(detail: String)                     : DomainError(detail)
class InvalidArgument(field: String, why: String)  : DomainError("$field: $why")

// One @ControllerAdvice translates the domain to HTTP — RFC 7807 ProblemDetail
@RestControllerAdvice
class GlobalExceptionHandler {

    @ExceptionHandler(NotFound::class)
    fun notFound(e: NotFound): ProblemDetail =
        problem(HttpStatus.NOT_FOUND, "Not found", e.message)

    @ExceptionHandler(Conflict::class)
    fun conflict(e: Conflict): ProblemDetail =
        problem(HttpStatus.CONFLICT, "Conflict", e.message)

    @ExceptionHandler(InvalidArgument::class)
    fun invalid(e: InvalidArgument): ProblemDetail =
        problem(HttpStatus.BAD_REQUEST, "Invalid argument", e.message)

    @ExceptionHandler(MethodArgumentNotValidException::class)
    fun beanValidation(e: MethodArgumentNotValidException): ProblemDetail {
        val errors = e.bindingResult.fieldErrors
            .associate { it.field to (it.defaultMessage ?: "invalid") }
        return problem(HttpStatus.BAD_REQUEST, "Validation failed", "$errors")
    }

    private fun problem(status: HttpStatus, title: String, detail: String?): ProblemDetail =
        ProblemDetail.forStatusAndDetail(status, detail ?: title).apply {
            this.title = title
        }
}
```

**Application-service methods now read straight**:
```kotlin
fun byId(id: OrderId): OrderView =
    orders.findById(id)?.let(OrderView::from)
        ?: throw NotFound("Order", id)
```

No `Result`. No try/catch. One throw site; one translation in `@ControllerAdvice`.

**Cross-link**: `api-design-principles` covers the HTTP-status / ProblemDetail conventions in detail.

---

## 4. CQS at the service layer — naming reflects the split

Martin's command/query separation, applied to service methods:

- **Command** method → returns `Unit`, an id, or a minimal acknowledgement. Verb-first name: `submit`, `cancel`, `pay`.
- **Query** method → returns a value (DTO, view, projection). Often noun-or-question name: `byId`, `forCustomer`, `isAvailable`.

```kotlin
@Service
class OrderApplicationService(...) {

    // Commands — verb names; return ID or minimal view; mutate
    @Transactional
    fun submit(command: SubmitOrder): OrderId = ...

    @Transactional
    fun cancel(id: OrderId, reason: String) { ... }

    // Queries — noun names; return DTOs; no mutation
    fun byId(id: OrderId): OrderView = ...
    fun forCustomer(customerId: CustomerId, page: Pageable): Page<OrderView> = ...
    fun isCancellable(id: OrderId): Boolean = ...
}
```

**Anti-patterns**:
- A "query" that lazily creates: `fun findOrCreate(...)` → name says it, but mixes — split to `findById` and `createIfMissing` if you can; if you can't, the name is the smell.
- A "command" that returns the full updated entity → reasonable when you need the optimistic-lock version; not when it's because you couldn't be bothered to expose a separate read.

**Cross-link**: For architectural CQRS (separate read models), `cqrs-implementation`.

---

## 5. Validation — push it to the boundary, no manual checks downstream

Martin's "do one thing" at the controller method: bind & validate the request, then call the use case. Bean Validation (`@Valid`) handles syntactic validation **before** the body executes.

```kotlin
// Request DTO — validation annotations are the spec
data class SubmitOrderRequest(
    @field:NotNull val customerId: CustomerId,
    @field:NotEmpty @field:Valid val lines: List<OrderLineRequest>,
    @field:NotNull val shippingAddress: AddressRequest,
)

data class OrderLineRequest(
    @field:NotNull val productId: ProductId,
    @field:Min(1) val quantity: Int,
)

@PostMapping
fun submit(@Valid @RequestBody request: SubmitOrderRequest): ResponseEntity<OrderView> = ...
```

**Failure mode** of NOT pushing validation to the boundary: every service method starts with 5 lines of `require(...)` re-validating the same fields, scattered through the codebase.

**Layered validation**:
- **Syntactic** (`@NotEmpty`, `@Min`, `@Pattern`): Bean Validation at controller boundary.
- **Semantic** (the order's customer exists; the product is in stock): the use-case method or domain aggregate. Throws a domain exception.
- **Invariants** (an `Order` cannot have zero lines, money is non-negative): in the domain constructor / factory. Throws `IllegalArgumentException` or `DomainError`.

Three different layers, three different failure modes — each in **one place** instead of repeated.

---

## 6. DTO mapping — one function, both directions explicit

DTOs are noise unless they earn their place. When they exist, give them an unambiguous direction and **one** mapping function each way.

```kotlin
// Request → Command (controller side)
data class SubmitOrderRequest(...) {
    fun toCommand(): SubmitOrder = SubmitOrder(
        customerId = customerId,
        lines = lines.map { OrderLine(it.productId, it.quantity) },
        shippingAddress = shippingAddress.toDomain(),
    )
}

// Domain → View (response side)
data class OrderView(val id: OrderId, val total: Money, val status: String) {
    companion object {
        fun from(order: Order) = OrderView(
            id = order.id,
            total = order.total,
            status = order.status.name,
        )
    }
}
```

**House rules**:
- Each DTO has one direction. `OrderRequest` is inbound. `OrderView` is outbound. Don't reuse one class for both — they evolve differently.
- The mapping function lives **on the DTO** (request) or in a `companion object` factory (response). One function per direction.
- No MapStruct / model-mapper magic that hides the mapping — when the mapping is wrong it's invisible.

---

## 7. Repository methods — short, expressive, no flag arguments

Spring Data repositories already encourage the right shape:

```kotlin
interface OrderRepository : JpaRepository<Order, OrderId> {
    // Each query is a verb + criteria. No flag arguments.
    fun findByCustomerId(customerId: CustomerId, page: Pageable): Page<Order>
    fun findFirstByCustomerIdOrderBySubmittedAtDesc(customerId: CustomerId): Order?
    fun existsByCustomerIdAndStatus(customerId: CustomerId, status: OrderStatus): Boolean

    @Query("SELECT o FROM Order o WHERE o.customer.id = :id AND o.status IN :statuses")
    fun findActiveForCustomer(@Param("id") id: CustomerId, @Param("statuses") active: Set<OrderStatus>): List<Order>
}

// Helper for the "throw on missing" pattern — single function, single purpose
fun OrderRepository.findByIdOrThrow(id: OrderId): Order =
    findById(id).orElseThrow { NotFound("Order", id) }
```

**Anti-patterns**:
- `findOrders(customerId, includeCancelled: Boolean, includePending: Boolean)` — two flag args. Split into `findActive`, `findAll`, `findByStatus(Set<OrderStatus>)`.
- `findX` that has side effects (logs, increments a counter) — query that commands.

---

## 8. `@Async` — fire-and-forget is one thing; name it clearly

`@Async` runs on a different thread. Function-level rules:

1. **Return `Unit`** (`void`) for fire-and-forget; **`CompletableFuture<T>`** when the caller needs the result. **Never** `T` directly — the value would be unrelated to the call.
2. **Name reflects asynchrony or side effect**: `notifyCustomer` (event-like name), not `sendEmail` (sounds synchronous).
3. **Cannot self-invoke `@Async`**: same proxy rule as `@Transactional`. Call from a different bean.
4. **Pair with `@Transactional` carefully**: `@Async` outside an existing TX runs *without* it; `@Async @Transactional` opens its own TX on its own thread.

```kotlin
@Service
class ReceiptNotifier(private val mailer: Mailer) {
    @Async
    fun notifyReceiptIssued(orderId: OrderId, email: Email) {
        mailer.send(...)
    }
}

@Service
class OrderApplicationService(
    private val notifier: ReceiptNotifier,
) {
    @Transactional
    fun submit(command: SubmitOrder): OrderId {
        val order = Order.submit(command)
        orders.save(order)
        notifier.notifyReceiptIssued(order.id, order.customerEmail)   // ← from another bean: proxy intercepts
        return order.id
    }
}
```

**Recommended alternative**: emit a domain event and let an `@EventListener` (or `@TransactionalEventListener(phase = AFTER_COMMIT)`) handle the async work. Function shape becomes even smaller — see §9.

---

## 9. `@EventListener` / `@TransactionalEventListener` / Modulith `@ApplicationModuleListener` — one event, one handler, small function

An event listener is one function. The Clean Code rules apply, plus a Spring nuance: **use the listener phase that matches your semantics**.

| Listener form | Runs | Use when |
|---|---|---|
| `@EventListener` | Synchronously in the publishing transaction | Side effect that *must* be in the same TX as the publish. |
| `@TransactionalEventListener(phase = AFTER_COMMIT)` | After the publishing TX commits | Most use cases — projection update, notification, integration. |
| `@TransactionalEventListener(phase = AFTER_ROLLBACK)` | After rollback | Compensating action, cleanup. |
| `@ApplicationModuleListener` (Spring Modulith) | Async, AFTER_COMMIT, with outbox | Inter-module event with at-least-once delivery via the publication log. |

```kotlin
// One event, one handler — small, single-purpose
@Component
class OrderProjectionUpdater(private val projection: OrderProjectionRepository) {
    @ApplicationModuleListener
    fun on(event: OrderSubmitted) {
        projection.upsert(OrderProjection.from(event))
    }
}

@Component
class ReceiptNotifier(private val mailer: Mailer) {
    @ApplicationModuleListener
    fun on(event: OrderSubmitted) {
        mailer.sendReceipt(event.customerEmail, event.orderId)
    }
}
```

**Anti-patterns**:
- One listener function handling three event types (a `when` over event class). Each event type wants its own listener.
- A listener that mutates state outside its module (cross-context write). Send a command, don't reach across.
- A listener with try/catch swallowing exceptions silently — let Modulith / Spring's retry handle it; log structured.

**Cross-link**: `cqrs-implementation` for projection-handler discipline; `messaging-rabbitmq-spring` for AMQP-equivalent patterns.

---

## 10. Method-level security — `@PreAuthorize` lifts auth out of the function body

Without method security, every service method starts with `if (!user.canDo(...)) throw Forbidden(...)`. That's a flag-like concern repeated everywhere.

```kotlin
@Service
class OrderApplicationService(...) {

    @PreAuthorize("hasRole('ADMIN') or @orderAuthz.canCancel(authentication, #id)")
    @Transactional
    fun cancel(id: OrderId, reason: String) {
        orders.findByIdOrThrow(id).cancel(reason)
    }
}
```

The auth decision becomes a declarative concern attached to the function, not part of the function body. **Do One Thing** stays: the function cancels; security is its annotation.

**House rule**: SpEL expressions in `@PreAuthorize` should not embed business logic — call a `@Component` (named `*Authz`) whose method does the check. Keeps the expression short and testable.

**Cross-link**: `spring-security-and-auth` for the broader filter chain and JWT story.

---

## 11. Caching annotations — `@Cacheable` etc. as decorators, body stays pure

`@Cacheable` on a query method keeps the **function body** pure (compute the answer); the caching is decoration.

```kotlin
@Service
class ProductCatalog(private val products: ProductRepository) {

    @Cacheable("products-by-id")
    fun byId(id: ProductId): Product = products.findByIdOrThrow(id)

    @CacheEvict("products-by-id", key = "#id")
    fun invalidate(id: ProductId) = Unit
}
```

**Function-level cleanliness**: the body of `byId` is one line and *what the function actually computes*. The annotation describes the side effect (cache lookup, cache write) without polluting the body.

**Cross-link**: `caching-strategies-spring` for cache stampede, invalidation, two-tier patterns.

---

## 12. WebFlux `suspend` and `Mono`/`Flux` handlers — same rules, reactive surface

In WebFlux (with Kotlin coroutines bridge):

```kotlin
@RestController
class OrderController(private val orders: OrderApplicationService) {

    @PostMapping("/orders")
    suspend fun submit(@Valid @RequestBody command: SubmitOrderRequest): OrderView =
        orders.submit(command.toCommand())

    @GetMapping("/orders")
    fun list(@RequestParam customerId: CustomerId): Flow<OrderView> =
        orders.streamForCustomer(customerId)
}
```

**Rules unchanged**:
- Controller method is thin.
- Validation at boundary.
- Error handling in `@ControllerAdvice` (works the same way; `ProblemDetail` flows through).

**Watch for**:
- **Blocking calls inside `suspend` or `Flow.map`**: a JDBC call in a coroutine controller blocks an event-loop thread. Use R2DBC or wrap with `withContext(Dispatchers.IO)`.
- **`@Transactional` with reactive**: needs `ReactiveTransactionManager` and propagates differently. Don't mix imperative `@Transactional` and reactive return types in the same method.

---

## 13. Test methods — small, one assertion-set, name says what's tested

Clean Code rules apply to test functions too:

```kotlin
@SpringBootTest
class OrderApplicationServiceIT(@Autowired private val service: OrderApplicationService) {

    @Test
    fun `submit rejects an order with no lines`() {
        val command = aSubmitOrder().withNoLines()
        assertThatThrownBy { service.submit(command) }
            .isInstanceOf(InvalidArgument::class.java)
    }

    @Test
    fun `submit persists the order and emits OrderSubmitted`() {
        val command = aValidSubmitOrder()
        val id = service.submit(command)
        assertThat(orders.findById(id)).isPresent
        assertThat(publishedEvents).anyMatch { it is OrderSubmitted && it.orderId == id }
    }
}
```

**Rules**:
- One scenario per `@Test`. Avoid multi-assertion drift.
- Backtick-name tests with a sentence — that's what the function "is".
- No `if` inside a test body — if you'd branch, you wanted two tests.
- Setup helpers (builders, `a*()` functions) are themselves clean functions, not throwaway.

**Cross-link**: `testing-strategy-kotlin-spring` for slice choice and pyramid shape.

---

## 14. Configuration methods — `@Bean` methods are functions too, keep them small

`@Bean` methods in `@Configuration` classes are pure factories:

```kotlin
@Configuration
class HttpClientConfig {

    @Bean
    fun externalApiClient(properties: ExternalApiProperties): HttpClient =
        HttpClient.newBuilder()
            .connectTimeout(properties.connectTimeout)
            .build()
}
```

If a `@Bean` method exceeds 15 lines, extract a builder function. Configuration classes should read top-down: properties → infrastructure beans → application beans, stepdown-rule order.

**Cross-link**: `spring-boot-mastery` for `@ConfigurationProperties` patterns.

---

## 15. Spring smell-to-fix quick table

| Smell in a function | Spring affordance to use |
|---|---|
| try/catch in controller for HTTP error mapping | `@ControllerAdvice` + `@ExceptionHandler` + `ProblemDetail`. |
| `if (input.x == null) throw ...` at top of service method | `@Valid @RequestBody` + `@field:NotNull`. |
| Two repository calls in a controller method | Move to an `@Transactional` application-service method. |
| Manual permission check (`if (!user.hasRole(...))`) | `@PreAuthorize` on the method. |
| Boolean `forceUpdate` flag on a service method | Two methods (`update`, `forceUpdate`) or a sealed `UpdatePolicy`. |
| Logging then re-throwing | Let the `@ControllerAdvice` log on translation; remove the per-method log. |
| Cache-aside boilerplate at the top of a query | `@Cacheable` on the query. |
| Email-send call inside a use-case method | Emit a domain event; `@TransactionalEventListener(AFTER_COMMIT)` handles it. |
| `Result<Order>` returning from a domain service | Throw a domain exception; let `@ControllerAdvice` map it. |
| `@Transactional` on every repository method | Lift to one `@Transactional` boundary per use case. |

---

## 16. Checklist before merging a Spring service change

1. **Controller method** ≤ 10 lines, validates input, delegates, responds. No try/catch.
2. **Service method** has one `@Transactional` (or `@Transactional(readOnly = true)`).
3. **Domain exception** thrown; one `@ExceptionHandler` translates it to `ProblemDetail`.
4. **No flag argument** on any public method.
5. **No `@Async` self-invocation**; called from a different bean.
6. **Listeners** consume one event type each; transactional phase chosen deliberately.
7. **Repository queries** have verb-named methods, no `Boolean includeX` parameters.
8. **DTO ↔ domain mapping** lives in one named function per direction.
9. **Authorization** is `@PreAuthorize` declarative, not inside the body.
10. **Tests**: one scenario per `@Test`; controller / service / repo slice chosen by what's actually under test.
