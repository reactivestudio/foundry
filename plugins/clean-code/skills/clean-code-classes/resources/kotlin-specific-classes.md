# Kotlin-specific class rules

Kotlin shifts the *Clean Code Ch. 10* rules in three ways: some are **solved by the language** and need no discipline, some are **expressed differently** and need a translation table, and a few are **new traps** introduced by Kotlin's own machinery. This file walks each one.

## 1. Primary-constructor properties — the Java "field-at-top" rule becomes free

In Java, the class organisation rule says: **public static constants → private static → private instance variables → public methods → private utilities**. The first three sections are explicit field declarations, written in order at the top.

Kotlin collapses 2–3 into the **primary constructor**:

```kotlin
class OrderProjectionUpdater(
    private val projections: OrderProjections,
    private val clock: Clock,
) {
    // class-level constants (companion object)
    companion object {
        private const val MAX_BATCH = 500
    }

    // additional internal state if needed
    private val pending = mutableListOf<OrderEvent>()

    // public API and private helpers in stepdown order
    fun apply(event: OrderEvent) { ... }
    private fun loadProjection(id: OrderId): OrderProjection = ...
}
```

**What this means in practice:**

- **Primary-constructor `val`s and `var`s are the field list.** You don't write a separate field block underneath — the constructor *is* the field block.
- **`companion object` replaces `public static final`.** Constants and class-level factory methods live there.
- **Additional state** (caches, mutable buffers) lives **inside the class body**, between the companion and the methods.
- **The stepdown rule is the same** — public methods first, private utilities placed directly after their first caller.

### Trap — too many primary-constructor parameters mask SRP violations

A primary constructor with 9 dependencies isn't "Kotlin is concise"; it's a god class with the field count hidden by the syntax. **Count the parameters. Apply the cohesion test. Split.**

## 2. `internal` visibility — the ideal test seam

In Java, the visibility levels for *test access* are awkward: `package-private` requires the test to live in the same package, `protected` exposes to subclasses, and there is no way to mark something "visible inside this module, invisible outside".

Kotlin has **`internal`**: visible within the **module** (Gradle/Maven module, IntelliJ module), invisible outside. This is the *strongest* test seam short of public.

```kotlin
class Order private constructor(
    val id: OrderId,
    private val lines: MutableList<OrderLine>,
    private var status: OrderStatus,
) {
    fun submit() { ... }

    companion object {
        fun draft(id: OrderId, lines: List<OrderLine>): Order =
            Order(id, lines.toMutableList(), OrderStatus.DRAFT)

        // internal: visible to in-module tests, invisible to other modules
        internal fun rehydrate(
            id: OrderId,
            lines: List<OrderLine>,
            status: OrderStatus,
        ): Order = Order(id, lines.toMutableList(), status)
    }
}
```

### The visibility decision tree, Kotlin-specific

When a test needs access:

1. **Drive through the public API.** Best.
2. **`internal`** (Kotlin module-scoped). Use freely; this is the right answer for most "the test needs to construct an instance in a state the lifecycle doesn't naturally produce" cases.
3. **`@VisibleForTesting internal`** (with a marker if you want to be explicit about *why* it's internal). Optional discipline.
4. **`protected` / `public`** — only if `internal` doesn't work (cross-module tests, Java-Kotlin mix where Kotlin's `internal` becomes a mangled public name on the JVM).

### Trap — `internal` becomes mangled `public` on the JVM

`internal` is enforced by the Kotlin compiler, not the JVM. From Java, `internal` methods are visible (with a mangled name like `submit$module_name`). For Kotlin-only modules this is fine; for Kotlin-Java mixed modules, the compiler can't stop a Java caller. Document the seam with `@VisibleForTesting` if mixing.

## 3. `sealed class` / `sealed interface` — OCP as a language feature

Java OCP via abstract base + open subclassing has a known weakness: the **set of subclasses is open at runtime**, so `instanceof` chains can be incomplete and you can't get exhaustiveness checking.

Kotlin `sealed`:

