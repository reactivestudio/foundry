# SOLID — Theory (language-agnostic)

The five principles, distilled. Definition + intent + why-it-matters per principle, with a canonical example that doesn't depend on Kotlin or Spring. The Kotlin idioms live in `kotlin.md`; the Spring conventions in `spring-boot.md`.

---

## S — Single Responsibility Principle

> **A class should have one, and only one, reason to change.**

Robert C. Martin's reformulation: *"Gather together the things that change for the same reason, and separate the things that change for different reasons."*

### What "responsibility" means

A responsibility is a **reason a person or a process can ask for the class to change**. Not a feature, not a method count, not "things the class does" — a *source of change*.

A class with multiple responsibilities is fragile. Each external change vector reaches into the same class; edits collide; the class becomes a dependency magnet.

### The "reason to change" prompt

For each class, complete: *"This class would change if ___"*. If the answer needs an "or", the class has multiple responsibilities:

> "if the registration policy changes **or** if the welcome email template changes" → two responsibilities.

### Canonical anti-pattern: the god service

A `UserService` that handles registration, login, password reset, profile updates, deactivation, and audit. Six different stakeholders (security, UX, ops, legal, product, compliance) can ask for changes to the same class. Six responsibilities → split into six focused classes.

### Why this matters more than people think

SRP is a **stability** rule, not a size rule. A 200-line class with one responsibility is fine. A 50-line class with three responsibilities is broken. The cost of mis-shaped responsibilities compounds: every new requirement edits multiple classes, every test setup pulls in unrelated dependencies, every merge conflict reveals the tangle.

---

## O — Open/Closed Principle

> **Software entities (classes, modules, functions) should be open for extension, but closed for modification.**

Bertrand Meyer, 1988. Refined by Robert Martin via the polymorphism interpretation: extend behaviour by adding new code (a new subtype, a new strategy), not by editing existing code.

### What "closed for modification" means

Once a class works and is deployed, you should be able to add new variants of its behaviour **without touching the class itself**. New behaviour ships as new code (new subclass, new module, new bean) — not as new branches in an existing `switch`.

### Canonical anti-pattern: the `switch`/`when` chain on type

```
if (paymentMethod == CARD) processCard(...)
else if (paymentMethod == BANK_TRANSFER) processBankTransfer(...)
else if (paymentMethod == PAYPAL) processPaypal(...)
```

Repeated across `process()`, `fee()`, `supports()`. Adding `CRYPTO` requires editing **three** methods. Each edit is a chance to forget a branch.

### The polymorphism fix

Push the per-type behaviour onto the type itself. Each variant becomes a class with its own implementation. Adding `CRYPTO` = adding one class. No edits to existing code.

### When OCP doesn't apply

OCP optimises for **anticipated change**. If a fourth payment method will never exist, extracting a sealed hierarchy is overhead. **Wait for the second concrete case** before generalising. Premature OCP is the single most common over-engineering source — more than premature optimisation.

### Why this matters

OCP is the principle that lets a system grow safely. Without it, every feature touches every existing file, regression risk is permanent, and the codebase ossifies. With it, new features are additions; existing code stays untouched and tested.

---

## L — Liskov Substitution Principle

> **Subtypes must be substitutable for their base types without altering the correctness of the program.**

Barbara Liskov, 1987. Original formulation: *"If for each object o₁ of type S there is an object o₂ of type T such that for all programs P defined in terms of T, the behaviour of P is unchanged when o₁ is substituted for o₂, then S is a subtype of T."*

In practice: code that works against the base type must continue to work against any subtype, with no surprise.

### The contract rules (design by contract)

A subtype must:

- **Not strengthen preconditions** — don't demand more than the base type does. (Base accepts `String?`, subtype demanding `String` is a violation.)
- **Not weaken postconditions** — don't return less than the base type promises. (Base returns `Animal`, subtype returning `Animal?` is a violation.)
- **Not throw new exceptions** — only throw what the base contract documents.
- **Preserve invariants** — `Stack.size >= 0` in the base must hold in every subclass.
- **Preserve history constraint** — observable state changes obey the base type's allowed sequences.

### Canonical anti-pattern: throws on inherited method

`Penguin extends Bird`, then `Penguin.fly()` throws. Any code that calls `bird.fly()` and accepts a `Bird` parameter will crash for `Penguin`. The hierarchy is wrong: `Bird.fly()` shouldn't be in `Bird`'s contract if not all birds fly.

### Fix: split the abstraction

`Bird` (no `fly()`), `FlyingBird : Bird` (has `fly()`), `Penguin : Bird`, `Sparrow : FlyingBird`. Now `makeBirdFly` takes `FlyingBird`, and the compiler enforces the rule.

### Why this matters

LSP is what makes inheritance safe. Without it, every override is a potential trap; clients have to know the concrete type to call methods correctly; polymorphism collapses. LSP is also the easiest principle to violate accidentally — most violations are added one override at a time, each "harmless" in isolation.

---

## I — Interface Segregation Principle

