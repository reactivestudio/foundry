# Kotlin-Specific — Objects and Data Structures

Kotlin moves several of Martin's anti-patterns into the past tense by giving you the right defaults out of the box. This file catalogues what the language already solves, where it shifts the cost calculation between objects and data structures, and where Kotlin-only mechanics (sealed hierarchies, `@JvmInline value class`, scope functions) change how the chapter's rules apply.

---

## `data class` is the canonical DTO

In Java, a DTO requires a private field, a public getter, a public setter, plus by-convention `equals`/`hashCode`/`toString`. Kotlin generates all of that from one line:

```kotlin
data class OrderRequest(
    val items: List<OrderItemRequest>,
    val customerId: CustomerId,
    val shippingAddress: AddressRequest,
)
```

What you get for free:
- Public `val` properties (read-only, no setter).
- Structural `equals`, hash-consistent `hashCode`, readable `toString`.
- `copy(...)` with named-argument support for "modify one field" workflows.
- Component functions for destructuring (`val (items, customerId, _) = order`).

**House rule**: every DTO is a `data class` with **`val` fields only**. Mutability on a transport object is a regression to bean-style hybrids — no caller should be able to mutate a request DTO in place.

### When NOT to use `data class`

- **As an aggregate / domain object.** `data class Order(val id: OrderId, var status: OrderStatus, ...)` looks tempting but exposes the entire state surface and lets any caller `.copy(status = SUBMITTED)` — bypassing every invariant the type was supposed to protect.
- **When inheritance is needed** (rare). `data class` cannot be `open`. If you genuinely need a hierarchy of "data carriers," use a sealed interface with `data class` leaves.
- **When most properties don't participate in equality.** `equals`/`hashCode` use *all* primary-constructor properties. If only one field (the id) defines identity, you have an aggregate, not a data class — write a class with explicit `equals` based on id.

---

## Properties replace JavaBean getters/setters

Kotlin compiles `val foo: Int` to `public final int getFoo()` for Java interop, but **in Kotlin source you never write `getFoo()`**. The property *is* the access surface.

This eliminates one whole anti-pattern: there's no temptation to write `getX()` / `setX()` ceremony around a private field, because the language doesn't reward you for it. Every `val` is a read-only accessor; every `var` is a read-write accessor; both come from a single declaration.

```kotlin
// ✗ Java instinct — explicit getter/setter pair around a private field
class Order {
    private var status: OrderStatus = OrderStatus.DRAFT
    fun getStatus(): OrderStatus = status
    fun setStatus(s: OrderStatus) { status = s }
}

// ✓ Kotlin — same thing, no ceremony
class Order(var status: OrderStatus = OrderStatus.DRAFT)
```

But this doesn't make `var status` *encapsulated* — see the next section.

### Custom getter / restricted setter — the encapsulation lever

When you do need to enforce a policy, custom property accessors let you keep the property surface and add the invariant inside:

```kotlin
// ✓ External: read-only. Internal: controlled mutation through behaviour.
class Order(initialStatus: OrderStatus = OrderStatus.DRAFT) {
    var status: OrderStatus = initialStatus
        private set                              // ← only the class can mutate

    fun submit() {
        check(status == OrderStatus.DRAFT) { "Only DRAFT can be submitted" }
        status = OrderStatus.SUBMITTED
    }
}
```

Or compute a derived view that isn't stored:

```kotlin
class Order(...) {
    val isSubmittable: Boolean
        get() = status == OrderStatus.DRAFT && items.isNotEmpty()
}
```

These two patterns — `private set` and computed `get()` — are the everyday Kotlin equivalents of "design the interface around what the data is for." Use them liberally.

---

## `@JvmInline value class` — typed wrappers without runtime cost

Primitives masquerading as domain values (a `String` that's "really" an email; a `Long` that's "really" cents of money) are the root of an entire family of bugs. Kotlin's value classes turn primitives into types, with zero allocation overhead in most paths:

```kotlin
@JvmInline
value class Email private constructor(val value: String) {
    init { require(value.matches(EMAIL_REGEX)) { "Invalid email: $value" } }
    companion object {
        private val EMAIL_REGEX = Regex("...")
        fun of(raw: String): Email = Email(raw.trim().lowercase())
    }
}

@JvmInline
value class Money(val cents: Long) {
    operator fun plus(other: Money) = Money(cents + other.cents)
    val isPositive: Boolean get() = cents > 0
}
```

This is the Kotlin shape of **"hide implementation, not just fields"**: the call site uses a meaningful type (`Email`, `Money`) instead of `String`/`Long`, the validation lives inside the wrapper, and the wrapper has the operations the domain needs.

### When `value class` doesn't fit

