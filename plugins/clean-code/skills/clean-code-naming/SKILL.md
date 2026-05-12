---
name: clean-code-naming
description: "Naming discipline for Kotlin/Spring code — opinionated rules for class, method, and variable names with bias toward single-word domain terms (Order, Reservation, Payment), zero tolerance for abstract / stack-noise suffixes (Item, Data, Manager, Helper, Util, Dto, Entity, Impl), and alignment with DDD ubiquitous language. Adapted from R. Martin's Clean Code Ch. 2 'Meaningful Names' (filtered through what Kotlin already solves), with house-rule extensions. Use when naming a new aggregate / entity / value object / class / method / variable, reviewing names in a PR, refactoring legacy Java-style names, auditing a module for naming consistency, or pre-merge checking that names read like the domain rather than like the framework."
risk: safe
source: "Adapted from R. Martin, Clean Code (2008), ch. 2 'Meaningful Names' and ch. 17 §N1-N7, filtered for Kotlin/Spring + house rules"
date_added: "2026-05-12"
---

# Clean Code: Naming Discipline

> "If a name requires a comment, the name does not reveal its intent." — R. Martin
>
> "If you typed `*Manager` at the end of a class name, you didn't finish thinking about what the class does." — house rule.

Names are 90% of what makes code readable. Most files are read fifty times for every time they're written; the per-name minute you spend now is paid back fifty-fold. This skill is the opinionated catalog: classical rules adapted for Kotlin/Spring, plus house extensions where Kotlin already changed the game (properties replacing JavaBean getters, sealed/value classes replacing encodings).

## Use this skill when
- Naming a new aggregate / entity / value object / class / method / variable.
- Reviewing names in a PR (this skill is the criterion).
- Refactoring Java-style names into idiomatic Kotlin.
- Auditing a module for naming consistency before merging.
- Picking a domain term in a workshop with experts — name the concept the way the business does.
- A name needs a comment to explain itself — that's the prompt to use this skill, not the comment.

## Do not use this skill when
- The name is enforced by an external API (overriding a framework method, JPA column matching a legacy DB).
- Renaming a 3-line-scope local variable — a reasonable choice, move on; this skill is overkill for that.
- The task is not naming at all (architecture, persistence, test strategy) — use the relevant sibling skill.

## Core principles (the ten)

1. **Domain-first.** The name comes from the experts' vocabulary, not from the stack. If the business says "Order", the class is `Order` — not `OrderEntity`, not `OrderModel`, not `OrderDto`.
2. **One word when the domain permits.** Aggregates, value objects, domain events default to a single domain noun: `Order`, `Reservation`, `Payment`, `Money`, `Email`. Multi-word names should *earn* the second word.
3. **Two words earn it through disambiguation.** `PurchaseOrder` vs `SalesOrder` if both live in the domain. `ShippingAddress` vs `BillingAddress` if they differ. `OrderEntity` — no: "Entity" doesn't disambiguate, it's stack noise.
4. **Three+ words are almost always a smell.** `OrderLineItemDetailRow` is an incantation, not a name. Distil to `OrderLine`.
5. **Abstract nouns are placeholders, not names.** `Item`, `Data`, `Info`, `Object`, `Thing`, `Element`, `Detail` all say "I didn't think hard enough about what this actually is."
6. **Verb-shaped suffixes hide the real name.** `*Manager`, `*Helper`, `*Handler`, `*Processor`, `*Util` conceal a verb. Pull it out: `OrderSubmitter`, `PaymentReconciler`, `SessionAuthenticator`.
7. **Names describe everything the code does, including side-effects.** A method called `getOos()` that *creates* the stream when missing is a lie. Name it `getOrCreateOos()`, or rebuild the API so creation is explicit.
8. **Level of abstraction matches the context.** A `Modem.dial(phoneNumber)` is the wrong abstraction the moment cable modems exist; `connect(locator)` fits both.
9. **Length is proportional to scope.** A loop counter `i` in a 5-line `for` is fine; a class field with the same name is not. Cross-file constants need long, search-friendly names.
10. **Pick one word per concept across the codebase.** `fetch` vs `retrieve` vs `get` for the same operation in three classes is friction. Pick one team-wide.

## The one-word rule (house style)

Default for domain types: a single word lifted from the ubiquitous language.

```kotlin
// ✗ Stack noise — the suffix reveals the framework, not the domain
class OrderEntity(...)
class OrderModel(...)
class OrderDto(...)
class OrderImpl : Order
class OrderBean(...)
class OrderObject(...)

// ✓ The domain term, period
class Order private constructor(...) { fun submit() {...} }
```

Two words earn the second when the domain itself distinguishes:

```kotlin
class PurchaseOrder(...)    // ← legitimate if SalesOrder also exists
class SalesOrder(...)

class ShippingAddress(...)  // ← legitimate if BillingAddress also exists
class BillingAddress(...)
```

**Test**: drop the second word — does the domain lose meaning? If no, one word is enough.

## The abstract-name red list

Words that promise nothing. Replace with a concrete domain term every time.

