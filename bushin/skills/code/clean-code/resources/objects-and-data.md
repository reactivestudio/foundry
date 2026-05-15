# Objects and Data — pick a side per class

For any class, the first question is: *behaviour-rich object* (data hidden, operations exposed) or *data structure* (data exposed, no behaviour)? Hybrids are the worst of both worlds.

## Output template — when reviewing a class for shape

1. **Which form is this?** Match against the 5-form table below.
2. **If hybrid**, identify which two sides are tangled and how to split.
3. **Look for train wrecks and feature envy** in callers.

## MUST-check before closing the review

Pass through this list **enumeratively** — not just principle-by-principle. Walk every signature; tick every parameter. The eye reads past raw primitives and entity-shaped returns because they look familiar.

- [ ] **Scan every public method signature.** List every parameter and return type that is `Long`/`String`/`Double`/`Int` — **including those hidden behind `typealias`**. `typealias UserId = Long` is **not encapsulation** — the compiler erases it to `Long`, and any `Long` can be passed where `UserId` is expected. Each raw-primitive (or typealiased-primitive) parameter is primitive obsession unless the value is truly a generic measurement with no domain identity. Fix: `@JvmInline value class UserId(val value: Long)`.
- [ ] **Scan every public method return type and parameter type for persistence-shaped types.** If the type name ends in `Entity`/`Row`/`Document`/`Record`, OR lives in a `persistence.*` / `repository.*` / `dao.*` package, OR is annotated `@Entity`/`@Document`/`@Table` — flag it. Persistence types belong at the repository edge, never in domain method signatures. Fix: separate aggregate type with a mapper.
- [ ] No train wreck `a.b().c().d()` in callers? (push the operation onto the first object — Tell, don't ask)
- [ ] No hybrid class (public/mutable state **and** business methods on the same type)?
- [ ] No anaemic data with all logic living elsewhere in a `*Service`?

## The 5 forms

| Form | Shape | When to use | Example |
|---|---|---|---|
| **Pure data structure** | `val` fields, no methods | Transport across a boundary; framework DTO | `data class OrderRequest(val items: List<...>, val customerId: CustomerId)` |
| **Behaviour-rich object** | private state, behavioural methods, factory in companion | Domain aggregate with invariants | `class Order private constructor(...) { fun submit(): OrderSubmitted; fun cancel(reason); ... }` |
| **Value object** | immutable, equality by value | Domain primitive with invariants | `@JvmInline value class Email private constructor(val value: String) { companion object { fun of(raw): Email = ... } }` |
| **Hybrid (BAD)** | public/`var` fields **and** business methods | Don't. Split. | JPA `@Entity` with `var status` *and* a `fun submit() { status = SUBMITTED }` that any caller can bypass |
| **Active Record / persistence shape** | ORM-mapped, public-ish state, save/find navigation | Persistence boundary only — never the domain | `@Entity class OrderRow(...)` — the real `Order` aggregate is separate |

**Test before writing members.** Finish the sentence: "This class is for ____."
- "transporting a submission from API to service" → pure data structure
- "representing a customer order with its invariants and lifecycle" → behaviour-rich object
- "mapping the `orders` table" → persistence shape, don't put business logic on it

## Anti-symmetry — pick the side that matches the axis of change

The two ways to model `Shape.area()` are diametrically opposed:

- **Procedural** (data + free function): new operation = one new function; new shape = every function changes.
- **OO** (polymorphism per shape): new shape = one new class; new operation = every class changes.

| Axis of expected change | Pick |
|---|---|
| Many new shapes, same operations | OO — polymorphism per shape |
| Many new operations, stable shapes | Procedural — sealed types + `when` |
| Both | Visitor / pattern matching — you pay twice |

In Kotlin, sealed hierarchies + exhaustive `when` make the procedural side cleaner than in Java.

## Law of Demeter — talk to friends, not strangers

A method may call methods of: itself, objects it creates, arguments passed to it, instance fields. It should **not** call methods on objects *returned* by those calls.

```kotlin
// ✗ Train wreck — three dots through three classes' internals
val outputDir = ctx.getOptions().getScratchDir().getAbsolutePath()
```

The fix isn't to split into temporaries (still the same violation). It's **Tell, don't ask** — push the operation onto the object:

```kotlin
// ✓ The operation lives on the object that owns the data
val stream: OutputStream = ctx.createScratchFileStream(name)
```

The criterion: **what was the caller going to do with the result?** If "use it to do something the object could do for me", the method belongs on the object.

**If you don't own the type** (third-party, generated code), an **extension function** in your code is the equivalent of "move the method": `fun Order.shippingCity(): String = customer.address.city.name`.

**When Demeter doesn't apply:** data structures (`dto.address.city` is fine), fluent builders, stdlib collection pipelines.

## Tell, don't ask

```kotlin
// ✗ Ask state, then mutate externally
if (order.status == DRAFT && order.items.isNotEmpty()) {
    order.status = SUBMITTED
    eventBus.publish(OrderSubmitted(order.id))
}

// ✓ Tell — the rule lives on the aggregate
order.submit().also { eventBus.publish(it) }

class Order private constructor(...) {
    fun submit(): OrderSubmitted {
        check(status == DRAFT)
        require(items.isNotEmpty())
        status = SUBMITTED
        return OrderSubmitted(id)
    }
}
```

## DTOs stay dumb

DTOs cross a boundary (HTTP body, message payload, projection, `@ConfigurationProperties`). They are `data class` with `val`s and no methods. No validation logic, no business rules, no persistence concerns. Validation lives at the boundary (Bean Validation or a parsing step into the domain type); rules live on aggregates; persistence on entities.

```kotlin
// ✓
data class SubmitOrderRequest(
    val items: List<OrderItemRequest>,
    val customerId: CustomerId,
    val shippingAddress: AddressRequest,
)
```

## JPA `@Entity` is a data structure, not an aggregate

A `@Entity` requires a no-arg constructor, mutable fields (for the ORM), and `id`-based identity. Putting business rules on it creates a hybrid bound to the persistence shape — and any caller can bypass `submit()` with `entity.status = SUBMITTED`.

Two acceptable shapes:

**Option A — single class, pragmatic:** keep `@Entity`, make state private with `protected set`, expose behavioural methods.

**Option B — two classes:** `OrderRow` is the persistence shape (`@Entity`), `Order` is the aggregate (pure Kotlin with private state, no Spring imports). A mapper sits at the repository edge.

Promote to Option B when invariants become non-trivial.

## Smell → fix lookup

| Smell | Fix |
|---|---|
| Class with public fields *and* business methods (hybrid) | Split: `data class` for data, behaviour-rich class for operations, explicit mapper. |
| `getX()`/`setX()` pair on every field of an "object" | Either DTO (`data class val`) or aggregate (private state, behavioural methods). Pick one. |
| Train wreck `a.b().c().d()` through objects | Push the operation into the first object: `a.doX(...)`. |
| Service fetches state, decides, calls a setter | Move decision and mutation into the aggregate. |
| JPA `@Entity` with business methods called from controllers | Either Option A (private `set` on entity) or Option B (separate aggregate type). |
| DTO with `validate()` / `compute()` / `save()` method | Move out: validation to boundary, computation to domain service, persistence to repository. |
| `when (entity.type)` returning behaviour | Move the per-type behaviour to each sealed subclass. |
| `if (obj.status == X) obj.doX()` everywhere | Move the precondition inside `doX()` — Tell, don't ask. |
| Domain aggregate exposed via Jackson on a controller | Add a separate response DTO; map at the boundary. |
