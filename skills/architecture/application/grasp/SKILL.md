---
name: grasp
description: "Method/class ownership — feature envy, fat controllers, scattered new, anaemic domain. NOT for SOLID class shape."
---

# GRASP

Picks the responsible class before SOLID validates its shape. Asks *who owns this method?* — the design question that precedes "is this class well-shaped?" and "what shape is this collaboration?".

Assumes meaningful domain classes already exist; gives shallow advice over anaemic CRUD.

## When to use

- Placing a new method or class — picking the owner before writing code.
- Reviewing a diff with new services, controllers, util classes, or vendor adapters.
- Refactoring after feature envy, scattered `new`, fat controllers, or `Util`/`Helper`/`Manager` accumulating methods.
- Choosing between a direct call and a domain event for a side effect.
- Wrapping a third-party SDK so business code doesn't import it.

## The nine patterns

| Pattern | Routing rule + discipline |
|---|---|
| **Information Expert** | The class with the data owns the operation. |
| **Creator** | A class that aggregates / contains / records / closely uses / has the initialising data for `A` creates `A`. Default to a factory method on that class. |
| **Controller** | A non-UI class at the boundary (HTTP / queue / scheduler) validates and delegates — never implements. Facade for small subsystems, Use-Case at scale (one handler per use case). |
| **Low Coupling** *(tiebreaker)* | Of placements, prefer fewest new dependencies. |
| **High Cohesion** *(tiebreaker)* | All methods on a class serve one purpose. |
| **Polymorphism** | Type-varying behaviour lives on the type. Earn-keep threshold: same `when (type)` chain in **3+ methods or files**. |
| **Pure Fabrication** | When no domain class fits, invent one with one purpose. **Only after Information Expert has failed on the two most plausible owners** — otherwise every concern grows its own `XxxService`. |
| **Indirection** | An intermediate object so two parties don't know each other. Skip at internal seams; apply where substitution, testability, or a layer boundary is real. |
| **Protected Variations** | Wrap a predicted change point behind a stable interface. **The most expensive GRASP pattern** — apply only at vendor SDKs, persistence stores, API versions, identity primitives, cross-context seams. Don't speculate. |

## Decision questions

Work through these when placing a new responsibility. The first to apply usually resolves the choice.

1. **Where does the data this operation needs live?** → that class is the **Information Expert**.
2. **Of the candidates, which already aggregates / contains / has the initialising data for `A`?** → `A`'s **Creator**.
3. **System-event boundary (HTTP / queue / scheduler)?** → a **Controller** receives, validates, *delegates*.
4. **Two placements otherwise equal?** → tie-break with **Low Coupling** + **High Cohesion**.
5. **Variation by type across multiple methods?** → push it onto the type via **Polymorphism**.
6. **No domain class won on 1–2 and forcing one pulls in infrastructure?** → focused **Pure Fabrication**.
7. **Boundary against infrastructure, or genuinely-predicted change?** → **Indirection** (testability / substitution) or **Protected Variations** (predicted change).

## Quick red flags

- **Information Expert** — service computes by reading entity fields; `obj.field.sub.method()` chains; anaemic class with only accessors.
- **Creator** — scattered `new SomeClass(...)` for the same type; public constructor on a class with invariants.
- **Controller** — handler method doing validation + persistence + vendor calls inline; same coordination duplicated across web / mobile / admin entries.
- **High Cohesion** — `*Util` / `*Helper` / `*Manager` accumulating unrelated methods; > 5 dependencies spanning concerns.
- **Low Coupling** — direct downstream call for a side effect with ≥ 2 plausible consumers; train wrecks (`a.b.c.d()`).
- **Polymorphism** — same `when (type)` chain in 3+ methods or files.
- **Pure Fabrication** — domain entity orchestrating infrastructure; a fabrication with multiple unrelated methods; decision tree on a counter / status / phase (retry, escalation, dunning) where no single entity owns the full chain — extract as `XxxPolicy` with one method.
- **Protected Variations** — vendor SDK calls in business code; primitive `String` / `UUID` for domain IDs.

## Worked example — god-service refactor

A typical compound refactor touches 3-4 patterns together.

**Starting code:** an `OrderController` with five dependencies does validation, pricing, persistence, payment, email, and analytics inline. Smells: fat controller (**Controller**), service computing `unitPrice * quantity` for the entity (**Information Expert**), five dependencies spanning concerns (**High Cohesion**), direct email / analytics calls for independent reactions (**Low Coupling**).

**Move 1 — entities own their computations** (Information Expert):

```kotlin
class Order(private val items: List<OrderItem>) {
    fun total(): Money = items.fold(Money.ZERO) { acc, i -> acc + i.subtotal() }
}
class OrderItem(val unitPrice: Money, val quantity: Int) {
    fun subtotal(): Money = unitPrice * quantity
}
```

**Move 2 — extract `PlaceOrderHandler`** (Controller + Pure Fabrication + High Cohesion). Controller becomes a one-line delegation; handler holds one use case with three dependencies.

**Move 3 — emit `OrderPlaced` event** (Low Coupling). Email and analytics become independent listeners; adding SMS later is a new listener, not an edit to the handler.

**End state:** controller delegates; handler orchestrates three collaborators (not five); entities own their computations; side-effect consumers are independent and additive. One refactor, four patterns — Quick red flags identified the smells, Decision questions led each move.

## When NOT to use

- Class is correctly shaped, the question is *form* (SRP / OCP / LSP / ISP / DIP) — use `solid`.
- Class has a clear owner but a poor label (`Manager`, `Helper`) — use `clean-code-naming`.
- Choosing module layout (Onion / Hexagonal / Modulith) — separate concern.
- One-off scripts, simple CRUD, hot paths where dispatch cost matters.
