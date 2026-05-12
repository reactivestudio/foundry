# SOLID — Kotlin Idioms

How each principle looks in idiomatic Kotlin. The principle is the same as in Java; the code shrinks because Kotlin gives you sealed hierarchies, `value class`, `by` delegation, scope functions, function types, and proper read-only/mutable variance.

For the principle definitions, see `theory.md`. For Spring usage, see `spring-boot.md`. For violations and fixes, see `bad-practices.md`.

---

## S — SRP in Kotlin

Kotlin makes splitting cheap. Several language features lower the friction of "many small classes":

### Primary-constructor properties keep new classes terse

```kotlin
@Service
class UserRegistration(
    private val users: UserRepository,
    private val hasher: PasswordHasher,
    private val publisher: ApplicationEventPublisher,
) {
    fun register(req: RegisterRequest): User { ... }
}
```

A new focused service is a one-line declaration. No field-at-top boilerplate, no `this.x = x` constructor body. The cost of "yet another small class" is near zero — so use it.

### Top-level functions for stateless responsibilities

Not everything needs to be a class. A pure transformation can live as a top-level `fun`:

```kotlin
// In pricing.kt, no class needed
fun applyVat(amount: Money, country: Country): Money = ...
```

Top-level functions express the smallest possible single responsibility. Use them for pure functions; promote to a class when state or DI appears.

### `internal` for module-private helpers

You can split a god class into `internal` collaborators that aren't part of the module's public API:

```kotlin
@Service
class PlaceOrderHandler(...) {
    fun handle(cmd: PlaceOrderCommand): OrderId { ... }
}

internal class PlaceOrderValidator(...) { ... }
internal class PlaceOrderPriceCalculator(...) { ... }
```

The handler keeps the public face; the validators / calculators are siblings within the module. SRP without polluting the public surface.

---

## O — OCP in Kotlin

Sealed hierarchies plus exhaustive `when` are the canonical OCP toolkit in Kotlin.

### Sealed interface + per-variant override

```kotlin
sealed interface PaymentMethod {
    fun process(amount: Money): Result
    fun fee(amount: Money): Money
    fun supports(country: Country): Boolean

    data object Card : PaymentMethod {
        override fun process(amount: Money) = chargeCard(amount)
        override fun fee(amount: Money) = amount * 0.029
        override fun supports(country: Country) = true
    }

    data object BankTransfer : PaymentMethod {
        override fun process(amount: Money) = initiateBankTransfer(amount)
        override fun fee(amount: Money) = Money.zero(amount.currency)
        override fun supports(country: Country) = country in setOf(Country.DE, Country.FR, Country.ES)
    }
}
```

Adding `Crypto` is one new `data object`. No `when`-chain to chase across files.

### `data object` for stateless variants

`data object` is Kotlin's stateless singleton with `equals`/`hashCode`/`toString` derived. Perfect for variant types whose identity is only the type itself.

### Function types as zero-cost Strategy

For per-call variation, a function type beats a sealed hierarchy:

```kotlin
fun price(cart: Cart, discount: (Cart) -> Money): Money =
    cart.subtotal() - discount(cart)

price(cart, discount = { Money.zero(EUR) })
price(cart, discount = ::standardDiscount)
price(cart, discount = ::vipDiscount)
```

OCP via function passing, no class needed. Use sealed types when the variants need to be discoverable / DI-injected / named.

### When to *not* introduce a sealed hierarchy

If a `when` chain has only one place and is unlikely to grow, leave it. Premature sealing is the OCP equivalent of premature optimisation.

---

## L — LSP in Kotlin

The contract rules from `theory.md` translate directly. Kotlin adds a few language-level traps and a few language-level safeguards.

### Trap: nullability narrowing in overrides

```kotlin
open class Greeter {
    open fun greet(name: String?): String = "Hello, ${name ?: "stranger"}"
}

class ShoutyGreeter : Greeter() {
    override fun greet(name: String?): String =
        "HI, ${name!!.uppercase()}"   // LSP violation: parent accepts null, child crashes
}
```

The signature still accepts `String?`, but the override narrows the precondition (`name` cannot be null). Callers using the parent type will fail with the child.

### Safeguard: read-only vs mutable collection variance

`List<Cat>` IS-A `List<Animal>` in Kotlin (because `List<out T>` is covariant). `MutableList<Cat>` is **not** assignable to `MutableList<Animal>` — invariant. The split between read-only and mutable collections is precisely the LSP-correct generic design:

```kotlin
fun feed(animals: List<Animal>) { ... }
val cats: List<Cat> = listOf(...)
feed(cats)                    // works — covariant on read

val animals: MutableList<Animal> = mutableListOf()
val cats: MutableList<Cat> = mutableListOf()
// animals = cats             // compile error — would let you add Dog to List<Cat>
```

Lean on `List` / `Map` / `Set` (read-only views) at API boundaries. Reach for `MutableList` only inside the implementation.

### Sealed hierarchies sidestep LSP violations

If you find yourself overriding a base class to disable behaviour, the hierarchy is wrong. Split it into a sealed type:

```kotlin
sealed interface Bird

sealed interface FlyingBird : Bird {
    fun fly()
}

class Sparrow : FlyingBird { override fun fly() { ... } }
class Penguin : Bird          // no fly() — correct hierarchy
```

The compiler now refuses any code that tries to fly a `Penguin`.

### `value class` against LSP-via-stringly-typing

Passing a `String` for a UserId where the domain expects a CustomerId is a runtime LSP-style trap (any string substitutes — but most strings break the contract). Wrap in a `value class`:

