# GRASP — Cross-References

How GRASP patterns map onto SOLID principles, GoF patterns, DDD tactical patterns, and architectural layout. Use this file when a GRASP question can be answered (or sharpened) by switching vocabulary.

---

## GRASP ↔ SOLID

GRASP picks the *owner* of a responsibility; SOLID validates the *shape* of the resulting class. They're complementary lenses on the same designs.

| GRASP pattern | SOLID principle that reinforces it |
|---|---|
| **Information Expert** | SRP (one reason to change → cohesion at the entity), DIP (entity stays domain-pure) |
| **Creator** | SRP (factory has one purpose: create A), no direct Liskov tie |
| **Controller** | SRP (one use case per handler), OCP (new use case = new handler, no edits) |
| **Low Coupling** | DIP (depend on abstractions, not concretes — minimises coupling), ISP (depend on smallest interface) |
| **High Cohesion** | SRP (cohesion follows from one reason to change) |
| **Polymorphism** | OCP (closed for modification — new variant = new class), LSP (subtypes substitute for the base) |
| **Pure Fabrication** | SRP (one focused responsibility per fabrication) |
| **Indirection** | DIP (the interface is the dependency-inversion seam), ISP (the indirection should be a small role interface) |
| **Protected Variations** | OCP (extension points absorb change), DIP (depend on the stable abstraction, not the volatile concrete) |

### Common refactor: god service → split + Info Expert

A god `OrderService` violates SRP (SOLID). Splitting may reveal that several extracted operations belong on `Order` itself (Info Expert). SOLID told you to split; GRASP told you where to put each piece.

See `solid-principles/resources/theory.md` for the full SOLID treatment.

---

## GRASP ↔ GoF

GRASP-driven refactors often land on a named GoF pattern. The pattern name is communication shorthand — it doesn't change the design, but it makes the design discussable.

