# General Rules — Objects and Data Structures

Adapted from R. Martin, *Clean Code* (2008), ch. 6. Examples translated to Kotlin for consistency with the rest of the skill series; the reasoning is language-independent.

---

## Rule 1 — Hide implementation, not just fields

Programmers keep fields private so that no one depends on their type, name, or layout. Adding `getX()`/`setX()` for every field undoes that protection silently — every reader still depends on the storage, just through one more layer of dots.

Real abstraction designs the public interface around **what the data is for**, not **how it is stored**.

```kotlin
// ✗ Bean-style "encapsulation" — private but transparent
class Point {
    private var x: Double = 0.0
    private var y: Double = 0.0
    fun getX(): Double = x; fun setX(v: Double) { x = v }
    fun getY(): Double = y; fun setY(v: Double) { y = v }
}

// ✗ Same exposure, fewer keystrokes — Kotlin properties don't change the substance
class Point(var x: Double, var y: Double)

// ✓ Abstract — caller cannot tell whether storage is rectangular or polar,
// and the *write* path is an atomic policy, not field-by-field mutation
interface Point {
    val cartesian: Cartesian
    val polar: Polar
    fun setCartesian(x: Double, y: Double)
    fun setPolar(r: Double, theta: Double)
}
```

**The question is not "are my fields private?"** It is **"if I rename, retype, or split a field tomorrow, how many callers break?"** If the answer is "all of them," the fields are public in every sense that matters.

### Worked example — vehicle fuel

```kotlin
// ✗ Caller has to compute the meaningful number itself, and now depends on the unit
interface Vehicle {
    val fuelTankCapacityInGallons: Double
    val gallonsOfGasoline: Double
}
val percentFuel = vehicle.gallonsOfGasoline / vehicle.fuelTankCapacityInGallons * 100

// ✓ Caller asks for the meaning, the unit and the formula are owned by Vehicle
interface Vehicle {
    val percentFuelRemaining: Double
}
val percentFuel = vehicle.percentFuelRemaining
```

If the storage moves from gallons to litres tomorrow, the abstract interface is unaffected. Every consumer of the concrete one is.

---

## Rule 2 — Object/Data anti-symmetry

> Objects hide their data behind abstractions and expose functions that operate on that data.
> Data structures expose their data and have no meaningful functions.

These are virtual opposites. The difference seems trivial until you see how it shapes the cost of every future change.

### Procedural / data-structure shape

```kotlin
sealed class Shape
class Square(val topLeft: Point, val side: Double) : Shape()
class Rectangle(val topLeft: Point, val height: Double, val width: Double) : Shape()
class Circle(val center: Point, val radius: Double) : Shape()

object Geometry {
    fun area(s: Shape): Double = when (s) {
        is Square    -> s.side * s.side
        is Rectangle -> s.height * s.width
        is Circle    -> PI * s.radius * s.radius
    }
}
```

- **Adding `perimeter`**: one new function in `Geometry`. No shape touched.
- **Adding `Triangle`**: every function in `Geometry` must change.

### Object-oriented shape

```kotlin
sealed interface Shape { fun area(): Double }
class Square(val topLeft: Point, val side: Double) : Shape    { override fun area() = side * side }
class Rectangle(val topLeft: Point, val h: Double, val w: Double) : Shape { override fun area() = h * w }
class Circle(val center: Point, val radius: Double) : Shape   { override fun area() = PI * radius * radius }
```

- **Adding `Triangle`**: one new class. Nothing else touched.
- **Adding `perimeter`**: every existing class needs a new method.

### The asymmetry — read this twice

| Change | Procedural | OO |
|---|---|---|
| New operation | **easy** | hard |
| New shape | hard | **easy** |

The things that are hard for OO are easy for procedures, and vice versa. Mature designers pick per axis of expected change. The myth that "everything should be an object" comes from forgetting half of the dichotomy.

### Picking the side

Ask: *over the next two years, which axis grows faster — new shapes or new operations?*