- More than one field — value classes accept exactly one constructor parameter. Use `data class` for multi-field value objects.
- Equality semantics need to differ from the wrapped value — value classes always delegate `equals` to the inner value.
- The wrapped type must be platform-mappable in code that uses reflection or a serialiser that doesn't understand inline classes — Jackson 2.16+ handles them, older versions need a `@JsonValue` workaround.

For multi-field value objects, use a `data class` with private constructor and a factory:

```kotlin
data class Money private constructor(val cents: Long, val currency: Currency) {
    companion object {
        fun of(amount: BigDecimal, currency: Currency): Money =
            Money(amount.movePointRight(currency.defaultFractionDigits).longValueExact(), currency)
    }
    operator fun plus(other: Money): Money {
        require(currency == other.currency) { "Cannot add different currencies" }
        return Money(cents + other.cents, currency)
    }
}
```

---

## Sealed hierarchies — the procedural side, made clean

In Java, picking the "data structure + procedure" side of Martin's anti-symmetry costs you `instanceof` chains, type casts, and no exhaustiveness checking. Kotlin's `sealed class` / `sealed interface` + `when` make procedural style structurally sound:

```kotlin
sealed interface Shape {
    val area: Double                       // a property if it's "just data"
}
data class Square(val side: Double) : Shape    { override val area get() = side * side }
data class Rectangle(val h: Double, val w: Double) : Shape { override val area get() = h * w }
data class Circle(val radius: Double) : Shape  { override val area get() = PI * radius * radius }

// Procedural side: add operations outside the hierarchy, exhaustive when()
fun perimeter(shape: Shape): Double = when (shape) {
    is Square    -> 4 * shape.side
    is Rectangle -> 2 * (shape.h + shape.w)
    is Circle    -> 2 * PI * shape.radius
}
```

The compiler enforces exhaustiveness, smart-casts the variable inside each branch, and refuses to compile if you add `Triangle` to the hierarchy without updating `perimeter`. This is the missing tool that makes the procedural side viable for domain modelling in Kotlin — choose it without guilt when operations are the axis of change.

### Sealed for "this is one of these N states"

Sealed hierarchies are also a clean way to replace nullable + boolean encoded state. Instead of:

```kotlin
// ✗ Encoded state — readers must remember which combinations are legal
data class Payment(val amount: Money, val authorisedAt: Instant?, val capturedAt: Instant?, val refundedAt: Instant?)
```

…use:

```kotlin
// ✓ State is a sealed type; illegal combinations are unrepresentable
sealed interface PaymentState {
    data object Pending : PaymentState
    data class Authorised(val at: Instant) : PaymentState
    data class Captured(val authorisedAt: Instant, val capturedAt: Instant) : PaymentState
    data class Refunded(val refundedAt: Instant) : PaymentState
}
class Payment(val amount: Money, val state: PaymentState) { ... }
```

The "data structure" side of Martin's dichotomy gets dramatically cleaner with sealed types; the "object" side still wins when the operations are stable. Pick per workload.

---

## Companion factories, private constructors — invariants the class owns

Bean-style construction (no-arg constructor, then a setter per field) leaves the object in an invalid state from the moment it's created until the last setter is called. The Kotlin convention is the opposite: a private constructor and a named factory that enforces invariants up front.

```kotlin
class Order private constructor(
    val id: OrderId,
    private val items: List<OrderItem>,
    private var status: OrderStatus,
) {
    companion object {
        fun place(items: List<OrderItem>): Order {
            require(items.isNotEmpty()) { "Order must have at least one item" }
            return Order(OrderId.fresh(), items.toList(), OrderStatus.DRAFT)
        }
    }

    fun submit() { /* ... */ }
}

val order = Order.place(items)             // ✓ named intent
// Order(...)                              // ✗ won't compile — private constructor
```

Named factories also let you have **multiple ways to create a thing**, each with a name that documents intent (`Order.place`, `Order.rehydrate`, `Order.fromDraft`). This is the missing feature that JavaBeans never had — you express *why* you're constructing the object, not just *what* fields it gets.

---

## Scope functions and Tell-Don't-Ask

`apply`, `also`, `run`, `let`, `with` each have a place; in the context of objects-vs-data they shine as **tell sequences** that read top-down with no temporaries.

```kotlin
// ✗ Ask-then-act — caller reaches into the aggregate
val account = repo.find(accountId)
if (account.canCredit(amount)) {
    account.credit(amount)
    auditLog.record(account, amount)
}

// ✓ Tell — the operation is one statement, the aggregate enforces its own invariants
repo.find(accountId).apply {
    credit(amount)
    recordAudit(amount, auditLog)
}
```

Two warnings on scope functions:
- **`apply` returns the receiver, `let` returns the lambda result.** Picking the wrong one introduces subtle data-flow bugs that no compiler will catch.
- **Don't chain three scope functions to look clever.** A pipeline with two `let`s, a `takeIf`, and an `also` is harder to read than two statements.

