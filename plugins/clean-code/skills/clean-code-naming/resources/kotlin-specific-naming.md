# Kotlin-Specific Naming

Kotlin's type system and language features replace several of Martin's classical encodings. This file covers what *changes* when moving from Java idioms to Kotlin: properties replacing getters, sealed/value/data classes, extension functions, companion factories, files, packages, and idiomatic suffixes.

For universal rules, see `general-naming-rules.md`. For Spring framework conventions, see `spring-boot-naming.md`. For DDD vocabulary, see `ddd-naming.md`.

---

## Rule K1: Properties replace JavaBean getter/setter prefixes

**Principle**: In Kotlin, accessors are properties. Don't write `getName()` / `setName(...)` style. Boolean properties skip the redundant `is` method form — Kotlin synthesises the `is` accessor from a property declared `val isActive`.

**Bad** (Java carried over):
```kotlin
class Customer {
    private var name: String = ""
    fun getName(): String = name                  // Java-style
    fun setName(newName: String) { name = newName }
    fun isActive(): Boolean = ...
}
```

**Good**:
```kotlin
class Customer {
    var name: String = ""
    val isActive: Boolean get() = ...
}
```

Callers write `customer.name`, `customer.isActive` — properties.

**Exception**: When implementing a Java interface that defines `getX()` / `isX()`, Kotlin auto-bridges — write `val x` or `val isX` and the JVM sees `getX()` / `isX()`. Don't introduce explicit getter methods unless writing for Java interop.

---

## Rule K2: `@JvmInline value class` is named for the concept, not the value

**Principle**: An inline value class encodes a domain concept (`Money`, `Email`, `UserId`) without runtime cost. Name it after the concept, not the underlying type.

**Bad**:
```kotlin
@JvmInline value class MoneyValue(val amount: BigDecimal)
@JvmInline value class EmailString(val raw: String)
@JvmInline value class UserIdLong(val v: Long)
```

**Good**:
```kotlin
@JvmInline value class Money(val amount: BigDecimal, val currency: Currency)
@JvmInline value class Email(val raw: String)
@JvmInline value class UserId(val value: UUID)
```

The constructor parameter is `value` or a domain-meaningful word (`amount`); the class is the concept.

---

## Rule K3: `data class` for DTOs and value objects, never for aggregates

**Principle**: `data class` autogenerates `equals` / `hashCode` / `copy` over all fields — perfect for DTOs and value objects, dangerous for JPA entities or aggregates with invariants.

**Bad**:
```kotlin
@Entity
data class Order(@Id val id: UUID, var status: Status, val items: MutableList<OrderItem>)
```

**Good**:
```kotlin
// Domain aggregate — plain class, private constructor, factory, methods
class Order private constructor(val id: OrderId, ...) {
    fun submit() { ... }
    companion object {
        fun create(...): Order { ... }
    }
}

// DTO at the API boundary — data class is fine
data class OrderSubmission(val customerId: UUID, val items: List<OrderLineSubmission>)

// View at the response boundary
data class OrderView(val id: UUID, val status: String, val total: BigDecimal)
```

**Why** `data class` for aggregates is wrong: Hibernate proxies, `equals` over a `MutableList`, `copy()` bypassing invariants — all bug factories. See `database-design` §JPA-entity-naming.

---

## Rule K4: Sealed hierarchies name variants by their concept, not by `*Impl`

**Principle**: Sealed `interface` / `class` variants are themselves the concrete type. `*Impl` suffix is meaningless.

**Bad**:
```kotlin
sealed interface Result<T> {
    class SuccessImpl<T>(val value: T) : Result<T>
    class FailureImpl(val error: Throwable) : Result<Nothing>
}

sealed interface OrderCommand {
    class SubmitImpl(...) : OrderCommand
    class CancelImpl(...) : OrderCommand
}
```

**Good**:
```kotlin
sealed interface Result<out T> {
    data class Success<T>(val value: T) : Result<T>
    data class Failure(val error: Throwable) : Result<Nothing>
}

sealed interface OrderCommand {
    data class Submit(val orderId: OrderId) : OrderCommand
    data class Cancel(val orderId: OrderId, val reason: String) : OrderCommand
}
```

**House extension**: when a sealed hierarchy models a state machine, the variants are *states* — singular nouns (`Draft`, `Submitted`, `Cancelled`), not verbs.

---

## Rule K5: Extension functions are verbs on the receiver

**Principle**: An extension function reads like a method on the receiver — it should be a verb the receiver "does".

**Bad**:
```kotlin
object StringUtils {
    fun makeEmailFromString(s: String): Email = ...
}
StringUtils.makeEmailFromString("a@b.com")
```

**Good**:
```kotlin
fun String.toEmail(): Email = ...
"a@b.com".toEmail()
```

