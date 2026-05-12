# Integration Testing — Kotlin Tooling

Kotlin-side tooling for the integration tier — Awaitility Kotlin DSL, AssertJ idioms, WireMock Kotlin, MockK at the boundary, Testcontainers `companion object` patterns, fixture factories with real IDs / FKs, brief Kotest `Spec` mention. Spring-specific patterns live in `spring.md`; the language-agnostic discipline in `general.md`.

---

## 1. Awaitility Kotlin DSL — the async assertion idiom

Plain Awaitility is Java-fluent; Kotlin wrappers make it read closer to a regular test assertion.

### Plain Awaitility

```kotlin
await()
    .atMost(Duration.ofSeconds(5))
    .pollInterval(Duration.ofMillis(100))
    .untilAsserted {
        val projection = projections.findByOrderId(orderId)
        assertThat(projection).isNotNull
        assertThat(projection!!.status).isEqualTo("PLACED")
    }
```

Functional, but reads with Java-fluent noise.

### Awaitility Kotlin extension (`awaitility-kotlin`)

```kotlin
await atMost Duration.ofSeconds(5) untilAsserted {
    val projection = projections.findByOrderId(orderId)
    assertThat(projection).isNotNull
    assertThat(projection!!.status).isEqualTo("PLACED")
}
```

Add the dependency:

```kotlin
testImplementation("org.awaitility:awaitility-kotlin:4.2.2")
```

### Patterns

- **Always specify `atMost`.** No default; a missing timeout is an infinite hang on CI.
- **Polling interval ≈ 1/10 of `atMost`.** 100ms poll for 5s timeout — tight enough to be quick on success, loose enough to not hammer the DB.
- **Idempotent body.** `untilAsserted` runs the lambda repeatedly; no state mutation inside.
- **Until null vs untilAsserted.** Use `untilNotNull { repo.findById(id) }` for "wait for it to exist"; use `untilAsserted` when the assertion has structure.

### Common shapes

```kotlin
// Wait for value to be non-null
val projection = await atMost Duration.ofSeconds(5) untilCallTo {
    projections.findByOrderId(orderId)
} matches { it != null }

// Wait for a specific predicate
await atMost Duration.ofSeconds(5) until {
    queue.size > 0
}

// Wait for an assertion to hold
await atMost Duration.ofSeconds(5) untilAsserted {
    assertThat(consumer.received()).hasSize(1)
}
```

### Anti-patterns

- `Thread.sleep(500)` — banned. Always Awaitility.
- `atMost(60.seconds)` — far too long; if your event takes 60s, something is wrong.
- `pollInterval(10.milliseconds)` — too tight; hammers the DB and the CPU.
- Awaitility without `atMost` — infinite hang potential.

---

## 2. AssertJ for response / result assertions

AssertJ is the dominant assertion library on the JVM and the house default. For integration tests, the chainable assertions over collections / responses / JSON pay off heavily.

### Collections

```kotlin
assertThat(orders).hasSize(3)
    .extracting<UUID> { it.id }
    .containsExactly(newer.id, middle.id, older.id)

assertThat(orders)
    .extracting<String> { it.status }
    .containsOnly("DRAFT", "SUBMITTED")

assertThat(orders)
    .filteredOn { it.status == "SUBMITTED" }
    .hasSize(2)
    .first()
    .satisfies({ assertThat(it.total).isGreaterThan(BigDecimal.ZERO) })
```

### `extracting` for type-safe field projection

```kotlin
assertThat(events)
    .extracting<UUID> { it.orderId }
    .containsExactlyInAnyOrder(orderId1, orderId2)

assertThat(orders)
    .extracting<UUID, String, OrderStatus> { Tuple.tuple(it.id, it.customer, it.status) }
    .containsExactly(
        Tuple.tuple(id1, "Ada", OrderStatus.SUBMITTED),
        Tuple.tuple(id2, "Bea", OrderStatus.DRAFT),
    )
```

### `usingRecursiveComparison` for deep equality

When the entity / DTO has many fields and you want field-by-field comparison without writing a custom `equals`:

```kotlin
assertThat(reloaded)
    .usingRecursiveComparison()
    .ignoringFields("id", "createdAt", "version")
    .isEqualTo(expected)
```

`ignoringFields` is the workhorse — ignore generated IDs, timestamps, optimistic-lock versions. Pair with `ignoringFieldsMatchingRegexes` for patterns (`"\\.audit.*"`).

