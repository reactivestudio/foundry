# Spring Modulith — Bounded-Context Enforcement

Spring Modulith is the opinionated counterpart to ArchUnit. It expects your application to be structured as a **modular monolith** — each top-level package under the application root is a **module**, treated as a bounded context — and provides a fitness function (`ApplicationModules.of(...).verify()`) plus a lightweight integration-test harness (`@ApplicationModuleTest`) that boots one module's slice of the Spring context.

> Modulith asks: are the modules talking to each other only through declared public types and events, or has someone reached into another module's internals? `verify()` answers that question on every CI run.

Use Modulith **with** ArchUnit, not instead of it. Modulith enforces module-level structure; ArchUnit enforces everything else (layer rules, naming, anti-patterns, cycles within a module).

## 1. Setup

```kotlin
// build.gradle.kts
dependencies {
    implementation("org.springframework.modulith:spring-modulith-starter-core")
    implementation("org.springframework.modulith:spring-modulith-starter-jpa")  // if using event publication

    testImplementation("org.springframework.modulith:spring-modulith-starter-test")
}
```

Spring Boot's BOM pins compatible Modulith versions; don't override unless you need a feature in a specific Modulith minor.

## 2. Package layout = module structure

Modulith treats **each direct child package** of your application's root package as a module. Public types live at the module root; internal types live in `<module>.internal` (any depth under `internal` is considered private to the module).

```
pro.vlprojects.assista.platform
├── AssistaPlatformApplication.kt
├── orders/
│   ├── OrderId.kt                   // public — exposed to other modules
│   ├── PlaceOrderHandler.kt         // public — exposed
│   ├── events/
│   │   └── OrderPlaced.kt           // public event type
│   └── internal/
│       ├── OrderAggregate.kt        // private — internal use only
│       ├── OrderRepository.kt       // private
│       └── persistence/
│           └── OrderJpaEntity.kt    // private
├── billing/
│   ├── BillingService.kt
│   └── internal/
│       └── InvoiceCalculator.kt
└── inventory/
    ├── InventoryService.kt
    └── internal/
        └── StockRepository.kt
```

Three modules: `orders`, `billing`, `inventory`. The aggregates, repositories, and persistence entities are hidden inside `internal`. Cross-module communication happens only through:

- Public types at the module root (`PlaceOrderHandler`, `BillingService`, …).
- Published events (`OrderPlaced`).

Modulith's `verify()` enforces this. A `BillingService` that injects `OrderRepository` directly (from `orders.internal`) fails the verification.

## 3. The fitness test — `ApplicationModules.of(...).verify()`

```kotlin
import org.springframework.modulith.core.ApplicationModules
import org.springframework.modulith.docs.Documenter

class ModularityTest {

    private val modules = ApplicationModules.of(AssistaPlatformApplication::class.java)

    @Test
    fun `module structure is valid`() {
        modules.verify()
    }

    @Test
    fun `write module documentation`() {
        Documenter(modules)
            .writeDocumentation()
            .writeIndividualModulesAsPlantUml()
    }
}
```

`modules.verify()` enforces:

- No `internal` class is referenced from outside its module.
- Cross-module references are only to declared public types or events.
- The declared module dependency graph (from `@ApplicationModule(allowedDependencies = ...)` if present) matches actual references.
- Cycles between modules are forbidden.

This test runs in **milliseconds**. It must be in CI. A `verify()` failure is the earliest possible signal that the bounded-context boundary has been breached — the alternative is discovering it during a refactor six months later when the modules are tangled.

`Documenter` is gold for onboarding: it generates PlantUML diagrams and AsciiDoc descriptions of the module graph. Run it as part of CI documentation publishing.

## 4. Declaring explicit module dependencies

By default, any module may depend on any other module. To restrict:

```kotlin
// orders/package-info.java  (or Kotlin equivalent via @ApplicationModule on a marker)
@ApplicationModule(allowedDependencies = ["shared"])
package pro.vlprojects.assista.platform.orders;
```

Now the `orders` module may **only** depend on the `shared` module. Any reference to `billing`, `inventory`, etc. fails `verify()`.

Used judiciously, this turns the module graph into a declared topology — much like a service mesh, but inside one JVM.

## 5. `@ApplicationModuleTest` — module-isolated tests

The classic problem: testing a feature in `orders` shouldn't require booting `billing` and `inventory`. `@ApplicationModuleTest` boots only the **current module** (the one containing the test class).

