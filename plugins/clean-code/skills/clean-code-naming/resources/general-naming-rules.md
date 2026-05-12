# General Naming Rules

Universal naming rules adapted from R. Martin's *Clean Code* (Ch. 2 "Meaningful Names" + Ch. 17 §N1-N7). Rules obsolete in Kotlin (Hungarian, `m_` prefix, `I*` for interface, JavaBean getter/setter) are pointed to `kotlin-specific-naming.md`; framework-specific applications go to `spring-boot-naming.md`; DDD-specific names to `ddd-naming.md`.

> "The hardest thing about choosing good names is that it requires good descriptive skills and a shared cultural background." — Martin

## How to read this file

Each rule has:
- **Principle** — the one-sentence rule.
- **Bad / Good** — Kotlin snippets adapted from Martin's Java originals.
- **Why** — the failure mode the rule prevents.
- **Exception** — when the rule legitimately bends.
- **House extension** (where applicable) — opinionated additions on top of Martin.

---

## Rule 1: Use Intention-Revealing Names

**Source**: Martin Ch. 2 §1
**Principle**: A name should answer why something exists, what it does, and how it is used. If a name needs a comment, the name is wrong.

**Bad**:
```kotlin
val d: Int = 0   // elapsed time in days
```

**Good**:
```kotlin
val elapsedDays: Int = 0
val daysSinceCreation: Int = 0
val fileAgeInDays: Int = 0
```

**Larger example** — what does this do?
```kotlin
fun getThem(): List<IntArray> {
    val list1 = mutableListOf<IntArray>()
    for (x in theList)
        if (x[0] == 4) list1.add(x)
    return list1
}
```

After:
```kotlin
fun flaggedCells(): List<Cell> =
    gameBoard.filter { cell -> cell.isFlagged() }
```

Same algorithm, same loop count — but every name now reveals intent.

**Why**: The reader should not maintain a mental dictionary of single-letter aliases. The cost of a longer name is paid once at the keyboard; the cost of an unreadable name is paid every read.

---

## Rule 2: Avoid Disinformation

**Source**: Martin Ch. 2 §2
**Principle**: Don't use words whose entrenched meanings differ from yours. Don't pick names that look alike.

**Bad**:
```kotlin
val accountList: Set<Account> = ...        // it's not a List
val l = 1
val O = 0
val XYZControllerForEfficientHandlingOfStrings = ...
val XYZControllerForEfficientStorageOfStrings  = ...  // nearly identical
```

**Good**:
```kotlin
val accounts: Set<Account> = ...
val maxLineLength = 80
val zero = 0
val stringHandlingController = ...
val stringStorageController = ...
```

**Why**: `List` is a type to Kotlin programmers — calling a `Set` an `accountList` lies. Lowercase `l` and uppercase `O` mimic the digits 1 and 0. Names that vary in tiny ways defeat IDE autocomplete and code review.

**Exception**: Iteration variables `i`, `j`, `k` in tight loops are tradition strong enough to remain readable. `l` is forbidden — too easily confused with 1.

---

## Rule 3: Make Meaningful Distinctions

**Source**: Martin Ch. 2 §3
**Principle**: If two names differ, they must mean something different. Number suffixes (`a1`, `a2`) and noise words (`Info`, `Data`, `Object`, `Manager`) are not distinctions.

**Bad**:
```kotlin
class Product(...)
class ProductInfo(...)         // what's the difference?
class ProductData(...)         // and this one?

fun copyChars(a1: CharArray, a2: CharArray) { ... }

fun getActiveAccount(): Account
fun getActiveAccounts(): List<Account>
fun getActiveAccountInfo(): Account    // which one do I call?
```

**Good**:
```kotlin
class Product(...)                     // the canonical name
class ProductCatalogEntry(...)         // only if you genuinely need a second concept

fun copyChars(source: CharArray, destination: CharArray) { ... }

fun activeAccount(): Account
fun activeAccounts(): List<Account>
fun activeAccountSummary(): AccountSummary
```

