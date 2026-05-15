# Review: `BoundedCache.put` throws when full

Yes — this is a **Liskov Substitution Principle** violation.

## Why

The `Cache` interface defines `put(key, value): Unit`. The implicit behavioral contract a caller reads off that signature is: *give me a key and value, and after the call returns the cache contains that mapping (subject to eviction policy)*. The return type `Unit` and the absence of a declared exception both say "this always succeeds."

`BoundedCache` keeps the signature but **strengthens the precondition** ("the cache must not already be full") and **weakens the postcondition** ("the mapping may not actually be stored — you might get an exception instead"). That is precisely the LSP failure mode the skill names: *a subtype tightens preconditions or weakens postconditions vs. its parent*. It's a cousin of the `UnsupportedOperationException`-in-an-override red flag — the override honors the signature but not the behavior.

The architectural smell follows quickly. Any code holding a `Cache` reference now has to know whether the concrete is bounded, or wrap every `put` in a try/catch — exactly the `if (cache is BoundedCache)` branching LSP exists to make unnecessary. One substitutability break pollutes every call site.

## The fix — pick one, deliberately

1. **Make eviction part of the `Cache` contract.** The interface promises `put` always succeeds; bounded implementations evict (LRU, LFU, whatever) to honor it. `BoundedCache` becomes a true substitute. This is almost always the right call for a cache — "cache" already implies "may forget things."

2. **Split the contract honestly.** If rejection-on-full is a real requirement somewhere, it's a different abstraction: `interface BoundedStore { fun tryPut(...): Boolean }` or `put` returning a `Result`/`Either`. Clients that need rejection semantics depend on `BoundedStore`; clients that just want a cache depend on `Cache`. No subtype lies about what its parent promised.

What you can't keep is the current shape: same interface, same signature, silently different behavior. That's the Square-extends-Rectangle pattern in another costume — the compiler is happy, the callers are not.
