No — OCP is not achievable on its own. "Design for extension" is the *what*; the other principles are the *how*. SOLID is a chain, and OCP sits in the middle of it.

## What OCP actually requires

OCP says: you should be able to add new behavior without modifying existing code. That promise rests on two mechanics — directional control of dependencies, and substitutable polymorphism. Neither is OCP's own machinery. They come from DIP and LSP.

### OCP needs DIP — "OCP is *what*, DIP is *how*"

"Closed for modification" only works if the volatile thing (the new payment provider, the new report format) points *at* the stable thing, not the other way around. If your domain class imports `StripeClient` by name, no amount of extension points saves you — adding PayPal still edits the domain.

DIP is the lever: volatile depends on stable, and the abstraction is owned by the stable side. Without that arrow direction, every "extension" is really a modification in disguise.

Concretely: an `interface PaymentGateway` owned by the domain, implemented in the infra layer. That single inversion is what makes the domain *closed* while the system stays *open*.

### LSP underwrites OCP

OCP's primary mechanism is polymorphism — you swap implementations behind an abstraction. The instant a subtype isn't behaviorally substitutable (tightens preconditions, weakens postconditions, throws on half its methods), callers start branching with `instanceof` and the closure breaks. Every `if (x instanceof SpecialCase)` is OCP leaking because LSP failed.

LSP is the contract that makes the polymorphic swap *safe*. Without it, OCP degrades into a switch statement with extra steps.

### SRP and ISP set up the seams

OCP also assumes you have the right seams to extend at. That's upstream work:

- **SRP** decides *where* the seams go. Split by actor, and the boundary between actors is the natural place to put the abstraction OCP will extend across. Without SRP, you don't know which axis of change to design extension for — and you can't be closed against every axis.
- **ISP** keeps the seam honest. An extension point bloated with methods no client uses forces every new implementor to fake-implement or throw. That's an OCP cost paid at every extension.

## The chain, applied to a concrete question

"How do I add a new report format without touching existing code?"

1. **SRP**: is "format the report" a different actor from "compute the report"? If yes, they belong in different modules. That's where the seam goes.
2. **DIP**: the computing module owns a `ReportRenderer` interface. The format modules implement it. Arrow points at the domain.
3. **LSP**: every renderer honors the same contract — same preconditions, same postconditions, no surprise exceptions. Caller never asks which renderer it has.
4. **ISP**: `ReportRenderer` exposes only what the caller actually uses. No `configure()`, `warmup()`, `getMetadata()` bolted on for one implementor.
5. **OCP falls out for free.** Adding PDF means adding a class. Zero edits to existing code.

Notice OCP wasn't a step. It's the *result* of the other four being correct.

## Recommendation

Stop treating OCP as something you do directly. When someone says "design for extension," translate it into the four upstream questions:

- Who's the actor whose changes I'm protecting against? (SRP)
- Which side owns the abstraction — volatile or stable? (DIP)
- Can every implementation be swapped without the caller noticing? (LSP)
- Does the interface answer to exactly one client role? (ISP)

If those four answers are clean, OCP is automatic. If OCP feels stuck, the fix is almost always one link up the chain — usually a missed DIP inversion or an SRP split you haven't made yet.
