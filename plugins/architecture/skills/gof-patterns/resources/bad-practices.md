# GoF — Bad Practices Catalogue

Java-flavoured anti-patterns and ceremony that show up in Kotlin codebases — usually from translation, from teams new to Kotlin, or from "I memorised GoF and now I see patterns everywhere" enthusiasm. Each entry: smell → why it's wrong → idiomatic Kotlin fix.

---

## Java-flavoured Singleton ceremony

### G-1: Hand-rolled Singleton via private constructor + companion field

**Smell.**

```kotlin
class PricingPolicy private constructor() {
    companion object {
        @JvmStatic val INSTANCE = PricingPolicy()
    }
    fun applyTax(amount: Money): Money = ...
}

PricingPolicy.INSTANCE.applyTax(money)
```

**Why it's wrong.** This is a Java idiom transliterated to Kotlin. Kotlin has `object` for this exact case — thread-safe, lazy, no ceremony.

**Fix.**

```kotlin
object PricingPolicy {
    fun applyTax(amount: Money): Money = ...
}

PricingPolicy.applyTax(money)
```

### G-2: Manual Singleton when Spring DI would do

**Smell.** A `@Service` that uses `object Singleton.INSTANCE` to access shared state, when Spring's bean container provides Singleton scope by default.

**Why it's wrong.** Hides the dependency; complicates testing; bypasses DI. Spring beans ARE singletons.

**Fix.** Inject the singleton bean via constructor injection. Let Spring manage the lifecycle.

---

## Java-flavoured Builder ceremony

### G-3: Fluent Builder when named arguments would do

**Smell.**

```kotlin
class HttpRequest private constructor(...) {
    class Builder {
        private var url: String = ""
        private var method: HttpMethod = HttpMethod.GET
        private var headers: MutableMap<String, String> = mutableMapOf()
        private var timeout: Duration = Duration.ofSeconds(10)

        fun url(url: String) = apply { this.url = url }
        fun method(m: HttpMethod) = apply { this.method = m }
        fun header(k: String, v: String) = apply { this.headers[k] = v }
        fun timeout(t: Duration) = apply { this.timeout = t }

        fun build() = HttpRequest(url, method, headers, timeout)
    }
}

val req = HttpRequest.Builder().url("...").method(HttpMethod.POST).header("Auth", "Bearer x").build()
```

**Why it's wrong.** Kotlin has named arguments + default values. The constructor IS the Builder. The fluent class adds boilerplate, mutable state, and an extra `.build()` step for nothing.

**Fix.**

```kotlin
class HttpRequest(
    val url: String,
    val method: HttpMethod = HttpMethod.GET,
    val headers: Map<String, String> = emptyMap(),
    val timeout: Duration = Duration.ofSeconds(10),
)

val req = HttpRequest(url = "...", method = HttpMethod.POST, headers = mapOf("Auth" to "Bearer x"))
```

### G-4: DSL when named arguments would do

**Smell.** Building a type-safe DSL for a one-off configuration that has 3 fields and is called once.

**Why it's wrong.** DSLs are heavy machinery — `@DslMarker`, scope receivers, builder lambdas. Worth it for repeated complex construction (HTML, Gradle); overkill for a single config object.

**Fix.** Named arguments. Promote to DSL only when the construction is genuinely repeated and complex.

---

## Java-flavoured Visitor

### G-5: Classical Visitor with `accept` / `visit` ceremony

**Smell.**

```kotlin
interface Shape {
    fun <R> accept(visitor: ShapeVisitor<R>): R
}

interface ShapeVisitor<R> {
    fun visitCircle(c: Circle): R
    fun visitRectangle(r: Rectangle): R
}

class Circle(val r: Double) : Shape {
    override fun <R> accept(visitor: ShapeVisitor<R>): R = visitor.visitCircle(this)
}

class Rectangle(val w: Double, val h: Double) : Shape {
    override fun <R> accept(visitor: ShapeVisitor<R>): R = visitor.visitRectangle(this)
}

class AreaVisitor : ShapeVisitor<Double> {
    override fun visitCircle(c: Circle) = PI * c.r * c.r
    override fun visitRectangle(r: Rectangle) = r.w * r.h
}

val area = shape.accept(AreaVisitor())
```

