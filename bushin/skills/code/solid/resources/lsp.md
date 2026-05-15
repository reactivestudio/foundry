# LSP — Liskov Substitution Principle

## Definition

Liskov's original (1988), quoted verbatim by Martin: *"If for each object o1 of type S there is an object o2 of type T such that for all programs P defined in terms of T, the behavior of P is unchanged when o1 is substituted for o2, then S is a subtype of T."*

**Plain version:** implementations of a contract must be **interchangeable by behavior**, not just by signature.

## What it's NOT

- Not "subclasses are fine as long as it compiles." Compilation only checks signatures; LSP is about behavior.
- Not confined to class inheritance. Any contract — interface, protocol, REST schema, RPC, message envelope — is in scope.
- "Square IS-A Rectangle in math, therefore in code" — the principle is **behavioral** substitutability, not real-world taxonomy.

## Beyond inheritance

Martin widens LSP beyond class hierarchies. It applies to any substitutable contract: language-level interfaces, duck-typed objects, REST endpoints, gRPC schemas, message contracts. LSP is therefore an **architectural** principle — violations leak into architecture as workaround mechanisms.

## Good example — License hierarchy

`License` is abstract with `calcFee()`. `PersonalLicense` and `BusinessLicense` compute fees differently. `Billing` depends only on `License`. Either subtype substitutes cleanly because both honor the same behavioral contract: given the inputs `License` defines, produce a valid fee.

## Bad example — Square / Rectangle

`Rectangle` has independently mutable width and height. `Square extends Rectangle` must keep `width == height`. A caller writes `r.setW(5); r.setH(2); assert r.area() == 10` — passes for `Rectangle`, fails for `Square`. The only defense is `if (r is Square)` — which is exactly what substitutability is supposed to make unnecessary.

## Architectural example — REST taxi dispatch

A taxi aggregator dispatches to many companies via a uniform URI shape ending `.../destination/ORD`. Acme abbreviates `destination` to `dest`. The aggregator now needs `if (uri.startsWith("acme.com")) ...` branches, a configuration database mapping URIs to per-company quirks, and carries those forever — with the bugs and security gaps that come with them. Martin's lesson: a single substitutability violation can pollute an entire architecture with extra mechanisms.

## Anti-pattern

```kotlin
open class Rectangle {
    open var width: Int = 0
    open var height: Int = 0
    fun area(): Int = width * height
}

class Square : Rectangle() {
    override var width: Int = 0
        set(value) { field = value; super.height = value }   // surprise
    override var height: Int = 0
        set(value) { field = value; super.width = value }    // surprise
}

// Callers must now know whether r is really a Square.
// `is`/`instanceof` checks leak into every consumer of Rectangle.
```

## Good pattern

```kotlin
interface Shape {
    fun area(): Int
}

class Rectangle(private val width: Int, private val height: Int) : Shape {
    override fun area(): Int = width * height
}

class Square(private val side: Int) : Shape {
    override fun area(): Int = side * side
}

// No subtype claims to be the other. Consumers depend on Shape;
// both are honest substitutes — neither overrides the other's contract.
```

## Red flags

- An override throws `UnsupportedOperationException` or no-ops.
- Callers need `instanceof` / `is` checks to use the abstraction correctly.
- A subtype tightens preconditions or weakens postconditions vs. its parent.
- Two implementations of the same interface are chosen by per-name special cases (`if (impl == "acme") ...`).
