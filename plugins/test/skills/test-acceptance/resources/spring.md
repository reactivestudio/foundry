# Spring Patterns for Acceptance Tests

Acceptance tests in a Spring service take one of two shapes:

1. **In-memory-adapter style** — no Spring context at all; the application service is instantiated directly with hand-rolled in-memory adapters. Tests run in milliseconds. Covered in `general.md` / `kotlin.md`.
2. **Narrow `@SpringBootTest` style** — the Spring context boots with real `@MockkBean`-stubbed external HTTP and a real DB via Testcontainers. Tests run in seconds. **This file is about that shape.**

The trick is staying *narrow* — booting the smallest context that exercises the use case, not the full app. The acceptance pyramid for a Spring service typically has 10-30 such tests, not 200.

> "A `@SpringBootTest` that boots in 5 seconds and exercises one use case end-to-end is acceptance. A `@SpringBootTest` that boots in 5 seconds and exercises one repository method is a misplaced slice test." — house ethos

---

## 1. Picking the seam — Spring acceptance test variants

| Variant | Boots | Use for |
|---|---|---|
| `@SpringBootTest(webEnvironment = MOCK)` + MockMvc | Full context, no real HTTP | Use-case tests through the HTTP boundary; idiomatic for REST-fronted services |
| `@SpringBootTest(webEnvironment = RANDOM_PORT)` + WebTestClient | Full context + real Tomcat | True HTTP smoke; rare; reserve for cross-protocol concerns |
| `@ApplicationModuleTest` (Spring Modulith) | One module + declared dependencies | Bounded-context acceptance — narrower than full app, captures cross-aggregate flows inside one context |
| `@SpringBootTest` + `@AutoConfigureWireMock` / WireMock container | Full context + WireMock stubs | Use-case with outbound HTTP integrations stubbed at the wire level |

**Rule of thumb**: prefer `@ApplicationModuleTest` for use cases inside one bounded context (faster, narrower, surfaces module-boundary leaks). Fall back to `@SpringBootTest(MOCK)` for cross-module flows.

---

## 2. The canonical `@SpringBootTest(MOCK)` acceptance test

```kotlin
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.MOCK)
@AutoConfigureMockMvc
@ImportTestcontainers(SharedPostgres::class)
@ActiveProfiles("test")
class SubmitOrderAcceptanceTest {

    @Autowired lateinit var mockMvc: MockMvc
    @Autowired lateinit var jdbc: JdbcTemplate
    @Autowired lateinit var publishedEvents: PublishedEvents       // Spring Modulith
    @MockkBean lateinit var inventory: InventoryApiClient          // stub external

    @BeforeEach
    fun clean() {
        jdbc.execute("TRUNCATE TABLE orders, order_lines, outbox RESTART IDENTITY CASCADE")
    }

    @Test
    fun `submitting a draft order returns 201, persists the order, and publishes OrderSubmitted`() {
        every { inventory.checkAvailability(any()) } returns InventoryStatus.AVAILABLE

        mockMvc.post("/api/v1/orders") {
            contentType = MediaType.APPLICATION_JSON
            content = """{"customerId":"$customerId","lines":[{"sku":"SKU-001","quantity":2}]}"""
        }.andExpect {
            status { isCreated() }
            jsonPath("$.status") { value("SUBMITTED") }
        }

        // DB side-effect
        val rows = jdbc.queryForList("SELECT status FROM orders")
        assertThat(rows).hasSize(1)
        assertThat(rows[0]["status"]).isEqualTo("SUBMITTED")

        // Event side-effect (Spring Modulith)
        assertThat(publishedEvents)
            .hasPublishedEventOfType(OrderSubmitted::class.java)
            .matching { it.lines.size == 1 }
    }
}
```

**What this test verifies in one shot**:
- HTTP routing + validation + JSON deserialisation.
- Application service orchestration.
- Domain aggregate behaviour.
- JPA persistence to real Postgres.
- Domain event emission via `ApplicationEventPublisher`.
- Outbound HTTP collaborator wiring (via stubbed `InventoryApiClient`).

