# GRASP — Best Practices, Heuristics, Decision Rules

Actionable playbook over the patterns. Heuristics for assignment, decision rules for picking between candidate placements, refactor recipes for the common moves, and a PR-review checklist.

For pattern definitions, see `theory.md`. For Kotlin idioms, see `kotlin.md`. For Spring usage, see `spring-boot.md`. For specific anti-patterns, see `bad-practices.md`.

---

## The "who has the data?" prompt (Information Expert)

Before adding any new method, ask: *"Where does the data this method needs live?"*

- All on one class → that class owns the method.
- Spread across two classes → the one with the most data owns it; the others are arguments.
- On infrastructure (DB, HTTP, queue) → it's not Info Expert; it's a Pure Fabrication candidate.

Most "should this go on the entity or the service?" disputes resolve cleanly. The exceptions go to Pure Fabrication.

---

## The "who has the context?" prompt (Creator)

Before adding `new SomeClass(...)` anywhere, ask: *"Of the candidates, which one already aggregates / contains / records / closely uses / has the initialising data for this?"*

- An aggregating type → that type is the Creator (`Order` creates `OrderItem`).
- No aggregator, but a clear "has the data" type → companion factory there (`Order.create(...)`).
- Neither → a dedicated factory class (Pure Fabrication: `OrderFactory`), but only if construction needs DI'd collaborators.

Default to companion factory; promote to a Spring bean factory only when DI is genuinely needed at construction time.

---

## The "use case per handler" rule (Controller)

For every system event (HTTP request, message bus message, scheduled job), there should be one Use-Case Handler with one reason to change. Default to one handler per command / query.

Facade Controller is fine for small subsystems. Use-Case Controllers (per-endpoint handlers) scale better as the system grows: each handler is small, focused, easy to test, easy to find.

CQRS makes this mechanical: one command type ↔ one command handler ↔ one Use-Case Controller (see `cqrs-implementation`).

---

## Low Coupling vs High Cohesion: the trade-off

These two pull in opposite directions:

- Pulling a method onto an entity raises **cohesion** there but may raise **coupling** if the entity now needs more dependencies.
- Splitting a class raises **cohesion** of each piece but may raise **coupling** as pieces communicate.

The art: maximise the **net** improvement.

### Heuristic

