---
name: clean-code-objects-and-data
description: "Objects-vs-data-structures discipline for Kotlin/Spring code — opinionated rules for data abstraction (hide implementation, not just fields behind getters), the object/data anti-symmetry (behaviour-rich objects vs anemic data carriers — pick one per class, never both), Law of Demeter (no train wrecks `a.b().c().d()`, talk to friends not strangers), banning hybrids (classes with public fields *and* business methods are the worst of both worlds), Tell-Don't-Ask (push the operation into the object rather than fetching state to decide externally), DTO discipline (data transfer objects stay dumb), Active Record anti-pattern (ORM rows are data structures, not aggregates). Adapted from R. Martin's Clean Code Ch. 6 'Objects and Data Structures', filtered for what Kotlin already solves (`data class` for ideal DTOs, properties instead of explicit getters/setters, `val` immutability default, `@JvmInline value class`, sealed hierarchies for closed type-axes, destructuring, scope functions like `apply`/`also` for tell-don't-ask), and extended with Spring/JPA conventions (JPA `@Entity` as persistence shape vs. domain aggregate, anemic domain model anti-pattern, DTO at every layer boundary — controller request/response, Kafka payloads, projections — and `@ConfigurationProperties` data classes, MapStruct/manual mappers between layers, Spring Data repository as a tell-not-ask seam). Use this skill whenever the user designs or reviews a class and the question is 'should this have behaviour or just hold data?' — including: designing a new aggregate vs. a new request/response DTO, refactoring an anemic JPA `@Entity` with public bean accessors into a real aggregate, spotting train wrecks (`ctx.getOptions().getScratchDir().getAbsolutePath()`) in code review, splitting a hybrid class that is half-DTO half-aggregate, deciding whether to expose `@Entity` types from a controller (don't), naming the API contract vs. the domain type, auditing a module for Demeter violations, feature envy, or anemic services that hold all the logic that belongs on the entity. Apply it proactively any time a class has both data and methods that operate on that data, even if the user hasn't named it as an objects-vs-data problem."
risk: safe
source: "Adapted from R. Martin, Clean Code (2008), ch. 6 'Objects and Data Structures', filtered for Kotlin/Spring + house rules"
date_added: "2026-05-12"
---

# Clean Code: Objects and Data Structures

> "Objects hide their data behind abstractions and expose functions that operate on that data. Data structures expose their data and have no meaningful functions." — R. Martin
>
> "Hiding implementation is not just a matter of putting a layer of functions between the variables. Hiding implementation is about abstractions." — R. Martin

Most "encapsulation" in Java codebases is theatre. A private field with `getX()` / `setX()` is not encapsulated — it's a public field with extra ceremony. Real encapsulation hides *what the data is*, not just *where the bytes live*. This skill is the opinionated catalog of how to decide, for any given class, whether it should be a **behaviour-rich object** (data hidden, operations exposed) or a **data structure** (data exposed, no behaviour) — and the rules that follow once you've decided.

Kotlin shifts the centre of gravity here: `data class` makes ideal DTOs in one line, `val` defaults to immutability, properties replace JavaBean getters, and `@JvmInline value class` lets you wrap primitives without runtime cost. Spring/JPA cuts the other way: `@Entity` classes look like aggregates but behave like data structures (no-arg constructors, mutable fields for the ORM, identity-by-id), and most "service layer" code in real codebases is procedural manipulation of those anemic entities.

## Use this skill when
- Designing a new class — the first question is "object or data?" Pick before you write the first member.
- Refactoring a JPA `@Entity` that has accumulated business methods into a real domain aggregate.
- Reviewing a class with public fields *and* significant methods — that's a hybrid; split it.
- Spotting a train wreck (`a.b().c().d()`) in a PR and deciding whether it's a Demeter violation.
- Splitting controllers, services, and entities into clean layers — DTO at the boundary, aggregate in the core.
- Designing the API contract between contexts — request/response DTOs vs. domain types.
- Reviewing an anemic service (`OrderService.submitOrder(order)` does everything; `Order` has only getters) and pushing behaviour back into the entity.
- A method takes a domain object and immediately calls three getters on it to make a decision — that's Tell-Don't-Ask in waiting.
- Naming a class `*Manager` / `*Service` and feeling that the *real* verb belongs on a noun you haven't created yet.
- Auditing a module for Demeter violations, feature envy, or hybrid classes.