That's six concerns covered in one test. The cost is ~3s boot + ~50ms per test method (with reused context). For 15 use cases, that's ~45s of CI time. Compared to writing 6 separate slice tests for each use case (each booting their own slice), this is a **better** trade — fewer tests, tighter signal.

---

## 3. `@SpringBootTest(RANDOM_PORT)` — when you actually need real HTTP

Reserve `RANDOM_PORT` + `WebTestClient` for:

- Verifying server-port behaviour you can't get from MockMvc (HTTP/2, server-sent events, real `HttpServletRequest` quirks).
- Smoke tests that prove the app boots and `/actuator/health` responds.
- Cross-protocol concerns (HTTPS termination, certificate handling).

For ordinary use-case-through-HTTP tests, **MockMvc beats RANDOM_PORT** — same protocol coverage at ~10× speed.

```kotlin
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@ImportTestcontainers(SharedPostgres::class)
class ApplicationSmokeTest {

    @LocalServerPort var port: Int = 0

    @Test
    fun `actuator health reports UP`() {
        val client = WebTestClient.bindToServer().baseUrl("http://localhost:$port").build()
        client.get().uri("/actuator/health")
            .exchange()
            .expectStatus().isOk
            .expectBody().jsonPath("$.status").isEqualTo("UP")
    }
}
```

One smoke test per service; not a pattern to replicate per use case.

---

## 4. Spring Modulith `@ApplicationModuleTest` — the narrower acceptance seam

For a use case that lives entirely inside one bounded context, `@ApplicationModuleTest` boots **only that module** and its declared dependencies. Much faster than full `@SpringBootTest`; better at catching module-boundary leaks.

```kotlin
@ApplicationModuleTest(mode = ApplicationModuleTest.BootstrapMode.DIRECT_DEPENDENCIES)
class OrderingModuleAcceptanceTest {

    @Autowired lateinit var submitOrder: SubmitOrderUseCase
    @Autowired lateinit var orderQueries: OrderQueryService
    @Autowired lateinit var publishedEvents: PublishedEvents

    @Test
    fun `submitting a draft order persists it and publishes OrderSubmitted`() {
        val outcome = submitOrder.execute(
            SubmitOrderCommand(
                customerId = CustomerId.random(),
                lines = listOf(OrderLineCommand(Sku("SKU-001"), 2)),
            ),
        )

        assertThat(outcome).isSuccess()
        assertThat(orderQueries.findById(outcome.orderId)).isPresent
        assertThat(publishedEvents).hasPublishedEventOfType(OrderSubmitted::class.java)
    }
}
```

**Modes**:
- `STANDALONE` — only this module's beans; cross-module collaborators must be mocked.
- `DIRECT_DEPENDENCIES` — this module + declared dependencies; idiomatic for use-case-level acceptance.
- `ALL_DEPENDENCIES` — transitively pulls in everything; usually too broad.

`DIRECT_DEPENDENCIES` is the sweet spot for acceptance tests inside one context.

---

## 5. Testcontainers + `@ServiceConnection` — the database

Acceptance tests almost always hit a real DB. `@ServiceConnection` (Spring Boot 3.1+) wires the container into Spring's `DataSource` config with zero boilerplate.

```kotlin
@TestConfiguration(proxyBeanMethods = false)
object SharedPostgres {
    @Bean
    @ServiceConnection
    @JvmStatic
    fun postgres(): PostgreSQLContainer<*> =
        PostgreSQLContainer("postgres:16-alpine").withReuse(true)
}
```

Enable container reuse globally in `~/.testcontainers.properties`:

```
testcontainers.reuse.enable=true
```

With reuse, the container starts once per developer / CI runner and is shared across acceptance-test classes. First boot ~3s; subsequent ~50ms lookup.

