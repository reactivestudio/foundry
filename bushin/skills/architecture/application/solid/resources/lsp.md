# LSP — Liskov Substitution

Implementations of a contract must be **interchangeable by behavior**, not just by signature. Compilation only checks signatures; LSP is about what callers can rely on **after** the call returns.

## What baseline gets wrong

- "Subclasses are fine as long as it compiles." Compilation only checks signatures.
- "Square IS-A Rectangle in math, therefore in code." The principle is **behavioral** substitutability, not real-world taxonomy.
- "LSP is about class inheritance." It applies to any substitutable contract — interfaces, REST endpoints, gRPC schemas, message envelopes.

## Diagnostic signature

The reliable smell: **callers need `instanceof` / `is X` checks to use the abstraction correctly.** That's exactly what substitutability is supposed to make unnecessary. Also:

- An override throws `UnsupportedOperationException` or no-ops.
- A subtype tightens preconditions or weakens postconditions.
- Two implementations of the same interface are chosen by per-name special cases.

**Silent semantic shifts.** Signature and return type match across subtypes, but meaning diverges — one subtype returns `Result(status="success")` synchronously, another returns `Result(status="pending")` for an async settlement under the same return type. The compiler sees a match; the caller sees a lie. LSP violation by postcondition — the base promises a meaning the subtype quietly breaks. Test: can you write caller code that handles every subtype identically? If not, the postcondition is broken even when the type system says it isn't.

## Architectural pollution

LSP violations don't stay local — they leak into architecture as workaround mechanisms. Example: a taxi aggregator dispatches via uniform URI `.../destination/ORD`. One company abbreviates to `dest`. Now the aggregator carries `if (uri.startsWith("acme.com"))` branches and a config DB mapping URIs to per-vendor quirks, forever — with the bugs and security gaps that come with it. **A single substitutability break pollutes an entire architecture.**