**Convention**:
- `to*` — conversions (`toEmail`, `toMoney`)
- `as*` — views / casts that don't allocate (`asSequence`, `asReversed`)
- `is*` — predicates (`isValidEmail`)
- no prefix — primary verbs (`trim`, `partition`, `chunked`)

---

## Rule K6: Companion factory methods follow standard verbs

**Principle**: Factory methods on `companion object` have established names. Use them consistently.

| Verb | Use for |
|---|---|
| `create` | New instance with full constructor parameters; may validate |
| `of` | Concise factory from one or two arguments (`UserId.of(uuid)`) |
| `from` | Convert from another representation (`Email.from(rawString)`) |
| `parse` | Parse a string representation; may throw |
| `tryParse` / `parseOrNull` | Parsing variant that returns `null` instead of throwing |
| `empty` | Canonical empty instance |
| `default` | Canonical default instance (use sparingly) |

**Bad**:
```kotlin
companion object {
    fun buildOrder(...): Order
    fun makeOrder(...): Order
    fun newOrder(...): Order
    fun get(id: UUID): Order            // get suggests a lookup, not construction
}
```

**Good**:
```kotlin
companion object {
    fun create(customerId: CustomerId, items: List<OrderLine>): Order
    fun from(submission: OrderSubmission): Order
    fun parse(serialised: String): Order
}
```

---

## Rule K7: File naming — `Orders.kt` for top-level helpers, `Order.kt` for the class

**Principle**: A file containing one class is named after the class. A file containing top-level functions or constants is named after the plural concept.

**Good**:
```
domain/order/
├── Order.kt              # class Order, sealed OrderStatus, related domain types
├── OrderRepository.kt    # interface
├── Orders.kt             # top-level helpers: fun Order.totalWithTax(...): Money
└── OrderEvents.kt        # if event types are numerous, group them in their own file
```

**Bad**:
```
domain/order/
├── orderClass.kt         # camelCase file name
├── order_repository.kt   # underscore
└── Util.kt               # what's in here?
```

---

## Rule K8: Package names — lowercase, no underscores, no camelCase

**Principle**: Kotlin package names are lowercase, separated by dots, no `_` or capitals.

**Good**:
```kotlin
package com.example.platform.checkout.domain
package com.example.platform.checkout.infrastructure.persistence
```

**Bad**:
```kotlin
package com.example.platform.Checkout.Domain        // capitalised
package com.example.platform.check_out.domain       // underscore
package com.example.platform.checkOut.domain        // camelCase
```

---

## Rule K9: Nullability suffixes — only when ambiguity warrants

**Principle**: Kotlin's `T?` already encodes nullability in the type, but established suffixes signal *expected* missing-value semantics where overload disambiguation matters.

| Suffix | Meaning |
|---|---|
| `*OrNull` | Returns `T?` instead of throwing (`firstOrNull`, `singleOrNull`) |
| `*OrEmpty` | Returns empty collection / string instead of `null` (`orEmpty`) |
| `*OrElse(default)` | Returns a fallback (`getOrElse`) |
| `try*` | Attempts; returns `Result<T>` or `T?` (`tryParse`) |

**Good**:
```kotlin
fun findById(id: OrderId): Order?           // explicit return-null
fun parseAmount(s: String): Money           // throws on failure
fun parseAmountOrNull(s: String): Money?    // null on failure
```

Don't double-encode: `findOrderByIdOrNull` is redundant when the only `findOrderById` already returns `Order?`. Add `OrNull` only when both throwing and non-throwing variants coexist.

---

## Rule K10: Operator functions follow Kotlin operator conventions

**Principle**: When implementing operator overloads, use Kotlin's operator names — `plus`, `minus`, `times`, `div`, `rem`, `compareTo`, `contains`, `get`, `set`, `invoke`.

**Good**:
```kotlin
class Money(...) : Comparable<Money> {
    operator fun plus(other: Money): Money = ...
    operator fun minus(other: Money): Money = ...
    operator fun times(factor: BigDecimal): Money = ...
    override fun compareTo(other: Money): Int = ...
}
```

**Bad** (a domain class overloading operators with non-operator semantics):
```kotlin
class Customer {
    operator fun plus(order: Order): Customer = ...   // what does this mean?
}
```

Operator overloading is for types where the operator has a clear, conventional meaning (numbers, collections, paths). Don't be cute with it.

---

## Rule K11: `suspend` and `Flow` — don't prefix the name with the modifier

**Principle**: `suspend` is a keyword and a JVM marker, not part of the name. The function name describes *what it does*, not *that it suspends*.

**Bad**:
```kotlin
suspend fun suspendingFetchOrder(id: OrderId): Order
fun observeOrdersFlow(): Flow<Order>
```

**Good**:
```kotlin
suspend fun fetchOrder(id: OrderId): Order
fun observeOrders(): Flow<Order>          // return type already says Flow
```

The signature `Flow<Order>` is the documentation; repeating "Flow" in the name is noise.

---

