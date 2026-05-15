# Review: `BoundedCache.put` throwing on full

**Verdict: yes, this is a SOLID violation — specifically the Liskov Substitution Principle (LSP).**

## Why it's an LSP violation

LSP says a subtype must be usable anywhere the supertype is expected, without callers needing to know which concrete implementation they got. That includes behavioral contracts, not just method signatures.

Your `Cache` interface advertises:

```
put(key, value): Unit
```

The return type `Unit` and the absence of a documented failure mode tell every caller: "this always succeeds." Callers written against `Cache` will reasonably do:

```kotlin
fun warm(cache: Cache<String, User>, users: List<User>) {
    users.forEach { cache.put(it.id, it) }
}
```

Drop `BoundedCache` in and that code now blows up with `IllegalStateException` once capacity is hit. The subtype **strengthened the preconditions** ("only call when not full") and **broadened the thrown exceptions** beyond what the supertype promises. Both are textbook LSP breaks (Meyer's history/precondition rules; Liskov & Wing's behavioral subtyping).

Note it is *not* SRP (one responsibility — caching) and *not* ISP (interface is already minimal). It also isn't OCP per se, though the design that forced this choice is OCP-adjacent.

## How to fix

Pick one of three, in order of preference:

1. **Honor the contract — evict.** A bounded cache's job *is* to evict (LRU/LFU/FIFO). Throwing defeats the point; callers use a cache precisely so they don't have to think about capacity. This is the right answer 95% of the time.

2. **Change the contract to admit failure.** If "reject on full" is a real business requirement (e.g. a write-through cache where silent eviction loses data), make it explicit on the interface:

   ```kotlin
   interface Cache<K, V> {
       fun get(key: K): V?
       fun put(key: K, value: V): PutResult   // Accepted | Rejected(reason)
   }
   ```

   Now *all* implementations share the failure mode and callers must handle it — no LSP surprise.

3. **Don't subtype.** If `BoundedCache` genuinely has different semantics, give it its own interface (`RejectingStore`) and don't pretend it's a `Cache`. Honest naming beats a leaky hierarchy.

Option 1 unless you have a written reason for option 2.