**Why it's wrong.** Visitor was invented to add operations over a hierarchy in languages without sealed types + exhaustive `when`. Kotlin has both. Sealed types let you add operations as new functions, with compile-time exhaustiveness — strictly better than Visitor.

**Fix.**

```kotlin
sealed class Shape
data class Circle(val r: Double) : Shape()
data class Rectangle(val w: Double, val h: Double) : Shape()

fun area(shape: Shape): Double = when (shape) {
    is Circle -> PI * shape.r * shape.r
    is Rectangle -> shape.w * shape.h
}
```

Adding `Triangle` causes a compile error in every `when` until handled. Exhaustiveness without ceremony.

---

## Java-flavoured Observer

### G-6: Hand-rolled `Observable` / `Observer`

**Smell.**

```kotlin
interface OrderObserver { fun onPlaced(order: Order) }

class OrderService {
    private val observers = mutableListOf<OrderObserver>()
    fun addObserver(obs: OrderObserver) { observers += obs }
    fun removeObserver(obs: OrderObserver) { observers -= obs }

    fun placeOrder(...) {
        ...
        observers.forEach { it.onPlaced(order) }
    }
}
```

**Why it's wrong.** Modern Kotlin/Spring has three idiomatic alternatives, all better:

1. **Spring `ApplicationEventPublisher` + `@EventListener` / `@ApplicationModuleListener`** — handles registration, transactional handoff, retry, outbox.
2. **Coroutine `Flow` / `StateFlow`** — for reactive in-process streams.
3. **Function-type subscriber** — for the simplest case, just pass `(Order) -> Unit` callbacks.

Hand-rolling Observer means re-implementing what frameworks already provide, badly.

**Fix.** Spring events:

```kotlin
@Service
class OrderService(private val events: ApplicationEventPublisher) {
    fun placeOrder(...) { ...; events.publishEvent(OrderPlaced(...)) }
}

@Component
class EmailNotifier { @ApplicationModuleListener fun on(e: OrderPlaced) { ... } }
```

---

## Java-flavoured Strategy

### G-7: Sealed Strategy with one variant

**Smell.**

```kotlin
sealed interface DiscountStrategy {
    fun apply(amount: Money): Money

    data object Standard : DiscountStrategy {
        override fun apply(amount: Money) = amount * 0.9
    }
}
```

One variant, no plan for a second. The sealed hierarchy is overhead.

**Why it's wrong.** Strategy is appropriate when you have *multiple* alternatives. With one, it's premature.

**Fix.** Inline the operation. Promote to Strategy when the second case appears:

```kotlin
fun applyStandardDiscount(amount: Money): Money = amount * 0.9
```

### G-8: Strategy interface when a function type would do

**Smell.**

```kotlin
fun interface DiscountStrategy { fun apply(amount: Money): Money }

class PricingService(private val discount: DiscountStrategy) {
    fun price(cart: Cart) = discount.apply(cart.subtotal())
}
```

For a single-method strategy with no identity, no DI requirements, no enumeration needed — the interface is overhead.

**Why it's wrong.** A function type does the same job:

**Fix.**

```kotlin
class PricingService(private val discount: (Money) -> Money) {
    fun price(cart: Cart) = discount(cart.subtotal())
}
```

In tests: pass `{ it * 0.5 }`. In production: pass a lambda or function reference.

Promote to a `fun interface` only when:
- You need DI to inject named beans.
- You need to enumerate strategies.
- The interface has > 1 method.

---

## Java-flavoured Factory

### G-9: `OrderFactory` Spring bean for what could be `Order.create(...)`

**Smell.**

```kotlin
@Component
class OrderFactory {
    fun create(customerId: CustomerId, items: List<OrderItem>): Order =
        Order(OrderId.new(), customerId, items)
}

@Service
class PlaceOrderHandler(private val orderFactory: OrderFactory) {
    fun handle(cmd: PlaceOrderCommand) = orderFactory.create(cmd.customerId, cmd.items)
}
```

