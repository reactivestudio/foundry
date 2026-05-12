# DDD & Hexagonal Boundary Patterns

Martin's chapter is about boundaries with *third-party code*. DDD adds two further sources of boundaries: the edge of a **bounded context** (where one model ends and another begins), and the layered structure of a **Hexagonal / Ports & Adapters** application (where the domain meets the infrastructure). This file maps the chapter's rules onto both.

> **Scope note.** This file covers boundaries *as code* — the Adapter, the Port, the seam class. For the relationship-level pattern (Customer-Supplier, Conformist, Open-Host Service, Published Language, Shared Kernel), use `ddd-context-mapping`. The two skills are paired: that one chooses the relationship; this one writes the code.

## The boundary types in a DDD/Hexagonal app

| Boundary | What's on the other side | Implementation |
|---|---|---|
| **System boundary** | HTTP, queues, files, schedulers | Driving Adapters (controllers, listeners). Inbound Ports are the application's primary API. |
| **Persistence boundary** | Database, search index, blob store | Driven Adapters (repository implementations). Outbound Ports are domain-defined interfaces. |
| **External vendor boundary** | SaaS, partner API, legacy system | Anti-Corruption Layer = a Driven Adapter that translates the vendor's language to your domain. |
| **Bounded-context boundary** | Another team's model in the same company | ACL or Open-Host Service (per `ddd-context-mapping`). |
| **Aggregate boundary** | Another aggregate in the same context | Domain events, repository per root. Not a boundary in Martin's sense — but a consistency boundary. |

The chapter's rules — *wrap, don't pass*; *learning tests*; *wishful interface*; *clean seam* — apply to the first three. The fourth (cross-context) needs both this skill and `ddd-context-mapping`. The fifth (aggregate-level) is `ddd-tactical-patterns`.

## Hexagonal layout — where the seam lives

```
┌──────────────────────────────────────────────────────────────┐
│  Driving adapters       Inbound ports         Domain          │
│  (controllers, jobs,    (application API)     (aggregates,    │
│   listeners, CLI) ────► OrderService    ────► invariants,     │
│                                               policies)       │
│                                                    │          │
│                                                    │ uses     │
│                                                    ▼          │
│  Driven adapters    ◄── Outbound ports       (domain          │
│  (JPA, Stripe,          OrderRepository       services)        │
│   Kafka producers, ◄── PaymentGateway                          │
│   S3, email)            EventPublisher                         │
└──────────────────────────────────────────────────────────────┘
                ↑                                  ↑
        owned by infrastructure              owned by domain
        (knows vendor SDKs)                  (knows nothing of HTTP/SQL/SDKs)
```

**Dependency direction is the rule.** Domain depends on its own outbound *ports* (interfaces). The infrastructure depends on the domain. Vendor SDKs sit at the outer ring and depend on nothing in the domain.

If your `Order` domain class imports `org.springframework.web.bind.annotation.RequestBody` or `software.amazon.awssdk.services.s3.S3Client`, the direction is reversed. That's the leak `clean-code-boundaries` exists to fix.

## Ports — the interface, named by the domain

A **port** is an interface that the domain owns. The domain dictates the verbs; the implementation lives on the other side.

```kotlin
// Domain package — knows nothing about JPA, Stripe, Kafka
package com.acme.orders.domain

interface OrderRepository {
    fun byId(id: OrderId): Order?
    fun save(order: Order)
}

interface PaymentGateway {
    fun charge(amount: Money, source: CardToken): Charge
}

interface DomainEvents {
    fun publish(event: OrderEvent)
}
```

**Naming.** A port is named for its **purpose**, not for its implementation. `OrderRepository`, not `JpaOrderRepository`. `PaymentGateway`, not `StripeClient`. `DomainEvents`, not `KafkaProducer`. The implementation may be Stripe today, Adyen tomorrow — the port doesn't care. See `clean-code-naming` for the broader rule about avoiding stack-noise suffixes (`*Client`, `*Impl`, `*Service`).

> **House rule on `*Impl`:** never. If there's only one implementation, name the class for what it is (`JpaOrderRepository`); if there are several, name each for its variant (`StripeGateway`, `AdyenGateway`).

