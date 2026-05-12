# GRASP — Theory (language-agnostic)

Nine patterns for assigning responsibilities. Each entry: definition, the question it answers, language-agnostic example, when it applies. Kotlin idioms live in `kotlin.md`; Spring usage in `spring-boot.md`.

The patterns originate from Craig Larman's *Applying UML and Patterns* (2002). They're older than DDD and complement it; they're at a different scale than SOLID (which validates a class's shape) and GoF (which names a recurring collaboration shape). GRASP answers the *prior* question: who should own this responsibility in the first place?

---

## 1. Information Expert

> **Assign the responsibility to the class that has the data needed to fulfil it.**

### The question

*"Who should do X?"* → *"Who has the data to do X?"*

### Why it works

A class that holds the data also has the cheapest path to compute over it. Pulling the data out into a service that does the computation forces the data through getters and creates a long-distance coupling — the service knows the entity's internals; the entity becomes a dumb data carrier (anaemic domain).

### Canonical example

To compute an order's total: the data lives on `Order` and `OrderItem` (the items, each with quantity and unit price). Therefore `Order.total()` and `OrderItem.subtotal()` own the operation:

```
class Order:
    def total():
        return sum(item.subtotal() for item in self.items)

class OrderItem:
    def subtotal():
        return self.unit_price * self.quantity
```

The service simply asks: `order.total()`.

### When it applies

Almost always for queries that derive a value from data. The exceptions are operations that combine data from *several* entities, or operations that need infrastructure (DB, HTTP, email) — those are Pure Fabrication candidates.

### The smell of violating it

A service reaches for `obj.field1.subField.method()` to compute something. That chain is "feature envy" — the method wants to live where the data is.

---

## 2. Creator

> **Class B is responsible for creating instances of A when B contains/aggregates A, records A, closely uses A, or has the initialising data.**

### The question

*"Who should call `new A()` / construct instances of A?"*

### The five "Creator" criteria

B is the right Creator for A if:

1. B aggregates A
2. B contains A (composition)
3. B records A
4. B closely uses A
5. B has the initialising data for A

In practice the rule resolves "scattered `new`" smells: if `Order` aggregates `OrderItem`, `Order` should be the one creating `OrderItem`. If something else is doing it, find the Order or extract a factory.

### Canonical example

```
class Order:
    def add_item(product_id, quantity, price):
        self.items.append(OrderItem(product_id, quantity, price))

class Order:
    @staticmethod
    def create(id, customer_id, items):
        require_non_empty(items)
        return Order(id, items)
```

`Order` is Creator of `OrderItem` (it aggregates them). `Order.create` is the Creator of `Order` itself (factory method).

### When it applies

Whenever you find scattered `new SomeClass(...)` calls across the codebase for the same type — usually a Creator violation. Centralise either on the aggregating type, or on a dedicated factory if no natural aggregator exists.

### The smell of violating it

`new` calls scattered across services for the same type. Constructors that take 10 parameters where 8 are "details I just looked up" — caller is forced into a Creator role they shouldn't have.

---

## 3. Controller

> **Assign the responsibility for handling a system event to a class that represents the overall system, the use case, or a frame.**

### The question

*"Who handles the request that just came in from the UI / API / event bus?"*

### Two flavours

- **Facade Controller** — represents the whole system or subsystem (e.g., `OrderController` for the Order subsystem). One per subsystem.
- **Use-Case Controller** — one per use case (e.g., `PlaceOrderHandler`). Better when the system grows: each handler has one reason to change, and the API surface stays comprehensible.

CQRS's command/query handlers ARE Use-Case Controllers (see `cqrs-implementation`).

### Canonical example

The HTTP controller receives the event, validates input, delegates to the use-case handler, formats the response. It does **not** contain business logic.

### When it applies

Always at the system boundary (HTTP, message bus, scheduler). The choice is between facade and use-case: facade for small systems, use-case as the system grows.

### The smell of violating it

Fat controller with `if/else` chains and DB calls. Multiple controllers doing similar coordination — extract a shared use-case handler.

---

## 4. Low Coupling

> **Assign responsibilities to minimise dependencies between classes.**

### The question (meta-criterion)

*"Of these placements, which creates the fewest new dependencies?"*

### Why it matters

Every dependency is a piece of the codebase that has to change when the dependee changes. Less coupling means smaller change radius, easier substitution, faster tests.

### Canonical example

Adding "send confirmation email when order is placed".

