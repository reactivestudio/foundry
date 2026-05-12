# GRASP — Bad Practices Catalogue

Diagnostic file. Each entry: the smell, which GRASP pattern it violates, why it's wrong, the fix. Use during code review or pre-merge audit when you suspect a responsibility is on the wrong class.

Organised by pattern, with cross-cutting "compound violations" at the end.

---

## Information Expert violations

### IE-1: Anaemic domain model

**Smell.** `@Entity` classes are pure data carriers (`@Id`, `@Column`, `@OneToMany` and Kotlin properties — no methods). All computation lives in `@Service` classes that fetch the entity, read its fields, and compute over them.

**Why it's wrong.** The data lives on the entity; the service reaches in. Info Expert says: the class with the data owns the operation.

**Fix.** Move the computation onto the entity:

```kotlin
// before
@Entity
class Order(val id: UUID, @OneToMany(...) val items: List<OrderItem>) { /* no methods */ }

@Service
class OrderService(...) {
    fun calculateTotal(orderId: UUID) =
        orderRepo.findById(orderId).get().items.fold(Money.ZERO) { ... }
}

// after
@Entity
class Order(val id: UUID, @OneToMany(...) val items: List<OrderItem>) {
    fun total(): Money = items.fold(Money.ZERO) { acc, item -> acc + item.subtotal() }
}

@Service
class OrderService(...) {
    fun calculateTotal(orderId: UUID) = orderRepo.findById(orderId).get().total()
}
```

(See `clean-code-objects-and-data` for the deeper anaemic-domain treatment; see `ddd-tactical-patterns` for aggregate-shaped fixes.)

### IE-2: Feature envy — service reaches `obj.field1.subField.method()`

**Smell.** A service method reaches several levels deep into an entity's fields to perform a computation: `order.customer.address.country.taxRate`.

**Why it's wrong.** The chain is "feature envy" (Fowler) — the method wants to live where the data is. Info Expert violated; Law of Demeter violated too (see `clean-code-objects-and-data`).

**Fix.** Push the method onto the type that has the data — usually the deepest type in the chain. Or extract a Pure Fabrication that takes only the values it needs.

### IE-3: Repository methods that compute aggregates

**Smell.** `OrderRepository.totalRevenue(): Money` — computing in the repository when the data could be loaded as entities and computed by the entities.

**Why it's wrong.** Mixes persistence (Repository's responsibility) with computation (which entity owns the data). Hard to test; hard to reason about; couples Info Expert to a specific store.

**Fix.** For *aggregations* that genuinely belong in SQL (sums over millions of rows), keep them in the repository or a separate read-model. For computations over a few entities, load and compute. (See `cqrs-implementation` for the read/write split.)

---

## Creator violations

### C-1: Scattered `new SomeClass(...)`

**Smell.** Five different services each `new OrderItem(productId, quantity, price)` for the same domain type, in slightly different ways (some forget validation, some forget defaults).

**Why it's wrong.** No single Creator. Construction logic is duplicated; invariants are inconsistently enforced; adding a required field requires editing five files.

**Fix.** Centralise on the natural Creator (per the five Creator criteria from `theory.md`). For `OrderItem`, the Creator is usually `Order`:

```kotlin
class Order private constructor(...) {
    fun addItem(productId: ProductId, qty: Int, price: Money) {
        items += OrderItem(productId, qty, price)   // single Creator
    }
}
```

External code calls `order.addItem(...)`, never `new OrderItem(...)`.

### C-2: Public constructor on an aggregate / domain type

**Smell.** `class Order(val id, val customerId, val items, var status, var total, var createdAt, ...)` — public constructor accepting all fields, including computed ones.

**Why it's wrong.** Callers can construct invalid orders (negative total, empty items, status that doesn't match other fields). Invariants are unenforced.

**Fix.** Private constructor + factory method:

```kotlin
class Order private constructor(...) {
    companion object {
        fun create(id: OrderId, customerId: CustomerId, items: List<OrderItem>): Order {
            require(items.isNotEmpty())
            return Order(id, customerId, items.toMutableList(), status = Draft, total = items.sumOf { it.subtotal() })
        }
    }
}
```

Now `new Order(...)` is impossible from outside; invariants pass through `create`.

### C-3: Constructors that take 10+ parameters because the caller "looked them up"

**Smell.** `OrderItem(productId, productName, productCategory, productSku, unitPrice, quantity, discount, tax, ...)` — constructor demands data the caller had to fetch separately.

