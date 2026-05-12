# GoF — Kotlin Idioms

Per-pattern Kotlin status. For each pattern: which language feature subsumes it (if any), or the idiomatic Kotlin form when the pattern still applies. The patterns themselves are defined in `theory.md`.

The 70/30 split: roughly 70% of GoF patterns are language features in Kotlin; the remaining 30% still apply with leaner forms than Java versions.

---

## Creational

### 1. Singleton — `object` keyword

Kotlin's `object` is a thread-safe, lazy-initialised singleton. No ceremony.

```kotlin
object PricingPolicy {
    private const val TAX_RATE = 0.21
    fun applyTax(amount: Money): Money = amount * (1 + TAX_RATE)
}

PricingPolicy.applyTax(money)
```

Thread-safe via JVM class-loading guarantees. Lazy by default.

**In Spring**, the default bean scope IS Singleton — managed by the container with explicit dependency declaration. Prefer Spring's DI singletons over manual `object` for anything that needs collaborators.

**Anti-pattern:** `class X private constructor() { companion object { @JvmStatic val INSTANCE = X() } }` is the Java leftover. Use `object`.

---

### 2. Builder — named arguments / `apply` / DSL

Kotlin replaces most Builder cases with named arguments + default values:

```kotlin
class HttpRequest(
    val url: String,
    val method: HttpMethod = HttpMethod.GET,
    val headers: Map<String, String> = emptyMap(),
    val body: ByteArray? = null,
    val timeout: Duration = Duration.ofSeconds(10),
    val retries: Int = 0,
)

val req = HttpRequest(url = "...", method = HttpMethod.POST, retries = 3)
```

The constructor IS the Builder. No fluent builder class needed.

For mutable builder-like APIs (e.g., when wrapping a Java fluent builder), `apply` is the idiomatic shortcut:

```kotlin
val request = HttpRequest.Builder().apply {
    url("...")
    method(HttpMethod.POST)
    header("Auth", "Bearer ...")
}.build()
```

For genuinely complex repeated construction (HTML, configuration, Gradle), build a type-safe DSL:

```kotlin
val request = http {
    url = "..."
    method = HttpMethod.POST
    headers { "Auth" to "Bearer ..." }
}
```

Used in Gradle DSL, kotlinx.html, Ktor routing. Heavy machinery — build a DSL only for repeated complex construction.

---

### 3. Factory Method — `companion fun create(...)`

```kotlin
class Order private constructor(...) {
    companion object {
        fun create(items: List<OrderItem>): Order {
            require(items.isNotEmpty()) { "Order must have at least one item" }
            return Order(...)
        }
    }
}

val order = Order.create(items)
```

For static-like factories, no GoF inheritance machinery — just companion methods. For factories that need DI'd collaborators, use a Spring `@Bean` or a `@Service` factory.

`operator fun invoke()` lets a factory look like construction:

```kotlin
class Order private constructor(...) {
    companion object {
        operator fun invoke(items: List<OrderItem>): Order { ... }
    }
}

val order = Order(items)   // calls Order.invoke
```

---

### 4. Abstract Factory — sealed interface + `data object`

```kotlin
sealed interface PaymentProcessorFactory {
    fun gateway(): PaymentGateway
    fun receipt(): ReceiptRenderer

    data object Stripe : PaymentProcessorFactory {
        override fun gateway() = StripeGateway()
        override fun receipt() = StripeReceiptRenderer()
    }

    data object Adyen : PaymentProcessorFactory {
        override fun gateway() = AdyenGateway()
        override fun receipt() = AdyenReceiptRenderer()
    }
}
```

Each `data object` is a complete factory for one family. Adding `Braintree` adds one `data object`.

**In Spring**, `@Profile` + `@ConditionalOnProperty` + DI replaces most Abstract Factory cases (see `spring-boot.md`).

---

### 5. Prototype — `data class.copy()`

```kotlin
data class OrderTemplate(val items: List<OrderItem>, val deliveryDays: Int)

val standard = OrderTemplate(items, deliveryDays = 5)
val express = standard.copy(deliveryDays = 1)
```