**House extension — the one-word rule**: when in doubt between `Product` and `ProductInfo`, the answer is almost always "just `Product`". A second word must add genuine domain meaning, not synonym noise. See SKILL.md §"The one-word rule".

---

## Rule 4: Use Pronounceable Names

**Source**: Martin Ch. 2 §4
**Principle**: Names get spoken aloud — in standups, pairing, code review. If you can't pronounce it, you can't discuss it.

**Bad**:
```kotlin
class DtaRcrd102 {
    val genymdhms: Instant     // "gen-why-em-dee-aitch-em-ess"
    val modymdhms: Instant
    val pszqint = "102"
}
```

**Good**:
```kotlin
class Customer {
    val generationTimestamp: Instant
    val modificationTimestamp: Instant
    val recordId = "102"
}
```

---

## Rule 5: Use Searchable Names

**Source**: Martin Ch. 2 §5
**Principle**: Numeric constants and single-letter names are hard to grep. Length should scale with scope.

**Bad**:
```kotlin
for (j in 0..33) s += (t[j] * 4) / 5
```

**Good**:
```kotlin
const val WORK_DAYS_PER_WEEK = 5
val realDaysPerIdealDay = 4
for (taskIndex in 0 until NUMBER_OF_TASKS) {
    val realTaskDays = taskEstimate[taskIndex] * realDaysPerIdealDay
    val realTaskWeeks = realTaskDays / WORK_DAYS_PER_WEEK
    sum += realTaskWeeks
}
```

**Exception**: Loop counter `i` inside a 3–5-line `for` is fine. The rule is "length proportional to scope".

---

## Rule 6: Avoid Encodings

**Source**: Martin Ch. 2 §6 + Ch. 17 §N6
**Principle**: Don't encode type, scope, or visibility into names. Modern languages and IDEs do this for you.

**Obsolete in Kotlin — see `kotlin-specific-naming.md`** for the full treatment. Forbidden encodings:
- Hungarian Notation: `strName`, `intCount`, `lstOrders`
- Member prefix: `m_description`, `_count`
- Interface marker: `IOrderRepository`
- Implementation marker as default: `OrderRepositoryImpl` (sometimes tolerated — see kotlin file)

**Bad**:
```kotlin
interface IOrderRepository {
    fun findById(id: String): IOrder?
}
class OrderRepositoryImpl : IOrderRepository {
    private val m_orders: MutableList<Order> = ...
}
```

**Good**:
```kotlin
interface OrderRepository {
    fun findById(id: OrderId): Order?
}
class JpaOrderRepository(...) : OrderRepository {
    private val orders: MutableList<Order> = ...
}
```

**Why**: Kotlin's type system, `val` / `var` distinction, visibility modifiers, and IDE colouring handle everything these encodings tried to encode in older languages.

---

## Rule 7: Avoid Mental Mapping

**Source**: Martin Ch. 2 §7
**Principle**: The reader should not translate your names to figure out what they mean.

**Bad**:
```kotlin
fun process(r: String) {       // r = "the lowercased URL with host and scheme removed"
    ...
}
```

**Good**:
```kotlin
fun process(urlPath: String) { ... }
```

---

## Rule 8: Class Names — Nouns, Not Verbs; Concrete, Not Abstract

**Source**: Martin Ch. 2 §8
**Principle**: Classes are nouns or noun phrases (`Customer`, `WikiPage`, `AddressParser`). Avoid abstract nouns (`Manager`, `Processor`, `Data`, `Info`). A class name is never a verb.

See SKILL.md §"The abstract-name red list" for the full forbidden list and replacements.

**Bad**:
```kotlin
class OrderManager(...)        // verb hidden inside
class OrderProcessor(...)      // same
class OrderInfo(...)           // noise word
class ProcessOrder(...)        // verb as class name
```

**Good**:
```kotlin
class Order(...)               // the noun
class OrderSubmitter(...)      // -er from the hidden verb "submit"
class OrderSnapshot(...)       // if you really need a read model, name what it is
```