```kotlin
@ApplicationModuleTest
class OrderingModuleTest {

    @Autowired private lateinit var placeOrder: PlaceOrderHandler
    @Autowired private lateinit var events: PublishedEvents

    @Test
    fun `placing an order publishes OrderPlaced`() {
        val cmd = PlaceOrderCommand(
            orderId = OrderId.random(),
            customerId = CustomerId("c-1"),
            lines = listOf(OrderLine(sku = "SKU-1", qty = 2)),
        )

        placeOrder(cmd)

        assertThat(events).hasPublishedEventOfType(OrderPlaced::class.java)
            .matching { it.orderId == cmd.orderId }
    }
}
```

`@ApplicationModuleTest` startup is much faster than `@SpringBootTest` because it only initializes the beans inside the named module. `PublishedEvents` is a Modulith-provided helper that captures all `ApplicationEvent`s published during the test — perfect for asserting "this operation produced the right event".

## 6. Cross-module event flow with `BootstrapMode.DIRECT_DEPENDENCIES`

When you need to test that a published event in one module is correctly consumed in another, bootstrap the current module **plus its declared dependencies**:

```kotlin
@ApplicationModuleTest(mode = ApplicationModuleTest.BootstrapMode.DIRECT_DEPENDENCIES)
class OrderProjectionIntegrationTest {

    @Autowired private lateinit var publisher: ApplicationEventPublisher
    @Autowired private lateinit var projections: OrderDetailViewRepository

    @Test
    fun `OrderPlaced event triggers projection write`() {
        val event = OrderPlaced(
            orderId = OrderId.random(),
            customerId = CustomerId("c-1"),
            placedAt = Instant.parse("2026-05-12T10:00:00Z"),
        )

        publisher.publishEvent(event)

        await().untilAsserted {
            assertThat(projections.findById(event.orderId.value)).isPresent
        }
    }
}
```

Three bootstrap modes:

| Mode | Boots |
|---|---|
| `STANDALONE` (default) | The current module only — fastest. |
| `DIRECT_DEPENDENCIES` | Current module + its directly declared dependencies. |
| `ALL_DEPENDENCIES` | Current module + transitive closure of dependencies. |

Use the narrowest mode the test needs. Most module tests work in `STANDALONE`; event-flow tests typically need `DIRECT_DEPENDENCIES`; `ALL_DEPENDENCIES` is rarely justified — at that point use `@SpringBootTest`.

## 7. `Scenario` API for fluent module tests

Modulith ships a `Scenario` DSL for event-driven module tests. Inject `Scenario` and write the test in terms of "publish an event, then expect this to happen":

```kotlin
@ApplicationModuleTest(mode = ApplicationModuleTest.BootstrapMode.DIRECT_DEPENDENCIES)
class OrderToInvoiceFlowTest {

    @Test
    fun `placing an order eventually creates an invoice`(scenario: Scenario) {
        scenario
            .publish(OrderPlaced(orderId = OrderId.random(), ...))
            .andWaitForEventOfType(InvoiceCreated::class.java)
            .toArriveAndVerify { invoice -> assertThat(invoice.amount).isPositive }
    }
}
```

The `Scenario` API handles the async wait, the `PublishedEvents` capture, and the event-correlation logic. For a complex cross-module flow it's much cleaner than hand-rolled `await().untilAsserted { ... }`.

## 8. Modulith vs ArchUnit — when to use which

| Question | Tool |
|---|---|
| Did someone import `orders.internal.OrderAggregate` from `billing`? | **Modulith** — that's a module-boundary breach. |
| Did someone import `org.springframework.*` from a class in `..domain..`? | **ArchUnit** — generic structural rule. |
| Did someone create a cycle between top-level modules? | **Modulith** (`verify()` checks this) **or ArchUnit** (`slices().beFreeOfCycles()`). Either works; Modulith comes free. |
| Did someone inject a `JpaRepository` into a controller? | **ArchUnit** — anti-pattern detection. |
| Did someone add a cross-module dependency that's not declared in `@ApplicationModule(allowedDependencies = ...)`? | **Modulith** — that's its core job. |
| Did a service class fail to end with `Service`? | **ArchUnit** — naming convention. |

**Use both.** Modulith for module-level structure (the "modular monolith" discipline). ArchUnit for everything finer-grained.

## 9. Documenter — generated module diagrams

```kotlin
@Test
fun `write module documentation`() {
    Documenter(modules)
        .writeDocumentation()                     // overview AsciiDoc
        .writeIndividualModulesAsPlantUml()        // one diagram per module
        .writeAggregatingDocument()                // all modules in one diagram
}
```

