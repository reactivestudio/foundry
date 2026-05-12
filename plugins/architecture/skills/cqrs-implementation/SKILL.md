---
name: cqrs-implementation
description: "CQRS (Command Query Responsibility Segregation) implementation patterns for Kotlin/Spring Boot — sealed command types, command bus with Spring DI, command handlers, aggregate emits domain events, projection handlers via Spring Modulith `@ApplicationModuleListener`, outbox via Modulith `event_publication` table, polyglot projection stores (Elasticsearch for search, Clickhouse for analytics, denormalised Postgres views for transactional reads), projection rebuild, read-your-writes tracking, eventual-consistency UX. Use when read and write workloads diverge in shape or scale, designing a projection pipeline, building eventual-consistency reads on a polyglot persistence stack, refactoring a 6-table-join read endpoint into a precomputed read model, or wiring Modulith events into projection handlers. Event sourcing is a separate, heavier commitment — not the default here."
risk: safe
source: custom
---

# CQRS Implementation (Kotlin / Spring)

> "Separate the model that *changes* state from the model that *answers questions about* it. The two have different lifecycles, different shapes, and increasingly different stores."

This skill covers **CQRS without mandatory event sourcing** — Postgres as the durable source of truth for the write side, domain events as a side effect for projections. Event sourcing is mentioned where relevant; it is not the default.

## Use this skill when
- Read and write workloads have **fundamentally different shapes** (transactional writes vs search/analytics reads).
- You need to project domain state into **Elasticsearch** (full-text/faceted search), **Clickhouse** (analytics rollups), or denormalised Postgres views.
- A read endpoint is too slow because it joins 6 tables; the natural answer is a precomputed read model.
- Designing a new bounded context where the query language doesn't match the aggregate shape.
- Wiring Spring Modulith `@ApplicationModuleListener` to project domain events into read stores.
- Implementing the outbox pattern via Modulith's `event_publication` table for reliable in-process event handling.

