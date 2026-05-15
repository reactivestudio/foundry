# Should `EmailValidator` get an `IEmailValidator` interface?

**No. Don't add the interface.** Your teammate is cargo-culting DIP. Here's the SOLID-grounded justification.

## What DIP actually says

Dependency Inversion Principle (Martin):

> A. High-level modules should not depend on low-level modules. Both should depend on **abstractions**.
> B. Abstractions should not depend on details. Details should depend on abstractions.

The word "abstractions" is doing real work here. DIP is about **inverting the direction of source-code dependencies across an architectural boundary that you care about**. It is not "every concrete class needs a matching `I`-prefixed twin."

An abstraction is valuable when it:

1. **Hides a volatile or replaceable implementation** behind a stable contract, OR
2. **Crosses a boundary** the high-level policy must not know about (DB, network, framework, clock, etc.), OR
3. **Has, or will plausibly have, more than one implementation** (real + fake, strategy A + B).

`EmailValidator.validate(email): Boolean` is none of these:

- It's a **pure function over a string**. No I/O, no clock, no framework. It is already the most abstract thing it can be — a deterministic predicate.
- It crosses no boundary. Regex matching is not a "low-level detail" in the DIP sense; it's the actual policy.
- It has one implementation and one call site.

Wrapping it in `IEmailValidator` doesn't invert a dependency — it just adds an indirection that points at the same concrete class. That's **ceremony, not inversion**.

## What the other SOLID letters say about this

- **SRP** — `EmailValidator` already has one reason to change (the rules for what counts as a valid email). The interface doesn't sharpen that; it duplicates it across two files.
- **OCP** — OCP is about being open to extension *where extension is anticipated*. There is no anticipated second validator. Adding the interface "in case" is speculative generality — the YAGNI failure mode OCP is most often misread into.
- **LSP** — Vacuous with one implementation. You cannot violate or honor LSP against a contract that has no substitutes.
- **ISP** — A one-method interface is technically ISP-clean, but ISP is a remedy for **fat interfaces forced on clients**. There is no fat interface here to segregate. ISP doesn't *demand* interfaces; it constrains their shape when they exist.
- **DIP** — Covered above. No volatility, no boundary, no substitution need => no abstraction owed.

## The honest cost of adding it

- Two files instead of one; navigation overhead on every read.
- A test double becomes tempting in the registration handler's tests — but `validate` is pure, so the real implementation is already the best test double. Mocking it would actively reduce test fidelity.
- Future readers will look for the "other implementation" that justifies the interface, find none, and lose trust in the codebase's signal-to-noise.

## When you *would* add it

Introduce `EmailValidator` as an interface (or better: a functional type `(String) -> Boolean`) the moment **any one** of these becomes true:

- A second strategy appears (e.g., RFC 5322 strict vs. lenient signup-time check).
- Validation needs I/O — DNS MX lookup, disposable-domain blocklist fetched from a service, etc. **Then** it crosses a boundary and DIP genuinely applies.
- The registration handler moves into a module/layer that must not depend on the validator's module (e.g., a domain-core module that can't see an infrastructure module). DIP-by-boundary, driven by the dependency graph, not by the class.

Until then: **delete the suggestion, keep the class.** Refactor *to* the interface when reality demands it — that refactor is cheap (one IDE action). The reverse refactor — deleting an interface everyone now mocks — is not.

## Recommendation

Keep `EmailValidator` as a concrete class. If you want to future-proof one thing, make the registration handler depend on it via constructor injection rather than `new`-ing it inline. That gives you substitutability **at the seam that matters** (the handler's tests, if they ever need it) without inventing an abstraction the domain doesn't have.