- **Most domain modelling** has stable operations (`submit`, `cancel`, `ship`) and many shapes (`Order`, `Reservation`, `Payment`) — OO wins.
- **Compilers, interpreters, format converters** have a stable AST and ever-growing passes — procedural wins (the visitor pattern is a way to fake the OO side back into procedural code when needed).
- **CRUD admin tools** have stable shapes and stable operations (R-E-A-D) — pick whichever is shorter.

There are escape hatches when you genuinely need both axes — the Visitor pattern, double dispatch, the Expression Problem — and they carry costs of their own. Use them only when both axes genuinely keep changing.

---

## Rule 3 — Hybrids are the worst of both worlds

A class with public fields **and** business methods has:

- The OO downside: a new operation requires touching the class.
- The procedural downside: a new variant requires touching every operation.
- A bonus downside: every caller is tempted to bypass the methods and poke the fields directly.

Hybrids are usually a sign that the author was unsure of — or worse, ignorant of — whether the class needed protection from new functions or from new types. They are *muddled design* in literal form.

```kotlin
// ✗ Hybrid — public field invites direct mutation, method is a polite suggestion
class Order(
    var status: OrderStatus,
    val items: MutableList<OrderItem>,
) {
    fun submit() { check(status == OrderStatus.DRAFT); status = OrderStatus.SUBMITTED }
}
order.status = OrderStatus.SUBMITTED  // 🤦 bypasses the only invariant the class had
```

The fix is always **split**: a clean data structure for the bag of fields, a clean object for the behaviour, and an explicit mapping (constructor, factory, or extension function) between them.

---

## Rule 4 — Law of Demeter

A method `f` of class `C` may invoke methods of:

1. `C` itself.
2. Objects `f` creates.
3. Objects passed in as arguments.
4. Objects held in instance variables of `C`.

It should **not** invoke methods on objects *returned* by any of the allowed calls.

> Talk to friends, not to strangers.

### Train wrecks

```kotlin
val outputDir: String = ctx.getOptions().getScratchDir().getAbsolutePath()
```

This is **a train wreck**: a chain of coupled "cars" reaching past `ctx` into `Options`, past `Options` into `ScratchDir`, past `ScratchDir` into a string. The calling function now knows the entire object graph.

**Whether this is a Demeter violation depends on what those types are**:

- If `ctx`, `Options`, `ScratchDir` are **objects** (they have business behaviour and hide their data), the chain violates Demeter. The caller has reached past three abstractions and is using the strangers' innards.
- If they are **data structures** (`data class` with `val`s and no methods), the chain is just reading fields — Demeter doesn't apply, because nothing was supposed to be hidden in the first place.

The accessors **confuse the issue**. If the same chain were spelled as direct field access on data classes:

```kotlin
val outputDir = ctx.options.scratchDir.absolutePath
```

…few people would describe it as a Demeter violation, because the types are obviously data structures. Bean-style getters muddy that signal: **they look like behaviour and act like fields**.

### What about splitting into temporary variables?

```kotlin
val opts = ctx.options
val dir  = opts.scratchDir
val outputDir = dir.absolutePath
```

This is *not* a Demeter fix. It is the same violation, written across three lines. Splitting train wrecks only to satisfy a line-length rule misses the point. The real question is **what was the caller going to do with the path?**

### The Tell-Don't-Ask fix

Look downstream of the chain:

```kotlin
val outFile = "$outputDir/${className.replace('.', '/')}.class"
val bos = BufferedOutputStream(FileOutputStream(outFile))
```

The caller wanted to **create a scratch file stream**, not navigate the configuration tree. So expose the operation on the object that owns the data:

```kotlin
val bos: BufferedOutputStream = ctx.createScratchFileStream(classFileName)
```

Now `ctx` keeps its options, scratch directory, and path-building logic to itself, and the caller does its real job.

### Two failure modes when you over-correct

1. **Method explosion on the root object.** Pushing every operation onto `ctx` turns it into a god class with `createScratchFileStream`, `createConfigFile`, `createLogFile`, `createCacheFile`, etc. The fix is hierarchy: `ctx.scratch.createFile(name)`, where `scratch` is itself a behaviour-rich object.
2. **Pretending objects are data.** Calling `getScratchDir()` and then `getAbsolutePath()` is "fine" only if `ScratchDir` was meant to be transparent (it has no invariants, no behaviour). In that case, just **don't pretend it's an object** — make it a `data class`, drop the getter style, and move on.