```kotlin
sealed class Sql(protected val table: String, protected val columns: Array<Column>) {
    abstract fun generate(): String
}

class CreateSql(table: String, columns: Array<Column>) : Sql(table, columns) {
    override fun generate(): String = ...
}

class InsertSql(
    table: String,
    columns: Array<Column>,
    private val fields: Array<Any>,
) : Sql(table, columns) {
    override fun generate(): String = ...
}

class SelectSql(table: String, columns: Array<Column>) : Sql(table, columns) {
    override fun generate(): String = ...
}
// ... more subclasses ...
```

**Why this is better than Java open subclassing:**

- The compiler **knows the full set** of subclasses, so `when (sql) { is CreateSql -> ...; is InsertSql -> ...; ... }` is **exhaustive** — adding a new subclass forces every `when` to be updated, which is the *good* failure mode for OCP enforcement.
- Subclasses live in the **same file** (Kotlin 1.5+) or **same package/module** (older), which keeps the closed hierarchy reviewable.
- New variants are added by **writing a new subclass** — no existing class changes. Pure OCP.

### Sealed interface vs sealed class

- **`sealed interface`** — preferred when subclasses don't share state, just contract. Multiple sealed interfaces can be implemented by one class (multiple inheritance of types).
- **`sealed class`** — when subclasses share state (the `table` and `columns` in the example) or want a common implementation hook.

### The tolerated `when` — the factory boundary

OCP via sealed hierarchies still leaves **one** place where you must `when` on type: at the boundary where an external input (a config record, a JSON tag, a DB row) is turned into the right subtype:

```kotlin
fun Sql.Companion.from(record: SqlRecord): Sql = when (record.type) {
    "create" -> CreateSql(record.table, record.columns)
    "insert" -> InsertSql(record.table, record.columns, record.fields)
    "select" -> SelectSql(record.table, record.columns)
}
```

That single `when` is the right place — every other operation dispatches through polymorphism. (See the same rule in `clean-code-functions`: "tolerated `when` on type — once, inside a factory, buried behind the sealed root".)

## 4. `object` and `companion object` — singletons and class-level helpers without static

### `object` — singleton without ceremony

```kotlin
object PrimeGenerator {
    fun generate(n: Int): IntArray { ... }
}

// usage
val primes = PrimeGenerator.generate(1000)
```

Replaces:
- Java `public static` utility classes (`PrimeGeneratorUtils` with all-static methods).
- Hand-rolled singletons (`getInstance()` + private constructor + lazy holder).
- Some Spring `@Configuration` patterns where lifecycle isn't actually needed.

**SRP implication:** `object` is a thread-safe singleton with one purpose. The 25-word test applies — an `object` with 30 methods serving 4 unrelated concerns is still a god class.

### `companion object` — the class-level scope

```kotlin
class Order private constructor(...) {
    companion object {
        const val MAX_LINES = 100

        fun draft(id: OrderId, lines: List<OrderLine>): Order = ...
        fun submitted(id: OrderId, lines: List<OrderLine>): Order = ...
    }
}
```

The `companion object` holds:
- Class-level constants (`const val`).
- Factory methods (replacing constructor overloads).
- Optionally interface implementations the *class* should expose (e.g., `Comparator<Order>` as a companion).

**Don't** use `companion object` as a dumping ground for "loose" helpers. The same SRP rule applies — if your companion has methods that don't touch the class's domain, they belong somewhere else (a top-level function, a separate `object`, or a different class).

## 5. `data class` — the value-shaped class is one line

```kotlin
data class Version(val major: Int, val minor: Int, val build: Int)
```

A `data class` gives you `equals` / `hashCode` / `toString` / `copy` / destructuring for free. It is the **ideal shape for a class whose responsibility is to hold immutable data**:

- DTOs (request/response bodies, Kafka payloads).
- Value objects with multiple fields (`Money`, `Period`, `Address`).
- The product of an extraction — when you split a god class's "version tracking" responsibility into its own class, it's almost always a `data class`.

**Connection to `clean-code-objects-and-data`:** `data class` is the pure-data side of the object/data anti-symmetry. Don't add business methods to it; if it needs behaviour, it's a behaviour-rich class with the data hidden, not a data class.

## 6. `@JvmInline value class` — the wrapper without runtime cost

