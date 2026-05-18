# Classes — bad/best examples

For the checklist, see `classes.md`. For the cadence rules, see `../SKILL.md`.

Examples use plain Kotlin syntax — no language-specific idioms (no coroutines, sealed hierarchies, scope functions, extensions). Stack-specific class shapes live in `kotlin/`, `framework/`, `ddd/` skills.

## Worked review: `OrderService`

The skill's `Output template` applied end-to-end on a realistic god-service.

### Input

```kotlin
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
    fun submit(cmd: SubmitOrderCommand): OrderId { ... }   // uses orders, payment, audit, clock, mailer
    fun cancel(cmd: CancelOrderCommand) { ... }            // uses orders, audit, clock
    fun refund(cmd: RefundOrderCommand) { ... }            // uses orders, refunds, audit
    fun exportToCsv(query: ExportQuery): CsvFile { ... }   // uses orders, csv
    fun recomputeStats() { ... }                           // uses orders, stats, clock
}
```

### 1. 25-word verdict

> *"Orchestrates the Order lifecycle, **and** exports orders to CSV, **and** recomputes order statistics."*

**Fails.** Two `and`s → three concerns: lifecycle, export, statistics.

### 2. Size & cohesion summary

- Public methods: **5**.
- Instance variables: **8** (over the ~7 heuristic).
- Cohesion clusters (by field usage):
  - **Lifecycle:** `submit` / `cancel` / `refund` share `orders`, `audit`, `clock`. `submit` adds `payment`, `mailer`. `refund` adds `refunds`.
  - **Export:** `exportToCsv` uses only `orders`, `csv`.
  - **Statistics:** `recomputeStats` uses `orders`, `stats`, `clock`.

`orders` is the only shared field across all three clusters; everything else cluster-local.

### 3. Smells found

- Plain `*Service` with no domain qualifier in the name (weasel red list).
- 8 constructor dependencies (size table: target ~< 7).
- 3 cohesion clusters in one class — fields used by only one method dominate.

### 4. Action plan

1. **Characterisation tests** for all 5 public methods. Green.
2. **Extract `OrdersCsvExporter(orders, csv)`** — single use case, 2 deps. Re-run tests.
3. **Extract `OrderStatisticsRecomputer(orders, stats, clock)`** — single use case, 3 deps. Re-run tests.
4. **Split the lifecycle cluster by command** into `SubmitOrder`, `CancelOrder`, `RefundOrder`. Each gets only the deps it uses. Re-run tests after each split.
5. **Delete `OrderService`** once callers migrate.

### Final shape

```kotlin
class SubmitOrder(orders, payment, audit, clock, mailer)       // 5 deps, 1 use case
class CancelOrder(orders, audit, clock)                        // 3 deps, 1 use case
class RefundOrder(orders, refunds, audit)                      // 3 deps, 1 use case
class OrdersCsvExporter(orders, csv)                           // 2 deps, 1 use case
class OrderStatisticsRecomputer(orders, stats, clock)          // 3 deps, 1 use case
```

Each new class passes the 25-word test. Each has 2-5 dependencies. A new use case (`ReassignOrder`) is a new class — no existing class changes.

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