| GRASP pattern | GoF pattern that often emerges |
|---|---|
| **Polymorphism** | **Strategy** (per-call variation), **State** (per-instance variation), **Template Method** (skeleton + hooks), **Visitor** (replaced by sealed + `when` in Kotlin) |
| **Indirection** (vendor seam) | **Adapter** (wrapping a vendor SDK), **Bridge** (decoupling abstraction from impl), **Facade** (simplified front to a subsystem) |
| **Indirection** (cross-cutting) | **Proxy** (Spring's `@Transactional` / `@Cacheable` / `@Async`), **Decorator** (`by` delegation in Kotlin) |
| **Indirection** (control-flow) | **Mediator** (orchestrator service), **Observer** (event publishing) |
| **Creator** | **Factory Method** (`Order.create(...)`), **Abstract Factory** (`PaymentProcessorFactory`) |
| **Pure Fabrication** | (Often unnamed — many "services" are Pure Fabrications without a named GoF pattern.) |
| **Protected Variations** | **Adapter** (ACL), **Bridge**, **Facade** at the seam |

See `gof-patterns/resources/theory.md` for the full pattern catalogue and Kotlin status.

### Important pivot

The same idea sits in three vocabularies at once:

```
GRASP: Polymorphism
SOLID: Open/Closed Principle
GoF:   Strategy (per-call) / State (per-instance)
Kotlin: sealed interface + per-variant override
```

A team conversation can pick whichever vocabulary fits — they're saying the same thing.

---

## GRASP ↔ DDD tactical patterns

DDD provides domain-specific names for the same physics. Use DDD vocabulary when the frame is a bounded context with explicit invariants.

| GRASP pattern | DDD tactical analogue |
|---|---|
| **Information Expert** | Aggregate methods — the aggregate root owns its data |
| **Creator** | Aggregate factory (`Order.create(...)`) |
| **Controller** | Application service / Use-Case Handler |
| **Low Coupling** | Bounded context boundaries + domain events |
| **High Cohesion** | Aggregate boundary (consistency boundary) |
| **Polymorphism** | Strategy via sealed interface; State machine over aggregate status |
| **Pure Fabrication** | Domain Service (lives in domain layer, no infra deps); Application Service (lives in application layer, orchestrates infra) |
| **Indirection** | Repository interface (domain) + JPA adapter (infra) |
| **Protected Variations** | Anti-Corruption Layer (between contexts or vs vendor) |

GRASP is the universal physics; DDD is the project-local vocabulary. They overlap deliberately.

See `ddd-tactical-patterns` for aggregate / value object / repository discipline; `ddd-context-mapping` for cross-context patterns including ACL.

---

## GRASP ↔ Architecture (Onion / Clean / Hexagonal / Modulith)

GRASP operates within and across architectural layers. Indirection and Protected Variations especially scale up to architectural seams.

```
                       ┌──────────────────┐
                       │   infrastructure │   (volatile: Spring, Hibernate, AWS, Stripe)
                       └────────┬─────────┘
                                │ implements
                                ▼
                       ┌──────────────────┐
                       │   application    │   (Use-Case Handlers — Controller GRASP)
                       └────────┬─────────┘
                                │ depends on
                                ▼
                       ┌──────────────────┐
                       │      domain      │   (Aggregates — Info Expert, Creator)
                       │                  │   (Domain ports — Indirection, PV)
                       └──────────────────┘

GRASP at architectural scale:
  - Indirection between layers (port + adapter)
  - Protected Variations at the infrastructure seam (vendor SDKs wrapped)
  - Low Coupling across modules (events, not direct calls)
  - High Cohesion within modules (each module = one bounded context)
```

The same GRASP rules apply at the module / context / service scale; the granularity changes, the patterns don't.

See `architecture-patterns` for module-layout discipline; `architect-review` for architecture-scale violation diagnosis.

---

## GRASP ↔ Other clean-code skills

The `clean-code-*` family provides Kotlin-flavoured discipline at finer scales. GRASP names *which class* should hold a responsibility; clean-code-* shapes *how the class itself* is written.

| GRASP pattern | clean-code-* sibling |
|---|---|
| **Information Expert** | `clean-code-objects-and-data` (Tell-Don't-Ask, anaemic-domain anti-pattern) |
| **High Cohesion** | `clean-code-classes` (25-word description test, weasel-suffix ban) + `clean-code-naming` (no Manager/Helper/Util) |
| **Pure Fabrication** | `clean-code-classes` (Many-Small-Classes rule), `clean-code-functions` (function-level SRP) |
| **Indirection** at the vendor seam | `clean-code-boundaries` (Wrap-Don't-Pass, Anti-Corruption Layer) |
| **Protected Variations** at the boundary | `clean-code-boundaries` (Wrap-Don't-Pass, Learning Tests) |
| **Polymorphism** in code shape | `clean-code-functions` (replace switch/when with polymorphism) |
| **Controller** as a thin orchestrator | `clean-code-systems` (composition root, transactional boundaries) |

---

## Quick lookup

If you're staring at a design problem and unsure which vocabulary to reach for:

| Question | Skill |
|---|---|
| "Which class should own this responsibility?" | `grasp-patterns` (this skill) |
| "Is the class that ended up owning this well-shaped?" | `solid-principles` |
| "Is there a name for the shape this collaboration takes?" | `gof-patterns` |
| "How does this fit into the bounded context?" | `ddd-tactical-patterns` |
| "Where are the cross-context translation seams?" | `ddd-context-mapping` |
| "What's the right module layout?" | `architecture-patterns` |
| "Is the architectural-scale dependency direction correct?" | `architect-review` |

The vocabularies overlap deliberately — they're different lenses on the same physics. A real design conversation usually crosses several.

---

## A worked example crossing four vocabularies

**Problem:** `OrderService` reaches into `Order.items` to compute a total, calls Stripe directly to charge, and emails the customer. Six dependencies in the constructor.

**Diagnosis (multi-vocabulary):**

| Lens | Diagnosis |
|---|---|
| **GRASP** | IE-1 (anaemic domain — service computes over entity fields), HC-1 (god service), PV-1 (vendor SDK in business code), LC-1 (direct downstream call instead of event) |
| **SOLID** | SRP (multiple responsibilities), DIP (concrete `StripeClient` injected), ISP (god repository), OCP (new payment provider = edit `OrderService`) |
| **GoF** | Missing Adapter (around Stripe), missing Strategy (for payment methods), missing Observer (for email side effect) |
| **DDD** | Anaemic aggregate; missing repository abstraction at domain boundary; missing ACL for Stripe; cross-aggregate side effects via direct call instead of domain events |

**Refactor (using all four):**

1. **GRASP Info Expert + DDD aggregate root**: push `total()` onto `Order`. Now `Order` is behaviour-rich.
2. **GRASP Pure Fabrication + GRASP Controller**: extract `PlaceOrderHandler` (use-case handler).
3. **GRASP Indirection + GRASP PV + GoF Adapter + DDD ACL**: define `PaymentGateway` port; `StripePaymentGateway : PaymentGateway` in `infrastructure/`.
4. **GRASP Polymorphism + SOLID OCP + GoF Strategy**: sealed `PaymentMethod` with per-variant `process()`; `PaymentProcessor` orchestrates.
5. **GRASP Low Coupling + DDD domain event + GoF Observer**: `OrderPlaced` event; `OrderEmailNotifier @ApplicationModuleListener` reacts.

The refactor lands on five named patterns from four vocabularies. Each vocabulary is a way to discuss the same change; together they make the conversation precise.