### Mixed levels of abstraction within one block

```kotlin
val outFile = outputDir + "/" + className.replace('.', '/') + ".class"
val fout = FileOutputStream(outFile)
val bos  = BufferedOutputStream(fout)
```

Dots, slashes, file extensions, and `File` objects mixed with `BufferedOutputStream` is a level-of-abstraction smell — separate concern from Demeter, but they often co-occur. Lift the path-building into a method called something like `classFilePath(className)` and the noise disappears.

---

## Rule 5 — Data Transfer Objects (DTOs)

The quintessential data structure: public fields, no functions.

DTOs serve as the **first stage of translation** when raw data crosses a boundary — a database row, a deserialised JSON message, a query projection. They are followed (in well-layered systems) by a translation into proper domain objects.

```kotlin
// ✓ Kotlin's data class is the canonical DTO — public val fields, equality, copy, destructuring
data class Address(
    val street: String,
    val streetExtra: String?,
    val city: String,
    val state: String,
    val zip: String,
)
```

The "bean form" (private fields manipulated through getters and setters) is **quasi-encapsulation**. It satisfies older frameworks that require `getX()` / `setX()` pairs (older Jackson, Hibernate proxies, JSP EL). It does **not** hide anything from a caller. Use it only where a framework forces your hand; do not invent it.

### What does *not* belong on a DTO

- Validation that throws on construction (boundary code validates *into* the DTO, not the DTO validates itself).
- Persistence methods (`save`, `delete`).
- Business rules (`canBeShipped()`, `applyDiscount()`).
- "Convenience" methods that compute domain values from the raw fields — those belong on a domain type the DTO maps to.

The moment you find yourself adding one of these, the DTO is graduating into a hybrid. Either move the method out, or admit that the type is actually a domain object and remove its public fields.

---

## Rule 6 — Active Record

Active Record is a special form of DTO: a data structure with public (or bean-accessed) fields, plus navigation methods like `save`, `find`, `findAll`. It is a near-1:1 translation from a database table.

Active Records are useful at the persistence boundary. The mistake is to **treat them as domain objects** by adding business-rule methods on them. That turns every Active Record into a hybrid (see Rule 3), with the additional twist that the field names are usually database column names — so the *persistence shape* now drives the *business rule shape*.

The remedy is conventional but uncomfortable: keep Active Records as data structures, and **create separate domain objects** that contain business rules and own a reference to (or are mapped from) the Active Record's data. The persistence layer hydrates rows, the domain layer enforces invariants, the mapping between them is explicit.

For Spring/JPA specifics, see `spring-boot-objects-and-data.md`.

---

## Anti-symmetry in one picture

```
                       New operation easy?    New type easy?
Pure Object              ✗                       ✓
Pure Data Structure      ✓                       ✗
Hybrid                   ✗                       ✗      ← never deliberately choose this
Active Record            ✓                       ✗      ← data structure; do not put rules here
```

If a project's cost of change is dominated by adding operations, build with data structures and functions. If it is dominated by adding types, build with objects and polymorphism. If both are growing, you have the Expression Problem — accept that it costs something to support both axes (Visitor, type-class-like patterns, sealed hierarchies with explicit dispatch tables), and budget for it.

---

## The big takeaways

1. **Encapsulation is not a syntax check** — `private` + `getX/setX` is not encapsulation.
2. **Objects and data structures are complements, not synonyms** — pick per class, never both.
3. **Demeter is about strangers, not dots** — it's the *concept* of reaching into hidden internals that violates the law.
4. **Train wrecks are symptoms of failing to push the operation to the right owner.**
5. **DTOs stay dumb; aggregates stay encapsulated; Active Records stay at the persistence boundary.**
6. **Mature designers use whichever side of the dichotomy serves the job — and don't mix.**