Output lands in `target/spring-modulith-docs/` (or configurable). Wire it into CI documentation publishing — a generated module diagram is **truth at the moment of CI**, unlike a hand-drawn diagram that rots.

## 10. Event publication registry — durable cross-module events

For production-grade cross-module communication, Modulith provides a **event publication registry**: events are persisted in a JPA table at publication time and only deleted after the listener consumes them successfully. Crash-safe.

```kotlin
@Configuration
@EnableModulithEventPublication
class ModulithConfig
```

Combined with `@TransactionalEventListener(phase = AFTER_COMMIT)`, this gives a transactional outbox pattern with no extra code. Test the wiring with `@ApplicationModuleTest(mode = DIRECT_DEPENDENCIES)` and `Scenario`.

## 11. A realistic bounded-context example

```
pro.vlprojects.assista.platform/
├── AssistaPlatformApplication.kt
├── shared/
│   ├── Money.kt
│   ├── UserId.kt
│   └── package-info.java   // @ApplicationModule(displayName = "Shared kernel")
├── orders/
│   ├── OrderId.kt                          // public id
│   ├── PlaceOrderHandler.kt                // public command handler
│   ├── PlaceOrderCommand.kt
│   ├── events/
│   │   ├── OrderPlaced.kt                  // public event
│   │   └── OrderCancelled.kt
│   ├── internal/
│   │   ├── Order.kt                        // aggregate
│   │   ├── OrderRepository.kt
│   │   └── persistence/
│   │       ├── OrderJpaEntity.kt
│   │       └── OrderJpaRepository.kt
│   └── package-info.java                   // @ApplicationModule(allowedDependencies = ["shared"])
├── billing/
│   ├── BillingService.kt
│   ├── events/
│   │   └── InvoiceCreated.kt
│   ├── internal/
│   │   ├── Invoice.kt
│   │   ├── OnOrderPlaced.kt                // @TransactionalEventListener
│   │   └── persistence/
│   │       └── InvoiceJpaEntity.kt
│   └── package-info.java                   // @ApplicationModule(allowedDependencies = ["shared", "orders"])
└── inventory/
    ├── InventoryService.kt
    ├── internal/
    │   └── StockLedger.kt
    └── package-info.java                   // @ApplicationModule(allowedDependencies = ["shared"])
```

- `orders` publishes `OrderPlaced` (public event).
- `billing` listens, creates `Invoice`, publishes `InvoiceCreated`.
- `inventory` listens to `OrderPlaced` and decrements stock.
- `billing` and `inventory` do **not** depend on each other — they're choreographed through events on the shared event bus.
- `shared` is the kernel (`Money`, `UserId`, etc.) every module may depend on.

`modules.verify()` enforces all of this. The test runs in ~50ms.

## 12. Anti-patterns

- **`verify()` not in CI.** Modules drift. The whole point is to catch the drift before it lands on `main`. Always run `verify()` in the unit-test phase.
- **Treating `internal` as decoration.** If everything is at the module root and nothing is in `internal`, the bounded context has no encapsulation — Modulith degrades to "ArchUnit with extra setup".
- **Using `@SpringBootTest` where `@ApplicationModuleTest` would do.** Boots the whole context, slow, and defeats the point of having modules. `@ApplicationModuleTest` is the right default for a feature test inside a module.
- **Cross-module synchronous service calls when an event would do.** Calling `billingService.createInvoice()` from `orders` creates a hard dependency. Publishing `OrderPlaced` and letting `billing` react is the decoupled alternative — and is what Modulith optimises for.
- **Mixing module boundaries with layer boundaries.** Modulith modules are **vertical slices** (bounded contexts). Layers (controller / application / domain / infrastructure) are **horizontal slices**. They're orthogonal. A "domain" module that holds all domain code across contexts is not a Modulith module — it's a layer.
- **Skipping `Documenter` integration.** A diagram in PNG that nobody updates is worse than no diagram. Modulith's generated docs stay accurate by construction.
- **Putting public types under `internal` for "convenience".** Then exposing them via getters elsewhere. Either it's public (lives at module root) or it's private (lives under `internal`); there's no in-between.
- **Declaring `allowedDependencies = []` for a module that genuinely needs the shared kernel.** Then carrying around copies of `Money` and `UserId` per module. The shared kernel is a valid module — declare it and depend on it.
- **Adding Modulith on top of a service that has only one bounded context.** It's overhead for nothing. Modulith pays when there are 3+ contexts under one JVM.