- If both pieces have meaningful, independent reasons to change → split (coupling cost is worth it).
- If both pieces would always change together → keep together (cohesion is fine; splitting just adds coupling).
- If unsure → start unified, split when the second reason to change appears (analogous to OCP's "wait for the second case").

---

## When to introduce an event (Low Coupling) vs a direct call

**Use an event** when:
- The reaction is genuinely independent of the operation (notification, analytics, audit log).
- More than one reaction is possible, or likely to be added.
- The reaction can fail or retry without affecting the original operation.
- The reaction can be eventually consistent.

**Use a direct call** when:
- The caller depends on the result.
- The reaction is intrinsic to the operation (debiting the wallet IS placing the order).
- There's exactly one consumer and it's stable.
- The reaction must be transactionally atomic with the operation (or use the outbox pattern).

Don't use events as decoration. Events lower coupling but raise debugging cost — apply where the trade favours decoupling.

---

## When a Pure Fabrication earns its keep

Pure Fabrications are good design when:
- The responsibility doesn't fit any domain entity.
- Forcing the responsibility onto an entity would require the entity to depend on infrastructure.
- The fabrication has *one* responsibility (focused, not a junk drawer).

The trap is the junk drawer: `OrderUtils`, `Helpers`, `CommonComponent`. Each fabrication should pass the SRP "reason to change" prompt:

> *"This fabrication would change if ___"*

If the answer needs an "or", split.

---

## Where to place an Indirection seam

Apply Indirection at boundaries where:
- Substitutability is real (you have or expect a second implementation).
- Testability requires a fake/stub.
- The implementation might change (provider migration, persistence rewrite).
- The boundary is across a context, layer, or module.

Don't apply at internal collaborations between two focused classes within the same layer — that's overhead with no benefit.

The Indirection cost is one interface, one DI link, one indirection in stack traces. The benefit must clear that bar.

---

## Where to place a Protected Variations seam

PV is the most expensive GRASP pattern. Apply only at boundaries where you have *good reason* to expect change:

- **Vendor SDKs** (Stripe, AWS, Slack, sendgrid). Every vendor will change pricing, deprecate APIs, or be replaced.
- **Persistence stores** when polyglot persistence is plausible (Postgres for writes, ES for search, Clickhouse for analytics).
- **API versioning seams** (v1 → v2 migration).
- **Identity primitives** (UUID today, ULID tomorrow). Wrap in `value class`.
- **Bounded-context boundaries** — Anti-Corruption Layer between contexts.

Don't apply PV speculatively. Don't wrap "in case we need to swap one day" — YAGNI applies. The smaller cost is to wait for the predicted change and refactor *then*.

---

## Refactor recipes

### Recipe: anaemic domain → behaviour-rich (Information Expert)

1. List the entity's data fields.
2. List the methods in services that read those fields and compute over them.
3. For each such method, decide where the data is most concentrated. Move the method there.
4. Reduce the service method to a delegation: `entity.method()`.
5. Verify: the entity has methods, not just getters; the service is thin; tests of the entity don't need Spring.

### Recipe: scattered `new` → centralised Creator

1. List every place that constructs the type.
2. Find the natural Creator (per the five Creator criteria).
3. Make the constructor `private`; expose a `companion fun create(...)` (or a method on the aggregating type).
4. Replace each call site with the new path.
5. Verify: invariants are enforced exactly once; no `new SomeClass(...)` outside the Creator.

### Recipe: god service → use-case handlers

1. List the service's methods. Group by *use case* (a use case is a system-level action: place order, cancel order, ship order).
2. Create one `*Handler` per use case (`PlaceOrderHandler`, `CancelOrderHandler`, …).
3. Each handler injects only the dependencies its use case needs.
4. The old god service either disappears or becomes a slim facade routing to handlers.
5. Verify: each handler has one reason to change; tests are smaller; controllers depend on handlers, not the god service.

### Recipe: Util/Helper class → focused fabrications

1. List the methods on the Util class. Group by *purpose* (not by "Order" in the name).
2. For each group, create a focused class named by what it does (`OrderPricing`, `OrderEmailFormat`, `OrderCsvExport`).
3. Move the methods.
4. Update callers.
5. Verify: each new class passes the "reason to change" prompt; the original Util is gone.

### Recipe: direct downstream call → event

1. Identify the call: `OrderService.placeOrder()` calling `EmailService.send()`.
2. Define a domain event (`OrderPlaced` with the data the consumer needs).
3. The producer publishes the event after the operation completes (and ideally after commit, via `@ApplicationModuleListener`).
4. Extract a listener (`OrderEmailNotifier`) that reacts to the event.
5. Remove the direct dependency from the producer.
6. Verify: producer no longer imports the consumer; adding a second consumer is a new class only.

### Recipe: vendor SDK call in business code → Protected Variations seam

1. Identify the SDK calls in business logic.
2. Define a domain port (`PaymentGateway`) with the operations business code actually uses.
3. Implement the port as an adapter (`StripePaymentGateway : PaymentGateway`) in `infrastructure/`.
4. Replace SDK calls in business code with port calls.
5. Verify: business packages have zero imports from the vendor SDK; the adapter is the only owner.

### Recipe: `when (type)` proliferation → polymorphic types

1. Find all the `when (type)` chains on the same type.
2. Convert the type to a `sealed interface` with the methods that vary by type.
3. Move each branch's body into the corresponding `data object`/`class` as a method.
4. Replace each `when` chain at call sites with a method call.
5. Verify: adding a new variant requires only adding a new `data object`; nothing else changes.

---

## GRASP × DDD mapping

DDD provides domain-specific names for the same physics. If your team uses DDD, prefer the DDD vocabulary for in-domain conversation; fall back to GRASP for cross-cutting design discussions or non-DDD systems.

| GRASP pattern | DDD analogue |
|---|---|
| Information Expert | Aggregate methods (the aggregate owns its data) |
| Creator | Aggregate factory (`Order.create(...)`); aggregate root creates internal entities |
| Controller | Application service / Use-Case Handler |
| Low Coupling | Bounded context boundaries + domain events |
| High Cohesion | Aggregate boundary (consistency boundary) |
| Polymorphism | Strategy via sealed interface; State machine over aggregate status |
| Pure Fabrication | Domain Service (in-domain) / Application Service (in-application layer) |
| Indirection | Repository interface (domain) + JPA adapter (infra); Anti-Corruption Layer |
| Protected Variations | Anti-Corruption Layer (between contexts or vs external) |

GRASP is the underlying physics; DDD is the project-local vocabulary. They're not in conflict — they overlap deliberately.

---

## PR-review checklist

A scan-the-diff routine. One pass per pattern.

### Information Expert

- [ ] Any new method on a service that reaches into entity fields to compute? Move to the entity.
- [ ] Any new `obj.field.subField.method()` chain? Push the method deeper (Info Expert) or expose a higher-level operation (Law of Demeter).
- [ ] Any new `@Entity` with no methods other than property accessors? Anaemic — push behaviour onto it.

### Creator

- [ ] Any new `new SomeClass(...)` in business code where a factory could centralise? Centralise.
- [ ] Any constructor with > 7 parameters? Caller is being forced into a Creator role.
- [ ] Any public constructor on a domain type that should validate invariants? Make it `private`; add factory.

### Controller

- [ ] Any controller method with business logic, persistence calls, or vendor calls? Extract a Use-Case Handler.
- [ ] Any controller injecting > 5 dependencies? It's a god orchestrator; inject only handlers.
- [ ] Any duplicated coordination across controllers? Extract a shared handler.

### Low Coupling

- [ ] Any new dependency in a class that doesn't actually call it? Remove.
- [ ] Any new direct call to a downstream service for a side effect (notification, analytics)? Consider an event.
- [ ] Any new `obj.x.y.z()` chain? Train wreck — couples to the chain's structure.

### High Cohesion

- [ ] Any new class with > 5 constructor dependencies? Often a god class; investigate splitting.
- [ ] Any new class named `*Util`, `*Helper`, `*Manager`, `*Processor`? Rename per `clean-code-naming`; verify single purpose.
- [ ] Any new class whose methods touch disjoint subsets of fields? Split.

### Polymorphism

- [ ] Any new `when (type)` chain? Check whether the same `when` exists elsewhere on the same type. If yes, refactor to sealed hierarchy.
- [ ] Any new `is`/`instanceof` chain in business logic? Sealed hierarchy candidate.

### Pure Fabrication

- [ ] Any new domain entity orchestrating infrastructure (DB / email / external API)? Extract a fabrication.
- [ ] Any new fabrication with multiple unrelated methods? Split into focused fabrications.

### Indirection

- [ ] Any new direct injection of a vendor concrete? Wrap behind a domain port.
- [ ] Any new interface added with one impl and no plan for substitution? Inline; apply Indirection where benefit is real.

### Protected Variations

- [ ] Any new vendor SDK call in business code? Wrap behind a domain port.
- [ ] Any new `String` / `UUID` parameter that represents a domain ID? Wrap in `value class`.
- [ ] Any new interface added "in case we swap one day"? Wait for the swap.

---

## Heuristics for "is this pattern worth applying here?"

GRASP has a cost. Apply only when the benefit clears the bar.

- **Information Expert:** apply always when an entity has the data and the operation is pure. The benefit (testable entity, no service reaching) almost always exceeds cost.
- **Creator:** apply when scattered `new` exists or invariants are at risk. With one call site and trivial construction, leave it alone.
- **Controller:** apply at every system boundary. Use-case granularity: as soon as the system grows past a handful of endpoints.
- **Low Coupling / High Cohesion:** apply always — they're meta-criteria, the lenses through which other choices are evaluated.
- **Polymorphism:** apply when the same `when (type)` repeats across files. With one occurrence in one place that won't grow, leave it.
- **Pure Fabrication:** apply when no domain entity fits. With a clear fit (the entity has the data), prefer Info Expert.
- **Indirection:** apply at substitution / testability / change-shielding boundaries. Skip at internal layer-internal collaborations.
- **Protected Variations:** apply only at boundaries where change is *predicted* (vendors, stores, API versions, identity primitives). Don't speculate.

---

## Team conventions worth standardising

- **Aggregate / entity invariants enforced in factory.** No public constructor on aggregate roots.
- **Domain events for cross-aggregate side effects.** No direct calls from one aggregate's service to another's.
- **Vendor SDKs always wrapped.** No `import com.stripe.*` outside `infrastructure/`.
- **`*Util` / `*Helper` / `*Manager` banned.** Reviewer rejects the name; ask the author what the responsibility is.
- **Handler per use case** when the system grows past a handful of endpoints.
- **Identity primitives via `value class`.** No raw `String` / `UUID` for domain IDs.
- **PR template prompts the GRASP scan** for non-trivial structural changes.

---

## When GRASP actively misleads

- **One-off scripts and migrations.** A 200-line script that runs once doesn't need Pure Fabrication discipline. Inline it.
- **Genuinely simple CRUD.** A controller that delegates to a single repository for one endpoint doesn't need a use-case handler, doesn't need an event, doesn't need Polymorphism.
- **Performance-critical hot paths.** Polymorphic dispatch, Indirection, and event-driven coupling all cost cycles. Optimise; document why.

The bias is toward *applying* GRASP, but the discipline is in *recognising* when not to.