## Adapters — implementations of ports, owned by infrastructure

An **adapter** is the implementation of a port. It lives on the opposite side of the seam and translates between the port's domain language and the foreign API.

```kotlin
// Infrastructure package — knows Stripe SDK exists
package com.acme.orders.infrastructure.stripe

@Component
internal class StripeGateway(
    private val client: StripeClient,
    private val properties: StripeProperties
) : PaymentGateway {
    override fun charge(amount: Money, source: CardToken): Charge =
        runCatching {
            client.charges.create(amount.toStripeAmount(), source.value).toDomain()
        }.getOrElse { translateException(it) }
}
```

**Properties of a healthy Adapter:**

- Implements **one** port.
- Lives in the infrastructure package, marked `internal` to its module (or behind a `@NamedInterface` in Spring Modulith).
- Vendor types appear in **private** members and as method-local variables. Public methods take and return domain types.
- Translates exceptions inside its body. Domain code never `catch`es `StripeException`.
- Contains **zero** business rules. If you find an `if (order.status == APPROVED && customer.tier == GOLD)` inside an Adapter, that logic belongs in the aggregate, not the seam.

## Anti-Corruption Layer (ACL) — the seam for external models

When the boundary is between **your domain** and **someone else's model** (a vendor with strong semantics, a legacy system with embedded rules, a partner whose data shape is awkward), the Adapter has more work to do. This is the **Anti-Corruption Layer**.

The ACL translates not just types but *semantics*:

| Translation | Example |
|---|---|
| Type | `Stripe.Charge.amount` (long cents) → `Money(cents, currency)` |
| Identifier | `"ch_3OqzVZAB12cd34"` (Stripe id) → `ChargeId(value)` (your id, possibly different from theirs) |
| Vocabulary | Stripe's `"succeeded"` / `"failed"` strings → your `ChargeStatus.Succeeded` / `Declined` enum |
| Error semantics | `CardException` (vendor) → `CardDeclined(code)` (domain) |
| Time | epoch seconds → `Instant` |
| Identity | Stripe's customer id ≠ your `CustomerId` — the ACL keeps a mapping (DB row or hash) |
| Workflow | Stripe's `requires_action` → no direct domain equivalent — the ACL emits a `ChargeNeedsConfirmation` event |

The ACL is the chapter's "depend on something you control" applied with *more* discipline. The reason: when the vendor is not just another library but an external model with its own ubiquitous language, you must defend your own language. Otherwise the team's vocabulary slowly drifts to Stripe's, and the domain becomes a Stripe-shaped subset.

For the strategic patterns that decide when an ACL is justified (Conformist, OHS, Customer-Supplier), see `ddd-context-mapping`. This skill is the implementation.

## Where to put what — package layout

A workable Hexagonal + DDD layout in a Spring/Kotlin module:

```
com.acme.orders/
├── domain/                                 ← pure domain, no Spring, no JPA
│   ├── Order.kt                            (aggregate)
│   ├── OrderId.kt                          (value object)
│   ├── Money.kt                            (value object)
│   ├── OrderRepository.kt                  (outbound port)
│   ├── PaymentGateway.kt                   (outbound port)
│   └── OrderSubmitted.kt                   (domain event)
├── application/                            ← use cases
│   ├── SubmitOrderService.kt               (inbound port + service)
│   └── ListOrdersService.kt
└── infrastructure/
    ├── web/
    │   └── OrderController.kt              (driving adapter)
    ├── persistence/
    │   ├── JpaOrderRepository.kt           (driven adapter)
    │   ├── OrderEntity.kt                  (JPA row, package-private)
    │   └── OrderEntityMapper.kt
    └── payments/
        ├── StripeGateway.kt                (driven adapter — ACL)
        ├── StripeChargeResponse.kt         (private wire DTO)
        ├── StripeProperties.kt
        └── StripeMappers.kt
```

**Enforcement.** Use **ArchUnit** or **Spring Modulith `ApplicationModuleTest`** to fail the build when:

- `domain.*` imports anything from `infrastructure.*`.
- `domain.*` imports anything from `org.springframework.web.*`, `jakarta.persistence.*`, `software.amazon.*`, `com.stripe.*`.
- `infrastructure.persistence.OrderEntity` is referenced from any package outside `infrastructure.persistence`.

