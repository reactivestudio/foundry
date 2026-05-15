# Clean Code — Naming Practices

Bad/best examples organised by topic. Read this when you want concrete patterns to copy. For the WHY behind each rule, see `theory.md`. For the high-level checklist, see `../SKILL.md`.

Examples use plain Kotlin syntax — no language-specific idioms (coroutines, scope functions, extensions). Stack-specific naming lives in `kotlin/`, `framework/`, `ddd/` skills.

## Implicit context → intent-revealing

```kotlin
// Bad — what are these numbers? what is in theList?
fun getThem(): List<IntArray> {
    val list1 = mutableListOf<IntArray>()
    for (x in theList) if (x[0] == 4) list1.add(x)
    return list1
}

// Good
fun getFlaggedCells(): List<Cell> {
    val flaggedCells = mutableListOf<Cell>()
    for (cell in gameBoard) if (cell.isFlagged()) flaggedCells.add(cell)
    return flaggedCells
}
```

## Magic numbers → named constants

```kotlin
// Bad
for (j in 0..33) s += t[j] * 4 / 5

// Good
for (j in 0 until NUMBER_OF_TASKS) {
    val realTaskDays = taskEstimate[j] * realDaysPerIdealDay
    val realTaskWeeks = realTaskDays / workDaysPerWeek
    sum += realTaskWeeks
}
```

## Noise-word triplet → distinct verbs

```kotlin
// Bad — caller can't tell which to call
fun getActiveAccount(): Account
fun getActiveAccounts(): List<Account>
fun getActiveAccountInfo(): AccountInfo

// Good — verb encodes intent
fun findActiveAccount(id: Long): Account
fun listActiveAccounts(): List<Account>
fun activeAccountSummary(id: Long): AccountSummary
```

## Cryptic / Hungarian → clean

```kotlin
// Bad
class DtaRcrd102 {
    private val genymdhms: Date = Date()
    private val modymdhms: Date = Date()
    private val pszqint: String = "102"
}

// Good
class Customer {
    val generationTimestamp: Date = Date()
    val modificationTimestamp: Date = Date()
    val recordId: String = "102"
}
```

## Side effects in the name (Rule N7)

```kotlin
// Bad — get* promises cheap, idempotent fetch but constructs a socket
class Server {
    private var oos: ObjectOutputStream? = null
    fun getOos(): ObjectOutputStream {
        if (oos == null) oos = ObjectOutputStream(socket.outputStream)
        return oos!!
    }
}

// Good — name reveals the side effect
fun getOrCreateOos(): ObjectOutputStream { ... }

// Better — restructure so construction is explicit
class Server {
    val oos: ObjectOutputStream by lazy { ObjectOutputStream(socket.outputStream) }
}
```

## Level of abstraction (Rule N2)

```kotlin
// Bad — name commits to dial-up implementation
interface Modem {
    fun dial(phoneNumber: String): Boolean
    fun connectedPhoneNumber(): String
}

// Good — works for cable, USB, dial-up, Bluetooth
interface Modem {
    fun connect(locator: String): Boolean
    fun connectedLocator(): String
}
```

## Abstract-name red list in action

```kotlin
// Bad — abstract nouns hide what the class actually is
class OrderItem(...)
class OrderData(...)
class OrderInfo(...)
class OrderThing(...)

// Good — concrete domain word
class OrderLine(...)             // line item on an order
class OrderSnapshot(...)         // historical view
class OrderSummary(...)          // reduced view
```

## Verb-shaped suffixes hide the real name

```kotlin
// Bad — verb is buried in *Manager/*Helper/*Processor
class OrderManager(...)
class PaymentHelper(...)
class SessionProcessor(...)

// Good — pull the verb out with -er suffix
class OrderSubmitter(...)
class PaymentReconciler(...)
class SessionAuthenticator(...)
```

## One-word default

```kotlin
// Bad — stack noise in the suffix
class OrderEntity(...)
class OrderModel(...)
class OrderDto(...)
class OrderImpl : Order

// Good — the domain term, period
class Order private constructor(...) {
    fun submit() { ... }
}
```

Two words earn the second when the domain actually distinguishes:

```kotlin
class PurchaseOrder(...)   // legitimate if SalesOrder also exists
class SalesOrder(...)

class ShippingAddress(...) // legitimate if BillingAddress also exists
class BillingAddress(...)
```

Test: drop the second word — does the domain lose meaning? If no, one word is enough.

## Negated booleans

```kotlin
// Bad
fun isNotDisabled(): Boolean
fun hasNoErrors(): Boolean

// Good
fun isEnabled(): Boolean
fun isValid(): Boolean
```

Double-negation in conditional expressions (`if (!isNotDisabled)`) is unforgivable.

## Conjunctions in class names

```kotlin
// Bad — the "And" is the smell
class OrderAndPaymentValidator(...)

// Good — split, or find the higher-level concept
class OrderValidator(...)
class PaymentValidator(...)
// or:
class CheckoutValidator(...)  // if there's a real higher-level concept
```

## Conversion methods in pairs

```kotlin
// Bad — asymmetric, no signal of the inverse relationship
fun toDomain(): Order
fun mapBack(): OrderRow

// Good — symmetric pair
fun toDomain(): Order
fun fromRow(row: OrderRow): Order
```

## Static factory methods with intent

```kotlin
// Bad — overloaded constructor; reader can't tell what 23.0 means
val fulcrum = Complex(23.0)

// Good — factory method names the role
val fulcrum = Complex.fromRealNumber(23.0)
val imaginary = Complex.fromImaginary(23.0)
```

Make the corresponding constructor private to enforce the factory.

## Context via class extraction

```kotlin
// Bad — number/verb/pluralModifier opaque, scope-bound to the function
fun printGuessStatistics(candidate: Char, count: Int) {
    val number: String = ...
    val verb: String = ...
    val pluralModifier: String = ...
    // ... 20 lines computing all three
}

// Good — context-bearing class, fields no longer ambiguous
class GuessStatisticsMessage(private val candidate: Char, private val count: Int) {
    private val number: String = ...
    private val verb: String = ...
    private val pluralModifier: String = ...
    fun render(): String = ...
}
```

Side effect: once context moves into a class, the original function shrinks into a few small methods.

## Gratuitous context (the GSD trap)

```kotlin
// Bad — project prefix on every class
class GSDAccountAddress(...)
class GSDCustomer(...)
class GSDPaymentMethod(...)

// Good — package carries the project context
// in package com.gsd.accounting
class Address(...)
class Customer(...)
class PaymentMethod(...)
```

Differentiate only when types actually collide:

```kotlin
class PostalAddress(...)
class MacAddress(...)
class WebAddress(...)
```
