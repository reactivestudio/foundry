# Spring Modulith Deep

Spring Modulith is the bridge between monolith and microservices: bounded contexts within one deployable, enforced at compile/test time.

`assista-platform` is built on this model (per CLAUDE.md). This file covers the depth beyond the basics.

---

## 1. The mental model

A **monolith** has implicit modules — packages, but nothing enforces who can call what.
A **microservices** architecture has explicit modules — separate deployables — but the operational cost is high.
**Spring Modulith** sits between: explicit modules within one deployable.

```
┌──────────────────────────────────────────────────────────┐
│  Spring Boot Application                                  │
├──────────────────────────────────────────────────────────┤
│  ┌────────────┐  ┌────────────┐  ┌────────────┐         │
│  │  module:   │  │  module:   │  │  module:   │         │
│  │  agile     │  │  cicd      │  │  work      │         │
│  ├────────────┤  ├────────────┤  ├────────────┤         │
│  │ - api      │  │ - api      │  │ - api      │         │
│  │ - service  │  │ - service  │  │ - service  │         │
│  │ - domain   │  │ - domain   │  │ - domain   │         │
│  └────┬───────┘  └────┬───────┘  └────┬───────┘         │
│       │ ApplicationEventPublisher    │                   │
│       └──────────────────────────────┘                   │
│                                                           │
│  ┌──────────────────────────────────────────────────┐   │
│  │  contract/  ← Published Language (events, IDs)   │   │
│  └──────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────┘
```

---

## 2. Module definition

A module = top-level package. Spring Modulith treats `com.example.app.order` as a module. Its sub-packages are private to it.

```
com.example.app/
├── App.kt                    (entry point)
├── order/                    ← module: order
│   ├── package-info.java     (or @ApplicationModule in package object)
│   ├── api/                  (exposed to other modules)
│   ├── internal/             (private)
│   └── service/              (private)
├── invoicing/                ← module: invoicing
│   ├── api/
│   └── ...
└── contract/                 ← shared published language
```

By convention:
- `api/` sub-package = the module's public API (services, types other modules can call)
- Other sub-packages = private (Modulith forbids cross-module access)

### Declare explicitly

```kotlin
// in order/package-info.java (or Kotlin via @file:JvmName)
@ApplicationModule(
    displayName = "Order Management",
    allowedDependencies = ["invoicing", "shared"]
)
package com.example.app.order;
```

Without explicit `allowedDependencies`, all sibling modules can be used. Explicit is better.

---

## 3. The exposed-only-via-api rule

```
com.example.app.order/
├── api/
│   ├── OrderService.kt          ← visible to other modules
│   └── PlaceOrderRequest.kt     ← visible
└── internal/
    ├── OrderRepository.kt       ← private (Modulith violation if used from outside)
    └── OrderJpaEntity.kt        ← private
```

If `invoicing/` module's code does `import com.example.app.order.internal.OrderJpaEntity` — `modules.verify()` fails. Compile-time-ish enforcement.

### What goes in `api/`?

- Application services (the use cases other modules invoke)
- Public DTOs / request-response types
- IDs and value objects shared cross-module

What does **not** go in `api/`:
- JPA entities
- Internal repository
- Internal domain model with invariants

---

## 4. Events — the preferred integration

Direct dependency between modules creates coupling. **Events** decouple.

```kotlin
// Module: order — publishes
@Service
class PlaceOrderService(
    private val orders: OrderRepository,
    private val events: ApplicationEventPublisher,
) {
    @Transactional
    fun place(request: PlaceOrderRequest): OrderId {
        val order = Order.create(...)
        orders.save(order)
        events.publishEvent(OrderPlaced(orderId = order.id, customerId = order.customerId, total = order.total))
        return order.id
    }
}

// Event lives in `contract/`
data class OrderPlaced(val orderId: OrderId, val customerId: CustomerId, val total: Money)

// Module: invoicing — subscribes
@Component
class InvoiceCreationListener(private val invoicing: InvoicingService) {
    @ApplicationModuleListener  // async, after order's transaction commits
    fun on(event: OrderPlaced) {
        invoicing.createInvoiceFor(event.orderId, event.customerId, event.total)
    }
}
```

`invoicing/` doesn't import `order/`. Coupling = via the event type. Adding a 3rd consumer of `OrderPlaced` (notifications, analytics) costs nothing in `order/`.

---

## 5. `@ApplicationModuleListener` — the magic annotation

```kotlin
@ApplicationModuleListener
fun on(event: OrderPlaced) { ... }
```

Equivalent to `@TransactionalEventListener(phase = AFTER_COMMIT) + @Async + @Transactional(REQUIRES_NEW)`.