**Caveat**: `@SpringBootTest` doesn't auto-rollback transactions like `@DataJpaTest` does. Clean up explicitly between tests — see §6.

---

## 6. Cleanup between tests — never auto-rollback at acceptance level

`@Transactional` on an acceptance test **lies** when the use case crosses transaction boundaries (events fired in `AFTER_COMMIT`; outbox writes in `REQUIRES_NEW`; async handlers). The rollback hides bugs.

Use explicit truncation:

```kotlin
@BeforeEach
fun clean() {
    jdbc.execute("TRUNCATE TABLE orders, order_lines, outbox, event_publication RESTART IDENTITY CASCADE")
}
```

Or `@Sql` scripts:

```kotlin
@Test
@Sql(scripts = ["/test-data/clean.sql"], executionPhase = BEFORE_TEST_METHOD)
fun `the use case`() { ... }
```

Truncate is faster (one DDL vs Flyway re-migrate). `RESTART IDENTITY` resets sequences — important for tests that assert on IDs.

For Spring Modulith's outbox, also clean `event_publication`:

```sql
TRUNCATE TABLE event_publication;
```

Otherwise stale events from a previous test trigger handlers in the next test — order-dependent flakiness.

---

## 7. `@MockkBean` for stubbing external HTTP

The acceptance test wires real DB but stubs external systems. Use `@MockkBean` for the outbound HTTP client port:

```kotlin
@MockkBean lateinit var inventory: InventoryApiClient
@MockkBean lateinit var payments: PaymentApiClient

@Test
fun `submitting an order with successful inventory and payment completes`() {
    every { inventory.checkAvailability(any()) } returns InventoryStatus.AVAILABLE
    every { payments.charge(any(), any()) } returns PaymentResult.Settled(reference = "ch_123")

    // ... HTTP request, assertions on DB / events
}
```

**Caveat — context caching**: each unique `@MockkBean` declaration set creates a new Spring context. Spring caches up to ~32 contexts by default; exceed that and contexts churn. Keep the declaration sets consistent across related acceptance tests — typically in a `@TestConfiguration` shared base.

---

## 8. WireMock-as-Testcontainer — when you want wire-level fidelity

For external HTTP integrations where the stub itself is meaningful (request shape, retry behaviour, timeouts), use WireMock as a container:

```kotlin
@Container
val wiremock: GenericContainer<*> = GenericContainer("wiremock/wiremock:latest")
    .withExposedPorts(8080)

@DynamicPropertySource
@JvmStatic
fun props(registry: DynamicPropertyRegistry) {
    registry.add("integrations.inventory.base-url") {
        "http://${wiremock.host}:${wiremock.firstMappedPort}"
    }
}

@Test
fun `the use case retries inventory on 503 and succeeds on second attempt`() {
    wiremock.stubFor(
        get("/inventory/SKU-001").inScenario("retry")
            .whenScenarioStateIs(STARTED)
            .willReturn(serviceUnavailable())
            .willSetStateTo("retried"),
    )
    wiremock.stubFor(
        get("/inventory/SKU-001").inScenario("retry")
            .whenScenarioStateIs("retried")
            .willReturn(okJson("""{"status":"AVAILABLE"}""")),
    )

    mockMvc.post("/api/v1/orders") { /* ... */ }.andExpect { status { isCreated() } }

    wiremock.verify(2, getRequestedFor(urlEqualTo("/inventory/SKU-001")))
}
```

For ordinary stubbing where retries / scenarios don't matter, `@MockkBean` is cheaper.

---

## 9. Asserting on event flow — Spring Modulith `PublishedEvents`

The most under-used acceptance-test assertion: that the right *domain events* were published.

```kotlin
@Test
fun `submitting an order publishes OrderSubmitted with the right ids`() {
    // ... command + assertions on response

    assertThat(publishedEvents)
        .hasPublishedEventOfType(OrderSubmitted::class.java)
        .matching { it.orderId == expectedId && it.lines.size == 1 }
}
```