**Why it's wrong.** Caller is forced into a Creator role they shouldn't have. The Creator should be the class that has the data; if it's not the caller, the wrong class is creating.

**Fix.** Either move the Creator to the class that has the data (e.g., `Product.toOrderItem(quantity, discount)` if `Product` has the price/sku/etc), or reduce the constructor surface and load the rest internally.

---

## Controller violations

### Ct-1: Fat controller

**Smell.** A `@RestController` method with validation, business logic, persistence calls, email sending — all inline.

**Why it's wrong.** The Controller's responsibility is to *receive* the system event and *delegate*. Doing the work itself violates Controller GRASP, SRP, and usually a few others.

**Fix.** Extract a Use-Case Handler:

```kotlin
@PostMapping
fun place(@Valid @RequestBody req: PlaceOrderRequest): ResponseEntity<OrderResponse> =
    placeOrder.handle(req.toCommand())
        .let { orderId -> ResponseEntity.created(URI("/api/v1/orders/$orderId")).body(OrderResponse(id = orderId)) }
```

The controller is thin: validation (via `@Valid` + Bean Validation), delegation, response shaping. Business logic is in the handler.

### Ct-2: Controller injects every domain service it needs

**Smell.** `OrderController(orderRepo, pricingClient, emailClient, paymentGateway, inventoryService, ...)` — eight dependencies on a controller.

**Why it's wrong.** The controller is being used as a god orchestrator. Each dependency is a sign the controller is doing too much.

**Fix.** Inject only the use-case handlers; the handlers compose the rest:

```kotlin
@RestController
class OrderController(
    private val placeOrder: PlaceOrderHandler,
    private val getOrder: GetOrderHandler,
    private val cancelOrder: CancelOrderHandler,
) { ... }
```

Three dependencies, all use-case handlers. Controller stays thin.

### Ct-3: Multiple controllers reimplementing the same coordination

**Smell.** `WebOrderController`, `MobileOrderController`, `AdminOrderController` — each reimplementing the same "validate → price → save → notify" sequence.

**Why it's wrong.** The coordination is the use case; it shouldn't be triplicated.

**Fix.** Extract `PlaceOrderHandler` (use case); each controller delegates. The controllers differ only in their HTTP surface (auth, request shape, response shape).

---

## High Cohesion violations

### HC-1: `Util` / `Helper` / `Manager` class

**Smell.** A class named `OrderUtils`, `OrderHelper`, or `OrderManager` collects unrelated functions: `calculateTotal`, `formatForEmail`, `exportToCsv`, `retryFailedOrders`, `cleanupOldOrders`.

**Why it's wrong.** Five unrelated responsibilities glued together by "Order" in the name. The name is a smell — `Util`/`Helper`/`Manager` are the surest signs that the author couldn't articulate one responsibility (see `clean-code-naming` for the weasel-suffix ban).

**Fix.** One class per responsibility:

```kotlin
class OrderPricing       { fun total(order: Order): Money }
class OrderEmailFormat   { fun format(order: Order): String }
class OrderCsvExport     { fun export(orders: List<Order>): ByteArray }
class OrderRetryJob      { fun run(): Int }
class OrderCleanupJob    { fun run(): Int }
```

### HC-2: Class with > 7 unrelated public methods

**Smell.** `class CheckoutService { fun startSession(); fun applyCoupon(); fun calculateShipping(); fun authenticate(); fun chargeCard(); fun reserveInventory(); fun sendReceipt(); fun trackAnalytics(); fun ... }` — methods spanning multiple responsibilities.

**Why it's wrong.** No single purpose. Tests pull in everything; changes to one concern risk breaking others; substituting one piece is awkward.

**Fix.** Group by responsibility, extract per-group classes. Often each group is a Pure Fabrication: `CheckoutSession`, `CouponApplier`, `ShippingCalculator`, etc.

### HC-3: Methods touching disjoint subsets of fields

**Smell.** A class has fields `a, b, c, d, e, f`. Method `m1` touches only `a, b`; `m2` touches only `c, d`; `m3` touches only `e, f`. Three disjoint method-field clusters in one class.

**Why it's wrong.** The class is three classes pretending to be one. Each cluster is a separate responsibility.

**Fix.** Split. The fields move to where their methods are; what was one god class becomes three focused ones.

---

## Low Coupling violations

### LC-1: Direct downstream call where event would do

**Smell.** `OrderService.placeOrder()` directly calls `EmailService.sendConfirmation()`. Adding SMS notification later forces an edit to `OrderService`. Adding analytics later, another edit.

