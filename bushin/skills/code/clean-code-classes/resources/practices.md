# Clean Code — Classes Practices

Bad/best examples organised by topic. Read this when you want concrete patterns. For the WHY, see `theory.md`. For the high-level checklist, see `../SKILL.md`.

Examples use plain Kotlin syntax — no language-specific idioms (no coroutines, sealed hierarchies, scope functions, extensions). Stack-specific class shapes live in `kotlin/`, `framework/`, `ddd/` skills.

## The small-looking god class (size = concerns)

```kotlin
// Bad — 5 methods, looks "small enough", but two unrelated concerns
class SuperDashboard {
    fun lastFocusedComponent(): Component = ...
    fun setLastFocused(c: Component) { ... }
    fun majorVersionNumber(): Int = ...
    fun minorVersionNumber(): Int = ...
    fun buildNumber(): Int = ...
}

// Good — two single-concern classes
class Dashboard {
    fun lastFocusedComponent(): Component = ...
    fun setLastFocused(c: Component) { ... }
}

class Version(val major: Int, val minor: Int, val build: Int)
```

The number of methods didn't matter; the number of *reasons to change* did. `Version` is now reusable across the system.

## Low cohesion → split into clusters

```kotlin
// Bad — two clusters wearing one trench coat
class CustomerService(
    private val cache: Cache,
    private val mailer: Mailer,
    private val auditLog: AuditLog,
    private val clock: Clock,
) {
    fun warmCache(id: CustomerId) { cache.put(id, load(id)) }
    fun sendWelcome(id: CustomerId) { mailer.send(load(id).email, "Welcome") }
    fun recordSignup(id: CustomerId) { auditLog.write(SignupEvent(id, clock.now())) }
    fun recordCancellation(id: CustomerId) { auditLog.write(CancelEvent(id, clock.now())) }
}

// Good — each cluster its own class
class CustomerNotifier(
    private val cache: Cache,
    private val mailer: Mailer,
) {
    fun warmCache(id: CustomerId) { ... }
    fun sendWelcome(id: CustomerId) { ... }
}

class CustomerAuditor(
    private val auditLog: AuditLog,
    private val clock: Clock,
) {
    fun recordSignup(id: CustomerId) { ... }
    fun recordCancellation(id: CustomerId) { ... }
}
```

The signal: `warmCache` and `sendWelcome` only use `cache` and `mailer`; `recordSignup` and `recordCancellation` only use `auditLog` and `clock`. Two clusters, two classes.

## Stepdown layout

```kotlin
class OrderProjectionUpdater(
    private val projections: OrderProjections,
    private val clock: Clock,
) {
    // 1. Class-level constants
    companion object {
        private const val MAX_BATCH = 500
    }

    // 2. Public API — narrative order, what readers look for first
    fun apply(event: OrderEvent) {
        val current = loadProjection(event.orderId)
        val next = current.apply(event, clock.now())
        save(next)
    }

    // 3. Private helpers — each directly after its first caller
    private fun loadProjection(id: OrderId): OrderProjection =
        projections.findById(id) ?: OrderProjection.empty(id)

    private fun save(projection: OrderProjection) {
        projections.save(projection)
    }
}
```

The reader can stop after understanding `apply()` — the helpers are right where they're called.

## Visibility tree in practice

```kotlin
// Bad — public field exposed for testing discards the invariant
class Order(
    var status: OrderStatus,   // public so the test can flip it directly
) {
    fun submit() { status = SUBMITTED }
}

// Good — public API hides the invariant; module-internal factory lets the test build instances in any state
class Order private constructor(
    val id: OrderId,
    private var status: OrderStatus,
) {
    fun submit() {
        require(status == DRAFT)
        status = SUBMITTED
    }

    companion object {
        fun draft(id: OrderId): Order = Order(id, OrderStatus.DRAFT)

        // for tests in this module only — builds an Order in any state
        internal fun rehydrate(id: OrderId, status: OrderStatus): Order =
            Order(id, status)
    }
}
```

The test uses `rehydrate(...)` instead of mutating a public field; the invariant survives.

## God service split by use case

```kotlin
// Bad — five unrelated use cases in one class, 8 dependencies
class OrderService(
    private val orders: OrderRepository,
    private val payment: PaymentGateway,
    private val refunds: RefundGateway,
    private val csv: CsvExporter,
    private val stats: StatisticsCache,
    private val audit: AuditLog,
    private val clock: Clock,
    private val mailer: Mailer,
) {
    fun submit(...) { ... }        // uses orders, payment, audit, clock, mailer
    fun cancel(...) { ... }        // uses orders, audit, clock
    fun refund(...) { ... }        // uses orders, refunds, audit
    fun exportToCsv(...) { ... }   // uses orders, csv
    fun recomputeStats() { ... }   // uses orders, stats, clock
}

// Good — one use case per class, 3-5 dependencies each
class SubmitOrder(
    private val orders: OrderRepository,
    private val payment: PaymentGateway,
    private val audit: AuditLog,
    private val clock: Clock,
    private val mailer: Mailer,
) {
    fun handle(command: SubmitOrderCommand): OrderId = ...
}

class CancelOrder(
    private val orders: OrderRepository,
    private val audit: AuditLog,
    private val clock: Clock,
) {
    fun handle(command: CancelOrderCommand) = ...
}

// ... RefundOrder, ExportOrdersToCsv, RecomputeOrderStatistics
```

Each new class passes the 25-word test; each has 3-5 dependencies (visibly cohesive); adding a new use case is a new class, not a new method on an existing god.

## Too many fields → value-object extraction

```kotlin
// Bad — 8 instance variables, half form a logical group
class Customer(
    private val id: CustomerId,
    private val name: String,
    private val email: String,
    private val phone: String,
    private val street: String,
    private val city: String,
    private val zipcode: String,
    private val country: String,
)

// Good — address is a value object trying to escape
class Customer(
    private val id: CustomerId,
    private val name: String,
    private val email: String,
    private val phone: String,
    private val address: Address,
)

class Address(
    val street: String,
    val city: String,
    val zipcode: String,
    val country: String,
)
```

`Address` is now reusable (billing address, shipping address) and `Customer` is back to 5 fields.

## Refactoring recipe — characterisation tests first

```kotlin
// Step 0: pin behaviour with tests BEFORE touching the class
class SuperDashboardCharacterisationTest {
    @Test fun `lastFocused tracking works`() { ... }
    @Test fun `version numbers are exposed correctly`() { ... }
    // ... cover every public method
}

// Step 1: run all tests, confirm green
// Step 2: extract Version class — Dashboard now delegates to it temporarily
// Step 3: run all tests, confirm green
// Step 4: rename Dashboard methods if needed
// Step 5: run all tests, confirm green
// Step 6: stop — both classes pass the 25-word test
```

Never two refactors in one step. Never a behaviour change while structure is moving.