**Why it's wrong.** Construction needs no DI'd collaborators. The factory adds a bean for no benefit; a `companion object create()` is simpler and lives on the type.

**Fix.**

```kotlin
class Order private constructor(...) {
    companion object {
        fun create(customerId: CustomerId, items: List<OrderItem>): Order = Order(...)
    }
}

@Service
class PlaceOrderHandler(...) {
    fun handle(cmd: PlaceOrderCommand) = Order.create(cmd.customerId, cmd.items)
}
```

Promote to a Spring `@Component` factory only when construction needs DI'd collaborators (e.g., a `PriceCalculator` to set initial prices).

---

## Premature Decorator

### G-10: Decorator chain with one decorator

**Smell.**

```kotlin
class CachingOrderRepository(...) : OrderRepository by inner { ... }
```

One decorator, no other wrappers. The "chain" is one step.

**Why it's wrong.** Per se this is fine — caching IS a Decorator. The smell is when teams add the Decorator pattern *before* needing caching, "just in case". Or build a multi-decorator framework when they have one wrapper.

**Fix.** Add the Decorator when you have the second concern. Until then, inline the caching in the inner repository or keep one wrapper.

---

## Misapplied Proxy

### G-11: Hand-rolled Proxy for what Spring AOP provides

**Smell.**

```kotlin
class TransactionalOrderService(
    private val inner: OrderService,
    private val txManager: PlatformTransactionManager,
) : OrderService by inner {
    override fun placeOrder(...) {
        val tx = txManager.getTransaction(DefaultTransactionDefinition())
        try {
            val result = inner.placeOrder(...)
            txManager.commit(tx)
            return result
        } catch (e: Exception) {
            txManager.rollback(tx)
            throw e
        }
    }
}
```

**Why it's wrong.** Spring's `@Transactional` does this for free, declaratively, with the right rollback rules and propagation.

**Fix.** `@Transactional` on the method. Delete the manual proxy.

---

## Visitor / State / Strategy confusion

### G-12: Using `when` over `is` chains across many files when the type is sealed

**Smell.** Same `when (shape)` appears in `area.kt`, `perimeter.kt`, `bounding-box.kt`. If `Shape` is sealed and the methods belong on the type, the `when`s are scattered Polymorphism violations (also GRASP P-1, SOLID OCP).

**Fix.** Push the methods onto the sealed type:

```kotlin
sealed interface Shape {
    fun area(): Double
    fun perimeter(): Double
    fun boundingBox(): BoundingBox

    data class Circle(val r: Double) : Shape {
        override fun area() = PI * r * r
        override fun perimeter() = 2 * PI * r
        override fun boundingBox() = BoundingBox(-r, -r, r, r)
    }
    // ... Rectangle, Triangle, ...
}
```

Adding `Triangle` adds one variant; nothing scattered to update.

The exception: when adding a new method shouldn't require modifying the sealed type (e.g., the methods are operation-specific and many), top-level functions over the sealed type are appropriate. Pick by frequency: methods that are intrinsic to the type live on the type; operations defined elsewhere live as functions over the type.

---

## Java-flavoured Memento

### G-13: Mutable `Memento` class with getters and setters

**Smell.**

```kotlin
class EditorMemento {
    private var content: String = ""
    private var timestamp: Instant = Instant.now()

    fun getContent() = content
    fun setContent(c: String) { content = c }
    fun getTimestamp() = timestamp
    fun setTimestamp(t: Instant) { timestamp = t }
}
```

**Why it's wrong.** Mementos should be immutable snapshots. `data class` provides equality, `copy`, `toString` for free.

**Fix.**

```kotlin
data class EditorMemento(val content: String, val timestamp: Instant)
```

---

## Misnaming patterns

### G-14: Calling a thing a "Pattern" when it's not one

**Smell.** `OrderManagerPattern`, `UserHelperPattern`, `PaymentFactoryPattern`. Affixing "Pattern" or generic suffixes to class names.

**Why it's wrong.** Names should reflect what the class *does*, not what design vocabulary inspired it. Good names are domain-rooted, not vocabulary-rooted. (See `clean-code-naming` for the weasel-suffix ban.)