---

## Rule 9: Method Names — Verbs or Verb Phrases

**Source**: Martin Ch. 2 §9
**Principle**: Methods are verbs. Booleans use `is*` / `has*` / `can*` / `should*`. Static factory methods describe arguments.

**Note**: Martin's JavaBean `get` / `set` prefix is **obsolete in Kotlin** — properties replace them. See `kotlin-specific-naming.md`.

**Bad**:
```kotlin
order.statusUpdate(SUBMITTED)
account.active()                  // returning Boolean?
val c = Complex(23.0)             // doesn't say what 23.0 is
```

**Good**:
```kotlin
order.submit()
account.isActive()                // or: val isActive: Boolean
val fulcrum = Complex.fromRealNumber(23.0)
```

---

## Rule 10: Don't Be Cute

**Source**: Martin Ch. 2 §10
**Principle**: Clarity over cleverness. No jokes, no slang, no cultural references in method names.

**Bad**:
```kotlin
fun holyHandGrenade()           // means: deleteItems
fun whack()                     // means: kill
fun eatMyShorts()               // means: abort
```

**Good**:
```kotlin
fun deleteItems()
fun kill()
fun abort()
```

**Why**: The joke ages out; the next reader doesn't share your sense of humour; translators and non-native English speakers are stranded.

---

## Rule 11: Pick One Word per Concept

**Source**: Martin Ch. 2 §11
**Principle**: Pick one verb for one operation and use it consistently across the codebase. Don't have `fetch` in one class, `retrieve` in another, `get` in a third.

**Bad** (three classes in the same module):
```kotlin
class OrderRepository { fun fetchById(id: OrderId): Order? }
class CustomerRepository { fun retrieveById(id: CustomerId): Customer? }
class PaymentRepository { fun getById(id: PaymentId): Payment? }
```

**Good**:
```kotlin
class OrderRepository { fun findById(id: OrderId): Order? }
class CustomerRepository { fun findById(id: CustomerId): Customer? }
class PaymentRepository { fun findById(id: PaymentId): Payment? }
```

**Why**: Three vocabularies for one operation means three places to look when searching, three idioms to remember, three styles in the same review.

---

## Rule 12: Don't Pun

**Source**: Martin Ch. 2 §12
**Principle**: Avoid using the same word for two different operations. If `add` means "concatenate" in some classes and "insert into collection" in others, the consistency is fake.

**Bad**:
```kotlin
class Money { fun add(other: Money): Money }     // arithmetic add
class Cart  { fun add(item: CartLine) }          // insert — different semantics
```

**Good**:
```kotlin
class Money { fun plus(other: Money): Money }    // or use the + operator
class Cart  { fun include(item: CartLine) }      // or insert / append
```

---

## Rule 13: Use Solution Domain Names

**Source**: Martin Ch. 2 §13
**Principle**: Use CS / pattern / algorithm names freely — your audience are programmers.

**Good**:
```kotlin
class AccountVisitor(...)       // Visitor pattern reference
class JobQueue(...)             // standard data structure
class CircuitBreaker(...)       // resilience term
```

These are *better* than inventing project-specific names because the reader already knows them.

---

## Rule 14: Use Problem Domain Names

**Source**: Martin Ch. 2 §14
**Principle**: When there is no programmer-ese, use the business term. The maintainer can ask a domain expert.

This is the gateway to DDD's *ubiquitous language*. See `ddd-naming.md` for the full discipline.

**Good**:
```kotlin
class Reservation(...)          // business term
class Cohort(...)               // education domain
class Underwriter(...)          // insurance domain
```

---

## Rule 15: Add Meaningful Context

**Source**: Martin Ch. 2 §15
**Principle**: A bare `state` variable is ambiguous; inside a class `Address`, the same field is obvious. Group related names via classes / namespaces; prefix only as a last resort.

