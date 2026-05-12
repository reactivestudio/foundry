# Kotlin-Specific Formatting

Layout decisions that are uniquely Kotlin's — either because Kotlin syntax differs from Java (primary constructors, expression bodies, scope functions, `when`, multi-line strings) or because Kotlin's official style guide takes a position Martin's Ch. 5 doesn't address. Where a rule is the same in Java and Kotlin, see `general-formatting-rules.md`.

## Source of truth

The **[Kotlin Coding Conventions](https://kotlinlang.org/docs/coding-conventions.html)** are the official baseline. Both ktlint and ktfmt (with `--kotlinlang-style`) implement it. Where this skill takes a position beyond the official guide, it is marked **house style**.

---

## 1. Class header — primary constructor layout

### 1a. Short constructor — one line

If all constructor parameters fit on a line ≤ 120 chars, keep them on one line:

```kotlin
class OrderId(val value: UUID)

class Money(val amount: BigDecimal, val currency: Currency)
```

### 1b. Long constructor — multi-line with trailing comma

When parameters overflow, put each on its own line with **trailing comma** (Kotlin 1.4+):

```kotlin
class OrderService(
    private val orderRepository: OrderRepository,
    private val paymentGateway: PaymentGateway,
    private val stockReservation: StockReservation,
    private val clock: Clock,
) {
    // ...
}
```

**Why trailing comma**:
- Adding a new parameter is a 1-line diff (`+ newParam: Type,`), not a 2-line diff (`previousLast,` then `newParam`).
- Line ordering is uniform — every line ends the same way; the eye doesn't need to special-case the last one.
- Auto-formatters preserve and reflow consistently.

### 1c. Inheritance / interface implementation — on its own line for long lists

```kotlin
class OrderService(
    private val orderRepository: OrderRepository,
    private val paymentGateway: PaymentGateway,
) : OrderApi,
    EventListener,
    InitializingBean {
    // ...
}
```

Short version (one parent, no params on multiple lines):
```kotlin
class Money(val amount: BigDecimal, val currency: Currency) : Comparable<Money>
```

---

## 2. Properties — at the top, primary constructor first

**House style**: the canonical layout for a class is:

```kotlin
class OrderService(
    // 1. Primary constructor properties (DI for Spring beans, identity for domain objects)
    private val orderRepository: OrderRepository,
    private val clock: Clock,
) {

    // 2. Class-level properties (state)
    private val cache: MutableMap<OrderId, Order> = mutableMapOf()

    // 3. Companion constants
    companion object {
        private const val MAX_RETRY = 3
    }

    // 4. init blocks (rare; prefer factory methods)
    init {
        require(MAX_RETRY > 0)
    }

    // 5. Public methods (stepdown order — see Ch. 5)
    fun submit(orderId: OrderId): SubmittedOrder { ... }

    fun cancel(orderId: OrderId) { ... }

    // 6. Private methods (called by public, in caller-callee order)
    private fun chargePayment(order: Order) { ... }
}
```

**Anti-pattern**: properties declared *after* methods.
```kotlin
class TestSuite : Test {
    fun createTest(...) { ... }
    fun getTestConstructor(...) { ... }
    private val name: String                    // ← buried
    private val tests: MutableList<Test> = ...
    constructor() { ... }
}
```
Move properties to the top — the reader needs to know the shape of the object before they read its behaviour.

---

## 3. Expression bodies vs. block bodies

### 3a. Use expression body when the function is a single expression

```kotlin
// ✓ Idiomatic
fun isPaid(order: Order): Boolean = order.payment.status == PAID

fun totalAmount(): Money = lines.sumOf { it.amount }

override fun toString(): String = "Order($id)"
```

### 3b. Don't pack multiple statements behind a scope function into an "expression body"

```kotlin
// ✗ Hides side effects, complex logic in the body — looks like a getter, isn't
fun submit(orderId: OrderId): SubmittedOrder = orderRepository.findById(orderId)
    .also { it.validateForSubmission() }
    .let { paymentGateway.charge(it); it }
    .apply { stockReservation.reserve(this); status = SUBMITTED }
    .also { eventPublisher.publish(OrderSubmitted(it.id)) }
    .let { SubmittedOrder(it.id, Instant.now()) }

// ✓ Block body — the steps are visible top-to-bottom
fun submit(orderId: OrderId): SubmittedOrder {
    val order = orderRepository.findById(orderId)
    order.validateForSubmission()
    paymentGateway.charge(order)
    stockReservation.reserve(order)
    order.status = SUBMITTED
    eventPublisher.publish(OrderSubmitted(order.id))
    return SubmittedOrder(order.id, Instant.now())
}
```

**Rule of thumb**: expression body is for **one expression that fits on one line**. Two or more steps, or a chain that needs reading, goes in a block body.

### 3c. Return type — explicit on public API, implicit on private

```kotlin
// ✓ Public API — explicit return type aids API consumers and IDE
fun totalAmount(): Money = lines.sumOf { it.amount }

// ✓ Private — inference is fine
private fun feeFor(amount: Money) = amount * FEE_RATE
```

The Kotlin style guide *recommends* explicit return types on public-facing functions, even with expression bodies. ktlint warns on this; ktfmt does not.

---

## 4. `when` blocks — layout and the alignment trap

### 4a. Short branches — one line each

```kotlin
fun status(order: Order): OrderStatus = when (order.state) {
    NEW -> Pending
    PAID -> AwaitingShipment
    SHIPPED -> InTransit
    DELIVERED -> Closed
    CANCELLED -> Closed
}
```

### 4b. Long branches — block per branch with blank lines between blocks

```kotlin
fun handle(event: OrderEvent) {
    when (event) {
        is OrderSubmitted -> {
            val order = orderRepository.findById(event.orderId)
            paymentGateway.charge(order)
            stockReservation.reserve(order)
        }

        is OrderCancelled -> {
            val order = orderRepository.findById(event.orderId)
            stockReservation.release(order)
            refundService.issueRefund(order)
        }

        is OrderShipped -> {
            notificationService.notifyCustomer(event.orderId)
        }
    }
}
```

### 4c. Don't align `->` arrows

```kotlin
// ✗ Manual alignment — destroyed by next formatter run; emphasises the wrong axis
fun status(s: State): Status = when (s) {
    NEW       -> Pending
    PAID      -> AwaitingShipment
    SHIPPED   -> InTransit
    DELIVERED -> Closed
}

// ✓ Single space — what every Kotlin formatter produces
fun status(s: State): Status = when (s) {
    NEW -> Pending
    PAID -> AwaitingShipment
    SHIPPED -> InTransit
    DELIVERED -> Closed
}
```

Same rule as Martin's Ch. 5 Rule 9 (no column alignment), but specifically called out because `when` is the place developers most often *want* to align.

---

## 5. Scope functions — when they help density, when they hide intent

Scope functions (`let`, `run`, `also`, `apply`, `with`) are *the* Kotlin construct most often misused for formatting.

### 5a. Good — null-safe transformation, value-binding

```kotlin
// ✓ let — null-safe continuation
val displayName: String = user.nickname?.let { "@$it" } ?: user.fullName

// ✓ apply — DSL-style configuration of a freshly created object
val builder = HttpClient.Builder().apply {
    connectTimeout(Duration.ofSeconds(5))
    readTimeout(Duration.ofSeconds(30))
    addInterceptor(authInterceptor)
}.build()
```

### 5b. Bad — scope-function abuse to compress unrelated steps

```kotlin
// ✗ apply hides 4 distinct steps behind a single expression
fun createOrder(req: OrderRequest): Order = Order(req.id).apply {
    paymentGateway.charge(this)
    stockReservation.reserve(this)
    eventPublisher.publish(OrderSubmitted(id))
    status = SUBMITTED
}

// ✓ Block body — each step on its own line, readable top to bottom
fun createOrder(req: OrderRequest): Order {
    val order = Order(req.id)
    paymentGateway.charge(order)
    stockReservation.reserve(order)
    eventPublisher.publish(OrderSubmitted(order.id))
    order.status = SUBMITTED
    return order
}
```

**Rule of thumb**: scope function is for **one transformation** or **one configuration block**. Multi-step business logic belongs in a block body where each step is visible at the indent level.

### 5c. Don't chain scope functions across lines

```kotlin
// ✗ Unreadable chain — `it` and `this` ambiguity, no obvious entry point
order.let { it.validate() }
    .run { paymentGateway.charge(this); this }
    .also { stockReservation.reserve(it) }
    .apply { status = SUBMITTED }

// ✓ Plain sequential calls
order.validate()
paymentGateway.charge(order)
stockReservation.reserve(order)
order.status = SUBMITTED
```

---

## 6. Lambdas — single-line vs. multi-line layout

### 6a. Single-line lambda — implicit `it`

```kotlin
val paidOrders = orders.filter { it.isPaid() }
val totals = orders.map { it.totalAmount() }
```

### 6b. Multi-line lambda — named parameter, indented body

```kotlin
val grouped = orders
    .groupBy { order ->
        OrderGroup(order.customer, order.placedAt.toLocalDate())
    }
    .mapValues { (_, group) ->
        group.sumOf { it.totalAmount().amount }
    }
```

**Rule**: if the lambda body is more than one statement or includes nested constructs, name the parameter explicitly. `it` is for one-line single-receiver-use lambdas only.

### 6c. Trailing lambda — when it improves readability

```kotlin
// ✓ Trailing lambda — DSL-feel, the lambda is the main payload
transaction {
    orderRepository.save(order)
    auditLog.record("submitted", order.id)
}

// ✓ Last argument as trailing lambda
orders.filter { it.isPaid() }.forEach { processPayment(it) }
```

When the lambda is *not* the main payload (e.g., it's one of several configuration arguments), don't force trailing-lambda syntax.

---

## 7. Multi-line strings — `trimIndent` and `trimMargin`

### 7a. Use `trimIndent()` for indented multi-line content

```kotlin
val sql = """
    SELECT o.id, o.customer_id, o.total
    FROM orders o
    JOIN customers c ON c.id = o.customer_id
    WHERE c.status = 'ACTIVE'
      AND o.placed_at >= ?
    ORDER BY o.placed_at DESC
""".trimIndent()
```

The leading whitespace common to all non-blank lines is removed. The visual indent matches the surrounding code; the runtime string does not carry the indent.

### 7b. Use `trimMargin()` when content itself starts with whitespace

```kotlin
val yamlSnippet = """
    |orders:
    |  - id: ${order.id}
    |    customer: ${order.customer.name}
    |    items:
    |      - product: WIDGET
    |        quantity: 3
""".trimMargin()
```

`trimMargin()` strips up to and including the margin character (default `|`) on each line.

### 7c. Layout — opening `"""` on the same line as `=`

```kotlin
// ✓ Standard layout
val message = """
    Order ${order.id} has been submitted.
    Total: ${order.total}
""".trimIndent()

// ✗ Avoid — opens immediately, awkward indent
val message =
    """
        Order ${order.id} has been submitted.
        Total: ${order.total}
    """.trimIndent()
```

---

## 8. Top-level declarations and extension functions

### 8a. File-level extension functions — group by receiver

```kotlin
// ✓ All Order extensions in one file, in stepdown order
// File: OrderExtensions.kt

fun Order.toSummary(): OrderSummary = OrderSummary(
    id = id,
    customer = customer.name,
    total = totalAmount(),
)

fun Order.isOverdue(now: Instant): Boolean = !isPaid() && placedAt.plus(GRACE_PERIOD).isBefore(now)

private val GRACE_PERIOD: Duration = Duration.ofDays(7)
```

### 8b. Don't scatter extension functions across the codebase

If `Order.toSummary()` lives in `OrderExtensions.kt`, `Order.isOverdue()` should live there too. If it grows past ~200 lines, split by *purpose* (e.g., `OrderQueryExtensions.kt`, `OrderRenderExtensions.kt`), not alphabetically.

### 8c. Package-level constants — colocate with consumers

```kotlin
// ✓ Constant lives next to the one place it's used
class OrderService {
    fun submit(...): Order { ... }

    fun cancel(...): Order { ... }

    companion object {
        private const val MAX_LINES_PER_ORDER = 100
    }
}
```

If a constant is used across files/packages, lift it to a domain object (`Order.MaxLines`) or a constants file in the same package. Don't bury it deep in a sibling utility class.

---

## 9. Companion objects

### 9a. At the bottom of the class

The Kotlin style guide places `companion object` at the bottom, *after* member declarations. This is the **opposite** of "instance variables at top" — the companion is not state, it's the class's class-level namespace.

```kotlin
class Order(...) {

    private var status: OrderStatus = OrderStatus.NEW

    fun submit(): SubmittedOrder { ... }

    fun cancel() { ... }

    companion object {
        const val MAX_LINES = 100
        fun create(customer: Customer): Order = Order(...)
    }
}
```

### 9b. Factory functions — named, not just `invoke`

```kotlin
// ✓ Explicit factory name
class Order private constructor(...) {
    companion object {
        fun fromCart(cart: Cart, customer: Customer): Order { ... }
    }
}

// Usage: Order.fromCart(cart, customer)
```

Avoid `invoke` operator overload for factories — it makes `Order(cart, customer)` look like a constructor call but isn't one.

---

## 10. Annotation layout

### 10a. One annotation per line for class-level / method-level

```kotlin
// ✓ Class-level — each on its own line
@Service
@Transactional(readOnly = true)
class OrderQueryService(...)

// ✓ Method-level — each on its own line
@PostMapping("/orders")
@PreAuthorize("hasRole('USER')")
@Transactional
fun submit(@RequestBody @Valid request: OrderRequest): ResponseEntity<Order> { ... }
```

### 10b. Parameter / field annotations — inline

```kotlin
// ✓ Parameter annotations on the same line
fun submit(@RequestBody @Valid request: OrderRequest): ResponseEntity<Order>

// ✓ Field-level (rare; usually constructor)
class Order(
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    val id: UUID,
)
```

### 10c. Use-site target — explicit when needed

```kotlin
class Order(
    @field:JsonProperty("order_id")        // ← targets the field, not the parameter
    val id: OrderId,
)
```

Use-site targets (`@field:`, `@get:`, `@param:`, `@property:`) appear on the same line as their annotation. Don't break across lines.

---

## 11. Imports

### 11a. No wildcards (with one exception)

```kotlin
// ✗ Wildcard hides which symbols are actually used
import org.springframework.web.bind.annotation.*

// ✓ Explicit imports
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RestController
```

**Exception**: assertion DSLs intended to be wildcarded (`org.assertj.core.api.Assertions.*`, `org.junit.jupiter.api.Assertions.*`). ktlint allows configuring a whitelist via `ij_kotlin_packages_to_use_import_on_demand`.

### 11b. Order

Kotlin official style: **single alphabetical list**, no grouping. ktlint enforces this. ktfmt too.

Don't manually group by `java.*`, `kotlin.*`, `com.company.*`, `org.*` — let the formatter do it.

---

## 12. Data classes — primary constructor is the API

```kotlin
// ✓ Data class — primary constructor is the entire definition
data class OrderSummary(
    val id: OrderId,
    val customer: String,
    val total: Money,
    val placedAt: Instant,
)
```

**Anti-patterns**:
- Adding methods that aren't `toString` / `equals` / `hashCode` / `copy` — if it has behaviour, it's not a data class.
- Mutable `var` fields in a data class — defeats the equality semantics.
- Inheritance into a data class — disallowed by the compiler; if you need it, you don't want a data class.

---

## 13. Sealed classes and interfaces

### 13a. Layout — declaration block on top, members below

```kotlin
sealed interface OrderEvent {
    val orderId: OrderId
    val occurredAt: Instant
}

data class OrderSubmitted(
    override val orderId: OrderId,
    override val occurredAt: Instant,
) : OrderEvent

data class OrderCancelled(
    override val orderId: OrderId,
    override val occurredAt: Instant,
    val reason: String,
) : OrderEvent

data class OrderShipped(
    override val orderId: OrderId,
    override val occurredAt: Instant,
    val trackingNumber: String,
) : OrderEvent
```

Keep the sealed root and all permitted subtypes in **one file**. The whole hierarchy is one concept; splitting it forces the reader to chase across files.

If the hierarchy grows past ~200 lines, that's a hint the events should themselves be split by sub-domain (e.g., separate `PaymentEvent` and `ShippingEvent` sealed roots).

---

## 14. Long argument lists at call sites

### 14a. Named arguments + one per line

```kotlin
// ✓ Long call — named, one per line, trailing comma
createOrder(
    customer = currentCustomer(),
    lines = cart.lines,
    shipping = checkoutForm.shippingAddress,
    billing = checkoutForm.billingAddress ?: checkoutForm.shippingAddress,
    placedAt = clock.instant(),
)
```

### 14b. Short calls — one line, positional is fine

```kotlin
orderRepository.save(order)
auditLog.record("submitted", order.id)
```

### 14c. Mixed — when 2 of 5 args matter

Named args are not all-or-nothing:

```kotlin
// ✓ The flag-like booleans named; the rest positional
slf4j.atInfo()
    .addKeyValue("orderId", orderId)
    .setMessage("Order submitted")
    .log()
```

---

## 15. Coroutines — async blocks

### 15a. `suspend` declaration — same as regular functions

```kotlin
suspend fun submit(orderId: OrderId): SubmittedOrder { ... }

suspend fun fetchAll(): List<Order> = withContext(Dispatchers.IO) {
    orderRepository.findAll()
}
```

### 15b. `coroutineScope` / `withContext` — blank line if non-trivial

```kotlin
suspend fun processBatch(orders: List<Order>): List<Result> = coroutineScope {
    orders.map { order ->
        async {
            processOne(order)
        }
    }.awaitAll()
}
```

For multi-line coroutine bodies, prefer block body over expression body — the structure is more visible.

---

## 16. Kotlin file structure

A Kotlin file is **not** required to contain exactly one public class (unlike Java). A `.kt` file can contain:
- A class + its companion + its extension functions (canonical case).
- A sealed hierarchy + helpers (one concept, one file — see §13).
- A collection of top-level extension functions on one receiver (`OrderExtensions.kt`).
- A package-level set of typealiases + constants (`OrderTypes.kt`).

**House style**: file name is `PascalCase.kt` matching the dominant concept. For multi-concept files, name by *theme* (`OrderExtensions.kt`), not arbitrary plural (`Helpers.kt` is the anti-pattern — see `clean-code-naming`).

**Don't** mix unrelated classes in one file because they're "small enough" — colocation implies conceptual affinity.

---

## Cross-references

| Need | File |
|---|---|
| Underlying universal rules | `general-formatting-rules.md` |
| Spring controller / `application.yml` / JPA layout | `spring-boot-formatting.md` |
| ktlint vs. ktfmt, `.editorconfig`, pre-commit / CI gate | `tooling-formatting.md` |
| Class / member naming (`OrderEntity` → `Order`, `*Helper` → `*er`) | sibling skill `clean-code-naming` |
| Function size & stepdown narrative inside a method | sibling skill `clean-code-functions` |
