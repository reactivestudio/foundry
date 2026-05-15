# PositiveIntList vs SOLID — verdict

**Yes — this violates the Liskov Substitution Principle (the "L" in SOLID).**

## The violation

LSP says: a subtype must be substitutable for its base type without breaking the contract clients rely on. Concretely, Liskov's rule for method overrides:

- **Preconditions may be weakened, never strengthened.**
- **Postconditions may be strengthened, never weakened.**
- **Invariants of the supertype must be preserved.**
- **No new exceptions** beyond those declared/expected by the supertype (history/exception rule).

`List<Integer>.add(E)` has a very permissive precondition: any `Integer` (including negatives, zero, `null` for most impls) is acceptable, and it returns `true` (or throws only structural exceptions like `UnsupportedOperationException`, `ClassCastException`, `NullPointerException` for specific documented reasons — never `IllegalArgumentException` for "value is negative").

`PositiveIntList.add(v)` **strengthens the precondition** to `v >= 0` and throws `IllegalArgumentException` otherwise. That is exactly the forbidden direction.

## Why it actually breaks code

Any method written against `List<Integer>` is allowed to assume "I can add any int." Pass it a `PositiveIntList`:

```java
void fill(List<Integer> xs) {
    xs.add(-1);          // legal per List contract
    xs.add(computeDelta()); // may be negative — caller has no reason to check
}
```

The caller is correct against the declared type. The subclass blows up at runtime. That is the canonical LSP smell: **the type system says it's safe; the runtime says otherwise.**

The fact that "tests on PositiveIntList pass" is the trap — LSP failures show up at the **call sites that use the supertype**, not in tests scoped to the subtype.

## Other SOLID angles (secondary)

- **ISP** isn't really at play — `List` is a single cohesive interface.
- **OCP** is fine in isolation.
- **SRP**: arguably `PositiveIntList` is conflating "list storage" with "domain validation rule," but that's a code-smell observation, not the core defect.

The core defect is LSP.

## Recommendation

Do **not** model "list of positive ints" by subclassing `List<Integer>`. Two clean options, in order of preference:

1. **Composition + a new type (preferred).** Create a `PositiveIntBag` (or `NonNegativeIntList`) that **does not extend `List<Integer>`**. Internally hold a `List<Integer>`; expose only the operations whose contracts you can honor (`add(int)` that validates, `get`, `size`, `iterator`, etc.). Clients that need "any list of ints" can't accidentally receive your type, so the LSP trap disappears. Bonus: you can take `int` instead of `Integer` and reject negatives at the type boundary clearly.

2. **Validate at the boundary, store in a plain `List<Integer>`.** Often the "positive only" rule belongs to the *use case* (a service, a constructor of the aggregate that owns the list), not to the collection itself. Validate on the way in; keep the collection generic. This is usually the right answer in practice — the rule is a domain invariant of the owning entity, not of "list-ness."

A stricter type **is allowed** to *return* something more specific (strengthen postconditions) — e.g. a `List<PositiveInteger>` where `PositiveInteger` is its own value type with a validating constructor. That pushes the check to object construction, where it doesn't violate any `List` contract.

## One-line takeaway

If your subclass throws on inputs the parent class accepts, it isn't a subtype — it's a different type wearing the parent's hat. Use composition, or move the invariant to a value type.