**Fix.** `OrderRepository` (not `OrderRepositoryPattern`), `PaymentGateway` (not `PaymentGatewayFacade`), etc.

### G-15: Calling everything a Factory

**Smell.** `OrderFactory`, `OrderItemFactory`, `OrderRequestFactory`, `OrderResponseFactory` — when most of these are just constructors with names.

**Why it's wrong.** Factory has a specific intent (decouple client from concrete type, often for inheritance polymorphism). Calling every constructor wrapper a Factory dilutes the term.

**Fix.** Use Factory when the intent is real (Abstract Factory for families, Factory Method for subclass-determined types, factory methods for invariant enforcement). Otherwise call them what they are: a `companion fun create()` is just construction with validation.

---

## Pattern over-application

### G-16: Speculative GoF patterns "in case we need them"

**Smell.** Sealed Strategy hierarchy added before any second variant exists. Decorator chain added "to make caching easy if we need it". Visitor (in Kotlin) "for future operation extensibility". Observer added when there's one direct caller.

**Why it's wrong.** Patterns have cost — abstraction layers, indirection in stack traces, mental load. Adding them speculatively is over-engineering. Wait for the second case (per `solid-principles/resources/best-practices.md`'s OCP rule).

**Fix.** Inline. Apply patterns when the pressure is real. The cost of *removing* a premature pattern is several IDE refactors; the cost of *introducing* one when needed is one extract-interface.

### G-17: Mechanical pattern-spotting in code review

**Smell.** Code review comment: "this should be a Strategy" / "this should be a Factory" / "this should be a Mediator" — without explanation of why the pattern fits or what concrete problem it solves.

**Why it's wrong.** Patterns are diagnostic, not prescriptive. Naming a pattern doesn't justify applying it. The right question is: "what concrete problem does this code have, and does pattern X solve it?"

**Fix.** Reviews ask about the problem, not the pattern. "I'm worried about coupling between A and B — let's discuss" is better than "use Mediator".

---

## Pattern misidentification

### G-18: Calling a Mediator a Facade (or vice versa)

**Smell.** A class that just exposes a high-level method (`checkout()`) is called a Mediator. A class that owns inter-collaborator wiring is called a Facade.

**Why it's wrong.** They're different patterns. Facade simplifies access to a subsystem (hides complexity from a *client*); Mediator manages *interaction between collaborators* who would otherwise know each other.

In practice, many `@Service` classes are *both* — they expose a high-level API AND coordinate collaborators. Call them what they are: a `CheckoutService` or `CheckoutOrchestrator`. The pattern-language naming is for design discussion, not class names.

### G-19: Calling a sealed hierarchy a Visitor

**Smell.** "We use the Visitor pattern over `Shape`" — when the actual code is sealed `Shape` + exhaustive `when`.

**Why it's wrong.** It's not Visitor. Visitor uses double-dispatch via `accept(visitor)`; sealed + `when` is direct exhaustive dispatch on the type. Different mechanism, different trade-offs.

**Fix.** Call it what it is: "sealed dispatch", "exhaustive `when`", or "polymorphic match". Reserve "Visitor" for the actual `accept(visitor)` mechanism — and avoid that in Kotlin.

---

## How to use this catalogue in code review

1. **Scan for ceremony.** Hand-rolled Singleton (G-1)? Fluent Builder (G-3)? Classical Visitor (G-5)? Hand-rolled Observable (G-6)? Manual transaction Proxy (G-11)? All are smell.
2. **Scan for pattern names in class names.** `*Manager`, `*Helper`, `*Util`, `*Pattern` (G-14)? Or excessive `*Factory` (G-15)? Likely misapplication.
3. **Check pattern necessity.** Sealed Strategy with one variant (G-7)? Decorator with one wrapper (G-10)? Speculative Observer (G-16)? Wait for the second case.
4. **Check pattern names accuracy.** Mediator vs Facade (G-18)? Sealed dispatch vs Visitor (G-19)? Naming should match the mechanism.
5. **Apply the fix.** Each entry has a Kotlin-idiomatic fix; the diff is usually a deletion plus a small addition.
