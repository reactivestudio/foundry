# DIP — Dependency Inversion

> Source code dependencies refer only to abstractions, not to concretions.

## The criterion is stability, not abstractness

Baseline reading of DIP collapses to "program to an interface." That's the wrong axis. The actual rule:

> Source-code dependencies should point toward things that **change less often** than you do.

Interfaces usually qualify because they change less than implementations — but the load-bearing property is **stability**, not abstractness. Stable concretes (`String`, stdlib types, mature value objects) — fine to depend on directly. Wrapping them in an interface adds noise without buying decoupling.

The operative question on every import line: *"Is this thing more or less volatile than me?"* If less, depend directly. If more, invert.

## Other things baseline gets wrong

- **"DIP = use a DI framework."** Wrong layer. Containers are one mechanism; DIP is about which way source-code dependencies point.
- **"Always program to an interface."** Overstated — DIP targets **volatile** concretes. Wrapping stable types is pointless.
- **"DIP just means inject your dependencies."** You can inject a concrete and still violate DIP.

## Four practices

1. **Don't refer to volatile concrete classes** — use an abstract interface instead.
2. **Don't derive from volatile concrete classes** — inheritance is the strongest source-code coupling.
3. **Don't override concrete functions** — the override doesn't remove the dependency. Make the function abstract and provide multiple implementations.
4. **Never mention the name of anything concrete and volatile** — the above three, stated operationally.

## When an interface is overkill

DIP says invert *volatile* dependencies — it does **not** say wrap every collaborator. An interface earns its place when it satisfies at least one:

1. **It crosses an architectural boundary** — domain↔infra, use-case↔framework, service↔external system.
2. **The concept is volatile** — implementations swap (payment providers, storage backends, notification channels), or is reasonably expected to.

If neither holds — one class, one implementation, stable concept, same layer — the interface is *anemic abstraction*: pure indirection, no decoupling. Reading harder, refactoring harder, runtime no different. Delete the interface, keep the class.

The test isn't *"could there be another implementation someday"* (almost always yes, vacuous). It's *"is the cost of changing this dependency today high enough to pay for the indirection."*

## Crossing the curve

Initialization unavoidably names a concrete. Where does that live?

```
Application ───▶ Service (interface)
Application ───▶ ServiceFactory (interface)
                 ServiceFactoryImpl ───▶ ConcreteImpl (implements Service)
```

Draw a curve: abstract entities on one side, concretes on the other.

- **Source-code dependencies cross the curve only toward the abstract side.**
- **Flow of control crosses the other way at runtime** — control reaches concrete impls via the abstractions.

That opposition is the **inversion** in *Dependency Inversion*.

Concrete components are gathered into one small region — `main`, a Spring `@Configuration`, the composition root — and that's the only place the system names volatile concretes.

## Red flags

- A use-case class imports an ORM, HTTP client, or framework type by name.
- `new ConcreteThing()` appears outside the composition root.
- A test for a domain object can't run without spinning up the DB.
- A subclass overrides a concrete method to customize behavior — prefer an abstract method with two implementations.
