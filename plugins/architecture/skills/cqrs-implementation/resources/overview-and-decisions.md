# CQRS Overview and Decisions

Decision tree, integration with existing architecture, stack mapping. Read this **before** writing any commands or queries.

---

## 1. CQRS vs CRUD vs Event Sourcing

Three related-but-distinct ideas. Don't conflate.

| | CRUD | CQRS | CQRS + Event Sourcing |
|---|---|---|---|
| Source of truth | Current state in DB | Current state in DB | Event log |
| Reads | Same model as writes | Separate read model | Separate read model, rebuilt from events |
| Writes | Mutate the row | Mutate aggregate + emit events | Append events; aggregate state derived |
| When | Simple domains | Read/write diverge in shape or scale | Audit, temporal queries, complex domain |
| Cost | Lowest | Medium (projection plumbing) | Highest (event store, schema evolution, snapshots) |

**Default position:** CRUD. Move to CQRS when reads and writes genuinely diverge. Move to event sourcing only when temporal queries or full audit are genuine requirements.

This skill covers **CQRS, optionally with events used for projections** — not full event sourcing.

---

## 2. Decision tree — should I apply CQRS to this feature?

```
Is the read shape fundamentally different from the write shape?
├── No  → CRUD. Stop. 
└── Yes
    │
    Is the slow read just a missing index or N+1?
    ├── Yes → Fix the query first. Re-evaluate.
    └── No
        │
        Will a read replica solve it?
        ├── Yes → Read replica is simpler than CQRS. Use that.
        └── No
            │
            Do you need search, analytics, or denormalised joins
            that don't fit Postgres / your primary store?
            ├── No  → Postgres materialised view first. Re-evaluate.
            └── Yes → CQRS earns its keep. Proceed.
```

Common false positives:
- "Our list endpoint is slow" — almost always an index or pagination problem, not a CQRS problem.
- "We need to search users by anything" — Elasticsearch is the answer; CQRS is how you keep ES in sync, but the trigger is the search requirement, not CQRS itself.
- "We want microservices" — CQRS is orthogonal to microservices. Don't bundle.

---

## 3. Hand-rolled vs Axon Framework

Two roads.

### Hand-rolled (Spring DI + Modulith events) — default

```
Pros:
- Stays close to vanilla Spring; no extra framework
- Integrates with Spring Modulith you already use
- Easy to read; team understands it
- Easy to incrementally add — one bounded context at a time

Cons:
- You build the patterns; small amount of boilerplate per command/query
- No built-in snapshotting, replay, or event store
- Coordinating projection rebuild is your problem
```

### Axon Framework

```
Pros:
- Full CQRS + event sourcing platform out of the box
- Snapshots, sagas, command routing, event store
- Production-tested

Cons:
- Big framework commitment; ties your domain to Axon abstractions
- Heavy compared to "just a few sealed classes + handlers"
- Axon Server (event store) is an operational dependency
- Learning curve for the team
```

### Recommendation

Hand-rolled by default. Reach for Axon only if:
- You're going full event sourcing (not just CQRS), AND
- You need its built-in saga / process manager / snapshotting features, AND
- The team is willing to take on the framework dependency.

For the polyglot-persistence + Modulith stack assumed here, hand-rolled wins on practically every axis. The rest of this skill assumes hand-rolled.

---

## 4. Integration with Onion / Clean / DDD

CQRS overlays on top of your existing layered architecture. It doesn't replace it.

```
┌──────────────────────────────────────────────────────────────┐
│ HTTP / gRPC layer                                            │
│ ┌─────────────────────────┐  ┌─────────────────────────────┐ │
│ │ Command controller      │  │ Query controller            │ │
│ │ POST /orders            │  │ GET  /orders/{id}           │ │
│ └────────────┬────────────┘  └──────────────┬──────────────┘ │
└──────────────┼──────────────────────────────┼────────────────┘
               ▼                              ▼
   ┌───────────────────────┐      ┌────────────────────────┐
   │ Application — write   │      │ Application — read     │
   │ command handlers      │      │ query handlers         │
   └──────────┬────────────┘      └────────────┬───────────┘
              ▼                                ▼
   ┌───────────────────────┐      ┌────────────────────────┐
   │ Domain — aggregates,  │      │ (no domain layer; read │
   │ invariants, events    │      │ models are flat data)  │
   └──────────┬────────────┘      └────────────┬───────────┘
              ▼                                ▼
   ┌───────────────────────┐      ┌────────────────────────┐
   │ Infrastructure        │      │ Infrastructure         │
   │ Postgres (write)      │      │ ES / CH / PG view      │
   │ Event publisher       │◀═════╝ (projection target)   │
   └──────────┬────────────┘      └────────────────────────┘
              │ events
              ▼
   ┌───────────────────────┐
   │ Projection handler    │── writes ──▶ Read infrastructure
   │ @ApplicationModule-   │
   │ Listener              │
   └───────────────────────┘
```