```kotlin
@JvmInline value class UserId(val value: UUID)
@JvmInline value class CustomerId(val value: UUID)
```

Now the type system enforces that a `UserId` is not a substitute for a `CustomerId`. Zero runtime cost.

---

## I — ISP in Kotlin

Kotlin's `interface` is lightweight; segregating costs almost nothing.

### Small role interfaces, composed at the implementation site

```kotlin
interface UserReader {
    fun findById(id: UserId): User?
    fun findByEmail(email: Email): User?
    fun exists(id: UserId): Boolean
}

interface UserWriter {
    fun save(user: User): User
    fun delete(id: UserId)
}

interface UserBulkOps {
    fun bulkInsert(users: List<User>)
    fun pageBy(filter: UserFilter, page: Pageable): Page<User>
}

class InMemoryUserRepository : UserReader, UserWriter   // no bulk
class JpaUserRepository(...) : UserReader, UserWriter, UserBulkOps   // full
```

Clients depend on the smallest interface that meets their need: `OrderService(private val users: UserReader)` — not `UserRepository`.

### `fun interface` (SAM) for one-method roles

Single-Abstract-Method interfaces become functional types:

```kotlin
fun interface PriceCalculator {
    fun price(cart: Cart): Money
}

val flatRate = PriceCalculator { cart -> cart.subtotal() }
val withDiscount = PriceCalculator { cart -> cart.subtotal() * 0.9 }
```

Effectively makes Strategy (and per-method ISP roles) ergonomic.

### Extension functions for opt-in capabilities

You can extend an interface from outside without modifying it:

```kotlin
interface UserReader { fun findById(id: UserId): User? }

fun UserReader.findByIdOrThrow(id: UserId): User =
    findById(id) ?: throw NotFoundException("User", id.value)
```

`findByIdOrThrow` is now available wherever `UserReader` is in scope — without adding a method to the interface, without forcing every implementer to provide it.

---

## D — DIP in Kotlin

DIP in Kotlin is the same as in Java conceptually; the idioms make it less ceremonious.

### Constructor-injected interfaces

```kotlin
class OrderService(
    private val repository: OrderRepository,        // interface in domain/
    private val notifications: NotificationService, // interface in domain/
) {
    fun place(req: PlaceOrderRequest): Order { ... }
}
```

Constructor injection IS DIP in Kotlin. Field injection (`@Autowired lateinit var`) breaks immutability and hides the dependency — avoid.

### Function types as ad-hoc abstractions

For a single point of variation, you don't even need an interface. A function type IS an abstraction:

```kotlin
class PaymentProcessor(
    private val charge: (Money, Customer) -> Result<TransactionId>,
) {
    fun process(amount: Money, customer: Customer): TransactionId =
        charge(amount, customer).getOrThrow()
}
```

In tests: pass a fake lambda. In production: pass `stripeGateway::charge`. No interface needed.

### `by` delegation as composition over inheritance

```kotlin
interface OrderRepository {
    fun findById(id: OrderId): Order?
    fun save(order: Order): Order
}

class CachingOrderRepository(
    private val inner: OrderRepository,
    private val cache: Cache<OrderId, Order>,
) : OrderRepository by inner {
    override fun findById(id: OrderId): Order? = cache.get(id) { inner.findById(id) }
}
```

The decorator/cache wrapper depends on the abstraction `OrderRepository` and reuses the implementation via delegation — overriding only the method that needs custom behaviour. Pure DIP, plus DRY.

### Domain-layer purity check

In a strictly DIP-compliant Kotlin project, `domain/` files import nothing from `org.springframework.*`, `org.hibernate.*`, `software.amazon.*`. If they do, infrastructure has leaked into the domain — DIP violation.

You can enforce this with ArchUnit tests (see `architecture-patterns`).

---

## SOLID-friendly Kotlin features at a glance

| Feature | Which principle it serves |
|---|---|
| `data class` + `copy()` | LSP (immutable carrier; no override surprises), SRP (single shape) |
| `sealed interface` / `sealed class` | OCP (closed extension surface), LSP (compile-time exhaustiveness) |
| `data object` | OCP (stateless variant), single-instance singleton without ceremony |
| `value class` (`@JvmInline`) | LSP (no stringly-typed substitution), SRP (single semantic) |
| `by` delegation | DIP (compose, don't inherit), ISP (delegate to small interfaces) |
| `fun interface` (SAM) | ISP (one-method role), DIP (lambda as abstraction) |
| Function types | OCP (pass a lambda for variation), DIP (lambda as ad-hoc abstraction) |
| Extension functions | ISP (add behaviour without bloating the interface), OCP (extend types you don't own) |
| `internal` visibility | SRP (split a god class into module-private helpers without polluting the public API) |
| Read-only `List<out T>` | LSP (covariance only where safe; mutable collections stay invariant) |
| Top-level functions | SRP (a stateless responsibility doesn't need a class) |

---

## What Kotlin does *not* solve

- **God services with too many constructor dependencies.** Kotlin won't tell you the class has six reasons to change. Read `bad-practices.md`.
- **Premature OCP.** Sealed hierarchies are cheap to write; that's exactly why people add them when they shouldn't. Wait for the second case.
- **LSP violations via behaviour, not type.** A subclass that "remembers more than the parent does" passes the type checker but breaks the contract. The contract rules in `theory.md` are still on you.
- **Domain leaks via convenience.** A `@Transactional` annotation in `domain/` is a DIP violation Kotlin won't flag. ArchUnit / Spring Modulith tests catch this.