`copy()` on `data class` IS Prototype. No `clone()` ceremony, no shallow/deep copy gotchas (immutable fields, structural sharing).

---

## Structural

### 6. Adapter — wrapper class or extension function

When you don't own the adaptee:

```kotlin
class LegacyOrderAdapter(private val legacy: LegacyOrderSystem) : OrderRepository {
    override fun findById(id: OrderId): Order? =
        legacy.fetch(id.value.toString())?.toDomainOrder()

    override fun save(order: Order): Order = order.also {
        legacy.persist(it.toLegacyRecord())
    }
}
```

For one-method adaptation:

```kotlin
fun ResultSet.toOrder(): Order = Order(
    id = OrderId(UUID.fromString(getString("id"))),
    customerId = CustomerId(UUID.fromString(getString("customer_id"))),
    ...
)
```

Adapter is essentially the Anti-Corruption Layer pattern in DDD (see `ddd-context-mapping`) and is the canonical shape of any vendor-SDK wrapper (see `clean-code-boundaries`).

---

### 7. Decorator — `by` delegation or extension function

Kotlin's class delegation is the canonical Decorator:

```kotlin
interface OrderRepository {
    fun findById(id: OrderId): Order?
    fun save(order: Order): Order
}

class CachingOrderRepository(
    private val inner: OrderRepository,
    private val cache: Cache<OrderId, Order>,
) : OrderRepository by inner {
    override fun findById(id: OrderId): Order? =
        cache.get(id) { inner.findById(id) }
}
```

`by inner` delegates all methods to `inner` except those overridden. Less ceremony than manual delegation; no missing-method-on-wrapper bugs.

For stateless decoration, an extension function is even leaner:

```kotlin
fun OrderRepository.findByIdOrThrow(id: OrderId): Order =
    findById(id) ?: throw NotFoundException("Order", id)
```

Doesn't modify the class; client opts in by importing.

---

### 8. Facade — regular service class

Kotlin doesn't add ceremony; it's just a service class hiding multiple collaborators:

```kotlin
@Service
class OrderCheckoutFacade(
    private val pricing: PricingService,
    private val tax: TaxCalculator,
    private val inventory: InventoryService,
    private val payment: PaymentGateway,
    private val notifications: NotificationService,
) {
    fun checkout(cart: Cart, paymentMethod: PaymentMethod): CheckoutResult {
        val priced = pricing.priceCart(cart)
        val withTax = tax.apply(priced)
        inventory.reserve(cart.items)
        val payRes = payment.charge(withTax.total, paymentMethod)
        if (payRes.isSuccess) notifications.sendReceipt(cart.customerId, withTax)
        return CheckoutResult(...)
    }
}
```

Most Spring `@Service` classes are Facades. The pattern is so common it doesn't get a special name in conversation.

---

### 9. Composite — sealed hierarchy

```kotlin
sealed interface FileSystemNode {
    val name: String
    fun size(): Long
}

data class File(override val name: String, val bytes: Long) : FileSystemNode {
    override fun size() = bytes
}

data class Directory(
    override val name: String,
    val children: List<FileSystemNode>,
) : FileSystemNode {
    override fun size() = children.sumOf { it.size() }
}
```

Recursive `size()` works uniformly across `File` and `Directory`. Sealed gives you compile-time exhaustiveness.

---

### 10. Bridge — interface + concrete implementation

The pattern hasn't disappeared in Kotlin; it's still useful when two axes vary independently.

```kotlin
interface MessageSender {
    fun send(to: String, msg: String)
}

class SmsSender(...) : MessageSender { ... }
class EmailSender(...) : MessageSender { ... }
class WhatsAppSender(...) : MessageSender { ... }

abstract class NotificationDispatcher(protected val sender: MessageSender) {
    abstract fun dispatch(notification: Notification)
}

class StandardDispatcher(sender: MessageSender) : NotificationDispatcher(sender) {
    override fun dispatch(n: Notification) { sender.send(n.recipient, n.body) }
}

class RetryingDispatcher(sender: MessageSender, val retries: Int) : NotificationDispatcher(sender) {
    override fun dispatch(n: Notification) {
        repeat(retries) { try { sender.send(n.recipient, n.body); return } catch (_: Exception) {} }
    }
}
```