Primitive obsession ("we just pass `String` around for `OrderId`") inflates class signatures and weakens the type system. Kotlin's solution:

```kotlin
@JvmInline value class OrderId(val value: UUID)
@JvmInline value class Email private constructor(val value: String) {
    companion object {
        fun of(raw: String): Email {
            require(raw.matches(EMAIL_REGEX)) { "Invalid email: $raw" }
            return Email(raw)
        }
    }
}
```

- **Zero runtime cost** in most cases (compiles to the underlying primitive at the bytecode level).
- **Type-safe** at compile time — `OrderId` is not interchangeable with `CustomerId`, even if both wrap `UUID`.
- **Single-responsibility** by design — a value class with one field is exactly one concept.

**SRP connection:** a value class is the smallest possible single-responsibility class. When a class would otherwise grow a field of type `String` that represents a domain concept, prefer a value class.

## 7. Extension functions — keep behaviour off god classes

In Java, adding a method to a class often means **modifying the class**. If you don't own the class (third-party library, framework type, JDK type), you write a `FooUtils.doX(Foo, ...)` static helper, which doesn't feel like the class's method but is.

Kotlin extension functions let you **add methods without modifying the class**:

```kotlin
fun LocalDate.isBusinessDay(): Boolean = dayOfWeek !in setOf(SATURDAY, SUNDAY)

fun List<Order>.totalValue(): Money = sumOf { it.value }
```

**Class-design implication:** When an existing class is getting a 31st method, ask: **does this method really belong on the class, or is it an extension?** Extensions:

- Don't bloat the original class.
- Are scoped to the file/module where they're declared (`import` for use elsewhere).
- Can be tested in isolation as top-level functions.

**Don't go too far.** Extensions on `Any?` or on framework types that *every* file needs (`Any.toJson()`, `Any.log()`) become invisible global verbs. Reserve extensions for cases where the receiver is unambiguous.

## 8. `by` delegation — composition over inheritance, finally easy

Java inheritance ("`AbstractFooService` with shared state and template methods") is the easy escape from "I have two classes that share 80% of their behaviour". It usually leads to brittle inheritance hierarchies that violate SRP (the parent has fields used by only some subclasses) and OCP (changing the parent breaks all subclasses).

Kotlin `by` delegation makes composition straightforward:

```kotlin
interface Repository<E, ID> {
    fun findById(id: ID): E?
    fun save(entity: E): E
    fun deleteById(id: ID)
}

class AuditingOrderRepository(
    private val underlying: Repository<Order, OrderId>,
    private val auditLog: AuditLog,
) : Repository<Order, OrderId> by underlying {

    override fun save(entity: Order): Order {
        auditLog.write("save", entity.id)
        return underlying.save(entity)
    }
}
```

`by underlying` forwards every method **not explicitly overridden** to the `underlying` instance. The auditing repository **adds behaviour without inheriting state**.

**Class-design implication:** When you find yourself reaching for inheritance to share fields or methods, reach for `by` instead. Inheritance is for *is-a* relationships at the domain level; sharing implementation is a *has-a* relationship and belongs as composition.

## 9. Traps Kotlin introduces

### `lateinit var` as a god-class lubricant

`lateinit var` lets you declare a non-null field initialised later. Spring's field injection sometimes uses this:

```kotlin
class CustomerService {
    @Autowired lateinit var cache: Cache
    @Autowired lateinit var mailer: Mailer
    @Autowired lateinit var auditLog: AuditLog
    @Autowired lateinit var clock: Clock
    // ... 11 more @Autowired lateinit vars
}
```

This **hides the SRP violation behind cosmetic syntax**. The class still has 15 dependencies; the constructor just doesn't show them.

**Rule:** prefer constructor injection (also for DIP — see SKILL.md). The number of primary-constructor parameters is the **dependency count visualisation** that triggers refactoring conversations. `lateinit` hides that signal.

### `init { }` blocks that do too much

```kotlin
class OrderProcessor(...) {
    init {
        loadCache()
        registerListeners()
        warmConnections()
        validateConfiguration()
    }
}
```

