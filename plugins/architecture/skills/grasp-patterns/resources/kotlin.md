# GRASP — Kotlin Idioms

How each GRASP pattern looks in idiomatic Kotlin. The patterns are language-agnostic; Kotlin's features (sealed hierarchies, function types, `by` delegation, extension functions, `value class`, scope functions) just change the syntax of expressing them.

For pattern definitions, see `theory.md`. For Spring conventions, see `spring-boot.md`. For violations and fixes, see `bad-practices.md`.

---

## 1. Information Expert in Kotlin

The Info Expert refactor in Kotlin pushes computation onto the data-owning class. Kotlin makes this cheap:

```kotlin
class Order(
    val id: OrderId,
    private val items: List<OrderItem>,
) {
    fun total(): Money = items.fold(Money.ZERO) { acc, item -> acc + item.subtotal() }
}

class OrderItem(
    val productId: ProductId,
    val quantity: Int,
    val unitPrice: Money,
) {
    fun subtotal(): Money = unitPrice * quantity
}

@Service
class OrderService(private val orders: OrderRepository) {
    fun totalFor(orderId: OrderId): Money =
        orders.findById(orderId)?.total() ?: throw NotFoundException(orderId)
}
```

The service doesn't reach inside `Order` — it asks `order.total()`. The data and the operation live together. Tests for `Order.total()` don't need Spring or a repository.

### Kotlin features that lower the cost

- **Primary-constructor properties** put the data right next to the methods that use it.
- **Expression-body functions** (`fun total(): Money = ...`) make one-line operations terse.
- **Extension functions** let you push behaviour onto a type you don't own:

```kotlin
fun List<OrderItem>.total(): Money = fold(Money.ZERO) { acc, item -> acc + item.subtotal() }
```

If `OrderItem` is a `data class` in another module, this extension keeps the Info Expert principle without modifying that module.

### Trap: anaemic `data class` with logic in the service

Kotlin's `data class` is so convenient for DTOs that teams use it for domain types too — and then put the behaviour in services. That's the anaemic-domain anti-pattern: Info Expert violated by default. Use a regular `class` for domain types with behaviour; reserve `data class` for value-objects and DTOs.

---

## 2. Creator in Kotlin

Companion-object factories and aggregate-internal construction are the canonical Creator implementations:

```kotlin
class Order private constructor(
    val id: OrderId,
    private val items: MutableList<OrderItem>,
) {
    fun addItem(productId: ProductId, qty: Int, price: Money) {
        // Order is Creator of OrderItem — it aggregates and has the context
        items += OrderItem(productId, qty, price)
    }

    companion object {
        // companion is Creator for Order itself
        fun create(id: OrderId, customerId: CustomerId, items: List<OrderItem>): Order {
            require(items.isNotEmpty()) { "Order must have at least one item" }
            return Order(id, items.toMutableList())
        }
    }
}
```

`private constructor` forbids external `new`; `Order.create(...)` is the only path. Now there are no scattered `new Order(...)` calls.

### `operator fun invoke()` for the smoothest factory

If you want `Order(id, items)` to look like construction but go through a factory:

```kotlin
class Order private constructor(...) {
    companion object {
        operator fun invoke(id: OrderId, items: List<OrderItem>): Order { ... }
    }
}

val order = Order(orderId, items)   // calls Order.invoke
```

Used judiciously, this gives factory semantics with constructor ergonomics.

### Trap: leaking mutation

If `Order.addItem(...)` is the Creator of `OrderItem`, exposing `items` as `MutableList<OrderItem>` undoes the encapsulation — external code can add items directly, bypassing the Creator. Always expose `items: List<OrderItem>` (read-only view) and keep the mutable list private.

---

## 3. Controller in Kotlin

Spring's `@RestController` is the canonical Controller (see `spring-boot.md`). In pure Kotlin (no Spring), a Controller is just a class that takes a request type, delegates, returns a response type:

```kotlin
class PlaceOrderHandler(
    private val orders: OrderRepository,
    private val pricing: PricingService,
    private val events: EventPublisher,
) {
    fun handle(cmd: PlaceOrderCommand): OrderId {
        val priced = pricing.priceCart(cmd.cart)
        val order = Order.create(OrderId.new(), cmd.customerId, priced.items)
        orders.save(order)
        events.publish(OrderPlaced(order.id, order.total()))
        return order.id
    }
}
```