**Bad**:
```kotlin
fun printGuessStatistics(candidate: Char, count: Int) {
    val number: String
    val verb: String
    val pluralModifier: String
    // ... 20 lines computing number/verb/pluralModifier
}
```

**Good**:
```kotlin
class GuessStatisticsMessage(private val candidate: Char, private val count: Int) {
    fun render(): String { ... }
    private fun number(): String { ... }
    private fun verb(): String { ... }
    private fun pluralModifier(): String { ... }
}
```

**Why**: The class name carries the context. Inside, `number` / `verb` / `pluralModifier` are no longer ambiguous.

---

## Rule 16: Don't Add Gratuitous Context

**Source**: Martin Ch. 2 §16
**Principle**: Don't prefix every class with the project / module abbreviation. Shorter names beat longer ones if they're still clear.

**Bad** (project called "Gas Station Deluxe"):
```kotlin
class GSDAccountAddress(...)
class GSDCustomer(...)
class GSDPaymentMethod(...)
```

**Good**:
```kotlin
// in package com.gsd.accounting
class Address(...)
class Customer(...)
class PaymentMethod(...)
```

**House note on Spring Modulith**: don't repeat the bounded-context name in the class — the package already says it. `pricing.Product` good; `pricing.PricingProduct` redundant. See `ddd-naming.md`.

---

## Rule N1: Choose Descriptive Names

**Source**: Martin Ch. 17 §N1
**Principle**: Names tend to drift. Re-evaluate as the code evolves; rename when the meaning has moved.

**Bad** (bowling scoring code):
```kotlin
fun x(): Int {
    var q = 0
    var z = 0
    for (kk in 0..9) {
        if (l[z] == 10) { q += 10 + (l[z + 1] + l[z + 2]); z += 1 }
        else if (l[z] + l[z + 1] == 10) { q += 10 + l[z + 2]; z += 2 }
        else { q += l[z] + l[z + 1]; z += 2 }
    }
    return q
}
```

**Good**:
```kotlin
fun score(): Int {
    var score = 0
    var frame = 0
    for (frameNumber in 0..9) {
        when {
            isStrike(frame) -> { score += 10 + nextTwoBallsForStrike(frame); frame += 1 }
            isSpare(frame)  -> { score += 10 + nextBallForSpare(frame);  frame += 2 }
            else            -> { score += twoBallsInFrame(frame);         frame += 2 }
        }
    }
    return score
}
```

The structure has not changed — only the names. But every reader now understands what the algorithm does without running it.

---

## Rule N2: Choose Names at the Appropriate Level of Abstraction

**Source**: Martin Ch. 17 §N2
**Principle**: Don't pick names that commit to a specific implementation. Names should fit every legitimate use of the abstraction.

**Bad**:
```kotlin
interface Modem {
    fun dial(phoneNumber: String): Boolean    // assumes dial-up
    fun connectedPhoneNumber(): String
}
```

**Good**:
```kotlin
interface Modem {
    fun connect(locator: String): Boolean
    fun connectedLocator(): String
}
```

The second works for cable, USB, and dial-up alike.

---

## Rule N3: Use Standard Nomenclature

**Source**: Martin Ch. 17 §N3
**Principle**: Patterns and conventions provide free vocabulary. Use them.

**Good**:
- Pattern names: `AutoHangupModemDecorator` (Decorator pattern)
- Language conventions: `toString()`, `equals()`, `hashCode()`
- DDD ubiquitous language — see `ddd-naming.md`

---

## Rule N4: Unambiguous Names

**Source**: Martin Ch. 17 §N4
**Principle**: A name must distinguish the function from its peers. `doRename` is hopeless when the same class has `renamePage`.

**Bad**:
```kotlin
fun doRename(): String {
    if (refactorReferences) renameReferences()
    renamePage()
    ...
}
```

**Good**:
```kotlin
fun renamePageAndOptionallyAllReferences(): String { ... }
```

Yes, it's long. But it's only called from one place and the explanatory value outweighs the length.

---

## Rule N5: Use Long Names for Long Scopes