`init` is constructor logic. If `init` is doing four unrelated initialisation steps, the class has four responsibilities. Move them to lifecycle methods (`@PostConstruct` in Spring) or to dedicated initialiser classes, or split the class.

### `object` as a hiding place for static utilities

Kotlin `object` removes the friction of Java static utility classes — which is sometimes a feature, sometimes a license to write `OrderUtils.doEverything(...)`:

```kotlin
object OrderUtils {
    fun calculateTotal(...) { ... }
    fun render(...) { ... }
    fun validate(...) { ... }
    fun export(...) { ... }
    fun cancel(...) { ... }
}
```

`object` doesn't dodge SRP. Each `object` should pass the 25-word test like any other class. If it doesn't, the `object` is a god in disguise.

### `companion object` accumulating unrelated factory methods

Companion objects sometimes grow into mini-namespaces:

```kotlin
class Order private constructor(...) {
    companion object {
        fun draft(...) = ...
        fun submitted(...) = ...
        fun rehydrate(...) = ...
        fun fromCsvRow(row: CsvRow) = ...     // ← CSV concern leaked into the domain
        fun fromKafkaPayload(p: ByteArray) = ... // ← messaging concern leaked
        fun fromLegacyRow(r: LegacyRow) = ...    // ← legacy adapter leaked
    }
}
```

The CSV / Kafka / legacy factory methods are **not domain concerns** — they're integration mappers. They belong on the adapter / port classes (`OrderCsvParser`, `OrderKafkaCodec`, `LegacyOrderTranslator`). Keeping them on `Order` makes the companion a god.

### Top-level functions as orphaned methods

Top-level Kotlin functions are sometimes the *right* tool (small utilities, extension functions). They are also sometimes **methods on a class that's not been written yet**. If a file has 12 top-level functions all operating on the same set of types, those types might want to be a class with those functions as methods (or extensions defined in the same file).

## 10. Quick-reference translation table — Java rule → Kotlin idiom

| Martin Ch. 10 rule | Java idiom | Kotlin idiom |
|---|---|---|
| Public static constants at top | `public static final int X = ...` | `companion object { const val X = ... }` |
| Private static state at top | `private static int counter;` | `companion object { private var counter = 0 }` (rare) |
| Private instance variables at top | `private final Foo foo;` ... constructor `this.foo = foo` | Primary-constructor `class C(private val foo: Foo)` |
| Public methods follow fields | identical | identical |
| Private utilities after their caller | identical (stepdown) | identical (stepdown) |
| Privacy by default; tests rule | `package-private` for tests | `internal` for tests |
| One reason to change | apply | apply |
| 25-word description test | apply | apply |
| Cohesion: fields used by many methods | apply | apply (count primary-constructor params + body fields) |
| Many small classes | one class per file | multiple classes per file when tightly coupled (sealed hierarchy in one file is *idiomatic*) |
| OCP via abstract base + subclasses | `abstract class X` + open subclasses | `sealed class X` + closed subclasses, exhaustive `when` |
| DIP via interface + constructor | `Portfolio(StockExchange exchange)` | `class Portfolio(private val exchange: StockExchange)` |
| Static utility class | `public final class Utils { private Utils(){} ... }` | `object Utils { ... }` |
| Wrapper class with one field | `class Email { private final String value; ... }` | `@JvmInline value class Email(val value: String)` |
| Helper method on a class you don't own | `FooUtils.doX(Foo, ...)` | `fun Foo.doX() = ...` (extension) |
| Sharing implementation across classes | inheritance | `by` delegation (composition) |

## Cross-references

- Martin's canonical rules: `resources/general-classes-rules.md`.
- Spring/JPA applications (constructor injection, thin controllers, god-service split): `resources/spring-boot-classes.md`.
- Aggregate / VO / Repository shapes: `resources/ddd-classes.md`.
- Function-level Kotlin idioms (named args, scope functions, `when`): `clean-code-functions` (`resources/kotlin-specific-functions.md`).
- DTO / value-class / `data class` shape vs. behaviour-rich object: `clean-code-objects-and-data`.
- Wrapping a third-party SDK behind a port: `clean-code-boundaries`.