The handler validates the command, orchestrates collaborators, returns a result. **No business logic computed here** — that's on `Order`, `pricing`, etc. (Info Expert).

### Use-Case Controller as a CQRS Command Handler

If the system is CQRS-shaped, the Use-Case Controller IS the command handler (see `cqrs-implementation`):

```kotlin
sealed interface OrderCommand {
    data class Place(val cart: Cart, val customerId: CustomerId) : OrderCommand
    data class Cancel(val orderId: OrderId, val reason: String) : OrderCommand
}

@Service
class PlaceOrderHandler(...) {
    fun handle(cmd: OrderCommand.Place): OrderId { ... }
}
```

One class per use case, one reason to change per class. SRP + Controller GRASP at the same time.

---

## 4. Low Coupling in Kotlin

The Kotlin idioms for Low Coupling:

### `ApplicationEventPublisher` / coroutine `Flow` / domain events

The canonical low-coupling tool: emit an event; let listeners subscribe. The publisher doesn't know who listens:

```kotlin
@Service
class PlaceOrderHandler(private val events: ApplicationEventPublisher) {
    fun handle(cmd: PlaceOrderCommand): OrderId {
        val order = ...
        orders.save(order)
        events.publishEvent(OrderPlaced(order.id, order.customerEmail))
        return order.id
    }
}

@Component
class OrderEmailNotifier(private val email: EmailSender) {
    @ApplicationModuleListener
    fun on(event: OrderPlaced) {
        email.send(event.customerEmail, "Your order")
    }
}
```

Adding an SMS notifier next month adds a class. Nothing in `PlaceOrderHandler` changes.

### Function types as light dependencies

For one-shot variation, a function type is the lowest-coupling form of dependency:

```kotlin
class PricingService(
    private val taxRate: (Country) -> BigDecimal,
) {
    fun price(amount: Money, country: Country): Money = amount * (BigDecimal.ONE + taxRate(country))
}
```

In production: pass `taxRateRepo::lookup`. In tests: pass `{ BigDecimal("0.20") }`. No interface, no class — minimal coupling surface.

### `internal` visibility to confine coupling

If two classes need to know each other but only within a module, mark the boundary `internal`:

```kotlin
// module: order
internal class OrderPriceCalculator(...) { ... }

class PlaceOrderHandler(
    private val calc: OrderPriceCalculator,   // internal — fine within the module
) { ... }
```

Cross-module coupling becomes a compile error. Forces consumers outside the module to go through a public interface.

### The trade-off

Events / function types lower coupling but also hide control flow. In a deep event chain, "what happens when X" requires hunting subscribers. Apply where reactions are genuinely independent; don't apply where a direct call is the honest design.

---

## 5. High Cohesion in Kotlin

Kotlin's "many small classes are cheap" property is the main lever. Strategies:

### Primary-constructor properties make small classes trivial

```kotlin
class OrderPricing { fun total(order: Order): Money { ... } }
class OrderEmailFormatter { fun format(order: Order): String { ... } }
class OrderCsvExporter { fun export(orders: List<Order>): ByteArray { ... } }
```

Three one-method classes. Each cohesion: maximum. Compare to one `OrderUtils` with the same three methods, where the methods touch different fields and have nothing in common.

### Top-level functions as the ultimate single-purpose class

When the responsibility is a pure function with no state, skip the class:

```kotlin
// In pricing.kt
fun applyVat(amount: Money, country: Country): Money = ...
fun applyDiscount(amount: Money, percentage: BigDecimal): Money = ...
```

Top-level functions are the highest-cohesion form possible — one purpose, no surface beyond the signature.

### Extension functions to keep behaviour close to data without bloating the class

```kotlin
fun Order.canBeCancelled(): Boolean = status == OrderStatus.Draft || status == OrderStatus.Submitted
```

The behaviour lives "on" `Order` semantically but doesn't enlarge the class. Use sparingly — extension functions can fragment cohesion if scattered across files.

### The smell of violating it (Kotlin-specific)