**High coupling:** `OrderService` directly calls `EmailService`. Adding SMS later means editing `OrderService`. Adding analytics later means editing `OrderService` again.

**Low coupling:** `OrderService` emits an `OrderPlaced` event. `EmailNotifier`, `SmsNotifier`, `AnalyticsRecorder` subscribe independently. `OrderService` has no idea who's listening.

### When it applies

Whenever you're tempted to add a "while I'm here" dependency. Whenever a new feature would force a previously-stable class to grow new collaborators.

### The trade-off

Low coupling can hide control flow. An event-driven system is low-coupled but harder to debug than a direct-call system. Apply where the indirection earns its keep (genuinely independent reactions); don't apply where it just adds noise (one immediate caller, unlikely to multiply).

---

## 5. High Cohesion

> **Assign responsibilities so that cohesion remains high — a class's methods all serve a closely related purpose.**

### The question (meta-criterion)

*"Do all methods on this class serve the same purpose?"*

### Why it matters

A class is a unit of change, of testing, of substitution. If its methods serve unrelated purposes, every change reaches into half the class; every test setup pulls in irrelevant dependencies; every substitution is awkward.

### Canonical example

`OrderUtils` with `calculateTotal`, `formatForEmail`, `exportToCsv`, `retryFailedOrders`, `cleanupOldOrders`. Five unrelated responsibilities glued together by "Order" in the name. Split into:

- `OrderPricing.total(order)`
- `OrderEmailFormat.format(order)`
- `OrderCsvExport.export(orders)`
- `OrderRetryJob.run()`
- `OrderCleanupJob.run()`

Each class has one purpose. Cohesion is high.

### When it applies

Always. High cohesion is one of the two universal evaluators (with Low Coupling).

### The smell of violating it

`Util` / `Helper` / `Manager` in the name. Methods that touch entirely different fields (a sign the class is multiple classes pretending to be one). Classes with > 7 unrelated public methods.

---

## 6. Polymorphism

> **When alternatives or variations vary by type, assign the behaviour to the types themselves using polymorphism.**

### The question

*"How do we handle this differs-by-type variation?"*

### Why it works

Pushing per-type behaviour onto the type itself eliminates the central `switch`/`when` chain. Adding a new variant becomes adding one new class instead of editing every `switch`.

### Canonical example

Payment methods: `Card`, `BankTransfer`, `PayPal`. Each can be implemented as a class with `process()`, `fee()`, `supports()`. Adding `Crypto` adds one class; nothing else changes.

This is GRASP Polymorphism + SOLID Open/Closed + GoF Strategy / State (depending on flavour) all expressing the same idea in different vocabularies.

### When it applies

When the same `switch (type)` appears across several methods or files. With one `switch` in one place that won't grow, polymorphism is overhead. With three or more, polymorphism is a clear win.

### The smell of violating it

`when (x.type) { … }` repeated across files. `is`/`instanceof` chains.

---

## 7. Pure Fabrication

> **When responsibility doesn't fit any domain class, invent a class to hold it.**

### The question

*"Where does X belong when no domain entity is a natural fit?"*

### Why it's needed

Some responsibilities — rendering a PDF, sending an email, computing an external tax — don't naturally belong to any domain entity. Forcing them onto an entity bloats the entity and couples it to infrastructure. Forcing them onto a service is fine *if* the service is a focused fabrication. The wrong move is to stuff them somewhere they don't fit.

### Canonical example

`InvoicePdfRenderer.render(order)` — renders an order as a PDF invoice. Not a domain entity; a fabrication. Lives in `application/` or `infrastructure/`. The domain `Order` knows nothing of PDFs.

Other examples: `EventPublisher`, `TaxCalculator`, `OrderEmailFormatter`, `PriceQuoter`. None are entities; all are Pure Fabrications.

### When it applies

Any time you need a class to hold infrastructure orchestration, cross-cutting computation, or a coordination role that no entity owns naturally.

### The trap (good vs bad fabrication)

A focused fabrication is good design. `OrderEmailFormatter` is a clean fabrication: one purpose, one method, easy to test.

A grab-bag fabrication is bad design. `OrderUtils` is a fabrication with no defined responsibility — it's the High Cohesion violation. The difference: focused fabrications have *a* responsibility; grab-bag ones have several.

---

## 8. Indirection

> **Assign responsibility to an intermediate object to mediate between two parties, decoupling them.**

### The question

*"How do we keep A and B from knowing about each other directly?"*

### Why it works