Two axes vary independently (dispatcher × sender). 3 senders × 2 dispatchers = 6 combinations, but only 5 classes.

---

### 11. Proxy — Spring `@Transactional` / `by` delegation

Spring weaves Proxy automatically via `@Transactional`, `@Cacheable`, `@Async`:

```kotlin
@Service
class OrderService(...) {
    @Transactional
    fun placeOrder(req: PlaceOrderRequest): Order { ... }
}
```

Spring wraps `OrderService` in a CGLIB / JDK dynamic proxy that opens / commits the transaction around the method. Callers see `OrderService`; Spring sees a proxy.

For non-Spring proxies, `by` delegation is the closest:

```kotlin
class LoggingRepository(private val inner: OrderRepository) : OrderRepository by inner {
    override fun save(order: Order): Order {
        log.info("saving order ${order.id}")
        return inner.save(order)
    }
}
```

Don't write Proxy by hand in business code. Spring or `by delegation` covers it.

---

### 12. Flyweight — `value class` or interning

Rarely needed in modern garbage-collected runtimes. JVM string interning, `@JvmInline value class` (no heap allocation), and `data class` equality usually suffice:

```kotlin
@JvmInline value class CurrencyCode(val value: String) {
    init { require(value.length == 3 && value.uppercase() == value) }
}
```

`CurrencyCode` is a value class — no heap allocation per instance, just a primitive `String` at the bytecode level.

For genuinely heavy-cached shared objects (e.g., character-rendering glyphs in a UI engine), a companion factory + map approximates Flyweight. Almost never needed in business code.

---

## Behavioural

### 13. Strategy — function type / lambda

Strategy in Kotlin is a function type:

```kotlin
class PricingService {
    fun price(cart: Cart, discount: (Cart) -> Money): Money {
        val subtotal = cart.subtotal()
        val reduction = discount(cart)
        return subtotal - reduction
    }
}

pricing.price(cart, discount = { Money.ZERO })
pricing.price(cart, discount = ::standardDiscount)
pricing.price(cart, discount = ::vipDiscount)
```

`Strategy = (Input) -> Output`. No interface needed unless you want named, DI-injected strategies.

For ceremony cases (named impls, DI-injected, enumerable), use sealed interface (see `data object` Strategy under Polymorphism).

---

### 14. Observer — `Flow` / `StateFlow` / `ApplicationEventPublisher`

```kotlin
@Service
class OrderService(private val events: ApplicationEventPublisher) {
    fun place(req: PlaceOrderRequest) {
        ...
        events.publishEvent(OrderPlaced(...))
    }
}

@Component
class OrderEmailNotifier(...) {
    @ApplicationModuleListener
    fun on(event: OrderPlaced) { ... }
}
```

Coroutine `Flow` / `StateFlow` for in-process reactive streams:

```kotlin
val orderEvents: Flow<OrderEvent> = orderService.events
orderEvents.collect { event -> handle(event) }
```

Spring events handle the listener registration plumbing. Don't write `Observable`/`Observer` interfaces by hand.

---

### 15. Command — sealed interface

```kotlin
sealed interface OrderCommand {
    val orderId: OrderId

    data class Place(override val orderId: OrderId, val items: List<OrderItem>) : OrderCommand
    data class Cancel(override val orderId: OrderId, val reason: String) : OrderCommand
    data class Ship(override val orderId: OrderId, val tracking: TrackingNumber) : OrderCommand
}
```

This is the CQRS write-side pattern (see `cqrs-implementation`). Command types as sealed gives exhaustive dispatch:

```kotlin
fun handle(cmd: OrderCommand) = when (cmd) {
    is OrderCommand.Place -> placeHandler.handle(cmd)
    is OrderCommand.Cancel -> cancelHandler.handle(cmd)
    is OrderCommand.Ship -> shipHandler.handle(cmd)
}
```