---

## Extension functions — adding behaviour to data classes without making them hybrids

A `data class` should have no methods. But some operations naturally read like "this is a thing the data does" — `OrderRequest.toCommand()`, `Address.formatted()`, `Money.format(locale)`. The Kotlin convention is to put these in **extension functions**, often in a separate file (`OrderMappers.kt`, `MoneyFormatters.kt`), keeping the `data class` definition itself a one-liner.

```kotlin
// ✓ DTO definition stays a one-liner
data class OrderRequest(val items: List<ItemRequest>, val customerId: CustomerId)

// ✓ Mapping lives in a separate file; can be replaced/tested independently
// file: OrderMappers.kt
fun OrderRequest.toCommand(now: Instant): SubmitOrderCommand =
    SubmitOrderCommand(customerId, items.map(ItemRequest::toLine), now)
```

This keeps the DTO honest (a data structure with no behaviour) and the mapping discoverable (anyone reading the DTO sees one declaration and can `Cmd-Click` the extension if they want to follow the mapping).

The same trick works the other way — extension functions on domain types that produce DTOs:

```kotlin
fun Order.toView(): OrderView = OrderView(id = id.value, status = status.name, items = items.map(...))
```

---

## Destructuring — the data-structure convenience

Destructuring is a syntactic admission that the type is a data structure. If you're destructuring `val (a, b, c) = thing`, you're saying "this thing is a tuple in disguise." That is fine — and is in fact a hint that the type should be a `data class`.

If you find yourself wanting to destructure an aggregate (`val (status, items) = order`), the smell points at design — you want to pull state out, which implies you want to *do something with the state externally*, which implies a Tell-Don't-Ask violation in progress.

---

## Immutable collections — `List` vs `MutableList`

Kotlin's `List<T>` is read-only at the type level (the underlying instance may still be mutable; `kotlinx.collections.immutable` exists for true immutability). Use the read-only interface in public DTO and aggregate signatures so callers can't tamper with collections handed to them:

```kotlin
// ✗ Caller can mutate the order's items from outside
class Order(private val items: MutableList<OrderItem>) {
    fun getItems(): MutableList<OrderItem> = items
}

// ✓ Caller gets a read-only view; mutation is only via aggregate methods
class Order(private val items: MutableList<OrderItem>) {
    val items: List<OrderItem> get() = this.items.toList()         // defensive copy
    fun addItem(item: OrderItem) { /* checks + items += item */ }
}
```

A defensive copy is the usual answer for collections that mutate over time. For collections that never mutate after construction, just expose `val items: List<OrderItem>` (immutable by convention) directly.

---

## What Kotlin does NOT solve

- **JPA still wants mutable entities.** Hibernate needs a no-arg constructor and `var` fields (or backing-field magic). Kotlin makes this less painful with `kotlin-jpa` plugin and `protected set`, but the cleanest answer is to **keep the JPA entity as a persistence shape** and have a separate aggregate. See `spring-boot-objects-and-data.md`.
- **Jackson still likes mutable types** in some shapes (default constructor + setters). Modern Jackson + the Kotlin module handle `data class` with `val`s fine — but older codebases may force concessions.
- **Frameworks that reach in via reflection** (Spring's `BeanWrapper`, older `@ConfigurationProperties`) sometimes need `var` and a no-arg constructor. Spring Boot 3.x supports `data class val ...` for `@ConstructorBinding`, but legacy code may still use bean style.

In all three, **don't fight the framework** — write a thin framework-shaped class at the boundary and map to a clean domain type immediately on the way in / out.

---

## Quick reference

| Need | Kotlin tool |
|---|---|
| DTO at a boundary | `data class` with `val`s |
| Single-field domain primitive | `@JvmInline value class` with private constructor + factory |
| Multi-field value object | `data class` with private constructor + factory; or sealed hierarchy for variant value objects |
| Aggregate with state machine | `class` with `private` mutable state and `private set` on visible properties; behavioural methods; no public mutators |
| Closed type axis (shape, state) | `sealed interface` / `sealed class` with `data class` leaves; `when` is exhaustive |
| Adding "behaviour" to a DTO without making it a hybrid | Extension function in a separate file |
| Read-only collection in a public type | `List<T>` (interface), not `MutableList<T>` |
| Defensive view of internal state | `val xs: List<T> get() = _xs.toList()` |
| Tell-Don't-Ask sequence | `obj.apply { doX(); doY() }` |
| Construct only via named intent | `private constructor` + `companion object { fun create(...) }` |

The recurring lesson: **Kotlin's defaults match Martin's recommendations more closely than Java's**. The job in a Kotlin codebase is to *not undo* those defaults by reaching for bean-style accessors, mutable DTOs, or anemic data classes with business methods bolted on.
