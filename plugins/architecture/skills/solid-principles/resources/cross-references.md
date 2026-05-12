# SOLID — Cross-References

How SOLID principles map onto the other foundational vocabularies of OO design: GRASP (responsibility assignment), GoF (pattern catalogue), DDD (domain modelling), and architectural layout. Use this file when a SOLID violation is the *symptom* and the right discussion is in another vocabulary.

---

## SOLID ↔ GRASP

GRASP answers *who should own this responsibility*; SOLID validates *whether the resulting class is well-shaped*. They're complementary — GRASP picks the owner, SOLID checks the result.

| SOLID principle | GRASP analogue | Same idea, different question |
|---|---|---|
| **SRP** | High Cohesion + Pure Fabrication | "all methods serve one purpose" + "give responsibility to a focused fabrication when no domain class fits" |
| **OCP** | Polymorphism | "handle differs-by-type variation by pushing behaviour onto the type" |
| **LSP** | (no direct equivalent) | LSP is a contract rule; GRASP is silent on substitution semantics |
| **ISP** | Low Coupling | "minimise the dependency surface" |
| **DIP** | Indirection + Protected Variations | "put a middleman between A and B" + "shield clients from likely change" |

### Common refactor: god service → split + Info Expert

A god `OrderService` violates SRP. Splitting may reveal that several extracted operations belong on `Order` itself (because `Order` has the data) — that's GRASP's Information Expert. SOLID told you to split; GRASP told you where to put each piece.

See `grasp-patterns/resources/theory.md` for the full GRASP catalogue.

---

## SOLID ↔ GoF

GoF is the pattern catalogue; SOLID-driven refactors often land on a named pattern. Naming the pattern is communication — it doesn't change the design, but it makes the design discussable.

| SOLID-driven refactor | GoF pattern that emerges |
|---|---|
| OCP via "push variation onto the type" | **Strategy** (per-call variation), **State** (per-instance variation), **Template Method** (skeleton with hooks) |
| OCP via "extend without modification" | **Decorator** (`by` delegation in Kotlin), **Chain of Responsibility** |
| DIP via "depend on an abstraction" | **Adapter** (wrapping a vendor SDK), **Bridge** (decoupling abstraction from implementation), **Facade** (simplified front to a subsystem) |
| ISP via "split into role interfaces" | **Adapter** roles, **Interface composition** |
| SRP via "extract focused class" | **Strategy / Command / Observer** for behaviour-only extractions; **Pure Fabrication** (GRASP) when no GoF name fits |
| LSP via "split the hierarchy" | **Composite** (when subtypes differ structurally), **Visitor** alternative via sealed hierarchy |

See `gof-patterns/resources/theory.md` for the full pattern catalogue and Kotlin status.

---

## SOLID ↔ DDD tactical patterns

DDD provides domain-specific names for the same physics:

| SOLID principle | DDD tactical analogue |
|---|---|
| **SRP** | Aggregate boundary (one consistency boundary per root); domain service has one focused responsibility |
| **OCP** | Domain events as extension points (new listeners react without editing publishers) |
| **LSP** | Value objects with `equals` based on value (substitutable by definition); aggregate roots' invariants are LSP-style postconditions |
| **ISP** | Repository per aggregate root (not per entity); separate query repositories from write repositories (CQRS-light) |
| **DIP** | Domain defines repository interfaces; infrastructure provides JPA/etc impls. Anti-Corruption Layer between contexts is DIP at context scale |

See `ddd-tactical-patterns` for aggregate / value object / repository discipline.

---

## SOLID ↔ Architecture (Onion / Clean / Hexagonal)

DIP is the principle that *makes* these architectures work. The other principles operate within the layers.

```
                       ┌──────────────────┐
                       │   infrastructure │   (volatile: Spring, Hibernate, AWS, Stripe)
                       └────────┬─────────┘
                                │ implements
                                ▼
                       ┌──────────────────┐
                       │   application    │   (use-case orchestration)
                       └────────┬─────────┘
                                │ depends on
                                ▼
                       ┌──────────────────┐
                       │      domain      │   (stable: aggregates, value objects, ports)
                       └──────────────────┘

DIP arrow: outer layers depend on inner. Domain knows nothing of infrastructure.
SRP: each layer has one responsibility (rules / orchestration / adaptation).
ISP: domain ports are small role interfaces; infrastructure adapters implement only what they fulfil.
OCP: new adapters add to infrastructure without editing the domain.
LSP: every adapter substitutes the domain port without surprise.
```

If a class in `domain/` imports `org.springframework.*` — DIP violation at the architectural scale. The same SOLID rules apply at module / context / system scale; the granularity changes, the principles don't.

See `architecture-patterns` for module-layout discipline; `architecture` for choosing the right level of architectural rigor.

---

## SOLID ↔ Other clean-code skills

The `clean-code-*` family provides Kotlin-flavoured discipline at finer scales. SOLID is the principle layer; these are the practice layers.

| SOLID principle | clean-code-* sibling |
|---|---|
| **SRP** at function scope | `clean-code-functions` ("do one thing", ≤ 20 lines) |
| **SRP** at class scope | `clean-code-classes` (encapsulation, weasel-suffix ban, 25-word description test) |
| **DIP** at composition root | `clean-code-systems` (constructor injection, no service-locator, POJOs in domain) |
| **DIP** at vendor-SDK seam | `clean-code-boundaries` (Wrap-Don't-Pass, ACL, Learning Tests) |
| **SRP** + **OCP** in error handling | `clean-code-error-handling` (`@RestControllerAdvice` extension, exception classes by caller need) |
| Object-vs-data distinction (orthogonal to SOLID but reinforces SRP) | `clean-code-objects-and-data` (Tell-Don't-Ask, anaemic domain anti-pattern, DTO discipline) |
| Naming reflects single responsibility | `clean-code-naming` (single-word domain terms, no Manager/Helper/Util) |

---

## Quick lookup

If you're staring at a design problem and unsure which vocabulary to reach for:

| Question | Skill |
|---|---|
| "Is this class well-shaped?" | `solid-principles` (this skill) |
| "Which class should own this responsibility?" | `grasp-patterns` |
| "Is there a name for the shape this collaboration takes?" | `gof-patterns` |
| "How does this fit into the bounded context?" | `ddd-tactical-patterns` |
| "What's the right module layout?" | `architecture-patterns` |
| "Is the architectural-scale dependency direction correct?" | `architect-review` |

The vocabularies overlap deliberately — they're different lenses on the same physics. A real design conversation usually crosses several.
