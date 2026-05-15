# Can OCP stand alone? No — it rides on LSP, DIP, and ISP.

**Short answer:** OCP is not an atomic principle. It is an *emergent property* you get when LSP, DIP, and ISP all hold. Try to "design for extension" without them and you produce a fake seam — code that *looks* extensible but breaks the moment someone tries to extend it.

## What OCP actually requires

OCP says: a module should be open for extension, closed for modification. Mechanically, that means new behavior arrives through new types plugged into an existing abstraction, not by editing the existing module. For that to be safe and real, three things must already be true:

### 1. LSP — without it, OCP is a lie

OCP works by holding a reference to an abstraction (`PaymentGateway`) and accepting any subtype (`Stripe`, `PayPal`, new `Adyen`). If subtypes don't honor the contract of the base — they throw on inputs the base accepts, tighten preconditions, weaken postconditions, leak side effects — then every "extension" forces a modification somewhere (a special case, a type check, a try/catch upstream). The closed module gets reopened.

**LSP is the precondition that makes "extension" actually extension and not "modification at a distance."** Without LSP you don't have polymorphism, you have a switch statement wearing a costume.

### 2. DIP — without it, there is no seam to extend through

OCP requires that the stable, closed module depend on an **abstraction**, not a concrete class. That is literally DIP ("depend on abstractions, not concretions"). If `OrderService` directly instantiates `StripeClient`, there is no extension point — adding PayPal means editing `OrderService`. DIP creates the plug; OCP plugs new things into it.

You cannot have OCP without DIP. They are the same mechanism viewed from two angles: DIP describes the dependency edge, OCP describes the behavioral consequence.

### 3. ISP — without it, every extension is over-broad

If the abstraction is a fat interface (15 methods, half irrelevant per implementation), every new extension is forced to implement — or stub, or throw `NotSupported` on — methods it doesn't need. That breaks LSP (see point 1) and pressures you to modify the interface whenever a new variant doesn't fit. ISP keeps the abstraction narrow enough that new implementations can actually satisfy it without lying.

### SRP — the enabling background condition

SRP isn't a direct dependency, but it's what makes the closed module *worth* closing. A module with one reason to change has a stable contract; a module with five reasons to change keeps mutating regardless of how cleverly you parameterized it. SRP defines the axis of variation; OCP keeps that axis open while freezing the rest.

## The dependency graph

```
SRP  →  defines the unit and its single reason to change
 │
 ▼
ISP  →  shapes a narrow abstraction around that unit
 │
 ▼
DIP  →  inverts the dependency so the unit depends on the abstraction
 │
 ▼
LSP  →  guarantees substitutes honor the abstraction's contract
 │
 ▼
OCP  ←  emerges. New behavior via new subtypes, no edits upstream.
```

OCP is at the **bottom** of this chain, not the top. It is the *payoff*, not the *input*.

## Concrete recommendation

Stop treating "follow OCP" as actionable advice. It isn't — it's a target state. When someone tells you to "design for extension," translate it into the three concrete moves that actually produce it:

1. **Find the axis of change.** What will vary? (SRP — name the single reason.)
2. **Define the narrowest interface that captures that variation.** (ISP — no kitchen-sink contracts.)
3. **Make the stable code depend on that interface, not on any implementation.** (DIP — inject it, don't `new` it.)
4. **Write a contract test the interface must pass.** Every implementation runs against it. (LSP — enforced, not hoped for.)

Do those four things and OCP falls out for free. Skip any of them and "designing for extension" produces ceremony — factories, strategies, and abstractions that nobody can actually extend without surgery.

**Bottom line:** OCP cannot be achieved on its own. It is the visible surface of LSP + DIP + ISP working together, with SRP defining what's worth closing in the first place. If you find yourself reaching for OCP directly, you're aiming at the symptom. Aim at the four moves above instead.
