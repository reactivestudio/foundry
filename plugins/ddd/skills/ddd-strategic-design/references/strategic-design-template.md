# Strategic Design Template

## Subdomain classification

| Capability | Subdomain type | Why | Owner team |
| --- | --- | --- | --- |
| Pricing | Core | Differentiates business value | Commerce |
| Identity | Supporting | Needed but not differentiating | Platform |

### Subdomain types

| Type | Definition | Investment level |
|---|---|---|
| **Core** | Where the business competes; the "secret sauce" | Highest — best people, custom code |
| **Supporting** | Necessary for the core to work; not a differentiator | Medium — custom only where needed |
| **Generic** | Solved problems (auth, payments, billing rails) | Lowest — buy / off-the-shelf wins |

Rule of thumb: a subdomain is Core if losing it means losing the business. Supporting if losing it means losing efficiency. Generic if any vendor can replace you.

## Bounded context catalog

| Context | Responsibility | Upstream dependencies | Downstream consumers |
| --- | --- | --- | --- |
| Catalog | Product data lifecycle | Supplier feed | Checkout, Search |
| Checkout | Order placement and payment authorization | Catalog, Pricing | Fulfillment, Billing |

Each context entry should answer:
- What is this context **responsible for**?
- What language does it speak? (its ubiquitous language)
- What does it **own** (data, decisions, business rules)?
- What does it **depend on** (other contexts, external systems)?
- Who **consumes** its output?
- Which team owns it?

## Ubiquitous language

| Term | Definition | Context |
| --- | --- | --- |
| Order | Confirmed purchase request | Checkout |
| Reservation | Temporary inventory hold | Fulfillment |

### Conflicts and anti-terms

Document terms that mean **different things in different contexts**:

| Term | Context | Meaning |
|---|---|---|
| Customer | Checkout | A registered shopper with a payment method |
| Customer | Support | Any person who has contacted us, may or may not have shopped |
| Customer | Billing | An account being charged (may differ from the shopper) |

When the same word means different things, the contexts are differentiating themselves — that's healthy. Don't try to unify "Customer" across contexts; each context owns its own definition.

## Boundary decisions — capture in an ADR

For each non-obvious boundary, capture:

1. **Decision**: where the boundary is drawn (e.g. "Pricing and Catalog are separate contexts").
2. **Alternatives considered**: at least one (e.g. "Pricing could be part of Catalog").
3. **Drivers**: what pushed the decision (consistency boundary, team ownership, change rate).
4. **Trade-offs**: what we give up (e.g. "Catalog can't directly know prices without going through Pricing").
5. **Revisit trigger**: when to reconsider (e.g. "When pricing logic becomes < 10% of Catalog code").

Use the `architecture-decision-records` skill for the ADR template.

## Common mistakes

- **Mistaking technical seams for domain boundaries.** "We need a microservice for X" is not a domain boundary; it's an infrastructure choice.
- **Letting the org chart drive context boundaries (Conway).** Sometimes correct, often a smell. Boundaries should follow the **domain**; if the org doesn't fit, the org needs to change, not the boundaries.
- **One big "core domain".** If your "core" is half the system, you haven't classified hard enough. Pick the 1-3 capabilities that are real differentiators.
- **Premature splitting.** A bounded context that has 200 lines of code and no team is not a context; it's a package. Splits should follow real divergence.
- **No glossary.** Without ubiquitous language, two teams have the same word meaning different things and don't know it.