What it gives:
- **After commit** — the publisher's transaction is fully durable before this runs
- **Async** — listener runs in another thread; publisher returns quickly
- **New transaction** — listener does its own DB work in its own tx
- **Outbox** — Spring Modulith records the publication; if listener fails, can be retried

The outbox table is auto-created (`event_publication`). For durable cross-service events to Kafka, pair with a relay.

---

## 6. Architecture verification

```kotlin
class ModularityTest {
    private val modules = ApplicationModules.of(App::class.java)

    @Test
    fun `module structure is valid`() {
        modules.verify()
    }
}
```

This catches at test time:
- Modules using each other's `internal/` packages
- Cyclic dependencies between modules
- Allowed-dependency violations (declared in `@ApplicationModule`)

**Add this test to every Modulith project from day 1.** Without it, the boundaries are aspirational.

---

## 7. Documenter — generate module diagrams

```kotlin
@Test
fun `print module documentation`() {
    Documenter(modules)
        .writeDocumentation()
        .writeIndividualModulesAsPlantUml()
}
```

Outputs:
- `target/spring-modulith-docs/all-modules.puml` — overall module diagram
- `target/spring-modulith-docs/<module>.puml` — per-module diagrams

Use to keep architecture documentation in sync with code automatically.

---

## 8. `@ApplicationModuleTest` — isolated module testing

```kotlin
@ApplicationModuleTest
class OrderModuleTest {

    @Autowired private lateinit var placeOrder: PlaceOrderService
    @Autowired private lateinit var events: PublishedEvents

    @Test
    fun `placing order publishes OrderPlaced`() {
        placeOrder.place(somePlaceRequest())

        assertThat(events).hasPublishedEventOfType(OrderPlaced::class.java)
            .matching { it.customerId == expectedCustomerId }
    }
}
```

Boots only the `order/` module + its declared dependencies — much faster than `@SpringBootTest`.

### Modes

| Mode | What boots |
|---|---|
| `BootstrapMode.STANDALONE` (default) | Just the module + needed beans |
| `BootstrapMode.DIRECT_DEPENDENCIES` | Module + declared module deps |
| `BootstrapMode.ALL_DEPENDENCIES` | Module + transitive deps |

Use `STANDALONE` for unit-like testing of one module; `DIRECT_DEPENDENCIES` for testing event flow between two modules.

---

## 9. Observation API — module-level metrics and tracing

```kotlin
@Configuration
@EnableScheduling
class ModulithObservability {

    @Bean
    fun observationFilter(): ObservationFilter = ObservationFilter { context ->
        // Tag each observation with module name
        ...
    }
}
```

Spring Modulith integrates with Micrometer Observability to emit metrics + traces tagged with the originating module. You can see:
- "Which module is slowest?"
- "Where do cross-module calls happen?"
- "What's the depth of event chains?"

Activate:
```yaml
management:
  modulith:
    events:
      observe: true
```

---

## 10. Common Modulith pitfalls

| Pitfall | Fix |
|---|---|
| Modules sharing entities | Put shared types in `contract/`; never share JPA entities |
| Synchronous cross-module call where event would suffice | Refactor to event listener |
| Big "shared" module that imports everything | Anti-pattern; collapse or split |
| No `modules.verify()` test | Add immediately; rules without enforcement are decoration |
| Modules with all logic in `api/` | Means there's no encapsulation; restructure |
| Events with full entity payload | Events should be facts (IDs + facts), not snapshots |
| Forgetting `kotlin-spring` plugin | Modules' final classes won't get AOP / proxy |

---

## 11. When to extract a module to a service

Modulith is monolith-at-first. Extract when:
- **Team independence** — another team owns this module fully
- **Independent scaling** — the module's load profile differs from rest of app
- **Different stack** — module would benefit from a different language / runtime
- **Operational independence** — different deploy cadence, different SLA

Extract steps:
1. The module's events become published to Kafka (via `event_publication` relay) — `cqrs-implementation` covers
2. The module's `api/` becomes an HTTP/gRPC API
3. Move code to a new service
4. Original app calls via Feign / OpenAPI client
5. Decommission internal API in original

Modulith → microservice migration is straightforward when boundaries were enforced from day 1. Without Modulith verification, the same migration takes 3-5× as long.

---

## 12. Bigger picture — Modulith is DDD operationalised

- Bounded contexts (`ddd-strategic-design`) → Modulith modules
- Context maps (`ddd-context-mapping`) → declared `allowedDependencies` + events
- Published Language → `contract/` package
- Anti-Corruption Layer → adapter module + module-internal translation

If your team takes DDD seriously, Modulith is the tool. If not, Modulith adds rigour even without full DDD adoption.