| Forbidden | What it really says | How to fix |
|---|---|---|
| `Item` | "I don't know what this is" | Be specific: `OrderLine`, `CartLine`, `MenuEntry`, `Reservation` |
| `Data` | Empty noun | `Profile`, `Settings`, `Metrics`, `Snapshot` |
| `Info` | Same as Data | `UserProfile`, `OrderSummary` |
| `Object` | Tautological | Any domain word will do |
| `Thing` | Comedic | — |
| `Detail` / `Details` | Usually = Info | `ShippingAddress`, not `ShippingDetails` |
| `Entity` | Leaks ORM into domain | Bare `Order`, not `OrderEntity` |
| `Record` | OK for Java records, otherwise weak | `Transaction`, `AuditLogEntry` |
| `Element` | XML flashback | A domain concept: `Node`, `OrderLine` |
| `Manager` | Verb hides inside | `*er` from the verb: `Reconciler`, `Authenticator` |
| `Handler` | Same | Verb + object: `OrderEventConsumer` |
| `Processor` | Same | Specific verb: `PaymentApprover` |
| `Helper` | Bag of unrelated functions | Likely extension functions or a missing class |
| `Util` / `Utils` | Same | Same |
| `Common` | Dumping ground | Distribute by topic |
| `Base*` | Inheritance for inheritance's sake | Composition; if you must, use `Abstract*` or an interface |
| `Service` (as default) | Vague when applied indiscriminately | OK for Spring service-layer orchestrators; not a fallback when no other word comes to mind |

## Stack-noise suffixes (Hungarian-derived)

These are the modern Hungarian Notation — they encode *layer or container type* into the name instead of intent.

| Suffix | Default action | When tolerated |
|---|---|---|
| `*Entity` | Remove — domain has no `Entity` suffix | A persistence-mapped row in its own package; `*Row` is better |
| `*Dto` | Remove — prefer purpose-specific (`OrderSubmission`, `OrderView`) | A project-wide pre-existing convention that would cost too much to revisit |
| `*Model` | Always remove — `Order` is the model | — |
| `*Impl` | Remove — the concrete class is the type | Two equally-valid implementations and the interface is the abstraction (`JpaOrderRepository` over `OrderRepositoryImpl`) |
| `*Bean` | Always remove | — |
| `*Object` | Always remove | — |
| `*Type` | Usually remove | Domain has a real "Type" concept (e.g., `LegalEntityType` enum) |
| `*Data` / `*Info` | Always remove | — |

## Selective Reading Rule

| File | When to read |
|---|---|
| `resources/general-naming-rules.md` | The 23 universal rules (Martin Ch.2 + Ch.17 §N1-N7, adapted for Kotlin) with before/after examples. Foundation — read first when starting on this skill. |
| `resources/kotlin-specific-naming.md` | Kotlin-only conventions: properties replacing getters, `data class` / `@JvmInline value class` / sealed hierarchies, extension functions, companion factory methods, file & package naming, nullability suffixes. |
| `resources/spring-boot-naming.md` | Spring & Spring Boot conventions: framework-mandated suffixes, configuration properties, beans, test class naming, Modulith listener naming, request/response DTO naming, REST URL paths. |
| `resources/ddd-naming.md` | Domain-driven naming: aggregate roots, value objects, domain events, commands, repositories, domain services, policies, specifications, ACL adapters, bounded-context discipline. |

## Anti-patterns in naming work itself

- **Renaming code you're not changing.** Surgical rule from `karpathy-guidelines` — don't rename a class in a file you opened for an unrelated fix. Open a separate PR.
- **Renaming a public API without a deprecation path.** Public names are contracts; rename only with `@Deprecated` shim and a migration window.
- **Bikeshedding naming in review when the design is wrong.** If the class shouldn't exist, the name is the wrong fight. Address the design first.
- **Inconsistent rename via find-and-replace.** Use the IDE's "Rename" refactor — string replace catches comments and breaks unrelated tokens.
- **Renaming in a hot deploy without coordination.** Class-name change in serialised state (cache, message queue payload, DB column) breaks live traffic. Plan the migration.

## Related skills

| Skill | This not that |
|---|---|
| `clean-code` | Smell vocabulary and refactoring cadence (long methods, deep nesting, primitive obsession); this skill is the deep dive on names. |
| `ddd-strategic-design` | Ubiquitous language is the *source* of names; this skill is how to apply it consistently in code. |
| `ddd-tactical-patterns` | Aggregate / VO / Repository structural patterns; this skill is the naming layer on top. |
| `architect-review` | Naming-as-smell during a structural audit; this skill provides the criteria the review applies. |
| `karpathy-guidelines` | §3 surgical changes — don't rename what you're not touching. |
| `solid-principles` | "Manager / Helper" anti-pattern intersects with SRP — name follows responsibility, not vice versa. |
| `grasp-patterns` | "Manager / Helper" also intersects with GRASP's Pure Fabrication and High Cohesion. |

## Limitations

- Names are negotiable inside a team; this skill encodes one consistent set of opinions. Local conventions can override individual rules, but consistency *within* a codebase is non-negotiable.
- Some rules trade off: short scope wants short names; long scope wants long names. Apply judgement, not mechanics.
- Stop and ask if the **business term** for a concept is unclear — naming with the wrong domain word is worse than naming with the right placeholder.