## Do not use this skill when
- The domain is simple CRUD on a single aggregate. CQRS for `GET /users/:id` is overkill — the cost (two models, projection lag, rebuild logic) without the benefit (no read/write divergence).
- **Strong consistency is required on every read.** CQRS implies projection lag. Read-your-writes can be partially mitigated, but if every read must see the latest write committed milliseconds ago, you're outside CQRS territory.
- **The read is slow but the query shape matches the aggregate.** Try caching (`caching-strategies-spring`) or a covering index (`database-design/resources/indexing.md`) first — both are dramatically cheaper than a projection pipeline.
- The task is **cross-service event delivery** (one service publishes, another consumes via a broker) → `messaging-rabbitmq-spring`. This skill is for **in-process** Modulith events that drive projections inside one deployable. Cross-service distribution is the next layer out.
- For general API contract design — `api-design-principles`.
- For picking architecture layout — `architecture-patterns`.
- For deciding whether you even need CQRS at all — `architecture` (it'll route you back here if yes).

## Core principles

1. **Write side is small and consistent.** Commands change state; aggregates enforce invariants; the database is the source of truth. One aggregate per command transaction.
2. **Read side is denormalised and many.** Each *query type* can have its own projection optimised for that query. One aggregate may feed three projections; one projection may consume events from three aggregates.
3. **Events bridge the two.** Aggregate emits domain events (see `ddd-tactical-patterns`); projections consume events; read models materialise.
4. **Eventual consistency is the price.** Projections lag the write — usually milliseconds, sometimes more under load. Design UI/UX accordingly: show "saving…", show projection version, or use read-your-writes patterns.
5. **Don't event-source unless you need it.** CQRS works fine with Postgres as the durable write side and events as a side effect. Event sourcing (events as the source of truth, state derived by replay) is a separate, much heavier commitment with its own learning curve, snapshotting, replay-perf, and schema-evolution concerns.

## Spring/Kotlin stack mapping

| Concern | Default for new services |
|---|---|
| Command type | Sealed Kotlin interface: `sealed interface OrderCommand { data class Submit(...) : OrderCommand; ... }` |
| Command bus | Spring DI: one `@Service` handler per command, or one grouped handler per aggregate. Optional bus interface for testability. |
| Command handler | `@Service` + `@Transactional`. Loads aggregate via domain repository, calls method, saves, returns. |
| Aggregate → events | Aggregate collects `pendingEvents`; persistence layer pulls and publishes after `save()` (see `ddd-tactical-patterns`). |
| In-process event publishing | `ApplicationEventPublisher.publishEvent(...)` for single-context; Spring Modulith `@ApplicationModuleListener` for cross-context-in-same-process. |
| Outbox pattern | Spring Modulith `event_publication` table — built-in transactional outbox for in-process events. Pair with a relay if cross-service delivery is needed (then see `messaging-rabbitmq-spring`). |
| Projection handler | `@ApplicationModuleListener` on a `@Component`; writes to the projection store. Should be idempotent (event may replay). |
| Projection store | Postgres view / table (in same DB) for transactional reads; Elasticsearch index for search; Clickhouse table for analytical rollups. Each is a separate Spring Data repository or low-level client. |
| Read-your-writes | Track projection version per write; query waits for the projection to catch up, or returns a "stale" hint to the UI. |
| Projection rebuild | Truncate the projection store, replay events (from `event_publication` or domain log). Plan for this from day one. |

## Canonical Kotlin snippet — projection handler

```kotlin
@Component
class OrderSearchProjection(
    private val es: ElasticsearchRepository<OrderSearchDoc, OrderId>,
) {
    @ApplicationModuleListener
    fun on(event: OrderCreated) {
        es.save(
            OrderSearchDoc(
                id = event.orderId,
                customerId = event.customerId,
                total = event.total.amount,
                status = "DRAFT",
                createdAt = event.occurredAt,
            )
        )
    }

    @ApplicationModuleListener
    fun on(event: OrderSubmitted) {
        es.findById(event.orderId).ifPresent { doc ->
            es.save(doc.copy(status = "SUBMITTED", submittedAt = event.occurredAt))
        }
    }
}
```

Notice:
- `@ApplicationModuleListener` runs in a *new* transaction *after* the publisher's transaction commits — guarantees the projection sees committed state and never sees a rolled-back write.
- The handler is **idempotent** — replaying `OrderCreated` twice produces the same document (overwrite via `save`). This matters when projections are rebuilt or events are replayed.
- The projection is **per query type**: a different query ("orders by customer") might warrant a different projection with different shape and different store.

## CQRS vs. simpler alternatives

| Symptom | First try | If insufficient |
|---|---|---|
| Read is slow because the join is expensive | A covering index. | Denormalised view in same DB. |
| Read is slow because data is hot but rarely changes | A cache (Caffeine / Redis — see `caching-strategies-spring`). | Projection rebuild + read-your-writes. |
| Read needs full-text or faceted search | Search index alongside Postgres (Elasticsearch). | Same — that's CQRS, you're already doing it. |
| Read needs analytical aggregation across time | Columnar store (Clickhouse) populated by projections. | Same. |
| Read and write share shape and aren't slow | **Don't apply CQRS.** Use the same model. | n/a. |

CQRS is the right answer when the read shape genuinely diverges from the write shape, not when the read is just slow. Most "we need CQRS" requests are actually "we need an index" or "we need a cache."

## Anti-patterns

| Anti-pattern | Why it hurts | Fix |
|---|---|---|
| **Cargo-cult CQRS** | "Microservices have CQRS so we should too" — pays the cost (two models, lag, rebuild) without benefit. | Apply only where read/write diverge in shape or scale. List the divergence in the ADR. |
| **CQRS + event sourcing together "because they go together"** | Two heavy commitments coupled; failure of one means rip out both. | Start CQRS with Postgres as source of truth. Adopt ES separately if and only if its specific benefits (audit, replay, temporal queries) are needed. |
| **Bidirectional projections** | Read side writing back to the source of truth — couples them, breaks "read is read-only." | Read side is read-only. Always. Commands write; projections read. |
| **Query handlers calling aggregates** | Queries reading via the write-side model — kills the perf benefit, couples reads to write-side schema. | Queries read projections directly. Aggregates exist for writes only. |
| **One projection per aggregate, mechanically** | Mistakes "what data exists" for "what queries do users run." | Projections are designed *per query*, not per aggregate. One aggregate may feed N projections; one projection may consume events from M aggregates. |
| **Synchronous reads through the write side "just for now"** | The stopgap stays forever; the two sides silently couple; lag-handling logic never gets written. | Project eagerly (high availability) or accept lag explicitly (read-your-writes hint to UI). Don't fudge. |
| **Projection handler that's not idempotent** | Replaying events (rebuild, retry, replay) duplicates or corrupts projection state. | Design handlers to be safe to call N times: `save` over `insert`, version checks, no `++counter` style updates. |
| **No projection rebuild plan** | When a projection bug ships, there's no way to fix the data without manual SQL. | Design rebuild from day one: truncate target, replay events, verify. Test it occasionally so you know it works. |
| **Outbox without a relay**, when external delivery is needed | Modulith outbox handles in-process; cross-service requires a relay to a broker. Without it, events stay trapped. | Use `messaging-rabbitmq-spring` to design the relay from the Modulith outbox to RabbitMQ when crossing service boundaries. |

## Selective reading rule

| File | When to read |
|---|---|
| `resources/overview-and-decisions.md` | Concepts, decision tree (do you need CQRS?), hand-rolled vs Axon, Onion/Modulith integration, deeper stack-mapping. |
| `resources/write-side-patterns.md` | Implementing the write path — commands, command bus, handlers, aggregate emits events, transaction boundary, idempotency, outbox detail. |
| `resources/read-side-patterns.md` | Implementing the read path — projection handlers per store (ES / CH / Postgres view), state tracking, rebuild procedure, read-your-writes patterns. |

## Related skills

| Skill | This not that |
|---|---|
| `architecture` | Decide *whether* CQRS is justified (cost/benefit, NFRs). This skill is the *how*. |
| `architecture-patterns` | Where CQRS fits inside an Onion/Clean overlay. |
| `architect-review` | Review of an existing CQRS proposal or implementation for smells (bidirectional projections, missing rebuild, etc.). |
| `ddd-tactical-patterns` | Aggregate design, domain event emission, value objects — the write-side substrate this skill builds on. |
| `api-design-principles` | REST/gRPC contracts for command endpoints (write) and query endpoints (read) — the wire surface that exposes each side. |
| `messaging-rabbitmq-spring` | **This skill handles in-process Modulith events + outbox table**; that skill handles **cross-service delivery via RabbitMQ**. The Modulith outbox can feed a relay → RabbitMQ when crossing service boundaries — design the relay there, the outbox here. |
| `caching-strategies-spring` | The lighter alternative when the read is slow but the shape matches the write. Try this first; CQRS is heavier. |
| `database-design` | The persistence shape underneath both write side (Postgres source of truth) and projection stores (Postgres view / ES / Clickhouse schemas, indexes). |
| `spring-boot-mastery` | Spring Modulith setup itself — applications modules, event_publication configuration, observability. This skill *uses* Modulith events; that one configures Modulith. |

## Limitations
- Patterns assume Kotlin/Spring Boot with Spring Modulith for in-process events. Cross-service projections via Kafka are gestured at, not deeply covered — see `messaging-rabbitmq-spring` for the broker layer.
- The skill covers CQRS *patterns*, not specific Axon Framework / EventStoreDB tooling. Both are mentioned in `overview-and-decisions.md`; hand-rolled with Spring is the default.
- Read-store choice (Postgres view vs ES vs Clickhouse) drives projection shape entirely; if that choice is unclear, stop and resolve it first — usually via `database-design` and `system-design-fundamentals`.