See `architecture-patterns` for the full Hexagonal / Onion / Clean discussion and the fitness-test code.

## When the boundary is another team's bounded context

When the foreign system is another bounded context owned by your company (an Inventory service consumed by the Orders context), the chapter's rules still apply — but **the strategic decision comes first**. Pick the relationship from `ddd-context-mapping`:

- **Conformist** — accept the upstream model as-is (cheap; binds you to their vocabulary).
- **Customer-Supplier** — collaborate to shape their contract (need political alignment).
- **Anti-Corruption Layer** — translate everything; you don't trust the upstream model to last.
- **Open-Host Service** — when *you* are upstream, publish a stable contract instead of leaking your internal model.

Once the relationship is chosen, the code-level seam is the same Adapter pattern this skill teaches. The relationship decides *how thick* the Adapter is (Conformist → thin; ACL → thick).

## Domain events as the inverted boundary

Outbound, the domain doesn't call the world — it announces things, and the infrastructure listens.

```kotlin
class Order(...) {
    private val events = mutableListOf<DomainEvent>()
    fun pull(): List<DomainEvent> = events.toList().also { events.clear() }

    fun submit() {
        require(status == Draft) { "Order must be Draft to submit" }
        status = Submitted
        events += OrderSubmitted(id, customerId, total)
    }
}
```

The aggregate emits `OrderSubmitted`. A `@TransactionalEventListener` in the infrastructure layer publishes to Kafka, writes to the audit log, sends an email. **The domain doesn't know any of those mechanisms exist.** That's a clean boundary — the seam is the event type itself.

See `ddd-tactical-patterns` for event collection patterns and `cqrs-implementation` for the outbox.

## The aggregate boundary — a different kind of boundary

The chapter's boundaries are about *foreign code*. The aggregate boundary is internal — it's a *consistency* boundary. Different rules apply:

- Aggregates reference each other by ID, not by reference.
- One transaction modifies one aggregate.
- Cross-aggregate coordination happens via domain events or sagas.

This is `ddd-tactical-patterns` territory, not Martin's Ch. 8 territory. Mentioning it here only to draw the line: when you see "boundary" in DDD literature, check which kind — *system* boundary (this skill) or *aggregate* boundary (the tactical-patterns skill).

## Quick reference

| Pattern | When | Where in the layout |
|---|---|---|
| **Inbound Port** (application service interface) | Whenever an external trigger needs to reach the domain (HTTP, schedule, queue, CLI) | `application/` |
| **Outbound Port** (repository, gateway, publisher) | Whenever the domain needs to talk *out* (persist, integrate, emit event) | `domain/` (interface) |
| **Driving Adapter** (controller, `@KafkaListener`, scheduler) | Implements the inbound trigger; calls the application service | `infrastructure/web/`, `infrastructure/messaging/` |
| **Driven Adapter** (repository impl, gateway impl, publisher impl) | Implements an outbound port; translates to the foreign API | `infrastructure/persistence/`, `infrastructure/payments/`, etc. |
| **Anti-Corruption Layer** | When the foreign system has its own model with strong semantics | A Driven Adapter doing semantic translation, not just type translation |
| **Open-Host Service** | When *you* are upstream and want to publish a stable contract | A controller + DTOs designed for stability, not for your internal model |
| **Domain Event** | When the aggregate needs to signal "something happened" without knowing who cares | Emitted by the aggregate, collected at the application layer, published by an infrastructure listener |

## Cross-references

- `ddd-context-mapping` — the relationship between contexts (Conformist, ACL, OHS, Customer-Supplier).
- `ddd-tactical-patterns` — aggregates, value objects, repositories at the aggregate-root boundary, domain events.
- `architecture-patterns` — Hexagonal / Onion / Clean as a module layout, with ArchUnit / Modulith fitness tests.
- `clean-code-naming` — port naming (no `*Impl`, no `*Service` as a default).
- `clean-code-objects-and-data` — DTO discipline at every layer boundary; Active Record anti-pattern for JPA entities.
- `cqrs-implementation` — read-side projections as a different kind of outbound boundary.