`PublishedEvents` is provided by `spring-modulith-starter-test`. It captures all `ApplicationEventPublisher` events fired during the test method — including async (`@TransactionalEventListener(AFTER_COMMIT)`) once the transaction commits.

For non-Modulith services, use `ApplicationEvents` (Spring Test):

```kotlin
@RecordApplicationEvents
class AcceptanceTest {
    @Autowired lateinit var events: ApplicationEvents

    @Test
    fun `...`() {
        // ...
        assertThat(events.stream(OrderSubmitted::class.java)).hasSize(1)
    }
}
```

---

## 10. Awaitility for async use cases

Use cases that emit events handled asynchronously (projection updates, outbox flushes) need polling — never `Thread.sleep`.

```kotlin
@Test
fun `submitting an order updates the OrderSearchProjection within 5 seconds`() {
    submitOrder.execute(aSubmitCommand())

    await()
        .atMost(Duration.ofSeconds(5))
        .pollInterval(Duration.ofMillis(100))
        .untilAsserted {
            val projection = projections.findByCustomer(customerId)
            assertThat(projection).hasSize(1)
            assertThat(projection[0].status).isEqualTo("SUBMITTED")
        }
}
```

**Tune `atMost` to twice the expected latency**, not the worst-case. A 30-second timeout for a 100ms expected handler hides bugs (the handler is now slow but the test still passes).

---

## 11. Outside-in TDD with a `@SpringBootTest` acceptance test

The acceptance test drives the implementation:

1. Write the failing `@SpringBootTest` acceptance test. It compiles but fails at "endpoint not found" or "command handler not wired".
2. Drop down to the unit layer: write the failing aggregate test (`Order.submit(...)` invariant). Implement until green.
3. Drop down further: write the failing value-object test (`OrderLine` quantity must be positive). Implement.
4. Climb back up: write the failing application-service test (in-memory adapters). Implement.
5. Climb back up: write the controller (`@WebMvcTest`-driven if you want speed) or rely on the `@SpringBootTest` to drive it. Implement.
6. The acceptance test goes green.

The acceptance test is **the goal**. The unit tests are *how you get there*. See `general.md` for the cross-language framing.

---

## 12. Profiles and test config

A minimal acceptance test profile (`src/test/resources/application-test.yml`):

```yaml
spring:
  jpa:
    properties:
      hibernate:
        jdbc:
          time_zone: UTC
        format_sql: false
  task:
    execution:
      pool:
        core-size: 1                        # deterministic async
features:
  outbox-flush-interval-ms: 100             # faster than prod for tests
integrations:
  inventory:
    timeout: 100ms                          # fail fast in tests
```

**Rule**: the test profile should differ from prod *only where necessary*. Big diffs hide bugs.

`@ActiveProfiles("test")` is sufficient — avoid stacking profiles (`@ActiveProfiles("test", "no-kafka", "fast-retries")` proliferates context combinations and slows CI).

---

## 13. Fixed `Clock` / `IdGenerator` via `@TestConfiguration`

Acceptance tests must be deterministic in time and ID. Wire test beans:

```kotlin
@TestConfiguration
class AcceptanceTestConfiguration {

    @Bean @Primary
    fun clock(): Clock = Clock.fixed(Instant.parse("2026-01-15T10:00:00Z"), UTC)

    @Bean @Primary
    fun idGenerator(): IdGenerator = object : IdGenerator {
        private val seq = AtomicLong(0)
        override fun next(): UUID = UUID(0, seq.incrementAndGet())
    }
}
```

Import in the acceptance test:

```kotlin
@SpringBootTest(...)
@Import(AcceptanceTestConfiguration::class)
class SubmitOrderAcceptanceTest { ... }
```

Now timestamps and IDs in assertions are predictable — including in JSON response bodies.

---

## 14. Per-test context state — `@DirtiesContext` is the LAST resort