## Do not use this skill when
- The class is enforced by a framework contract (Spring `@ConfigurationProperties`, JPA `@Entity`, Jackson DTO) — the shape is partly outside your control; apply where you can, accept the shape where you can't.
- The class is a one-line value wrapper (`@JvmInline value class Email(val value: String)`) — the rules don't fight there.
- The task is broader architecture (module boundaries, persistence pattern, context mapping) — use `architecture-patterns`, `ddd-tactical-patterns`, or `architect-review`.
- The data is genuinely transport-only (HTTP request body, Kafka payload, projection result) — `data class` with `val`s, no methods, you're done.

## Core principles (the ten)

1. **Hide implementation, not just fields.** A wall of getters/setters around private fields does **not** hide implementation — it advertises it. Real abstraction designs the interface around what the data is **for** (`vehicle.percentFuelRemaining()`), not how it is stored (`vehicle.gallonsOfGasoline / vehicle.tankCapacityInGallons`).
2. **Object/Data anti-symmetry.** Objects **hide data, expose behaviour**. Data structures **expose data, have no behaviour**. The two are complementary opposites. A class should be one or the other — never both. (Section *Object/Data Anti-Symmetry* below.)
3. **Pick the side that's right for the axis of change.** New shape with the same operations? Polymorphism (OO) is easier. New operation across many shapes? Data + procedure is easier. Match the model to the dimension you expect to grow.
4. **Hybrids are the worst of both worlds.** A class with public fields *and* significant business methods is hard to extend along **both** axes (new shape *and* new operation) and tempts every caller to bypass the methods. Avoid; split into a clean data structure and a clean object.
5. **Law of Demeter — talk to friends, not strangers.** A method should only call methods of its own class, its arguments, objects it creates, and direct fields. It should **not** call methods on objects *returned* by those calls. Each dot past the first asks the reader to know more than they should.
6. **Train wrecks (`a.b().c().d()`) are a symptom of Tell-Don't-Ask failure.** The chain isn't the problem; the problem is that you asked the object for its internals so you could do something to them externally. Push the operation into the object: `ctx.createScratchFileStream(name)`, not `ctx.getOptions().getScratchDir().getAbsolutePath()`.
7. **Tell, don't ask.** If you fetch state from an object and then make a decision based on it, the decision belongs *on* that object. `if (order.status == DRAFT) order.submit()` should be `order.submit()`, with the status check inside.
8. **DTOs stay dumb.** Data transfer objects (controller request/response, Kafka payloads, projection results, `@ConfigurationProperties`) carry data across a wire or layer boundary. They are `data class`es with `val`s and no methods. No validation logic. No business rules. No persistence concerns.
9. **Active Record is a data structure.** ORM-mapped rows (JPA `@Entity` in the default Spring shape, Active Record in the Rails sense) are data structures with navigation methods (`save`, `findAll`). Putting business rules on them creates a hybrid bound to the persistence shape. Keep the entity as the persistence boundary and put domain rules on a separate aggregate.
10. **Beans are not encapsulation.** The JavaBean pattern (private fields + getter/setter pair for every one) is **public fields with extra steps**. It satisfies frameworks (older Jackson, JPA) but does not hide anything. In Kotlin, prefer `data class val ...` (immutable DTO) or a real aggregate with private state and behavioural methods — never both at once.

## The five forms (decide which one each class is)