`object`-based "utility singletons" (`object OrderUtils { fun calculateTotal(...); fun formatForEmail(...) }`) — the Kotlin form of `Util`/`Helper`. Same anti-pattern, same fix: split into focused classes / top-level functions.

---

## 6. Polymorphism in Kotlin

Sealed hierarchies plus exhaustive `when` are the canonical Polymorphism toolkit. This pattern covers GRASP Polymorphism + SOLID OCP + GoF Strategy/State simultaneously.

```kotlin
sealed interface DeliveryMethod {
    fun estimatedDays(): Int
    fun price(weight: Kilograms, distance: Kilometres): Money

    data object Standard : DeliveryMethod {
        override fun estimatedDays() = 5
        override fun price(weight: Kilograms, distance: Kilometres) =
            Money.eur(5_00) + Money.eur((distance.value * 1).toLong())
    }

    data object Express : DeliveryMethod {
        override fun estimatedDays() = 1
        override fun price(weight: Kilograms, distance: Kilometres) =
            Money.eur(20_00) + Money.eur((distance.value * 3).toLong())
    }
}
```

Adding `Overnight` is adding one `data object`. The compiler enforces exhaustiveness; no `when` to chase.

### Function-type polymorphism for stateless variation

If the variation is "what algorithm runs here" and not "what kind of thing am I", a function type beats a sealed hierarchy:

```kotlin
fun price(cart: Cart, discount: (Cart) -> Money): Money =
    cart.subtotal() - discount(cart)
```

Choose between forms:

- **Sealed hierarchy** when the variants need to be named, DI-injected, or enumerated.
- **Function type** when the variation is per-call and the strategies don't need identity.

---

## 7. Pure Fabrication in Kotlin

A Pure Fabrication is just a class that holds a focused responsibility not belonging to any domain entity. Kotlin doesn't have a special idiom — the discipline is naming:

```kotlin
class InvoicePdfRenderer(...) {
    fun render(order: Order): ByteArray { ... }
}

class TaxCalculator(private val rates: TaxRateProvider) {
    fun apply(amount: Money, country: Country): Money { ... }
}

class OrderEmailFormatter {
    fun format(order: Order): String { ... }
}
```

Each has one responsibility, names its purpose, doesn't pollute domain entities.

### The Pure-Fabrication-as-`@Service` shortcut in Spring

In Spring, most `@Service` beans are Pure Fabrications. `PricingService`, `NotificationService`, `OrderEmailNotifier` — none are domain entities; all are fabrications that hold focused orchestration responsibilities. This is fine and idiomatic. The trap is `OrderService` as a god service — that's a fabrication with too many responsibilities. (See `bad-practices.md`.)

### Kotlin features that support clean fabrications

- `internal` for module-private fabrications that aren't part of the public surface
- `object` for stateless fabrications (a single global instance — but be careful, see `gof-patterns` Singleton notes)
- Constructor injection for dependencies — keeps the fabrication testable and substitutable

---

## 8. Indirection in Kotlin

The Indirection pattern in Kotlin is interface-based, exactly like Java, but the syntax is cheaper:

### Domain port + infrastructure adapter

```kotlin
// domain/
interface EmailSender {
    fun send(to: Email, subject: String, body: String)
}

@Service
class OrderEmailNotifier(private val email: EmailSender) { ... }

// infrastructure/
@Component
class SmtpEmailSender(...) : EmailSender { ... }

// tests/
class FakeEmailSender : EmailSender {
    val sent = mutableListOf<SentEmail>()
    override fun send(to: Email, subject: String, body: String) { sent += SentEmail(to, subject, body) }
}
```

Three implementations of the same interface, none knowing about the others. `OrderEmailNotifier` depends on the indirection.

### Function-type indirection (no interface needed)

For one-method indirection roles, skip the interface:

```kotlin
class OrderEmailNotifier(
    private val send: (Email, String, String) -> Unit,
) { ... }
```

In tests: `OrderEmailNotifier(send = { _, _, _ -> })`. In Spring: `OrderEmailNotifier(send = emailSender::send)` via `@Bean` config.

### `by delegation` for delegating Indirection

```kotlin
class CachingOrderRepository(
    private val inner: OrderRepository,
    private val cache: Cache<OrderId, Order>,
) : OrderRepository by inner {
    override fun findById(id: OrderId): Order? = cache.get(id) { inner.findById(id) }
}
```