If an acceptance test mutates global state (a cached singleton, a bean field), the next test sees the dirty state. **Don't** sprinkle `@DirtiesContext` to "fix" — every use of it forces a full context restart (seconds added to CI per use).

Instead:
- Find the mutated singleton.
- Add a `@BeforeEach reset()` that explicitly clears it.
- Or — refactor the production code so the state is per-request, not per-singleton.

`@DirtiesContext` is appropriate for **one** test in the suite that legitimately tests bean recreation (e.g. a `@ConditionalOnProperty`-driven bean lifecycle). Everywhere else, it's a smell.

---

## 15. The acceptance-test count budget

For a typical Spring service of moderate complexity:

| Layer | Test type | Count | Time |
|---|---|---|---|
| Domain unit | pure JVM | 150 | ~10ms each |
| Slice (`@WebMvcTest` / `@DataJpaTest` / ...) | slice | 50 | ~500ms each |
| **Acceptance** (`@SpringBootTest` narrow or `@ApplicationModuleTest`) | **full or narrow** | **15-30** | **~2-5s each** |
| Smoke (`@SpringBootTest` RANDOM_PORT) | full | 1-3 | ~5-10s each |

Acceptance tests are **scarce**. Each one earns its place by exercising a *complete use case end-to-end through the right boundary*. If the count creeps above 50, the layer is being used for things that belong in slices or unit tests — audit.

---

## 16. Anti-patterns specific to Spring acceptance tests

- **`@SpringBootTest` everywhere** — most of those should be slices. Audit.
- **`@Transactional` on the acceptance test** — masks events / outbox / async handlers. Use explicit truncation.
- **One mega-test that asserts on six different concerns** — split per-concern; reuse the context (it's cached).
- **`@DirtiesContext` sprinkled** — find the leak, fix the production code.
- **Acceptance test that calls a real third party** — `@MockkBean` or WireMock; never a real network call.
- **Acceptance test driven by a real cron / scheduler** — disable `@EnableScheduling` in test profile; trigger the operation directly.
- **Acceptance test reading log lines for assertions** — use `OutputCaptureExtension` *only* if logs are a contract; otherwise assert on observable state.
- **Acceptance test waiting on a hardcoded `Thread.sleep`** — replace with Awaitility against a real condition.
- **Per-test fresh container** — defeats container reuse; use a singleton or `@ImportTestcontainers`.

---

## 17. Cross-references

- See `test-integration` for slice-level Spring testing (`@WebMvcTest`, `@DataJpaTest`, `@RestClientTest`).
- See `test-contract` for cross-service compatibility (Pact, Spring Cloud Contract).
- See `test-architecture` for the `ApplicationModules.of(...).verify()` fitness test (different from `@ApplicationModuleTest`).
- See `cqrs-implementation` for the projection-side acceptance patterns (write side acceptance + read side projection update verified together).
- See `spring-boot-mastery` and `spring-bean` for the bean-lifecycle concerns that make `@TestConfiguration` work.

---

## Summary

- Acceptance test = one use case end-to-end through the application service boundary. Real DB via Testcontainers. External HTTP stubbed.
- Prefer `@ApplicationModuleTest` for inside-one-context flows; `@SpringBootTest(MOCK)` + MockMvc for cross-module / HTTP-fronted.
- Reserve `RANDOM_PORT` + `WebTestClient` for true HTTP smoke; one or two per service.
- No `@Transactional` rollback — truncate explicitly.
- Fix `Clock` / `IdGenerator` via `@TestConfiguration` for determinism.
- Assert on **state + emitted events**. `PublishedEvents` (Modulith) or `ApplicationEvents` (Spring Test).
- Use Awaitility for async; never `Thread.sleep`.
- Acceptance count is small (15-30 for moderate services). Each one earns its place.
- The acceptance test drives outside-in TDD; unit tests are *how you get there*, the acceptance test is *whether you got there*.