> **Clients should not be forced to depend on methods they do not use.**

A fat interface forces every implementer to provide methods that don't apply, usually by stubbing or throwing. Worse, every consumer of the interface drags in irrelevant capabilities, expanding the surface area for change.

### The smell

An interface with ten methods, where each implementer uses three. The implementer that "doesn't support" the others throws `UnsupportedOperationException` on call. Clients that need only `findById` end up depending on `bulkInsert`, `pageBy`, `stream` — none of which they call.

### The fix: small, role-shaped interfaces

Split the fat interface into per-client-need interfaces. A class implements only the roles it genuinely fulfils. Clients depend on the smallest interface that meets their need.

`UserReader` (read-only), `UserWriter` (mutations), `UserBulkOps` (batch). `InMemoryUserRepository : UserReader, UserWriter`. `JpaUserRepository : UserReader, UserWriter, UserBulkOps`. Each can be tested independently; each grows independently.

### The heuristic

For every method on an interface, ask: *"Does every implementer use this?"* If not — ISP violation. Either split the interface, or move the method off the interface entirely.

### Why this matters

ISP is what keeps test doubles cheap and substitution real. Without it, swapping an implementation drags in a tax of irrelevant methods to stub; unit tests grow setup; the abstraction stops abstracting.

---

## D — Dependency Inversion Principle

> **High-level modules should not depend on low-level modules. Both should depend on abstractions.**
> **Abstractions should not depend on details. Details should depend on abstractions.**

Two related rules. Together they invert the naive dependency arrow:

- *Naïve:* `OrderService` (high-level policy) → `JpaOrderRepository` (low-level Hibernate detail) → JDBC → driver.
- *Inverted:* `OrderService` → `OrderRepository` (interface). `JpaOrderRepository` *also* → `OrderRepository`. Both depend on the abstraction; neither depends on the other.

### The architectural reading

DIP is what makes Onion / Clean / Hexagonal architecture work. The domain defines interfaces (high-level abstractions). Infrastructure provides implementations (low-level details). The arrow points **inward**: infrastructure depends on domain, never the reverse.

If a class in `domain/` imports `org.springframework.*`, `org.hibernate.*`, or `software.amazon.awssdk.*` — DIP violation at architectural scale.

### Why testability is a side effect, not the goal

People justify DIP with testability ("I need to mock the DB"). That works but undersells it. The real point is **stability of dependencies**:

> Code that is more stable should be depended upon by code that is less stable, never the reverse.

Frameworks change. Databases change. Cloud providers change. Vendor SDKs deprecate. The domain — the policy of your business — changes far less often. DIP routes the dependency arrows so the volatile depends on the stable, never the other way around.

### Canonical anti-pattern: high-level service depends on infra

`OrderService` directly instantiates `SmtpEmailClient` and `JpaOrderRepository`. Can't test without SMTP and Postgres. Can't swap providers. Can't reason about the domain without dragging in framework concerns.

### Fix: introduce abstractions in the domain

Define `OrderRepository` and `NotificationService` interfaces in the domain package. `OrderService` depends on the interfaces. The implementations live in `infrastructure/` and depend on the same interfaces. The DI container wires them at runtime.

### Why this matters

DIP is the principle that lets a domain outlive its frameworks. Hibernate goes, Postgres goes, Stripe goes, the framework upgrades break. The domain — properly inverted — survives all of them.

---

## How the principles interact

A real violation usually triggers multiple principles. SRP and DIP overlap (a god service usually depends on too many concretes). OCP and LSP overlap (a sealed hierarchy without LSP discipline is brittle). ISP and SRP overlap (a fat interface implies a fat implementer).

| Symptom | Principles violated |
|---|---|
| God service | SRP (multiple responsibilities), ISP (clients use few methods each), DIP (depends on too much) |
| `when` chain on type | OCP (closed for extension), often DIP (caller knows concrete types) |
| Subclass throws on inherited method | LSP (not substitutable), often SRP (base class responsibility unclear) |
| Tests can't run without Postgres | DIP (no abstraction), often SRP (domain mixed with infra) |
| Big inheritance hierarchy with many overrides | LSP (overrides change contract), ISP (fat base class) |

**Fix one, the others often fall into place.**

---

## Refactor order

When multiple violations are present, fix them in this order:

1. **SRP first** — split god classes. The other violations often disappear with the split.
2. **DIP second** — introduce abstractions where infra leaks into domain.
3. **ISP third** — when interfaces feel fat at the point of use.
4. **OCP fourth** — only when you have the second concrete case (don't speculate).
5. **LSP always** — verify each `override` against the contract rules.

---

## What SOLID is *not*

- Not a checklist to apply mechanically. Mechanical application produced the over-engineered Java enterprise patterns of the 2000s.
- Not a substitute for domain knowledge. SOLID tells you the shape; the domain tells you the responsibilities.
- Not architecture. SOLID is class-scale; architecture is module-and-context scale.
- Not patterns. SOLID is principles; GoF is patterns. A pattern is a recurring solution; a principle is a quality you check.