**Why it's wrong.** The publisher knows about every consumer. New consumers force edits to the publisher. Coupling grows with each new reaction.

**Fix.** Emit a domain event; let consumers subscribe:

```kotlin
@Service
class PlaceOrderHandler(private val events: ApplicationEventPublisher) {
    fun handle(cmd: PlaceOrderCommand): OrderId {
        val order = ...
        events.publishEvent(OrderPlaced(order.id, order.customerEmail))
        return order.id
    }
}

@Component class EmailNotifier { @ApplicationModuleListener fun on(e: OrderPlaced) { ... } }
@Component class SmsNotifier { @ApplicationModuleListener fun on(e: OrderPlaced) { ... } }
@Component class Analytics { @ApplicationModuleListener fun on(e: OrderPlaced) { ... } }
```

`PlaceOrderHandler` is unchanged when reactions are added.

### LC-2: "While I'm here" injection

**Smell.** A class injects a dependency it doesn't currently use, "in case we need it later". Or injects something it uses for one trivial computation when a parameter would do.

**Why it's wrong.** Every injection is permanent coupling. Unused dependencies bloat constructors and tests.

**Fix.** Inject only what you call. If you need a value once, accept it as a parameter at the call site.

### LC-3: Train wreck (`a.getB().getC().getD().method()`)

**Smell.** A method that walks a chain of objects to reach a deep value.

**Why it's wrong.** Couples the caller to the structure of B, C, D. Any restructure of the chain breaks the caller. Law of Demeter violated. (See `clean-code-objects-and-data`.)

**Fix.** Push the operation deeper into the chain (Info Expert), or expose a higher-level operation that doesn't require the walk.

---

## Polymorphism violations

### P-1: `when (type)` chain proliferating across methods

**Smell.** The same `when (paymentMethod)` appears in `process()`, `fee()`, `supports()`, `formatReceipt()`. Adding a new payment method requires editing all four.

**Why it's wrong.** The variation is by type; it should live on the type. Polymorphism (GRASP) and OCP (SOLID) both violated.

**Fix.** Sealed interface with per-variant override:

```kotlin
sealed interface PaymentMethod {
    fun process(amount: Money): Result
    fun fee(amount: Money): Money
    fun supports(country: Country): Boolean
}
```

Adding `Crypto` is one new `data object`. (See `solid-principles/resources/bad-practices.md` O-1 for full treatment.)

### P-2: `instanceof` / `is` chains for behaviour dispatch

**Smell.** `if (x is Foo) ... else if (x is Bar) ... else if (x is Baz) ...` repeated in several places.

**Same fix as P-1:** push behaviour onto the types via sealed hierarchy.

---

## Pure Fabrication violations

### PF-1: Domain entity with infrastructure code

**Smell.** `Order.placeOrder()` that calls `EmailService.send()`, `PaymentGateway.charge()`, `OrderRepository.save()`. The entity orchestrates infrastructure.

**Why it's wrong.** Entity becomes a Spring bean (or worse, a JPA entity that needs Spring at construction). Infrastructure leaks into domain. Tests of `Order` need Spring.

**Fix.** Extract a Pure Fabrication (`PlaceOrderHandler`) that orchestrates infra; `Order` stays narrow.

### PF-2: Pure Fabrication used as a junk drawer

**Smell.** `OrderHelpers`, `CommonComponent`, `Misc`, `Stuff`. A fabrication with no defined responsibility.

**Why it's wrong.** Same as HC-1 (High Cohesion). A focused fabrication is good design; a grab-bag fabrication is the High Cohesion violation.

**Fix.** Split into focused fabrications, each with one responsibility.

---

## Indirection violations

### Ind-1: Direct concrete-class injection

**Smell.** `class OrderService(private val email: SmtpEmailClient)` — high-level service depends on a low-level concrete (also DIP violation; see `solid-principles`).

**Why it's wrong.** Can't substitute; can't test without SMTP; can't swap providers without editing the consumer.

**Fix.** Define an interface in the domain (`EmailSender`); depend on it; the SMTP impl is in `infrastructure/`.

### Ind-2: Service knows HOW its dependency works

**Smell.** Caller code structures itself around the dependency's internals — preparing data in the dependency's expected format, handling its specific exceptions, calling methods in a specific order required by the impl.

**Why it's wrong.** The "indirection" is theoretical — substituting the impl breaks the caller because it relied on impl-specific details.