### JSON assertions (with `assertj-core` + JsonPath)

```kotlin
assertThat(responseBody).hasJsonPath("$.id")
assertThat(responseBody).extractingJsonPathStringValue("$.status").isEqualTo("PLACED")
assertThat(responseBody).extractingJsonPathNumberValue("$.total.amountMinor").isEqualTo(15000)
```

For Spring `@JsonTest`, use `JacksonTester<T>` and `JsonContent` (built on top of AssertJ).

### Anti-patterns

- `assertEquals(expected, actual)` — JUnit 5 ships them but AssertJ is the house default; mixing in plain JUnit asserts is style drift.
- `assertThat(foo).isNotNull; assertThat(foo!!.bar)...` — use `satisfies` or chained `extracting`:
  ```kotlin
  assertThat(foo).isNotNull.satisfies({ assertThat(it.bar).isEqualTo("x") })
  ```
- Soft assertions (`assertSoftly`) for things that should fail-fast — soft assertions are for cases where the test legitimately checks multiple facets of a single outcome and you want to see all failures at once. Use them sparingly.

---

## 3. WireMock Kotlin idioms

WireMock is the JVM standard for HTTP stubbing. Used in two flavours: inline (`WireMockExtension`) and Testcontainer (for end-to-end-style outbound integrations).

### Inline (`WireMockExtension`) — for `@RestClientTest` and similar

```kotlin
class InventoryClientTest {

    companion object {
        @RegisterExtension
        @JvmStatic
        val wireMock: WireMockExtension = WireMockExtension.newInstance()
            .options(wireMockConfig().dynamicPort())
            .build()
    }

    @Test
    fun `availability lookup`() {
        wireMock.stubFor(
            get(urlPathEqualTo("/inventory/SKU-001/availability"))
                .willReturn(okJson("""{"available": 12}"""))
        )

        val client = InventoryClient(baseUrl = wireMock.baseUrl())
        val result = client.checkAvailability(Sku("SKU-001"))

        assertThat(result.available).isEqualTo(12)
        wireMock.verify(getRequestedFor(urlPathEqualTo("/inventory/SKU-001/availability")))
    }
}
```

### Kotlin helper extensions

A house DSL trims the noise:

```kotlin
fun WireMockExtension.stubGet(path: String, body: String, status: Int = 200) {
    stubFor(get(urlPathEqualTo(path)).willReturn(
        aResponse().withStatus(status).withHeader("Content-Type", "application/json").withBody(body)
    ))
}

fun WireMockExtension.expectGetCalled(path: String) {
    verify(getRequestedFor(urlPathEqualTo(path)))
}
```

Used:

```kotlin
wireMock.stubGet("/inventory/SKU-001/availability", """{"available": 12}""")
// ... test code ...
wireMock.expectGetCalled("/inventory/SKU-001/availability")
```

Each project tends to grow ~10 such helpers; keep them in one `test/kotlin/.../WireMockExtensions.kt`.

### Testcontainer flavour — see `spring.md` §11

For full-context tests, a `wiremock/wiremock:latest` Testcontainer plays the role of an external HTTP API. The production code is wired to point at it via a `@DynamicPropertySource`-provided URL.

### Anti-patterns

- WireMock without `verify(...)` — the stub responds, but you never assert that the call was made → tests pass if the production code skipped the call entirely.
- Stubbing too loosely (`urlPathMatching(".*")`) — masks bugs where the production code calls the wrong path.
- Stubbing in `@BeforeEach` and never resetting — stubs from a prior test bleed into the next. `wireMock.resetAll()` in `@AfterEach`, or use `WireMockExtension` with default `failOnUnmatchedRequests = true`.
- A test that doesn't fail if WireMock isn't running — usually means the production code silently swallows the connection refused. Diagnose; fix the code.

---

## 4. MockK at the boundary — when used in slice tests

In integration tests, MockK isn't the primary tool — the **point** of integration testing is to use real infrastructure. But at certain boundaries, mocking is the right call:

- A `@WebMvcTest` mocks the application service / use case (the seam below the controller).
- A `@DataJpaTest` doesn't mock anything (the seam under test is the repository → DB; no class above is loaded).
- A `@RestClientTest` mocks nothing inside Spring (the stub is the WireMock / `MockRestServiceServer`).
- A full `@SpringBootTest` may mock external collaborators that you cannot easily Testcontainerise (a payment provider; an SMS gateway).

### `@MockkBean` (from `com.ninja-squad:springmockk`) — Spring + MockK