The caching wrapper delegates everything to `inner` except `findById`. `OrderRepository` is the indirection; the wrapper is itself an indirection over the inner one. Composition without ceremony.

---

## 9. Protected Variations in Kotlin

PV is essentially Indirection + intent ("this seam exists *because* we expect change here"). The Kotlin idioms are the same as Indirection; the discipline is in *where* you place the seam.

### Vendor SDK wrapped behind a domain port

```kotlin
// domain/
interface PaymentGateway {
    fun charge(amount: Money, customer: Customer): Result<TransactionId>
    fun refund(transactionId: TransactionId): Result<RefundReceipt>
}

// infrastructure/stripe/
@Component
@Profile("!test")
class StripePaymentGateway(...) : PaymentGateway {
    override fun charge(amount: Money, customer: Customer): Result<TransactionId> = runCatching {
        stripeClient.charges.create(...).let { TransactionId(it.id) }
    }
}

// infrastructure/fake/
@Component
@Profile("test")
class FakePaymentGateway : PaymentGateway { ... }
```

Migrating Stripe → Adyen: write `AdyenPaymentGateway : PaymentGateway`, swap profile. No domain code touches.

### `Result<T>` as PV against exception-shape changes

If a third-party SDK throws diverse exceptions you don't want leaking into business logic, wrap with `runCatching` / `Result<T>`:

```kotlin
override fun charge(amount: Money, customer: Customer): Result<TransactionId> = runCatching {
    stripeClient.charges.create(...)
}.mapCatching { TransactionId(it.id) }
```

The domain depends on `Result<TransactionId>`; Stripe-specific exceptions stay inside the adapter. Stripe could rename its exception hierarchy — domain code wouldn't notice.

### `value class` to protect against primitive obsession

```kotlin
@JvmInline value class OrderId(val value: UUID)
@JvmInline value class CustomerId(val value: UUID)
```

If you decide tomorrow that order IDs are no longer UUIDs but ULIDs, the change is in one place — the `value class` definition. Code that takes `OrderId` doesn't care about the underlying representation. Protected Variations at the type-system level.

### The discipline

Apply PV at boundaries where you *predict* change:

- Vendor SDKs (Stripe, AWS SDK, Slack, sendgrid)
- Persistence stores when polyglot persistence is plausible
- Communication protocols (REST vs gRPC vs Kafka)
- Identity primitives (UUID today, ULID tomorrow)

Don't apply at every internal seam — every interface is a cost.

---

## Kotlin features that serve multiple GRASP patterns

| Feature | Patterns served |
|---|---|
| Primary-constructor properties | Information Expert (data + behaviour together), Creator (concise factories) |
| `companion object` with factory | Creator (`Order.create(...)`), Protected Variations (private constructor) |
| `sealed interface` / `data object` | Polymorphism, Protected Variations |
| Function types | Low Coupling (light dependency), Indirection (no-interface form), Polymorphism (per-call variation) |
| `by` delegation | Indirection (delegate all but override the chosen method), Pure Fabrication composition |
| Extension functions | High Cohesion (push behaviour onto data without bloating the class), Information Expert (when you don't own the class) |
| `value class` | Protected Variations (encapsulate the primitive shape), LSP-style substitution safety |
| `internal` visibility | High Cohesion + module-scope encapsulation, contains coupling |
| Top-level functions | High Cohesion (single-purpose), Pure Fabrication (stateless) |
| `Result<T>` / `runCatching` | Indirection (ACL boundary), Protected Variations (against exception shape changes) |

---

## What Kotlin does *not* solve

- **Anaemic domain.** Kotlin's `data class` is so convenient for DTOs that domain types end up as `data class` too, with all logic in services. Info Expert violated by default. Use regular `class` for domain types.
- **God services.** A Kotlin god service is still a god service. SRP + High Cohesion violations.
- **Over-application of PV.** Sealed hierarchies and interfaces are cheap to write — exactly why teams over-apply them. The discipline is in knowing where the seam earns its keep.
- **Coupling hidden in lambdas.** Function-type dependencies can hide who's calling whom. In a maze of `(X) -> Y` parameters, debugging gets hard. Trade-off the same as event-driven indirection.
