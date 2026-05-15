# LSP — Liskov Substitution

Implementations of a contract must be **interchangeable by behavior**, not just by signature. Compilation only checks signatures; LSP is about what callers can rely on **after** the call returns.

## What baseline gets wrong

- "Subclasses are fine as long as it compiles." Compilation only checks signatures.
- "Square IS-A Rectangle in math, therefore in code." The principle is **behavioral** substitutability, not real-world taxonomy.
- "LSP is about class inheritance." It applies to any substitutable contract — interfaces, REST endpoints, gRPC schemas, message envelopes.

## Diagnostic signature

The reliable smell: **callers need `instanceof` / `is X` checks to use the abstraction correctly.** That's exactly what substitutability is supposed to make unnecessary. Also:

- An override throws `UnsupportedOperationException` or no-ops.
- A subtype **tightens preconditions** (callers must now ensure something the parent didn't require).
- A subtype **weakens postconditions** (parent promised X; subtype delivers less than X).
- Two implementations of the same interface are chosen by per-name special cases.

## Architectural pollution

LSP violations don't stay local — they leak into architecture as workaround mechanisms. Example: a taxi aggregator dispatches via uniform URI `.../destination/ORD`. One company abbreviates to `dest`. Now the aggregator carries `if (uri.startsWith("acme.com"))` branches and a config DB mapping URIs to per-vendor quirks, forever — with the bugs and security gaps that come with it. **A single substitutability break pollutes an entire architecture.**