---

### 16. Iterator — `Iterable<T>` / `Sequence<T>`

Built-in. Custom Iterator implementation almost never needed:

```kotlin
listOf(1, 2, 3).forEach { ... }

generateSequence(1) { it + 1 }
    .filter { it % 2 == 0 }
    .take(100)
    .forEach { ... }
```

`Iterable` for eager / re-iterable; `Sequence` for lazy streaming (analogous to Java `Stream`).

---

### 17. Template Method — abstract class with `final` + `open` (use sparingly)

```kotlin
abstract class BatchJob {
    fun run() {                       // skeleton fixed (Kotlin's default `final`)
        log.info("starting ${jobName()}")
        val records = loadRecords()
        records.forEach { process(it) }
        cleanup()
        log.info("finished ${jobName()}")
    }

    protected abstract fun jobName(): String
    protected abstract fun loadRecords(): List<Record>
    protected abstract fun process(record: Record)
    protected open fun cleanup() { /* default no-op */ }
}
```

Modern alternative: pass functions to a top-level `runBatch(name, load, process, cleanup)` — composition over inheritance, no Template Method needed.

Use Template Method only when the steps share state through `protected` fields, or when subclassing is the natural fit.

---

### 18. Chain of Responsibility — list + first-match

```kotlin
fun interface RequestHandler {
    fun handle(req: Request): Response?    // null = "not my problem"
}

class HandlerChain(private val handlers: List<RequestHandler>) {
    fun handle(req: Request): Response =
        handlers.firstNotNullOfOrNull { it.handle(req) }
            ?: throw NotFoundException()
}

HandlerChain(listOf(
    AuthHandler(),
    AdminRouteHandler(),
    PublicRouteHandler(),
)).handle(req)
```

Servlet filter chains in Spring are this pattern, applied to HTTP requests.

---

### 19. State — sealed class + `when` (functional FSM)

```kotlin
sealed class OrderStatus {
    abstract fun cancel(reason: String): OrderStatus

    data object Draft : OrderStatus() {
        override fun cancel(reason: String) = Cancelled(reason)
    }

    data object Submitted : OrderStatus() {
        override fun cancel(reason: String) = Cancelled(reason)
    }

    data object Shipped : OrderStatus() {
        override fun cancel(reason: String): Nothing =
            throw IllegalStateException("Cannot cancel shipped order")
    }

    data class Cancelled(val reason: String) : OrderStatus() {
        override fun cancel(reason: String) = this
    }
}
```

Transitions live on the states themselves. Idiomatic and exhaustive.

For complex FSMs (5+ states, 10+ transitions, guards), Spring State Machine is the heavyweight tool — but for most domain state machines, sealed classes are the right level.

---

### 20. Mediator — orchestrator service

```kotlin
@Service
class CheckoutOrchestrator(
    private val pricing: PricingService,
    private val inventory: InventoryService,
    private val payment: PaymentGateway,
    private val notifications: NotificationService,
) {
    fun checkout(cart: Cart, paymentMethod: PaymentMethod): CheckoutResult { ... }
}
```

`Cart`, `PricingService`, `InventoryService`, etc. don't reference each other directly — the orchestrator mediates. Same idea as Application Service in DDD; same shape as Facade.

---

### 21. Memento — `data class` snapshot

```kotlin
class TextEditor {
    private var content: String = ""
    private val history = mutableListOf<Snapshot>()

    data class Snapshot(val content: String, val timestamp: Instant)

    fun edit(newContent: String) {
        history += Snapshot(content, Instant.now())
        content = newContent
    }

    fun undo(): String? {
        val last = history.removeLastOrNull() ?: return null
        content = last.content
        return content
    }
}
```

`data class` provides equality, copy, `toString` for free. Memento with no ceremony.

---

### 22. Visitor — **obsolete**, use sealed + exhaustive `when`