Key rules:

- **Write side keeps its domain layer.** Aggregates, value objects, invariants live in `domain/`. No change from your Onion / Clean setup.
- **Read side has no domain layer.** Read models are flat data classes. There's no business logic; queries just return projections.
- **Projection handlers live on the boundary** between write infrastructure (events) and read infrastructure (projection store). Treat them as adapters.
- **Events are the contract** between the two sides. Treat them with the same discipline as a public API — version carefully, never break.

---

## 5. Stack mapping for polyglot persistence

| Read shape | Store | When |
|---|---|---|
| **Denormalised Postgres view** | Same Postgres, materialised view or denormalised table | Simple joins still in SQL territory; same transactional store |
| **Elasticsearch index** | ES cluster | Full-text search, faceted filters, geo queries, "search by anything" |
| **Clickhouse table** | CH cluster | Time-series aggregations, dashboards, analytical rollups (sum, count, percentiles over millions of rows) |
| **Redis structure** | Redis | Leaderboards, counters, hot lookups by a single key |
| **MongoDB collection** | Mongo | Documents with variable schema, large blob payloads tied to entities |

Projection handler picks the right store per query type. **One aggregate can feed multiple projections** in different stores — that's the point of CQRS.

Example for an `Order` aggregate:

- `order_detail_view` in Postgres (single-record reads with joined customer info)
- `orders_search_index` in Elasticsearch (multi-field search)
- `daily_order_stats` in Clickhouse (analytics rollups)

Three projections, one source of truth, one set of domain events.

---

## 6. Spring Modulith as the projection mechanism

Spring Modulith provides:

1. **`ApplicationEventPublisher`** — publish from the aggregate's `@Service` after commit.
2. **`@ApplicationModuleListener`** — annotation-based listener that runs **asynchronously after the publishing transaction commits**. This is the right hook for projections.
3. **`event_publication` table** — built-in outbox. Modulith writes each event to this table before delivery; if delivery fails, you can replay. This is your durability guarantee for in-process projections.

Pseudocode:

```kotlin
// Write side
@Service
class PlaceOrder(
    private val orders: OrderRepository,
    private val events: ApplicationEventPublisher,
) {
    @Transactional
    operator fun invoke(cmd: PlaceOrderCommand): OrderId {
        val order = Order.create(cmd)
        orders.save(order)
        events.publishEvent(OrderPlaced(order.id, order.customerId, order.total))
        return order.id
    }
}

// Read side
@Component
class OrderSearchProjection(private val es: OrderSearchRepository) {
    @ApplicationModuleListener
    fun on(event: OrderPlaced) {
        es.save(OrderSearchDoc.fromEvent(event))
    }
}
```

That's the entire glue. The skill's other files go deeper into command shape, handler patterns, projection state tracking, and rebuild.

---

## 7. Costs and tradeoffs

CQRS is not free. Before adopting, account for:

| Cost | Mitigation |
|---|---|
| **Projection lag** — reads are eventually consistent | Read-your-writes hint (see `read-side-patterns.md`); UI loading states |
| **Schema evolution across two stores** — write side and projection schemas drift | Event versioning; treat events as public API |
| **Projection rebuild on schema change** — adding a field requires reprojecting all events | Stream-from-zero capability; checkpointing (see `read-side-patterns.md`) |
| **Doubled storage cost** — same data in 2-3 stores | Accept it; the search/analytics use case wouldn't be possible otherwise |
| **More moving parts** — extra deploy targets, projection lag monitoring | Spring Boot Actuator metrics on lag; alerts on stalled projections |

If the team can't afford these costs, stay CRUD.

---

## 8. When NOT to apply CQRS (re-emphasis)

- The read endpoint is slow → look at indexes / N+1 first.
- The team is small → fewer moving parts wins.
- Strong consistency is required → projections introduce lag.
- The aggregate has a single canonical query shape → one model is fine.
- You're attracted to CQRS because it sounds advanced → that's not a requirement.

If you nod yes to any of those, stop. CQRS is a specific tool for a specific shape of problem.