| Form | Shape | When to use | Example |
|---|---|---|---|
| **Pure data structure** | `val` fields, no methods | Transport across a boundary; framework-mandated DTO | Kotlin `data class OrderRequest(val items: List<LineRequest>, val customerId: CustomerId)` |
| **Behaviour-rich object** | private state, behavioural methods, factory in companion | Domain aggregate; business invariants live inside | `class Order private constructor(...) { fun submit(): OrderSubmitted; fun cancel(reason: CancelReason); ... }` |
| **Value object** | immutable, equality by value, often `@JvmInline value class` | Domain primitive with invariants (`Money`, `Email`, `OrderId`) | `@JvmInline value class Email private constructor(val value: String) { companion object { fun of(raw: String): Email = ... } }` |
| **Hybrid (BAD)** | public/`var` fields **and** business methods | Don't. Split into the two cleaner forms. | A JPA `@Entity` with `var status: OrderStatus` exposed and a `fun submit() { this.status = SUBMITTED; ... }` method that any caller can bypass |
| **Active Record / persistence shape** | ORM-mapped, public-ish state, navigation methods (`save`/`find`) | Persistence boundary only — never the domain | JPA `@Entity class OrderRow(...)`; the real `Order` aggregate is a separate class that uses it |

**Test before you write members:** name the class out loud and finish the sentence "This class is for ____."
- "...transporting a submission request from the API to the service" → pure data structure.
- "...representing a customer order with its invariants and lifecycle" → behaviour-rich object.
- "...mapping the `orders` table" → persistence shape, don't put business logic on it.

## Data abstraction — hide *what*, not just *where*

```kotlin
// ✗ Bean-style: private but transparent — `_x` and `_y` are visible to every caller through a chain of dots
class Point(var x: Double, var y: Double)

// ✗ Same as above with a JavaBean accent — extra ceremony, same exposure
class Point {
    private var x: Double = 0.0
    private var y: Double = 0.0
    fun getX() = x; fun setX(v: Double) { x = v }
    fun getY() = y; fun setY(v: Double) { y = v }
}

// ✓ Abstract — the *interface* expresses the data, the *implementation* is invisible
interface Point {
    val cartesian: Cartesian              // ← reading is independent
    val polar: Polar
    fun setCartesian(x: Double, y: Double)  // ← writing is atomic, an access policy not just a setter
    fun setPolar(r: Double, theta: Double)
}
```

```kotlin
// ✗ "Concrete vehicle" — caller must know about tanks and gallons to compute the only thing they actually want
interface Vehicle {
    val fuelTankCapacityInGallons: Double
    val gallonsOfGasoline: Double
}

// ✓ "Abstract vehicle" — caller asks for the meaning, not the parts
interface Vehicle {
    val percentFuelRemaining: Double
}
```

**The criterion isn't "is the field private?" — it's "does the interface speak the language of the consumer's need, or the language of the storage layout?"**

## Object/Data anti-symmetry — the fundamental dichotomy

Two equivalent ways to model `Shape.area()`:

```kotlin
// === Procedural / data-structure style ===
sealed class Shape
class Square(val topLeft: Point, val side: Double) : Shape()
class Rectangle(val topLeft: Point, val height: Double, val width: Double) : Shape()
class Circle(val center: Point, val radius: Double) : Shape()

object Geometry {
    fun area(s: Shape): Double = when (s) {                   // ← all behaviour here
        is Square    -> s.side * s.side
        is Rectangle -> s.height * s.width
        is Circle    -> PI * s.radius * s.radius
    }
    fun perimeter(s: Shape): Double = when (s) { ... }        // ← new operation: add a function, shapes untouched
}
// New operation = easy (one new function in Geometry). New shape = hard (every function in Geometry must change).
```

```kotlin
// === Object-oriented style ===
sealed interface Shape { fun area(): Double }
class Square(val topLeft: Point, val side: Double) : Shape    { override fun area() = side * side }
class Rectangle(val topLeft: Point, val h: Double, val w: Double) : Shape { override fun area() = h * w }
class Circle(val center: Point, val radius: Double) : Shape   { override fun area() = PI * radius * radius }
// New shape = easy (one new class). New operation = hard (every existing class must add the method).
```

