Yes — this is a textbook **LSP violation**, and "compiles + own tests pass" is exactly the trap LSP warns about. The compiler only checks signatures; LSP is about what callers can rely on **after** the call returns.

## The specific break

`List<Integer>.add(value)` has a contract: it accepts any `int`, including negatives, and is documented to return `true` (or follow `Collection.add`'s rules). Your subclass **strengthens the precondition** — it now demands `value >= 0` and throws `IllegalArgumentException` otherwise.

That is mechanism #1 of the two ways LSP gets broken. Every caller written against `List<Integer>` is allowed to do this:

```java
void fill(List<Integer> xs) { xs.add(-1); }   // legal per List's contract
```

Hand them a `PositiveIntList` and that perfectly correct code blows up at runtime. Your own tests don't catch it because they exercise the subclass directly — they never substitute it where a `List<Integer>` is expected, which is the only place the violation manifests.

Bonus damage: `Collection.add` is specified to throw a small, named set of exceptions (`UnsupportedOperationException`, `ClassCastException`, `NullPointerException`, `IllegalArgumentException`, `IllegalStateException`). You picked `IllegalArgumentException`, which is technically in the set, but the **semantic** contract — "rejects elements whose *properties* prevent addition" — was never meant to cover "negative number is a domain rule of mine." Callers don't catch it; they're not expecting domain validation from `List`.

## Why the diagnostic fits

Predict what happens next: somewhere upstream, code that takes `List<Integer>` will need to know "is this one of those picky lists?" and you'll see `if (list instanceof PositiveIntList)` appear — or a try/catch papering over the throw. **That `instanceof` is the LSP smell**: substitutability was supposed to make it unnecessary.

This also kills OCP for any code polymorphic over `List<Integer>` — adding your subtype forces edits in callers. LSP underwrites OCP; break one, lose the other.

## Recommendation

Don't subclass `List`. Two clean options:

1. **Composition + narrower type (preferred).** `PositiveIntList` is **not** a `List<Integer>`; it's a new abstraction that *has* one.

   ```java
   public final class PositiveIntList {
       private final List<Integer> backing = new ArrayList<>();
       public void add(int value) {
           if (value < 0) throw new IllegalArgumentException();
           backing.add(value);
       }
       public int get(int i) { return backing.get(i); }
       public int size() { return backing.size(); }
       // expose only what clients need — see ISP
   }
   ```
   No inheritance, no contract to violate, and the type itself documents the invariant.

2. **Validate at the boundary, store a plain `List<Integer>`.** If "non-negative" is a property of the *input flow*, not of the collection itself, reject negatives where data enters the system and keep `List<Integer>` everywhere internally. Often the right call — the constraint usually belongs to a use case, not a data structure.

Either way: the subclass goes. Substitutability is non-negotiable for a type as widely-used as `List`; the cost of every caller having to know which flavor they hold is enormous, and a single break of this kind tends to pollute an entire codebase with workaround branches.