Direct coupling between A and B means changes to either propagate. An intermediary I lets A and B evolve independently, as long as I's contract holds.

### Canonical example

`OrderService` shouldn't know about SMTP. Introduce an `EmailSender` interface; `OrderService` depends on it; `SmtpEmailSender` implements it. The interface is the indirection.

### Other examples of Indirection

- **Repository pattern** — `OrderRepository` interface mediates between `OrderService` and JPA
- **API Gateway** — mediates between clients and microservices
- **Event Bus** — mediates between publisher and subscriber (also Low Coupling)
- **Anti-Corruption Layer** (DDD) — mediates between bounded contexts

### When it applies

When you need decoupling for testability, swappability, or to shield from change. Don't apply for its own sake — every indirection is a class to maintain.

### The smell of violating it

Direct concrete-class injection where an interface would buy you something. Code that knows too much about HOW its dependencies work, not just WHAT they do.

---

## 9. Protected Variations

> **Identify points of predicted variation, and shield other parts of the system from those changes by wrapping them with a stable interface.**

### The question

*"What's most likely to change here, and how do we limit the blast radius?"*

### Why it matters

Some change is inevitable: vendor providers (Stripe → Adyen), persistence stores (Postgres → Mongo for a read model), API contracts (v1 → v2). Wrapping the volatile concern behind a stable interface lets the change land in one place.

### Canonical example

```
interface PaymentGateway:
    def charge(amount, customer): TransactionId
    def refund(transaction_id): RefundResult

class StripePaymentGateway implements PaymentGateway: ...
class AdyenPaymentGateway implements PaymentGateway: ...
```

Migrating Stripe → Adyen requires writing `AdyenPaymentGateway`. The rest of the system doesn't care.

### Examples of Protected Variations

- **Polyglot persistence** — `OrderRepository` interface protects from Postgres → Mongo migration
- **API versioning** — `/api/v1/...` vs `/api/v2/...` protects clients from breaking changes
- **Feature flags** — `if (features.newCheckoutEnabled)` protects from rollback
- **Anti-Corruption Layer** — protects domain from vendor SDK changes

### The cost

Protected Variations is the most expensive GRASP pattern — every interface costs design effort, mental load, and a layer of indirection. Apply at boundaries where you have *good reason* to expect change. Don't protect every variation: YAGNI applies.

### The smell of violating it

Concrete vendor SDK calls scattered throughout business logic. Code that breaks every time a third-party library is upgraded.

---

## GRASP cheat sheet

| Question | Pattern |
|---|---|
| Who has the data → who owns the behaviour? | **Information Expert** |
| Who calls `new`? | **Creator** |
| Who handles the system event? | **Controller** |
| Which placement creates fewest dependencies? | **Low Coupling** (meta) |
| Which methods belong together? | **High Cohesion** (meta) |
| Differs-by-type variation? | **Polymorphism** |
| No natural domain class? | **Pure Fabrication** |
| A and B shouldn't know each other? | **Indirection** |
| What's likely to change next? | **Protected Variations** |

---

## How GRASP, SOLID, GoF and DDD relate

```
                       Scale of design decision
   Smaller ─────────────────────────────────────────► Larger

   GoF pattern        SOLID principle       GRASP responsibility    Architecture
   (one technique)    (class shape)         (which class owns this) (whole system)

   "Use Strategy"     "SRP — split this"    "Info Expert — owner"   "Onion + DDD"
```

- **GRASP** answers *who*: *which* class should hold this responsibility?
- **SOLID** answers *how-shaped*: does the resulting class follow the rules?
- **GoF** answers *what shape*: what's the recurring pattern this collaboration takes?
- **DDD tactical** is GRASP with bounded-context vocabulary: aggregate root ≈ Info Expert, domain service ≈ Pure Fabrication, repository ≈ Indirection + Protected Variations.

A typical refactor: GRASP picks the right owner → SOLID validates the class shape → GoF names the pattern that emerges → DDD maps the result to the bounded-context vocabulary.

---

## What GRASP is *not*

- **Not an algorithm.** GRASP gives you names and questions; the answers come from understanding the domain.
- **Not a substitute for domain knowledge.** GRASP tells you "Info Expert"; the domain tells you who has the data.
- **Not a checklist to apply mechanically.** Like SOLID, mechanical application produces over-engineered Java enterprise abstractions.
- **Not patterns in the GoF sense.** GoF patterns are recurring solutions to recurring problems; GRASP patterns are recurring *questions* about responsibility assignment.