```kotlin
@WebMvcTest(OrderController::class)
class OrderControllerTest {
    @Autowired private lateinit var mvc: MockMvc
    @MockkBean private lateinit var placeOrder: PlaceOrderHandler

    @Test
    fun `POST orders returns 201`() {
        every { placeOrder(any()) } returns expectedId
        // ... mockMvc.post(...) ...
    }
}
```

Caveats specific to MockK + slices:

- **`relaxed = true`** is rarely the right default in slice tests — you want every interaction to be explicitly stubbed, so unexpected paths fail loudly.
- **`@MockkBean` and `@MockBean` are not mix-and-match** — pick one project-wide.
- **`every { ... } returns ...` runs before `mockMvc.post(...)`** — the Given block goes first, as always (BUILD-OPERATE-CHECK).
- **`coEvery` for `suspend` functions** — MockK supports `suspend` natively, unlike Mockito.

For full coverage of `@MockkBean` vs `@MockBean` see `spring.md` §13.

---

## 5. Testcontainers Kotlin patterns

Kotlin idioms make Testcontainers setup terse.

### Singleton container — `companion object` + `@Container` + `@JvmStatic`

```kotlin
abstract class AbstractPostgresIntegrationTest {

    companion object {
        @JvmStatic
        @Container
        @ServiceConnection
        val postgres: PostgreSQLContainer<*> = PostgreSQLContainer("postgres:16-alpine")
            .withReuse(true)
            .apply { start() }
    }
}

@SpringBootTest
@Testcontainers
class OrderServiceIntegrationTest : AbstractPostgresIntegrationTest() {
    @Autowired private lateinit var orderService: OrderService

    @Test
    fun `places order, persists to Postgres`() { /* ... */ }
}
```

Key points:

- `companion object` — Java-static equivalent; required for `@Container` lifecycle.
- `@JvmStatic` — Spring's `@DynamicPropertySource` / Testcontainers reflection looks up Java-static fields.
- `@Container` — registers the lifecycle with `@Testcontainers` (start before tests, stop after).
- `@ServiceConnection` — Spring Boot 3.1+ auto-wires the container into Spring properties (no `@DynamicPropertySource` needed for standard datasources).
- `.withReuse(true)` — only effective if `~/.testcontainers.properties: testcontainers.reuse.enable=true` is set globally.
- `.apply { start() }` — starts the container explicitly; combined with `@Container`, the JUnit lifecycle handles stop.

### `@ImportTestcontainers` (Spring Boot 3.1+) — shared containers as test config

Define the containers in a separate object / class:

```kotlin
@TestConfiguration
class SharedContainers {
    companion object {
        @Container
        @ServiceConnection
        val postgres: PostgreSQLContainer<*> = PostgreSQLContainer("postgres:16-alpine")
            .withReuse(true)

        @Container
        @ServiceConnection
        val kafka: KafkaContainer = KafkaContainer(DockerImageName.parse("confluentinc/cp-kafka:7.5.0"))
            .withReuse(true)
    }
}
```

Then in test classes:

```kotlin
@SpringBootTest
@ImportTestcontainers(SharedContainers::class)
class OrderEndToEndTest { /* ... */ }
```

Much cleaner than a base-class hierarchy when many test classes need the same containers.

### `companion object` vs top-level `object` containers

A top-level `object SharedPostgres { @Container ... }` works in Kotlin but requires `@ImportTestcontainers` or manual property registration. A `companion object` on an abstract base class is the simpler pattern when you don't already use Spring Boot 3.1+.

### Anti-patterns

- `@Container val container = ...` (instance field) — starts a new container per test instance. Use `@JvmStatic` in `companion object`.
- `lateinit var container: PostgreSQLContainer<*>` then start manually — works but error-prone; rely on `@Container` + `@Testcontainers`.
- One container per test class without reuse — slow. Use the shared base / `@ImportTestcontainers` + `.withReuse(true)` + global reuse flag.
- Skipping `.withReuse(true)` and wondering why CI is slow on developer machines — the global flag does nothing without per-container opt-in.

---

## 6. Object-mother / fixture factories for integration data

Integration-tier fixtures are not unit-tier fixtures. Differences:

| Concern | Unit fixture | Integration fixture |
|---|---|---|
| IDs | Often `null` (entity not yet persisted) or hardcoded UUIDs | Generated UUIDs or DB-generated (`null` on the entity, set after `persist`) |
| Timestamps | Pinned for assertion (fixed `Clock`) | Real `Instant.now()` for transient data; pinned for assert-on-value tests |
| FKs | Whatever — unit code doesn't dereference | Real, FK-constraint-satisfying — the DB will reject otherwise |
| Persistence | Fixture builder returns the object; test consumes it | Fixture builder persists it (via `TestEntityManager` or a repository) |
| Composition | One entity at a time | Often a graph: customer + addresses + orders + lines |

### Builder pattern

```kotlin
fun anOrderEntity(
    id: UUID? = null,
    customerId: UUID = UUID.randomUUID(),
    status: OrderStatus = OrderStatus.DRAFT,
    total: Money = Money(10000, "EUR"),
    createdAt: Instant = Instant.parse("2026-01-01T00:00:00Z"),
) = OrderEntity(
    id = id,
    customerId = customerId,
    status = status,
    total = total,
    createdAt = createdAt,
)
```

Use:

```kotlin
val order = em.persist(anOrderEntity(customerId = ada.id, status = OrderStatus.SUBMITTED))
```

### Graph builder

```kotlin
fun givenCustomerWithOrders(
    em: TestEntityManager,
    customerName: String = "Ada",
    orderCount: Int = 3,
): CustomerWithOrders {
    val customer = em.persist(aCustomerEntity(name = customerName))
    val orders = (1..orderCount).map {
        em.persist(anOrderEntity(customerId = customer.id, createdAt = Instant.now().minusSeconds(60L * it)))
    }
    em.flush()
    return CustomerWithOrders(customer, orders)
}
```

The returned data class is the "given" handle the test asserts against.

### Sharing builders across test classes

Put builders in `src/test/kotlin/.../fixtures/Fixtures.kt`. Top-level `fun`s, not methods on a `TestKit` class — Kotlin's top-level functions are the lightweight idiom. One file per aggregate; no inheritance.

### When the builder isn't enough — `@Sql` fixtures

For scenarios shared by ≥3 tests where the data is large and unchanging (e.g., "a customer with 50 historical orders for the reporting test"), an `@Sql("/fixtures/customer-with-50-orders.sql")` script is more honest than a 50-line builder call. See `spring.md` §18.

### Anti-patterns

- Builder that takes 12 positional parameters → unreadable call sites. Use named arguments with defaults.
- Builder that allocates DB resources eagerly (`val ada = anCustomerEntity()` as a top-level `val`) — shared mutable state across tests.
- Builders that depend on each other transitively, hidden through class hierarchy → debug nightmare. Keep builders flat: each builder takes its FKs as parameters.
- Persisting inside the builder + returning the persisted entity, with the test then mutating it → confusing ownership. Either the builder persists *and* returns the persisted handle (the test treats it as read-only), or the builder constructs and the test persists (explicit). Pick one per project.

---

## 7. Kotest `Spec` for integration-flavoured tests

Kotest is the alternative test framework on the JVM (vs JUnit Jupiter). Spring + Kotest integration works, but is **rare in practice** — most Spring services standardise on JUnit Jupiter because the slice annotations (`@WebMvcTest`, `@DataJpaTest`) are JUnit-centric.

Brief mention for completeness:

```kotlin
@SpringBootTest
@Testcontainers
class OrderRepositorySpec(
    private val orders: OrderRepository,
) : BehaviorSpec({

    given("a saved order") {
        val order = orders.save(anOrderEntity())

        `when`("looked up by id") {
            val found = orders.findById(order.id).orElseThrow()
            then("it returns the order") {
                found.id shouldBe order.id
            }
        }
    }
})
```

**House rule**: if the project uses JUnit Jupiter, conform; do not introduce Kotest into a slice that doesn't already use it. Mixing frameworks fragments the suite and confuses the test runner config. The integration-tier annotations (`@WebMvcTest`, `@DataJpaTest`, `@Testcontainers`) are JUnit-centric — Kotest support is possible but secondary.

When Kotest works well for integration tests:

- The project already uses Kotest project-wide.
- The integration test is full-context (`@SpringBootTest`) — slice annotations have less Kotest tooling.
- The `BehaviorSpec` / `DescribeSpec` style suits the team's BDD preference.

When it doesn't:

- Mixed JUnit + Kotest suite — pick one.
- Slice-heavy testing — JUnit Jupiter is the path of least resistance.

For deeper Kotest content see `test-unit` resources/kotlin.md.

---

## 8. Kotlin coroutines in integration tests