In Kotlin, classical Visitor is replaced by sealed hierarchies + exhaustive `when`. The reason: sealed types let you add new operations as new functions over the type, without modifying the type, with compile-time exhaustiveness:

```kotlin
sealed class Shape
data class Circle(val r: Double) : Shape()
data class Rectangle(val w: Double, val h: Double) : Shape()

fun area(shape: Shape): Double = when (shape) {
    is Circle -> PI * shape.r * shape.r
    is Rectangle -> shape.w * shape.h
}

fun perimeter(shape: Shape): Double = when (shape) {
    is Circle -> 2 * PI * shape.r
    is Rectangle -> 2 * (shape.w + shape.h)
}
```

Adding `Triangle` to `Shape` causes a compile error in every `when` until handled. That's exhaustiveness + structural typing — strictly better than Visitor's double-dispatch.

**Don't write classical Visitor in Kotlin.** It's a Java workaround for a problem Kotlin doesn't have.

---

### 23. Interpreter — type-safe DSL

```kotlin
@DslMarker annotation class SqlDsl

@SqlDsl
class SelectBuilder {
    private val columns = mutableListOf<String>()
    private var from: String = ""
    private val wheres = mutableListOf<String>()

    fun col(name: String) { columns += name }
    fun from(table: String) { from = table }
    fun where(condition: String) { wheres += condition }

    fun build(): String = "SELECT ${columns.joinToString()} FROM $from" +
        if (wheres.isEmpty()) "" else " WHERE ${wheres.joinToString(" AND ")}"
}

fun select(block: SelectBuilder.() -> Unit) = SelectBuilder().apply(block).build()

val q = select {
    col("id"); col("name"); col("email")
    from("users")
    where("status = 'ACTIVE'")
}
```

Examples in the wild: Gradle DSL, kotlinx.html, Ktor routing, Exposed. Heavy machinery; build only when you genuinely need a DSL.

---

## Status summary table

| Category | Pattern | Kotlin form | Verdict |
|---|---|---|---|
| Creational | Singleton | `object` | language feature |
| | Builder | named args / `apply` / DSL | mostly unnecessary |
| | Factory Method | `companion fun create()` | trivial |
| | Abstract Factory | sealed interface + `data object` | useful for families |
| | Prototype | `data class.copy()` | language feature |
| Structural | Adapter | wrapper class / extension fn | useful, especially for ACL |
| | Decorator | `by` delegation | language feature |
| | Facade | service class | unnamed but common |
| | Composite | sealed hierarchy | language feature |
| | Bridge | interface + impl | still applies |
| | Proxy | Spring AOP / `by` delegation | framework feature |
| | Flyweight | `value class` / interning | rarely needed |
| Behavioural | Strategy | function type | language feature |
| | Observer | `Flow` / Spring events | framework feature |
| | Command | sealed interface | language feature |
| | Iterator | `Iterable` / `Sequence` | language feature |
| | Template Method | abstract class | use sparingly |
| | Chain of Responsibility | list + first-match | trivial |
| | State | sealed class + `when` | language feature |
| | Mediator | orchestrator service | regular service |
| | Memento | `data class` snapshot | language feature |
| | Visitor | sealed + exhaustive `when` | **obsolete** — use sealed |
| | Interpreter | type-safe DSL | advanced, rarely needed |

**General rule:** ~70% of GoF patterns are subsumed by Kotlin language features. The remaining ~30% (Adapter, Bridge, Facade, Abstract Factory, Mediator, Template Method, Interpreter) still apply but with less ceremony than Java versions.

---

## What Kotlin does *not* solve

- **Pattern misapplication.** Kotlin won't tell you that `OrderUtils` is a Pure Fabrication anti-pattern, or that your sealed hierarchy with one variant is premature. The discipline is yours.
- **Deciding which pattern fits.** Kotlin removes ceremony from many patterns; you still need to know when each is the right shape.
- **Java-flavoured Kotlin from translation.** Code mechanically converted from Java will have hand-rolled Singletons, fluent Builders, classical Visitors. The migration step is yours; see `bad-practices.md` for the catalogue.