**The two are diametrically opposed.** Pick based on the axis you expect to grow:

| Axis of expected change | Pick |
|---|---|
| Many new shapes, same operations | OO — polymorphism per shape |
| Many new operations, stable shapes | Procedural — data structures + free functions |
| Genuinely both (rare) | Visitor / pattern matching with sealed hierarchies; understand you're paying twice |

> "The idea that everything is an object is a myth." — Sometimes you really do want simple data structures with procedures operating on them.

In Kotlin, the procedural side reads cleanly with **sealed hierarchies + `when`** (exhaustive, no `instanceof` casts), so the cost gap is much smaller than in old-school Java.

## Law of Demeter — talk to friends, not strangers

A method `f` of class `C` may call methods of:
1. `C` itself.
2. Objects `f` creates.
3. Objects passed to `f` as arguments.
4. Objects held in instance variables of `C`.

It **should not** call methods on objects *returned* by any of the above.

```kotlin
// ✗ Train wreck — three dots through three classes' internals
val outputDir = ctx.getOptions().getScratchDir().getAbsolutePath()
```

This violates Demeter **if** `ctx`, `Options`, `ScratchDir` are objects. (If they're plain data structures, Demeter doesn't apply — you're just reading fields.) The fix isn't to break the chain into three temporary variables (still the same violation, just spelled out) — it's to **stop asking and start telling**:

```kotlin
// ✗ Splitting the chain — feels safer, same violation
val opts = ctx.options
val dir  = opts.scratchDir
val outputDir = dir.absolutePath

// ✗ Still wrong — even after we got the path, what we wanted was a stream
val outFile = "$outputDir/${className.replace('.', '/')}.class"
val bos = BufferedOutputStream(FileOutputStream(outFile))

// ✓ Tell, don't ask — the operation lives on the object that owns the data
val bos: BufferedOutputStream = ctx.createScratchFileStream(classFileName)
```

The criterion: **what was the caller going to do with the result?** If the answer is "use it to do something the object could do for me," the method belongs on the object.

**If you don't own the type** (third-party library, JPA entity behind an ORM, generated code), the same fix lands as an **extension function** in your code: `fun Order.shippingCity(): String = customer.shippingAddress.city.name`. The call site reads identically (`order.shippingCity()`), the Demeter chain stays out of the caller, and the original type stays untouched.

### When Demeter doesn't apply

- **Data structures.** `dto.address.city` is fine — `Address` is a data class, it exists to be read.
- **Fluent builders.** `Query.from("orders").where("id").eq(42).build()` is a DSL, not a Demeter chain; the *type* of every link is the same builder.
- **Stdlib collections.** `list.filter { ... }.map { ... }.first()` is a pipeline of values, not navigation through one object's internals.

### Spotting Demeter violations in Kotlin (vs. Java)

Kotlin's safe-call (`?.`) tempts long chains: `user?.profile?.address?.city ?: "unknown"`. Each `?.` is still a Demeter dot — the only difference is null-safety. If the chain is *querying* an object's internals to compute a value, the same Tell-Don't-Ask fix applies (`user.cityOrUnknown()`). If it's navigating a DTO graph, it's fine.

## Tell, don't ask — the rule behind Demeter

```kotlin
// ✗ Ask, then act externally
if (order.status == OrderStatus.DRAFT && order.items.isNotEmpty() && order.totalAmount.isPositive()) {
    order.status = OrderStatus.SUBMITTED
    order.submittedAt = clock.now()
    eventBus.publish(OrderSubmitted(order.id))
}

// ✓ Tell — the rules live inside the aggregate
order.submit(clock.now()).also { eventBus.publish(it) }

class Order private constructor(...) {
    fun submit(now: Instant): OrderSubmitted {
        check(status == DRAFT) { "Only DRAFT orders can be submitted" }
        require(items.isNotEmpty()) { "Order must have items" }
        require(totalAmount.isPositive()) { "Order total must be positive" }
        status = SUBMITTED
        submittedAt = now
        return OrderSubmitted(id)
    }
}
```

The external code goes from procedural choreography to a single domain sentence. The invariants live with the data they constrain. Adding a fourth precondition is one edit, in one place, hidden from every caller.

## DTOs — keep them dumb

DTOs cross a boundary (HTTP body, message payload, projection result, configuration tree). They are immutable, public, no methods.

```kotlin
// ✓ HTTP request DTO — Kotlin data class, all val, no behaviour
data class SubmitOrderRequest(
    val items: List<OrderItemRequest>,
    val customerId: CustomerId,
    val shippingAddress: AddressRequest,
)

data class OrderItemRequest(val productId: ProductId, val quantity: Int)

// ✓ Spring @ConfigurationProperties — a typed view of application.yml; data class with val
@ConfigurationProperties(prefix = "billing")
data class BillingProperties(
    val invoicePrefix: String,
    val retryAttempts: Int,
    val timeout: Duration,
)
```

**Anti-pattern**: putting validation, persistence, or business methods on a DTO. Validation lives at the boundary (Bean Validation annotations or a parsing step into the domain type); business rules live on the aggregate; persistence lives on the entity. Each layer has its own type, and `MapStruct` / hand-written mappers cross the seams.

### DTO → domain on the way in, domain → DTO on the way out

```kotlin
// Controller: DTO in, DTO out — never expose the aggregate directly
@PostMapping("/orders")
fun submit(@Valid @RequestBody request: SubmitOrderRequest): OrderView {
    val command = request.toCommand()                  // ← explicit DTO → domain mapping
    val order   = orderService.submit(command)
    return order.toView()                              // ← explicit domain → DTO
}
```

The two mappings (`toCommand`, `toView`) are extension functions or a dedicated mapper. Never `@JsonAutoDetect` straight onto an aggregate — that leaks the persistence shape into the wire format and into every API consumer.

## Active Record — a data structure, not an aggregate

```kotlin
// ✗ Hybrid — JPA entity with business logic; bypassable via public setters; persistence shape leaks into rules
@Entity
class Order(
    @Id var id: UUID,
    @Enumerated(EnumType.STRING) var status: OrderStatus,
    @OneToMany(...) var items: MutableList<OrderItem>,
) {
    fun submit() {                    // ← business rule on a mutable, openly-mutated entity
        check(status == DRAFT)
        status = SUBMITTED
    }
}

// Caller can still bypass:
order.status = SUBMITTED              // 🤦
orderRepository.save(order)
```

Two clean options:

```kotlin
// ✓ Option A — domain aggregate is a separate class; the entity is a persistence shape only
@Entity
internal class OrderRow(
    @Id var id: UUID,
    @Enumerated(EnumType.STRING) var status: OrderStatus,
    @OneToMany(...) var items: MutableList<OrderItemRow>,
)

class Order private constructor(
    val id: OrderId,
    private var status: OrderStatus,
    private val items: MutableList<OrderItem>,
) {
    fun submit(): OrderSubmitted { /* invariants here, status mutation private */ }
    companion object { internal fun rehydrate(row: OrderRow): Order = ... }
}

// ✓ Option B (smaller systems) — single class, but private state and `protected set` to keep the entity behaviour-rich
@Entity
class Order private constructor(
    @Id val id: OrderId,
    @Enumerated(EnumType.STRING) var status: OrderStatus = OrderStatus.DRAFT,
        protected set,
    @OneToMany(...) private val items: MutableList<OrderItem> = mutableListOf(),
) {
    fun submit() { check(status == DRAFT); status = SUBMITTED; ... }
    protected constructor() : this(...)                  // ← JPA's no-arg requirement, hidden
}
```

Option A is the cleaner separation; option B is pragmatic when the team isn't ready for two parallel class hierarchies. **Both keep the business rules inside the type that owns them, with no public mutators.**

## Hybrid — the worst of both worlds

A class with public/`var` fields **and** business methods has the disadvantages of both forms:

- New operation? Has to be added in one of two places, and no convention says which.
- New variant? Has to be added in one of two places, and no convention says which.
- Every caller is tempted to bypass the method and poke the field directly.
- The author was unsure whether they needed protection from functions or types — and shipped both.

Spotting hybrids:
- A class has `data class` *and* method definitions beyond the auto-generated ones.
- A JPA entity has business methods *and* public/`var` fields.
- A DTO has a `validate()` method.
- An aggregate has a public `setStatus(s: OrderStatus)` *and* a `submit()` method.

The fix is always **split**: pull the data shape into a `data class` (or persistence entity), pull the behaviour into a behaviour-rich object, and add an explicit mapping between them.

## Anemic domain model — the Spring/JPA shape of the same problem

In Spring codebases the hybrid usually inverts: **all data on the entity, all behaviour on a service**.

```kotlin
// ✗ Anemic — entity is a data carrier, service is a procedural manipulator
@Entity
class Order(@Id var id: UUID, var status: OrderStatus, ...) {
    // only getters/setters via Kotlin properties
}

@Service
class OrderService(private val repo: OrderRepository, private val clock: Clock) {
    fun submitOrder(orderId: UUID) {
        val order = repo.findById(orderId).orElseThrow()
        check(order.status == OrderStatus.DRAFT) { "..." }
        order.status = OrderStatus.SUBMITTED
        order.submittedAt = clock.instant()
        repo.save(order)
    }
}
```

The smell: `OrderService` does the entire business operation **by manipulating fields on a passive `Order`**. The invariant ("only DRAFT can be submitted") lives in the service. Add a new transition (`cancel`, `ship`, `refund`) — every check lives in the service, every caller has to know which service method to call to keep the state machine consistent, and the entity is one `entity.status = SHIPPED` typo away from corruption.

The cure is **push behaviour onto the aggregate** (the Tell-Don't-Ask example above). The service becomes a thin orchestrator: load aggregate, call one domain method, save, publish events.

## Smell → fix quick reference

| Smell | Fix |
|---|---|
| Class with public fields *and* business methods (hybrid) | Split: `data class` for the data, behaviour-rich class for the operations, explicit mapper between. |
| `getX()`/`setX()` pair on every field of an "object" | Either it's a DTO (use `data class val`) or an aggregate (private state, behavioural methods). Pick one. |
| Train wreck `a.b().c().d()` through objects | Push the operation into the first object: `a.doX(...)`. |
| Service that fetches state, decides, then calls a setter | Move the decision and the mutation into the aggregate; service becomes a one-liner orchestrator. |
| JPA `@Entity` with business methods called from controllers | Add an aggregate type; entity becomes a persistence shape; map between them. |
| DTO with a `validate()` / `compute()` / `save()` method | Move the method out: validation to the boundary, computation to a domain service, persistence to a repository. |
| Anemic `OrderService.submitOrder(order)` does everything | Push to `order.submit()`; service just loads, calls, saves, publishes. |
| `when (entity.type)` on a sealed shape that should have polymorphism | Move the per-type behaviour to each subclass; keep one `when` in a factory. |
| `if (obj.status == X) obj.doX()` everywhere | Move the precondition inside `doX()` — `Tell, don't ask`. |
| DTO classes leaked from `@Entity` via Jackson on the controller | Add a separate response DTO; map at the boundary. |

## Kotlin-specific summary

- **`data class` is the ideal DTO.** `val` fields, generated `equals`/`hashCode`/`toString`/`copy`/destructuring. Use for every request/response/payload/projection type.
- **Properties replace getters/setters.** `class Order(val id: OrderId)` already gives consumers `order.id` — there's no `getId()` to add. Don't introduce explicit getters/setters unless you need custom logic, and then prefer a behavioural method (`order.submit()`) over a custom setter.
- **`val` defaults to immutability.** Use `val` for DTOs and aggregate state that doesn't change; use `private var` for state that changes (and never `public var` on a real object).
- **`@JvmInline value class` for domain primitives.** `value class Money(val cents: Long)` and `value class Email private constructor(val value: String)` give you typed wrappers with zero runtime cost.
- **Sealed hierarchies replace `instanceof` switches.** Procedural style is much cleaner in Kotlin (`when (shape) { is Circle -> ... }`) than in Java — the cost of choosing the data-structure side of the anti-symmetry is lower.
- **Companion object factories.** Keep constructors private and expose `Order.create(...)`; combined with `init`/validation, this enforces invariants the same way JavaBeans never could.
- **Scope functions support Tell-Don't-Ask.** `account.apply { credit(amount); recordAudit() }` reads as a sequence of tells, no temporaries, no leaked state.
- See `resources/kotlin-specific-objects-and-data.md` for the full Kotlin-side detail.

## Spring / JPA summary

- **`@Entity` is a persistence shape, not an aggregate.** Treat it as a data structure mapped to a row, even though JPA requires it to be a class with a no-arg constructor and mutable fields.
- **Keep `@Entity` mutators non-public** where the ORM allows (`protected set`, package-private setters in Java idiom). Frame the business methods as the only legal mutation paths.
- **DTOs everywhere boundaries exist.** Controller in/out, Kafka payloads, projection queries, `@ConfigurationProperties`, scheduled-task arguments — `data class` with `val`s. Never expose entities directly through Jackson; that ties the wire format to the persistence shape.
- **Use Spring Data repositories as a tell-not-ask seam.** `repo.save(order)` and `repo.findById(id)` are commands and queries against the aggregate boundary; avoid leaking JPA `EntityManager` into business code.
- **Anemic services are a smell.** A `*Service` whose every method is "load entity, check state, mutate, save" should be pushing the check-and-mutate onto the aggregate.
- See `resources/spring-boot-objects-and-data.md` for `@ConfigurationProperties`, MapStruct, JPA-vs-aggregate patterns, and Spring Data idioms.

## Selective Reading Rule

| File | When to read |
|---|---|
| `resources/general-objects-and-data-rules.md` | Martin Ch. 6 in depth — data abstraction, anti-symmetry, Law of Demeter, hybrids, DTOs, Active Record — with full before/after examples in Kotlin. Read first when starting on this skill. |
| `resources/kotlin-specific-objects-and-data.md` | Kotlin-only mechanics: `data class` shape and copy/destructuring, `@JvmInline value class`, properties replacing accessors, sealed hierarchies for procedural-style anti-symmetry, scope functions for Tell-Don't-Ask, companion factories, private constructors. |
| `resources/spring-boot-objects-and-data.md` | Spring & JPA conventions: `@Entity` as persistence shape vs. domain aggregate, anemic domain model anti-pattern, MapStruct / manual mappers, request/response DTOs at controllers, `@ConfigurationProperties`, Spring Data repository discipline, projections, Modulith module boundaries. |
| `resources/ddd-objects-and-data.md` | DDD overlay: aggregate root vs. entity vs. value object vs. DTO mapping, the "domain object → persistence row" boundary, identity vs. equality, repository contracts at the aggregate root, anti-corruption layers translating external DTOs into domain types. |

## Anti-patterns in objects-and-data work itself

- **Going all-objects or all-data on principle.** Martin's point is the *anti-symmetry* — there's a right answer per class. A codebase made entirely of "rich domain objects" can become unworkable when most of the work is moving DTOs across wires; a codebase made entirely of data classes + free functions can lose the encapsulation that keeps invariants real. Choose per class, not per project.
- **Wholesale-rewriting an anemic codebase.** Spring projects that have been anemic for years won't tolerate a "we'll move everything to aggregates this sprint" rewrite. Pick one bounded context, one aggregate at a time; characterization test first; refactor second.
- **Hiding everything behind methods, calling it "encapsulation".** A getter-and-setter pair per field is still public state with extra ceremony. Real encapsulation is *fewer* public members than fields, not more.
- **Train-wreck → temporary variables, no real fix.** Splitting `a.b().c().d()` into three temporaries doesn't address the underlying Demeter violation; the caller still knows too much about `a`'s internals. Use the temporary-variable split only as a diagnostic step toward "what behaviour should `a` expose?"
- **Refusing DTOs because "data class everywhere".** A controller that returns a domain aggregate via Jackson **looks** convenient and **is** a coupling time bomb; the moment you rename a private field for clarity, every API consumer's contract breaks.
- **MapStruct-everywhere overhead on tiny projects.** For a 3-class service the explicit `Order.toView()` extension function beats a 30-line generated mapper. Reach for MapStruct (or Mappie) when the mappings outnumber the domain classes.
- **Putting behaviour on a JPA entity and ignoring proxy / lazy-loading.** JPA hydrates entities via proxies; behaviour that fires in the constructor or in `init {}` runs before fields are populated. Keep entities lightweight; put real behaviour on a separate aggregate.

## Related skills

| Skill | This not that |
|---|---|
| `clean-code-naming` | Names of classes, methods, fields. This skill is the **shape and responsibility** of classes — pick after the name discipline frames the domain. |
| `clean-code-functions` | Function-level discipline (size, arguments, CQS). This skill is the class-level / data-shape decision that the functions live inside. |
| `clean-code` | Smell vocabulary and refactoring cadence. This skill is the deep dive on objects-vs-data choices specifically. |
| `solid-principles` | SRP, OCP, LSP at class scope — the principles Tell-Don't-Ask reinforces. |
| `grasp-patterns` | GRASP's Information Expert and Pure Fabrication intersect directly with Tell-Don't-Ask. |
| `ddd-tactical-patterns` | Aggregate / Entity / Value Object / Repository structure. This skill is the cleanliness criterion *inside* each of those forms. |
| `ddd-context-mapping` | DTOs at context seams; anti-corruption layers as the canonical "data structure at the boundary, object inside" pattern. |
| `api-design-principles` | DTO shapes at the API boundary — REST/gRPC contracts. This skill is the rule that those DTOs stay dumb. |
| `database-design` | Persistence shape (entity, table, index). This skill is the rule that the persistence shape is **not** the domain shape. |
| `architect-review` | Anemic-domain / hybrid-class smells during a structural audit; this skill provides the criteria the review applies. |
| `karpathy-guidelines` | §3 surgical changes — don't refactor anemic services you weren't asked to touch; open a separate PR. |
| `methodology-verification` | After splitting a hybrid: re-run the proving command before claiming the refactor is safe. |

## Limitations

- **Anti-symmetry is a guideline, not a law of nature.** Real systems have places where a tiny convenience method on a DTO (e.g., `toQueryParam()`) is the pragmatic choice. Don't escalate every small hybrid to a refactor — escalate the ones that *grow* into mixed responsibilities.
- **Framework gravity wins.** JPA wants entities to be classes with no-arg constructors and mutable fields. Spring Configuration Properties want public, settable fields (until v3.x). Jackson wants either. You can fight the framework or you can keep your behaviour on a separate type and let the framework's class be a data structure; the second is almost always less work.
- **Performance can override.** A behaviour-rich aggregate hydrated from JPA pays the cost of proxies, lazy loading, and N+1 if naive. For hot paths, a projection (data class) and a stateless service is sometimes the right answer — the skill's job is to ensure that's a *decision*, not a *default*.
- **Team consistency is non-negotiable.** If the codebase puts business rules on `@Entity` classes, putting one new aggregate in a separate type creates inconsistency that costs more than it saves. Convert the convention with the team, then refactor; don't refactor unilaterally.
- **Active Record can be the right answer for small CRUD apps.** Martin's critique is correct in the large; for a CRUD admin with no real domain rules, separating persistence shape from aggregate is overhead. Reach for the separation when invariants appear, not before.