**Source**: Martin Ch. 17 §N5
**Principle**: Variable name length should be proportional to scope. A 5-line scope tolerates `i`; a 50-line method does not.

**Good**:
```kotlin
private fun rollMany(n: Int, pins: Int) {
    for (i in 0 until n) game.roll(pins)    // i is fine
}
```

```kotlin
class OrderProcessingPipeline {
    private val currentBatchIndex = 0       // long scope → long name
    ...
}
```

---

## Rule N6: Avoid Encodings

Merged with Rule 6 above.

---

## Rule N7: Names Should Describe Side Effects

**Source**: Martin Ch. 17 §N7
**Principle**: A name must not hide what the function actually does, especially if it has side effects.

**Bad**:
```kotlin
fun getOos(): ObjectOutputStream {
    if (oos == null) oos = ObjectOutputStream(socket.outputStream)
    return oos!!
}
```

**Good**:
```kotlin
fun getOrCreateOos(): ObjectOutputStream {
    if (oos == null) oos = ObjectOutputStream(socket.outputStream)
    return oos!!
}
```

Or — better still — restructure so creation is explicit:
```kotlin
val oos: ObjectOutputStream by lazy {
    ObjectOutputStream(socket.outputStream)
}
```

**Why**: `get` promises a cheap, idempotent fetch. A `get` that constructs, opens a socket, or makes a network call lies to the caller about cost and failure modes.

---

## House extension: Naming-as-API discipline

These are not in Martin — they reflect the additional constraints of modern Kotlin/Spring services.

### House rule 1: Verbs for state transitions, not setters

Setters on aggregates are anti-patterns in DDD. State transitions are named operations.

**Bad**:
```kotlin
order.setStatus(SUBMITTED)
```

**Good**:
```kotlin
order.submit()
```

See `ddd-naming.md` §"Aggregate operations".

### House rule 2: Conversion methods come in pairs

Inverse operations should be named symmetrically.

**Good**:
```kotlin
fun toDomain(): Order
fun toRow(): OrderRow

fun toView(): OrderView
fun fromSubmission(submission: OrderSubmission): Order
```

**Bad** (asymmetric):
```kotlin
fun toDomain(): Order
fun mapBack(): OrderRow         // no relation to toDomain
```

### House rule 3: Don't conjoin in class names

A class doing two things should be two classes. The conjunction is the smell.

**Bad**:
```kotlin
class OrderAndPaymentValidator(...)
```

**Good**:
```kotlin
class OrderValidator(...)
class PaymentValidator(...)
// or: class CheckoutValidator(...) if there's a higher-level concept
```

### House rule 4: Negation is never the natural form of a boolean

**Bad**:
```kotlin
fun isNotDisabled(): Boolean
fun hasNoErrors(): Boolean
```

**Good**:
```kotlin
fun isEnabled(): Boolean
fun isValid(): Boolean
```

Double negation in conditional expressions (`if (!isNotDisabled)`) is unforgivable.

---

## Summary checklist

Before merging a new class, run this list:

- [ ] Class name is a noun, not a verb.
- [ ] Class name is from the domain, not from the framework or container type.
- [ ] Class name is one word, unless the domain genuinely needs the second.
- [ ] No abstract-noun suffix (Item, Data, Info, Object, Detail, Element, Entity, Manager, Helper, Util).
- [ ] No stack-noise suffix (`*Dto`, `*Model`, `*Impl`, `*Bean`) unless explicitly justified.
- [ ] Method names are verbs; booleans use `is` / `has` / `can` / `should` prefix.
- [ ] No `get*` method that does non-trivial work (creation, IO, computation).
- [ ] No conjunctions in class names (`X-And-Y`).
- [ ] No negated booleans (`isNotDisabled`).
- [ ] No project-wide prefix (`GSDOrder` in the GSD project).
- [ ] No bounded-context name repeated when already in the package.
- [ ] Conversion methods exist in pairs.
- [ ] Long-scope names are search-friendly; short-scope names can be terse.
