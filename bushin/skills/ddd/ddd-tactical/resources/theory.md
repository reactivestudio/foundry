# Theory — Why Tactical DDD Looks Like This

Open when someone asks *why* a tactical pattern exists, or when an aggregate decision needs justification beyond "the rule says so". Each section is one durable distinction; none of them are obvious from the body of `SKILL.md`.

## Ubiquitous language inside one bounded context

Inside a single bounded context, **a word means one thing**, in code and in conversation. `Order` in fulfilment is not the same `Order` in invoicing — those are two contexts with two separate types, even if the database has one table called `orders`.

This matters tactically because:

- When a method is called `process()`, `handle()`, or `update()`, the ubiquitous language has been bypassed. Rename to the verb the business actually uses (`submit()`, `cancel(reason)`, `markAsFulfilled()`).
- When the same field name carries two meanings across methods (`status` = "draft/submitted/cancelled" in one method, "active/inactive" in another), the bounded context is leaking — escalate (see `ddd-strategic-bridge.md`).
- When you can't read a method aloud to a domain expert and have them nod, the naming is wrong.

The test: a non-coder reading the public API of an aggregate should recognise their vocabulary. If they don't, the names — not the structure — are the first thing to fix.

## Aggregate is a consistency unit, transaction is a tool

In a single-database monolith, an aggregate's transactional boundary and a database transaction look identical. They're not the same thing:

- The **aggregate** is the unit of atomic consistency the *business* requires — "you can't submit an empty order".
- The **transaction** is the tool the *database* provides to enforce it locally.

The distinction surfaces the moment writes cross processes (sharding, microservices, event-sourcing). The aggregate is still the consistency unit; the transaction may not be available. That's when **eventual consistency via domain events** is no longer a stylistic choice but the only mechanism left.

Designing aggregates as if transactions might disappear keeps the model honest even when, today, you can wrap everything in `@Transactional`.

## Aggregate root vs. GRASP Information Expert

GRASP asks "which class should own this method?" and answers: *the class that has the data*. That's Information Expert. DDD's aggregate root answers the same question but adds the bounded-context discipline:

- *Information Expert* says: the class with the data owns the method.
- *Aggregate root* says: **the class with the data AND the invariants for the cluster owns the method, and is the only entry point**.

They're parallel, not competing. Use GRASP (`architecture/application/grasp`) when the question is generic responsibility assignment. Use this skill when the bounded-context discipline (consistency boundary, ubiquitous language, references by ID) is the frame.

## Domain events are facts, not commands

A domain event names something that **already happened** — past tense (`OrderSubmitted`, `PaymentCaptured`), never imperative (`SubmitOrder`, `CapturePayment`). Two consequences fall out:

- **An event with a verb in the imperative is actually a command in disguise** — that's a different pattern (a command bus / use case). Don't conflate.
- **Events carry the minimum facts about what happened**, not the whole aggregate state. `OrderSubmitted(orderId, total)` is a fact; `OrderSubmitted(theWholeOrder)` is a snapshot leaking aggregate internals.

Listeners react to the fact. If a listener needs more, it loads the aggregate by ID — it doesn't get pre-fed the state.

## Why factory + private constructor (instead of validation in `init`)

`init {}`-block validation works for *single-shot* invariants: this `Email` is well-formed. It doesn't extend cleanly to multi-step creation: an `Order` that requires a customer lookup, an inventory check, and event emission on creation.

A factory method captures *all* of creation as one named operation, atomically:

1. Pre-conditions checked once at the entry.
2. The constructor (private, unguarded) is called.
3. Initial domain events are recorded as part of creation.

The caller sees one method that either returns a valid aggregate or throws. They can't construct invalid intermediates, and they can't accidentally skip the creation event. That's the principle worth the syntactic overhead.

## One repository per root — the "where would I look for it?" test

If you have `OrderRepository`, `OrderLineRepository`, and `OrderLineAttachmentRepository`, the question "where does the rule about an order's max line count get enforced?" has three plausible answers. That's the bug.

With one repository per root, the question has one answer: **on the root, during a `save` that necessarily goes through `OrderRepository`**. Inner entities have no separate door; they cannot be modified except through the root, so the root sees every change and enforces every rule.

This is also why the JPA-mapped class for an inner entity is **not** exposed via its own Spring Data interface — even if it's technically possible. Wherever there's a way around the root, that way will be used.

## Pattern layering — three faces, one pattern

Each tactical pattern has three faces that engineers conflate:

- **Principle** — language-agnostic DDD (aggregate = consistency boundary).
- **Idiom** — how the principle renders in a specific language (Kotlin `companion object` factory).
- **Placement** — where the wiring code lives in a framework (Spring `@Repository` implementation in `infrastructure/`).

Mixing them is how `@Entity` ends up on an aggregate (placement leaking into principle), or how a `data class` becomes an aggregate (idiom leaking into principle). The body of `SKILL.md` covers principle. `code/clean-code/resources/objects-and-data.md` covers idiom. Framework placement is stack-specific (Spring / JPA), addressed in the relevant `framework/*` and `database/*` skills.

## Source

E. Evans, *Domain-Driven Design* (2003) — Part II, especially chapters 5-7 (Building Blocks: Entities, Value Objects, Services), 6 (Aggregates), 6-10 (Factories, Repositories). V. Vernon, *Implementing Domain-Driven Design* (2013) — chapters 5, 8-10 for tactical patterns with Java idiom.