When the production code uses `suspend` functions or `Flow`s, integration tests must drive them with `runTest` (kotlinx-coroutines-test) or `runBlocking`.

### `runTest` for `suspend` tests

```kotlin
@Test
fun `processes orders concurrently`() = runTest {
    val orderIds = (1..10).map { UUID.randomUUID() }
    orderIds.map { async { processor.process(it) } }.awaitAll()

    assertThat(orderProjections.findAll()).hasSize(10)
}
```

### `coEvery` for suspending mocks

```kotlin
@MockkBean private lateinit var paymentClient: PaymentClient

@Test
fun `submits order with payment`() = runTest {
    coEvery { paymentClient.charge(any()) } returns PaymentResult.success(txId)
    // ...
}
```

### Awaitility inside `runTest`

Awaitility blocks (uses `Thread.sleep` internally between polls). Inside `runTest`, this is fine — Awaitility runs on the test thread, polling against the actual DB. The virtual-time semantics of `runTest` don't conflict because the DB / container is on real time.

---

## 9. Dependency set — Kotlin-specific extras

```kotlin
dependencies {
    // AssertJ (house default)
    testImplementation("org.assertj:assertj-core:3.26.3")

    // Awaitility + Kotlin DSL
    testImplementation("org.awaitility:awaitility:4.2.2")
    testImplementation("org.awaitility:awaitility-kotlin:4.2.2")

    // MockK + Spring integration
    testImplementation("io.mockk:mockk:1.13.13")
    testImplementation("com.ninja-squad:springmockk:4.0.2")

    // WireMock
    testImplementation("org.wiremock:wiremock-standalone:3.9.2")

    // Testcontainers (see spring.md for module-specific deps)
    testImplementation("org.testcontainers:junit-jupiter:1.20.4")

    // kotlinx-coroutines-test (if using suspend functions)
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.9.0")
}
```

Version notes:
- Pin versions in `gradle/libs.versions.toml` or equivalent; don't use `+`/`latest` (reproducibility).
- Mockk + springmockk versions must be compatible — check the springmockk release notes for the supported MockK version.

---

## 10. Smell → fix (Kotlin-specific)

| Smell | Fix |
|---|---|
| Awaitility used without Kotlin extension — Java-fluent in Kotlin file | Add `awaitility-kotlin`, switch to `await atMost ... untilAsserted { ... }` |
| `Thread.sleep(N)` in a coroutine test | `delay(N)` or Awaitility; sleep blocks the event loop |
| `@MockBean lateinit var x: ...` in a Kotlin project that otherwise uses MockK | Switch to `@MockkBean`; consistency over micro-correctness |
| Builder with 10 positional params | Named arguments with defaults; one-line at the call site |
| Top-level `object Container { @Container val pg = ... }` not picked up by Spring | Use `companion object` on a base class, or `@ImportTestcontainers` |
| Kotest `BehaviorSpec` in a project that's 95% JUnit Jupiter | Convert to `@Test` — consistency wins |
| `assertThat(foo!!.bar)` after a null check | `assertThat(foo).isNotNull.satisfies({ ... })` |
| Long chain of `usingRecursiveComparison().ignoringFields(...)` repeated across tests | Extract a custom AssertJ assertion class or a Kotlin extension `fun OrderAssert.matchesIgnoringIds(...)` |

---

## 11. Summary — Kotlin idioms for the integration tier

- **Awaitility-kotlin** for any async assertion. Never `Thread.sleep`.
- **AssertJ** with `extracting`, `usingRecursiveComparison`, `satisfies` — the chainable API matches Kotlin's preference for trailing-lambda DSL.
- **WireMock** with thin Kotlin extensions for the common stubs.
- **MockK + springmockk** for boundary mocking inside slices; `relaxed = false` by default.
- **`companion object` + `@JvmStatic` + `@Container` + `@ServiceConnection`** for the singleton container pattern. `.withReuse(true)` paired with the global flag.
- **`@ImportTestcontainers`** for sharing containers across test classes (Spring Boot 3.1+).
- **Fixture builders** as top-level functions with named-defaulted parameters; one file per aggregate; persist inside or persist outside, but **pick one rule per project**.
- **Kotest is the alternative**, not the default; conform to the project's standard.

For Spring-specific patterns (`@WebMvcTest`, `@DataJpaTest`, transactional traps, `@ServiceConnection`) see `spring.md`. For the language-agnostic discipline (deployment seam, real-infrastructure, isolation) see `general.md`.