## Rule K12: Backticked names — legitimate only for tests and Java interop

**Principle**: Backticks (`` `name` ``) allow arbitrary characters in identifiers. They are useful for two cases only.

**Legitimate**:
```kotlin
// Tests — sentence-case names for readability
@Test
fun `given empty cart, when submitting order, then throws EmptyOrderException`() { ... }

// Interop with a Java identifier that clashes with a Kotlin keyword
javaThing.`object`()
```

**Illegitimate**:
```kotlin
val `customer name` = "..."          // production code
val `2025-revenue` = ...             // production code
```

Backticks in production are a smell signalling either a Java boundary that should be wrapped (good) or laziness about identifier conflicts (bad).

---

## Rule K13: Type aliases — used sparingly, named like the concept

**Principle**: `typealias` is for shortening verbose generic types or giving a concept a name when a full `value class` is overkill. It does *not* create a new type — `typealias UserId = UUID` is still a `UUID` to the compiler.

**Good**:
```kotlin
typealias EventHandler<E> = suspend (E) -> Unit
typealias OrderItems = List<OrderLine>           // local readability alias
```

**Bad** (use a `value class` instead):
```kotlin
typealias UserId = UUID                          // no compile-time safety
                                                 // UserId and OrderId are interchangeable
```

**Rule of thumb**: if you want type safety (no mixing `UserId` and `OrderId` at the call site), use `@JvmInline value class`. If you just want a shorter name for an existing type that's already domain-meaningful, `typealias`.

---

## Rule K14: Top-level functions when they're not a method on anything

**Principle**: If a function doesn't belong to a class, make it a top-level function — don't invent a `*Utils` object to hold it.

**Bad**:
```kotlin
object StringUtils {
    fun isValidEmail(s: String): Boolean = ...
}
StringUtils.isValidEmail("a@b.com")
```

**Good**:
```kotlin
// In Strings.kt or Emails.kt
fun isValidEmail(s: String): Boolean = ...

// Even better — as extension
fun String.isValidEmail(): Boolean = ...
```

**Why**: `*Utils` objects are bag-of-functions; they violate cohesion and exist only because Java required a class. Kotlin doesn't.

---

## Rule K15: Constants — `UPPER_SNAKE_CASE`; `const val` when truly compile-time

**Principle**: Compile-time constants are `UPPER_SNAKE_CASE`. `const val` requires the value to be a `String` or primitive and known at compile time.

**Good**:
```kotlin
const val MAX_ORDER_ITEMS = 100
const val DEFAULT_CURRENCY = "EUR"

// Not a compile-time constant — use plain val
val DEFAULT_TIMEZONE: ZoneId = ZoneId.of("UTC")
```

**Bad**:
```kotlin
const val maxOrderItems = 100               // wrong case
val MaxOrderItems = 100                     // mixed case
```

---

## Rule K16: `*Impl` — last-resort suffix, not the default

**Principle**: Kotlin doesn't force separate interface/impl pairs the way Java did. When you do have an interface with one implementation, prefer naming the implementation for *what makes it specific*, not generic `*Impl`.

**Bad**:
```kotlin
interface OrderRepository { ... }
class OrderRepositoryImpl : OrderRepository { ... }
```

**Good**:
```kotlin
interface OrderRepository { ... }
class JpaOrderRepository(...) : OrderRepository { ... }     // says it's JPA-backed
// or
class InMemoryOrderRepository : OrderRepository { ... }     // says it's in-memory
// or
class PostgresOrderRepository(...) : OrderRepository { ... } // says it's Postgres-specific
```

**Exception**: a one-implementation interface with no meaningful disambiguation can use `*Default` or remain `*Impl` — but at that point, ask why the interface exists at all.

---

## Summary checklist (Kotlin-specific)

- [ ] No `get*` / `set*` for properties (use `val` / `var`).
- [ ] `@JvmInline value class` named for the concept (`Money`, not `MoneyValue`).
- [ ] `data class` only for DTOs and value objects, never for JPA entities or aggregates.
- [ ] Sealed variants named for the concept, no `*Impl`.
- [ ] Extension functions are verbs on the receiver (`String.toEmail()`).
- [ ] Companion factories use established verbs (`create`, `of`, `from`, `parse`).
- [ ] File names match the principal class or use plural for top-level helpers.
- [ ] Package names lowercase, dot-separated.
- [ ] `*OrNull` / `*OrEmpty` / `try*` only when ambiguity warrants.
- [ ] Operator overloads have conventional meaning.
- [ ] `suspend` / `Flow` not repeated in the function name.
- [ ] Backticked names only in tests or Java interop.
- [ ] `typealias` only for verbose generics; use `value class` for type safety.
- [ ] No `*Utils` objects — top-level functions or extensions instead.
- [ ] Compile-time constants `UPPER_SNAKE_CASE` with `const val`.
- [ ] `*Impl` only when there is genuinely no specific name for the implementation.
