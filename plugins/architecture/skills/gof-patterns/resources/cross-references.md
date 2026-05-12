# GoF — Cross-References

How GoF patterns map onto SOLID principles, GRASP responsibility patterns, DDD tactical patterns, and architectural concerns. The vocabularies overlap deliberately — they're different lenses on the same recurring shapes.

---

## GoF ↔ SOLID

GoF patterns often emerge from SOLID-driven refactors. SOLID drives the change; GoF gives a name to the result.

| GoF pattern | SOLID principle that motivates it |
|---|---|
| **Strategy** | OCP (closed for modification — new strategy = new class), DIP (depend on the strategy abstraction) |
| **State** | OCP (transitions are encapsulated in the State variants), LSP (subtypes substitute) |
| **Template Method** | OCP (skeleton is closed; hook methods are the extension points), LSP (subclasses must honour the protocol) |
| **Decorator** | OCP (extend behaviour without modifying the inner), DIP (decorator depends on the interface, not the concrete) |
| **Adapter** | DIP (depend on the target interface, not the adaptee), ISP (the target interface is what the client needs) |
| **Bridge** | DIP (abstraction depends on Implementor interface, not concrete) |
| **Facade** | ISP (clients see one method, not the subsystem's full surface) |
| **Composite** | LSP (Leaf and Composite both substitute Component) |
| **Proxy** | OCP (add behaviour transparently), DIP (proxy and target share the interface) |
| **Observer** | OCP (publisher closed; new subscribers added without edits), DIP (publisher depends on Observer interface) |
| **Command** | OCP (new command types added without changing the dispatcher), SRP (one class per request type) |
| **Iterator** | ISP (clients see only `hasNext` / `next`), DIP (depend on Iterator, not concrete collection) |
| **Chain of Responsibility** | OCP (add a new handler to the chain), SRP (each handler does one thing) |
| **Mediator** | DIP (collaborators depend on Mediator interface, not each other) |
| **Memento** | SRP (Memento's only job is state capture), encapsulation (originator's internals stay hidden) |
| **Visitor** | OCP (new operations as new Visitors) — but in Kotlin, sealed + `when` covers OCP without Visitor's machinery |
| **Singleton** | (No specific SOLID tie; mostly a convenience pattern with DI being the modern version) |
| **Factory Method / Abstract Factory** | DIP (clients depend on the interface, factory hides concrete) |
| **Builder** | SRP (separates construction from representation) |
| **Prototype** | (Mostly a language feature now; weak SOLID tie) |
| **Flyweight** | (Memory optimisation; weak SOLID tie) |

### The big three in Kotlin's polymorphism story

Strategy, State, and Visitor all express variation by type — and all collapse to the same Kotlin idiom: sealed hierarchies + behaviour on the variant. The OCP / Polymorphism connection is one of the most useful things to internalise:

```
GRASP: Polymorphism
SOLID: Open/Closed Principle
GoF:   Strategy (per-call) / State (per-instance) / Visitor (replaced)
Kotlin: sealed interface + per-variant behaviour
```

A code reviewer can name this from any of four vocabularies; they're saying the same thing.

See `solid-principles/resources/theory.md` for the SOLID treatment.

---

## GoF ↔ GRASP

GRASP picks the *owner* of a responsibility; GoF often names the resulting collaboration shape.

| GRASP pattern | GoF pattern that often emerges |
|---|---|
| **Information Expert** | (Often no GoF name — just "method on the entity") |
| **Creator** | **Factory Method** (`Order.create(...)`), **Abstract Factory** (`PaymentProcessorFactory`) |
| **Controller** | **Mediator** (Application Service / Use-Case Handler) |
| **Low Coupling** | **Observer** (event-based reactions), **Mediator** (collaborators don't know each other) |
| **High Cohesion** | (Meta — no specific GoF) |
| **Polymorphism** | **Strategy** (per-call variation), **State** (per-instance variation), sealed `when` (replaces Visitor) |
| **Pure Fabrication** | **Facade** (most service classes), **Mediator** (orchestrators) |
| **Indirection** | **Adapter** (vendor seam), **Proxy** (transparent wrap), **Facade** (subsystem hide), **Bridge** (decoupled axes) |
| **Protected Variations** | **Adapter** (ACL), **Bridge**, **Facade** at the seam |

See `grasp-patterns/resources/theory.md` for the GRASP treatment.

---

## GoF ↔ DDD tactical patterns

DDD adds bounded-context discipline and domain-specific names. Many GoF patterns map onto DDD constructs:

| GoF pattern | DDD analogue |
|---|---|
| **Factory Method** | Aggregate factory (`Order.create(...)`) |
| **Abstract Factory** | Factory family for producing related domain objects (e.g., per-tenant aggregate variants) |
| **Adapter** | Anti-Corruption Layer (between contexts or vs. external) |
| **Facade** | Application Service (use-case orchestrator at the application layer) |
| **Mediator** | Application Service / Domain Service (orchestrating across aggregates / domain types) |
| **Observer** | Domain Events (aggregate publishes events; other aggregates / contexts subscribe) |
| **Command** | Application Service command (CQRS write side) |
| **State** | Aggregate state machine (often modelled as `OrderStatus` sealed type with transition methods) |
| **Strategy** | Domain Policy (e.g., `PricingPolicy`, `DiscountPolicy`) — strategy injected into the aggregate or service |
| **Specification** (Fowler/Evans, not classical GoF) | Domain Specification — predicate over an aggregate state |
| **Repository** (Fowler/Evans, not classical GoF) | Repository — the canonical Indirection at the aggregate boundary |

See `ddd-tactical-patterns` for aggregate / value object / repository discipline; `ddd-context-mapping` for cross-context patterns including ACL.

---

## GoF ↔ Architecture (Onion / Clean / Hexagonal / Modulith)

Several GoF patterns operate at architectural scale:

```
                       ┌──────────────────┐
                       │   infrastructure │   ← Adapter (vendor SDK), Proxy (Spring AOP)
                       └────────┬─────────┘
                                │ implements (DIP via interface)
                                ▼
                       ┌──────────────────┐
                       │   application    │   ← Mediator (Use-Case Handlers), Facade (services)
                       │                  │   ← Command (sealed types crossing the layer)
                       └────────┬─────────┘
                                │ depends on
                                ▼
                       ┌──────────────────┐
                       │      domain      │   ← Strategy (domain policies), State (aggregate FSM)
                       │                  │   ← Composite (aggregate part-whole)
                       └──────────────────┘

Cross-cutting:
  - Observer / domain events — between aggregates, between contexts (Spring Modulith)
  - Adapter — at the bounded-context boundary (ACL)
  - Bridge — when domain abstraction varies independently of infrastructure impl
```

See `architecture-patterns` for module-layout discipline; `architect-review` for architecture-scale violation diagnosis.

---

## GoF ↔ Other clean-code skills

The `clean-code-*` family often lands on a GoF pattern as the recommended fix.

| GoF pattern | clean-code-* sibling |
|---|---|
| **Adapter** at the vendor seam | `clean-code-boundaries` (Wrap-Don't-Pass, ACL) |
| **Decorator** via `by` delegation | `clean-code-classes` (composition over inheritance) |
| **Facade** as service class | `clean-code-classes` (Many-Small-Classes), `clean-code-systems` (composition root) |
| **Strategy** via function type | `clean-code-functions` (replace switch/when with polymorphism) |
| **State** via sealed types | `clean-code-objects-and-data` (Tell-Don't-Ask via state methods) |
| **Command** as sealed type | `clean-code-error-handling` (sealed `Result<T>` / `Outcome` types) |
| **Builder** for construction validation | `clean-code-error-handling` (Bean Validation at the boundary) |
| **Proxy** for cross-cutting | `clean-code-systems` (cross-cutting concerns wired declaratively) |

---

## Quick lookup

If you're staring at a problem and unsure which vocabulary to reach for:

| Question | Skill |
|---|---|
| "Is there a name for the shape this collaboration takes?" | `gof-patterns` (this skill) |
| "Is this class well-shaped (SRP / OCP / LSP / ISP / DIP)?" | `solid-principles` |
| "Which class should own this responsibility?" | `grasp-patterns` |
| "How does this fit into the bounded context?" | `ddd-tactical-patterns` |
| "Where are the cross-context translation seams?" | `ddd-context-mapping` |
| "What's the right module layout?" | `architecture-patterns` |
| "Is the architectural-scale dependency direction correct?" | `architect-review` |

The vocabularies overlap deliberately. A real design conversation usually crosses several.

---

## A worked example crossing four vocabularies

**Problem:** An `OrderService` directly calls `StripeClient` to charge cards, manually wraps a transaction with `try/catch` + commit/rollback, and notifies the customer via direct `EmailService.send()` calls. Adding Adyen as a second payment provider would require editing `OrderService`.

**Diagnosis (multi-vocabulary):**

| Lens | Diagnosis |
|---|---|
| **GoF** | Missing **Adapter** (around Stripe), missing **Proxy** (Spring `@Transactional` would handle it), missing **Strategy** (for payment method dispatch), missing **Observer** (for the email side effect) |
| **SOLID** | DIP (concrete `StripeClient` injected), OCP (`when (paymentMethod)` requires editing for Adyen), SRP (`OrderService` does payment + transaction + notification + business logic) |
| **GRASP** | PV-1 (vendor SDK in business code), Ind-1 (concrete dep), LC-1 (direct downstream call), HC (god service) |
| **DDD** | Anaemic application service mixing cross-aggregate side effects; missing ACL for Stripe; missing domain events for the cross-context notification |

**Refactor (using all four):**

1. **GoF Adapter + GRASP Indirection + DDD ACL**: define `PaymentGateway` interface; `StripePaymentGateway : PaymentGateway` in `infrastructure/`. `OrderService` depends on `PaymentGateway`, not `StripeClient`.
2. **GoF Strategy + GRASP Polymorphism + SOLID OCP**: sealed `PaymentMethod` with per-variant `process()` (or `Map<PaymentMethod, PaymentGateway>` injection). Adding Adyen is a new bean.
3. **GoF Proxy + Spring AOP**: replace manual `try/catch + commit/rollback` with `@Transactional`. The Spring proxy handles it.
4. **GoF Observer + GRASP Low Coupling + DDD domain event**: `OrderPlaced` event; `OrderEmailNotifier @ApplicationModuleListener` reacts. `OrderService` no longer calls `EmailService`.

Five named patterns from four vocabularies. Each vocabulary is a way to discuss the same change; together they make the conversation precise.

---

## Pattern names you'll see that aren't in the GoF book

The GoF book is from 1994. Several patterns since became canonical without being in it. Some you'll encounter:

| Pattern | Source | Mechanism |
|---|---|---|
| **Repository** | Fowler / Evans | Indirection at the aggregate-root boundary; collection-like interface for persistence |
| **Specification** | Evans | Predicate over an aggregate state, composable via and/or/not |
| **Anti-Corruption Layer** (ACL) | Evans | Adapter + Facade at a bounded-context boundary |
| **Domain Event** | Evans / Fowler | Observer at the domain layer, with bounded-context propagation discipline |
| **Aggregate Root** | Evans | Information Expert + Creator + Encapsulation, with consistency-boundary discipline |
| **Outbox** | Microservices community | Reliable Observer-via-storage for cross-process events |
| **Saga** | Garcia-Molina (1987), repopularised | Long-running command/compensation chain across services |
| **Circuit Breaker** | Nygard | State pattern for failing-fast under upstream failure |
| **Strangler Fig** | Fowler | Gradual migration of a monolith via Adapter-then-replace |
| **Onion / Hexagonal / Clean Architecture** | Cockburn / Palermo / Martin | DIP at architectural scale |

These extend GoF's vocabulary with names from the patterns community of 1995–2015. They're as widely understood as the original 23.
