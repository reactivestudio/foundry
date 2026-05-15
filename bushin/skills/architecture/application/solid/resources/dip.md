# DIP — Dependency Inversion Principle

## Definition

**"The most flexible systems are those in which source code dependencies refer only to abstractions, not to concretions."**

In statically typed languages: `import`, `use`, `include` statements name interfaces or abstract classes — never volatile concrete classes.

## What it's NOT

- "DIP = use a DI framework." Wrong layer. DIP is about which way source-code dependencies point; a container is one mechanism among many.
- "Always program to an interface." Overstated — DIP targets **volatile** concretes. Wrapping `String` in an interface is pointless.
- "DIP just means inject your dependencies." Misses the directional point — you can inject a concrete and still violate DIP.

## Stability is the operative property

Interfaces change far less often than the implementations behind them. **Abstractions are stable; concretions are volatile.** DIP says: point source-code dependencies toward the stable side. Stable concrete classes from the language (`String`, stdlib) can be referenced directly — stability, not abstractness, is the criterion.

## Four practices

1. **Don't refer to volatile concrete classes.** Refer to an abstract interface instead.
2. **Don't derive from volatile concrete classes.** Inheritance is the strongest source-code coupling — subclassing drags all the parent's volatility in.
3. **Don't override concrete functions.** The override doesn't remove the source dependency. Make the function abstract and provide multiple implementations.
4. **Never mention the name of anything concrete and volatile.** The above three, stated operationally.

## Abstract Factory and "crossing the curve"

Initialization unavoidably names a concrete. Where does that live?

```
Application ───▶ Service (interface)
Application ───▶ ServiceFactory (interface)
                 ServiceFactoryImpl ───▶ ConcreteImpl (implements Service)
```

Draw a curve through the diagram. Abstract entities (`Service`, `ServiceFactory`, `Application`) sit on one side; concrete entities (`ServiceFactoryImpl`, `ConcreteImpl`) on the other. **All source-code dependencies cross the curve toward the abstract side.** **Flow of control crosses in the opposite direction** — control reaches concrete impls at runtime. That opposition is the **inversion** in Dependency Inversion.

Concrete components are gathered into a small region — often `main` or a composition root — and that's the only place the system names volatile concretes.

## Anti-pattern

```kotlin
class ReportInteractor {
    private val db = PostgresClient("jdbc:postgresql://...")     // names a volatile concrete
    fun run(id: Long): ReportData {
        return db.query("SELECT ... FROM reports WHERE id = $id")
    }
}
// The domain layer now requires Postgres to compile and to test.
```

## Good pattern

```kotlin
// Domain (stable, abstract).
interface ReportGateway {
    fun load(id: Long): ReportData
}

class ReportInteractor(private val gateway: ReportGateway) {
    fun run(id: Long): ReportData = gateway.load(id)
}

// Infrastructure (concrete, volatile). Implements an interface the domain owns.
class PostgresReportGateway(private val db: PostgresClient) : ReportGateway {
    override fun load(id: Long): ReportData { /* ... */ }
}

// Composition root — the only place that names concretes.
fun main() {
    val gateway: ReportGateway = PostgresReportGateway(PostgresClient("..."))
    val interactor = ReportInteractor(gateway)
}
```

## Red flags

- A use-case class `import`s an ORM, HTTP client, or framework type.
- A test for a domain object can't run without spinning up the DB.
- `new ConcreteThing()` appears outside the composition root.
- The domain layer sees framework packages by name.
- A subclass overrides a concrete method to customize behavior — prefer an abstract method with two implementations.
