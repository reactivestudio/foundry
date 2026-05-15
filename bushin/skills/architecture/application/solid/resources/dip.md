# DIP — Dependency Inversion

> Source code dependencies refer only to abstractions, not to concretions.

## What baseline gets wrong

- **"DIP = use a DI framework."** Wrong layer. Containers are one mechanism; DIP is about which way source-code dependencies point.
- **"Always program to an interface."** Overstated — DIP targets **volatile** concretes. Wrapping `String` or stdlib types is pointless.
- **"DIP just means inject your dependencies."** You can inject a concrete and still violate DIP.

The criterion is **stability**, not abstractness. Interfaces change less often than implementations. Stable concretes (stdlib) — fine to reference directly.

## Four practices

1. **Don't refer to volatile concrete classes** — use an abstract interface instead.
2. **Don't derive from volatile concrete classes** — inheritance is the strongest source-code coupling.
3. **Don't override concrete functions** — the override doesn't remove the dependency. Make the function abstract and provide multiple implementations.
4. **Never mention the name of anything concrete and volatile** — the above three, stated operationally.

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