**Fix.** Extract a richer interface that hides the impl-specific protocol; or wrap the dependency behind an Adapter that exposes a cleaner contract.

### Ind-3: Indirection added with no purpose

**Smell.** An interface with one impl, and no plan for a second. A factory bean for a class Spring could have constructed directly.

**Why it's wrong.** Indirection has cost — DI complexity, mental overhead, indirection in stack traces. With no benefit (no substitution, no protected variation), it's overhead.

**Fix.** Inline. Apply Indirection where you have *reason* to expect substitution.

---

## Protected Variations violations

### PV-1: Vendor SDK calls scattered through business logic

**Smell.** `stripeClient.charges.create(...)` appears in `OrderService`, `RefundService`, `SubscriptionService`. Each carries Stripe-specific exception handling, request shaping, error parsing.

**Why it's wrong.** Migrating Stripe → Adyen requires editing every caller. Stripe SDK upgrades break business code.

**Fix.** Wrap behind `PaymentGateway` interface; one Spring bean (`StripePaymentGateway`) owns the SDK; business code depends on the interface.

(See `clean-code-boundaries` for full Wrap-Don't-Pass treatment.)

### PV-2: Primitive obsession at the type-system level

**Smell.** `OrderId` is `String` everywhere. `CustomerId` is `String` too. Code passing the wrong string into the wrong place fails at runtime.

**Why it's wrong.** When the underlying representation needs to change (UUID → ULID, string → snowflake), every signature changes. Strings are also LSP-style substitutable in dangerous ways.

**Fix.** `value class`:

```kotlin
@JvmInline value class OrderId(val value: UUID)
@JvmInline value class CustomerId(val value: UUID)
```

Type system enforces; underlying representation is one place to change.

### PV-3: Over-applied PV — interface for every internal collaboration

**Smell.** Every Spring bean has a sister interface, even when there's only one impl, no plan for substitution, no test substitution needed (because the bean has no dependencies to mock anyway).

**Why it's wrong.** PV is the most expensive GRASP pattern. Applied universally, it inflates the codebase, hides implementations behind type-search, slows DI, and provides zero benefit.

**Fix.** Apply PV at boundaries where you have *reason* to expect change: vendor SDKs, persistence stores, API versions, identity primitives, integration adapters. Skip everywhere else.

---

## Compound violations

### Compound-1: God service + anaemic entity + scattered `new`

A `UserService` that registers, authenticates, deactivates users. Constructs `User(...)` directly in three methods. Reads user fields and computes everything in the service. Three GRASP patterns violated:

- HC-1 (god service)
- IE-1 (anaemic domain)
- C-1 (scattered `new`)

**Fix order:**
1. Split the god service per use case (HC-1).
2. Push computations onto `User` (IE-1).
3. Make `User.create(...)` the single Creator (C-1).

Each step makes the next clearer.

### Compound-2: Fat controller + direct vendor call + service-locator pull

A `@RestController` that has business logic, calls Stripe directly, and pulls beans via `ApplicationContext.getBean(...)`:

- Ct-1 (fat controller)
- PV-1 (vendor call in business code)
- Ind-2 / DIP violation (service-locator)

**Fix order:**
1. Extract use-case handler from the controller (Ct-1).
2. Wrap Stripe behind `PaymentGateway` (PV-1).
3. Constructor-inject `PaymentGateway` into the handler (DIP / Ind).

### Compound-3: `when (type)` chain + each branch news up vendor classes

```kotlin
fun process(method: PaymentMethod, amount: Money) = when (method) {
    CARD -> StripeClient(apiKey).charge(amount)
    BANK -> AdyenClient(apiKey).transfer(amount)
}
```

P-1 + PV-1 + Ind-1 in one. Sealed `PaymentMethod` + `PaymentGateway` strategy beans + DI of `Map<PaymentMethod, PaymentGateway>`. (See `solid-principles/resources/bad-practices.md` Compound-3.)

---

## How to use this catalogue in code review

1. **Scan the diff for the smells.** New `@Service` with > 5 dependencies? HC-1 / Compound-1. New direct call to `EmailService` / `Stripe` from business code? LC-1 / PV-1. New `when (type)` branch? P-1. New constructor with 10 parameters? C-3.
2. **Name the violation.** "This is IE-1 (anaemic domain)" frames the discussion precisely.
3. **Apply the fix.** The fix per entry is the standard refactor; read the entry, apply.
4. **Watch for compounds.** Most real violations are compound — fixing one usually clears one or two adjacent ones. Use the fix order from `best-practices.md`.
