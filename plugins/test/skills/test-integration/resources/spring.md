# Integration Testing — Spring Tooling

The largest file in this skill — Spring is where the integration tier lives. The slice catalogue in depth, `@SpringBootTest` when (and only when), `@ServiceConnection` vs `@DynamicPropertySource`, Testcontainers + Spring for each store, container reuse, `@MockkBean` vs `@MockBean`, `@TestConfiguration`, application-context caching, the `@DataJpaTest` H2 trap, transactional traps (the `@Transactional` rollback lie, `AFTER_COMMIT` listeners, JPA flush vs commit), MockMvc Kotlin DSL, WebTestClient, WireMock-as-Testcontainer, OAuth2 / JWT in slices, `@Sql`, `OutputCaptureExtension`, profiles, the Spring slice test pyramid.

For language-agnostic discipline see `general.md`. For Kotlin tooling (Awaitility, AssertJ, fixture builders) see `kotlin.md`.

---

## 1. The slice catalogue in depth

Each Spring Boot test slice loads a curated subset of beans optimised for one layer. Pick the smallest slice that hosts the test.

### `@WebMvcTest(Controller::class)`

**Loads:** Spring MVC infrastructure (`DispatcherServlet`, `HandlerMapping`, `MessageConverter`s), the named `@Controller`, all `@ControllerAdvice` / `@RestControllerAdvice` discovered by classpath scan, Spring Security if present on the classpath. **Does not load:** `@Service`, `@Repository`, `@Component` (general).

**Use for:** Controller behaviour — request mapping, content negotiation, `@Valid` validation, exception → HTTP mapping, security filters, ProblemDetail response shape, Location headers, cache headers.

**Don't use for:** Business logic that lives in the application service (mock the service; test it elsewhere). End-to-end HTTP-through-DB tests (`@SpringBootTest` if necessary).

```kotlin
@WebMvcTest(OrderController::class)
@Import(GlobalExceptionHandler::class)
class OrderControllerTest {
    @Autowired private lateinit var mvc: MockMvc
    @MockkBean private lateinit var placeOrder: PlaceOrderHandler

    @Test
    fun `POST orders returns 201 with Location header`() {
        val expectedId = UUID.randomUUID()
        every { placeOrder(any()) } returns expectedId

        mvc.post("/api/v1/orders") {
            contentType = MediaType.APPLICATION_JSON
            content = """{"customerId":"$customerId","items":[{"productId":"$pid","quantity":2}]}"""
        }.andExpect {
            status { isCreated() }
            header { string("Location", "/api/v1/orders/$expectedId") }
            jsonPath("$.orderId") { value(expectedId.toString()) }
        }
    }

    @Test
    fun `POST orders with invalid body returns 422 ProblemDetail`() {
        mvc.post("/api/v1/orders") {
            contentType = MediaType.APPLICATION_JSON
            content = """{"customerId":""}"""
        }.andExpect {
            status { isUnprocessableEntity() }
            jsonPath("$.title") { value("Validation failed") }
            jsonPath("$.errors[*].field") { value(hasItem("customerId")) }
        }
    }
}
```

Key annotations:

- `@Import(GlobalExceptionHandler::class)` — `@RestControllerAdvice` is not always auto-discovered in `@WebMvcTest`; import it explicitly.
- `@MockkBean private lateinit var placeOrder: PlaceOrderHandler` — replaces the real service with a MockK mock.

**Typical time:** ~800 ms first test, ~100 ms subsequent (context cached).

### `@DataJpaTest`

**Loads:** JPA infrastructure (`EntityManagerFactory`, `EntityManager`, `TestEntityManager`), all `@Entity` classes, all `@Repository` beans, transactional management, `DataSource`. **By default:** substitutes an embedded H2 database — **almost always wrong for production code that runs on Postgres**.

**Use for:** Repository methods, custom queries, JPA mapping, `@Query` correctness, derived query method names, projection interfaces, pagination, Specifications, cascade behaviour.

**Don't use for:** Business logic (mock-free domain tests belong at the unit tier). Cross-aggregate flows that span multiple repositories with events.

```kotlin
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@Testcontainers
class OrderRepositoryTest {

    companion object {
        @Container
        @ServiceConnection
        val postgres: PostgreSQLContainer<*> = PostgreSQLContainer("postgres:16-alpine")
    }

    @Autowired private lateinit var repo: OrderRepository
    @Autowired private lateinit var em: TestEntityManager

    @Test
    fun `findByCustomerIdOrderByCreatedAtDesc returns newest first`() {
        val customerId = UUID.randomUUID()
        val older = em.persist(anOrderEntity(customerId = customerId, createdAt = Instant.parse("2026-01-01T00:00:00Z")))
        val newer = em.persist(anOrderEntity(customerId = customerId, createdAt = Instant.parse("2026-02-01T00:00:00Z")))
        em.flush()

        val page = repo.findByCustomerIdOrderByCreatedAtDesc(customerId, PageRequest.of(0, 10))

        assertThat(page.content).extracting<UUID> { it.id }.containsExactly(newer.id, older.id)
    }
}
```

The two critical annotations:

- `@AutoConfigureTestDatabase(replace = NONE)` — disables H2 substitution. **Mandatory** whenever you're using Testcontainers Postgres.
- `@ServiceConnection` on the container — Spring Boot 3.1+ auto-wires the JDBC URL, username, password into the datasource. Avoids `@DynamicPropertySource` boilerplate.

**`@DataJpaTest` rolls back each test by default.** Great for independence, but it means *changes made outside the transaction are not visible*. For multi-tx scenarios (events committed elsewhere), use `@Transactional(propagation = NOT_SUPPORTED)` or step up to `@SpringBootTest`.

**Typical time:** ~400 ms with shared Testcontainer (after warmup), ~3 s first run.

### `@JsonTest`

**Loads:** Jackson `ObjectMapper`, `JacksonTester<T>`. Nothing else.

**Use for:** Custom `JsonSerializer` / `JsonDeserializer`, `@JsonView`, polymorphic `@JsonTypeInfo`, `@JsonProperty` rename, date / instant formatting, Kotlin module behaviour.

```kotlin
@JsonTest
class OrderResponseSerializationTest {
    @Autowired private lateinit var json: JacksonTester<OrderResponse>

    @Test
    fun `serializes id, status, total`() {
        val response = OrderResponse(
            id = UUID.fromString("00000000-0000-0000-0000-000000000001"),
            status = "PENDING",
            total = Money(15000, "EUR"),
        )

        val content = json.write(response)

        assertThat(content).hasJsonPath("$.id")
        assertThat(content).extractingJsonPathStringValue("$.status").isEqualTo("PENDING")
        assertThat(content).extractingJsonPathNumberValue("$.total.amountMinor").isEqualTo(15000)
    }
}
```

**Typical time:** ~100 ms.

### `@JdbcTest`

**Loads:** `JdbcTemplate`, `DataSource`. Nothing else.

**Use for:** Raw SQL repositories (no JPA), legacy DAO classes, query-only services that use `NamedParameterJdbcTemplate`.

Combine with `@AutoConfigureTestDatabase(replace = NONE)` + Testcontainers for real Postgres.

**Typical time:** ~400 ms with shared container.

### `@RestClientTest(Client::class)`

**Loads:** `RestClient` / `RestTemplate` autoconfiguration + the named client class + `MockRestServiceServer` to stub the remote endpoint.

**Use for:** Outbound HTTP clients — URL construction, headers, body serialisation, error handling, retries.

```kotlin
@RestClientTest(InventoryApiClient::class)
class InventoryApiClientTest {
    @Autowired private lateinit var client: InventoryApiClient
    @Autowired private lateinit var server: MockRestServiceServer

    @Test
    fun `availability lookup hits the right path`() {
        server.expect(requestTo("/inventory/SKU-001/availability"))
            .andExpect(method(HttpMethod.GET))
            .andRespond(withSuccess("""{"available": 12}""", APPLICATION_JSON))

        val result = client.checkAvailability(Sku("SKU-001"))

        assertThat(result.available).isEqualTo(12)
        server.verify()
    }
}
```

`server.verify()` asserts the stubbed call was actually made — don't skip it.

**Typical time:** ~150 ms.

### `@DataMongoTest`

**Loads:** Mongo infrastructure, `MongoTemplate`, `@Document` classes, repositories.

**Use for:** Mongo repository queries, aggregation pipelines, projection interfaces.

```kotlin
@DataMongoTest
@Testcontainers
class UserPreferencesRepositoryTest {

    companion object {
        @Container
        @ServiceConnection
        val mongo = MongoDBContainer("mongo:7-jammy")
    }

    @Autowired private lateinit var repo: UserPreferencesRepository

    @Test
    fun `saves and retrieves document`() {
        val prefs = UserPreferencesDocument(userId = "u1", theme = "dark")
        repo.save(prefs)

        val found = repo.findById("u1").orElseThrow()
        assertThat(found.theme).isEqualTo("dark")
    }
}
```

### `@DataRedisTest`

**Loads:** `RedisTemplate` / `StringRedisTemplate`, `RedisConnectionFactory`. (Note: requires Spring Data Redis on the classpath.)

**Use for:** Redis-backed repositories, cache TTL behaviour, Lua scripts.

```kotlin
@DataRedisTest
@Testcontainers
class TokenStoreTest {
    companion object {
        @Container
        @ServiceConnection
        val redis = GenericContainer<Nothing>("redis:7-alpine").apply { withExposedPorts(6379) }
    }

    @Autowired private lateinit var template: StringRedisTemplate

    @Test
    fun `setex expires after the TTL`() {
        template.opsForValue().set("token:1", "abc", Duration.ofSeconds(2))
        assertThat(template.opsForValue().get("token:1")).isEqualTo("abc")

        await atMost Duration.ofSeconds(5) untilAsserted {
            assertThat(template.opsForValue().get("token:1")).isNull()
        }
    }
}
```

### Other slices

- `@DataNeo4jTest`, `@DataCassandraTest`, `@DataLdapTest`, `@DataR2dbcTest` — each loads its specific store; pattern is the same.
- `@WebFluxTest` — reactive equivalent of `@WebMvcTest`; uses `WebTestClient` instead of `MockMvc`.
- `@GraphQlTest` — GraphQL endpoint slice (Spring for GraphQL).
- `@DataElasticsearchTest` — Elasticsearch / OpenSearch slice.

The pattern: **smallest slice that hosts the test**. New slices appear in newer Spring Boot versions; consult the docs for the current set.

---

## 2. `@SpringBootTest` — when (and only when) it's appropriate

`@SpringBootTest` loads the entire `ApplicationContext`. Use it when:

- You're testing **across multiple slices** — controller → service → repo → DB → event publisher in one flow.
- You're testing the **bootstrap** itself — `@SpringBootApplication` wires up, `ApplicationRunner` runs, `@Bean`s connect.
- You're testing **integration with the deployed configuration** — profiles, `application.yml`, conditional beans.
- A slice annotation doesn't exist for the layer (Spring Batch, Quartz, complex `@EventListener` chains).

Don't use it when:

- The test fits a slice. `@WebMvcTest` over `@SpringBootTest(MOCK)` for a controller — always.
- The test is testing a pure domain rule. Drop Spring entirely; use `test-unit`.
- The test is testing a single repository query. `@DataJpaTest` is the right tool.

### Two `WebEnvironment` modes

```kotlin
// MOCK (default) — MockMvc, no real HTTP server
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.MOCK)
@AutoConfigureMockMvc
class XTest {
    @Autowired private lateinit var mvc: MockMvc
    @Test fun `...`() { mvc.get(...).andExpect { ... } }
}

// RANDOM_PORT — real Tomcat / Jetty, real HTTP, WebTestClient or TestRestTemplate
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class XTest {
    @LocalServerPort private var port: Int = 0
    @Autowired private lateinit var rest: TestRestTemplate
    @Test fun `...`() { rest.getForEntity("/...", ...) }
}
```

`MOCK` is faster (no real network); `RANDOM_PORT` exercises the actual HTTP stack including connectors, request decoding, real timeouts. Pick `RANDOM_PORT` only when you need that fidelity (smoke tests, true end-to-end-through-HTTP).

**Each `@SpringBootTest` adds ~5-15s to CI.** Less is more.

---

## 3. `@ServiceConnection` (Spring Boot 3.1+) vs `@DynamicPropertySource`

### `@ServiceConnection` — the modern default

```kotlin
@SpringBootTest
@Testcontainers
class XTest {
    companion object {
        @Container
        @ServiceConnection                              // ← one line wires it
        val postgres: PostgreSQLContainer<*> = PostgreSQLContainer("postgres:16-alpine")
    }
}
```

Spring detects the container type via `org.springframework.boot:spring-boot-testcontainers` and auto-wires:

- For `PostgreSQLContainer`: `spring.datasource.url`, `.username`, `.password`
- For `MongoDBContainer`: `spring.data.mongodb.uri`
- For `KafkaContainer`: `spring.kafka.bootstrap-servers`
- For `ElasticsearchContainer`: `spring.elasticsearch.uris`
- For `RedisContainer`: `spring.data.redis.host`, `.port`

Supported containers grow with each Spring Boot release.

### `@DynamicPropertySource` — the explicit fallback

Use when you need a custom property mapping or when `@ServiceConnection` isn't available for your container:

```kotlin
@SpringBootTest
@Testcontainers
class XTest {
    companion object {
        @Container val clickhouse = ClickHouseContainer("clickhouse/clickhouse-server:24.3-alpine")

        @JvmStatic
        @DynamicPropertySource
        fun props(registry: DynamicPropertyRegistry) {
            registry.add("clickhouse.url") { clickhouse.jdbcUrl }
            registry.add("clickhouse.username") { clickhouse.username }
            registry.add("clickhouse.password") { clickhouse.password }
        }
    }
}
```

Common case: custom datasource property names (`clickhouse.*`, `events.kafka.*`).

### `@TestPropertySource` — for static values

```kotlin
@SpringBootTest
@TestPropertySource(properties = [
    "feature.new-checkout=true",
    "external.api.timeout=100ms",
])
class XTest { /* ... */ }
```

Use for test-only feature flags and static overrides.

---

## 4. Testcontainers + Spring — per data store

### PostgreSQL

```kotlin
@SpringBootTest
@Testcontainers
class OrderServiceIntegrationTest {

    companion object {
        @Container
        @ServiceConnection
        val postgres: PostgreSQLContainer<*> = PostgreSQLContainer("postgres:16-alpine")
            .withReuse(true)
    }

    @Autowired private lateinit var orderService: OrderService

    @Test
    fun `places order, persists to Postgres`() {
        val orderId = orderService.place(somePlaceCommand())
        assertThat(orderService.findById(orderId)).isNotNull
    }
}
```

Pin the image (`postgres:16-alpine`, never `postgres:latest`) for reproducibility.

### MongoDB

```kotlin
@SpringBootTest
@Testcontainers
class UserPreferencesIntegrationTest {

    companion object {
        @Container
        @ServiceConnection
        val mongo = MongoDBContainer("mongo:7-jammy")
    }
    // ...
}
```

`MongoDBContainer` defaults to a single-node replica set — needed for Mongo transactions, harmless for non-tx tests.

### Elasticsearch

```kotlin
@SpringBootTest
@Testcontainers
class OrderSearchProjectionTest {

    companion object {
        @Container
        @ServiceConnection
        val elasticsearch = ElasticsearchContainer(
            DockerImageName.parse("docker.elastic.co/elasticsearch/elasticsearch:8.13.0")
        ).withEnv("xpack.security.enabled", "false")
            .withEnv("discovery.type", "single-node")
    }

    @Autowired private lateinit var operations: ElasticsearchOperations

    @Test
    fun `indexes order on OrderPlaced event`() {
        // publish OrderPlaced
        await atMost Duration.ofSeconds(5) untilAsserted {
            val hits = operations.search(
                NativeQueryBuilder().withQuery(matchAll()).build(),
                OrderSearchDoc::class.java,
            )
            assertThat(hits.totalHits).isGreaterThan(0)
        }
    }
}
```

ES indexing is async — Awaitility, not `Thread.sleep`.

### Kafka

```kotlin
@SpringBootTest
@Testcontainers
class OrderPlacedKafkaTest {

    companion object {
        @Container
        @ServiceConnection
        val kafka = KafkaContainer(DockerImageName.parse("confluentinc/cp-kafka:7.5.0"))
    }

    @Autowired private lateinit var producer: KafkaTemplate<String, ByteArray>

    @Test
    fun `produces OrderPlaced event with correct partition key`() {
        val orderId = UUID.randomUUID()
        producer.send("orders", orderId.toString(), byteArrayOf(1, 2, 3))

        val records = KafkaTestUtils.getRecords(consumer(), Duration.ofSeconds(5))
        assertThat(records.records("orders")).hasSize(1)
            .first().extracting("key").isEqualTo(orderId.toString())
    }

    private fun consumer(): Consumer<String, ByteArray> {
        val props = KafkaTestUtils.consumerProps(kafka.bootstrapServers, "test", "true")
        return DefaultKafkaConsumerFactory<String, ByteArray>(
            props, StringDeserializer(), ByteArrayDeserializer()
        ).createConsumer().apply { subscribe(listOf("orders")) }
    }
}
```

### Clickhouse

```kotlin
@SpringBootTest
@Testcontainers
class OrderAnalyticsClickhouseTest {

    companion object {
        @Container
        val clickhouse = ClickHouseContainer("clickhouse/clickhouse-server:24.3-alpine").withReuse(true)

        @JvmStatic
        @DynamicPropertySource
        fun props(registry: DynamicPropertyRegistry) {
            registry.add("clickhouse.url") { clickhouse.jdbcUrl }
            registry.add("clickhouse.username") { clickhouse.username }
            registry.add("clickhouse.password") { clickhouse.password }
        }
    }

    @Autowired @Qualifier("clickhouseJdbcTemplate")
    private lateinit var ch: JdbcTemplate

    @Test
    fun `inserts and reads`() {
        ch.execute("""
            CREATE TABLE IF NOT EXISTS order_events (
                event_id UUID, order_id UUID, created_at DateTime64(3), total_minor Int64
            ) ENGINE = MergeTree() ORDER BY (created_at, order_id)
        """)
        ch.update("INSERT INTO order_events VALUES (?, ?, now(), 1500)", UUID.randomUUID(), UUID.randomUUID())
        assertThat(ch.queryForObject("SELECT count() FROM order_events", Long::class.java)).isEqualTo(1L)
    }
}
```

Clickhouse startup is ~5-10s; container reuse is essential.

### Redis

`RedisContainer` from the `org.testcontainers:redis` module isn't part of Testcontainers core; use `GenericContainer`:

```kotlin
@Container
@ServiceConnection(name = "redis")
val redis = GenericContainer<Nothing>("redis:7-alpine").apply {
    withExposedPorts(6379)
}
```

`@ServiceConnection(name = "redis")` (Spring Boot 3.1+) wires generic containers when the connection-details class is provided. For older setups, fall back to `@DynamicPropertySource`:

```kotlin
@JvmStatic
@DynamicPropertySource
fun props(registry: DynamicPropertyRegistry) {
    registry.add("spring.data.redis.host") { redis.host }
    registry.add("spring.data.redis.port") { redis.firstMappedPort }
}
```

---

## 5. Container reuse — CI implications

### Enable reuse globally

```
# ~/.testcontainers.properties
testcontainers.reuse.enable=true
```

Plus per-container opt-in:

```kotlin
val postgres = PostgreSQLContainer("postgres:16-alpine").withReuse(true)
```

**Both** are required; the global flag without per-container opt-in does nothing, and vice-versa.

### How reuse works

Testcontainers computes a hash of: image + ports + env vars + cmd. If a running container matches that hash, it's reused. Otherwise, a new one starts.

- **Same hash → reused.** Container survives JVM exit (developer machine).
- **Different hash → fresh container.** Changing image tag, env var, cmd triggers a new start.

### CI implications

- **Ephemeral CI runners** that destroy the Docker daemon between jobs cannot reuse. Either accept the cold-start cost, or use persistent runners with the reuse flag set.
- **GitHub Actions / GitLab CI default runners** are typically ephemeral. Reuse helps the *next test in the same job*, not the next job.
- **`testcontainers.reuse.enable=true` on CI** is harmless if the daemon doesn't persist — the second test still starts a fresh container. Use it everywhere; let the environment decide whether it actually reuses.

### Schema-state-survives-reuse pitfall

When the same container is reused across multiple JVM runs, the schema and data persist. Either:

- Use Flyway / Liquibase migrations as production does — they're idempotent.
- Truncate explicitly in `@BeforeEach`.
- Design tests to coexist (namespacing).

The default `@DataJpaTest` rollback handles most read-side cases, but write-side / event tests need explicit cleanup.

---

## 6. `@MockkBean` (mockk-spring) vs `@MockBean` (Spring's Mockito)

Spring's `@MockBean` creates a Mockito mock and registers it in the context. `mockk-spring` provides `@MockkBean` for MockK.

### Side-by-side

```kotlin
// Spring's @MockBean — Mockito syntax
@WebMvcTest(OrderController::class)
class OrderControllerTest {
    @Autowired lateinit var mvc: MockMvc
    @MockBean lateinit var service: OrderApplicationService

    @Test fun `...`() {
        whenever(service.byId(OrderId("123"))).thenReturn(anOrderView())
    }
}

// mockk-spring's @MockkBean — MockK syntax
@WebMvcTest(OrderController::class)
class OrderControllerTest {
    @Autowired lateinit var mvc: MockMvc
    @MockkBean lateinit var service: OrderApplicationService

    @Test fun `...`() {
        every { service.byId(OrderId("123")) } returns anOrderView()
    }
}
```

### House recommendation: MockK + `@MockkBean`

For Kotlin services:

- Matches the production-code mocking style (MockK is the Kotlin default).
- Handles `suspend` natively without `@OpenForTesting` workarounds.
- Handles `final` classes (Kotlin's default) without needing `mockito-inline`.
- Handles `object` singletons.

**Pick one and stick with it project-wide.** Mixing `@MockBean` and `@MockkBean` for the same type in one suite forces every reader to context-switch.

### Application-context caching pitfall

**Every distinct combination of `@MockBean` / `@MockkBean` declarations creates a new `ApplicationContext`.** Spring cannot cache across mock-declaration sets.

- 30 `@WebMvcTest` classes, each with one different `@MockkBean` → 30 cached contexts.
- Default cache size is 32 (`spring.test.context.cache.size`); exceed it and contexts churn.

Mitigation:

- **Group consistent mock declarations** in a base class:
  ```kotlin
  abstract class AbstractControllerTest {
      @MockkBean protected lateinit var auth: AuthService
      @MockkBean protected lateinit var rateLimiter: RateLimiter
  }
  ```
- **Reuse `@TestConfiguration`** for shared test beans across multiple test classes.
- **Audit cache size**: enable `spring.test.context.cache.maxSize=64` or higher if churn shows.

---

## 7. `@TestConfiguration` for fixed beans

For deterministic test runs, replace beans like `Clock`, `IdGenerator`, `Random` with test versions:

```kotlin
@TestConfiguration
class TestBeans {
    @Bean fun clock(): Clock = Clock.fixed(Instant.parse("2026-01-01T00:00:00Z"), ZoneOffset.UTC)

    @Bean fun idGenerator(): IdGenerator = object : IdGenerator {
        private var seq = 0L
        override fun next(): Long = ++seq
    }

    @Bean fun random(): Random = Random(42)  // seeded
}

@SpringBootTest
@Import(TestBeans::class)
class XTest { /* ... */ }
```

### When to use vs `@MockkBean`

- `@MockkBean`: one-off mocking, per-test setup, behaviour verification.
- `@TestConfiguration`: shared test wiring, deterministic infrastructure beans (clock, ID, RNG), stubbed external services that need real behaviour rather than per-test stubs.

A `Clock` is almost always better as a `@TestConfiguration @Bean` than as a `@MockkBean` — the test code doesn't need to stub it; it just gets the fixed time.

---

## 8. Application-context caching pitfalls — in depth

Spring caches `ApplicationContext`s by a key derived from:

- `@SpringBootTest` class and configuration
- `@Import` annotations
- `@TestPropertySource` properties
- `@ActiveProfiles`
- `@MockBean` / `@MockkBean` declarations (the set of mocked types)
- `@DirtiesContext` markers

**Two test classes with identical key → shared context** (huge speedup).

**Two test classes with different keys → two contexts** (each costs ~5-15s startup).

### Symptoms of context churn

- CI takes 3× longer than expected.
- Log shows `Loaded Spring ApplicationContext` 20+ times.
- `spring.test.context.cache.size` is at default and you have >32 test classes with varying keys.

### Diagnosis

Add logging:

```yaml
logging.level.org.springframework.test.context.cache: DEBUG
```

Output shows context cache hits / misses per test class.

### Fixes

- **Standardise on a single base class** per test type with the same mock declarations.
- **Bump the cache size**: `-Dspring.test.context.cache.maxSize=64` (or in `application-test.yml`).
- **Move per-test stubbing into `every { mock.x() } returns ...`** inside the test body, rather than declaring different mock types per class.
- **Avoid `@DirtiesContext` as a workaround** — it invalidates the cache entry, forcing a rebuild on the next run.

---

## 9. The `@DataJpaTest` H2 trap

By default, `@DataJpaTest` substitutes the production datasource with an embedded H2. This is fast (no container) but **silently incorrect** when production runs on Postgres:

| Production code | H2 says | Postgres says |
|---|---|---|
| `WHERE jsonb_col @> '{"a": 1}'` | Syntax error → test fails | Works → passes |
| `INSERT ... ON CONFLICT (id) DO UPDATE` | Different syntax | Real upsert |
| `RETURNING id` | Different behaviour | Real |
| `GIN` index on JSONB | Doesn't exist | Exists, used by query planner |
| Partial / expression indexes | Limited | Real |
| MVCC isolation behaviour | Different | Real |

The fix:

```kotlin
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@Testcontainers
class OrderRepositoryTest {
    companion object {
        @Container @ServiceConnection
        val postgres = PostgreSQLContainer("postgres:16-alpine")
    }
    // ...
}
```

`@AutoConfigureTestDatabase(replace = NONE)` — **mandatory** whenever Testcontainers is in play. Without it, Spring substitutes H2 regardless of the container.

**House rule**: `@DataJpaTest` without `@AutoConfigureTestDatabase(replace = NONE)` + Testcontainers is a bug.

---

## 10. Transactional traps — the `@Transactional` rollback lie

`@DataJpaTest` and `@Transactional` on test classes roll back each method's transaction. **For most read-side tests, this is great** — independence is automatic, no cleanup code.

For three specific cases, the rollback **lies about behaviour**:

### 10a. Code that crosses transaction boundaries (`REQUIRES_NEW`)

```kotlin
@SpringBootTest
@Transactional
class OutboxIntegrationTest {
    @Autowired lateinit var service: OrderService
    @Autowired lateinit var outbox: OutboxRepository

    @Test
    fun `submit writes an outbox entry`() {
        service.submit(aSubmitOrder())                  // service runs in REQUIRES_NEW
        assertThat(outbox.findAll()).hasSize(1)         // might pass; might fail; might pass for the wrong reason
    }
}
```

If `service.submit` is `@Transactional(propagation = REQUIRES_NEW)`, it commits its own tx — independent of the test's outer one. The outbox row is **committed**. After the test rolls back its outer tx, the outbox row **still exists** → the next test sees polluted state.

Fix: **don't use `@Transactional` on integration tests that exercise cross-tx flows.** Clean up explicitly:

```kotlin
@SpringBootTest
class OutboxIntegrationTest {
    @Autowired lateinit var jdbc: JdbcTemplate

    @AfterEach
    fun cleanup() {
        jdbc.execute("TRUNCATE TABLE outbox, orders RESTART IDENTITY CASCADE")
    }

    @Test
    fun `submit writes an outbox entry`() { /* ... */ }
}
```

### 10b. `@TransactionalEventListener(AFTER_COMMIT)` listeners

```kotlin
@Component
class OrderEmailNotifier {
    @TransactionalEventListener(phase = AFTER_COMMIT)
    fun on(event: OrderSubmitted) = emailer.send("Order ${event.orderId} submitted")
}

// ✗ The listener never fires — the test's tx rolls back
@SpringBootTest
@Transactional
class OrderEmailNotifierTest {
    @MockkBean lateinit var emailer: Emailer
    @Autowired lateinit var service: OrderService

    @Test
    fun `submit triggers the email`() {
        service.submit(...)
        verify { emailer.send(any()) }   // ← fails — listener never fired
    }
}
```

The listener fires on commit. The test's tx rolls back → no commit → no listener call.

Fix: either let the service's own `@Transactional` commit (don't put `@Transactional` on the test), or unit-test the listener with a synthesised event:

```kotlin
// ✓ Service commits; listener fires
@SpringBootTest
class OrderEmailNotifierIntegrationTest {
    @MockkBean lateinit var emailer: Emailer
    @Autowired lateinit var service: OrderService

    @AfterEach fun cleanup() { /* truncate */ }

    @Test
    fun `submit triggers the email`() {
        service.submit(...)
        await atMost Duration.ofSeconds(2) untilAsserted {
            verify { emailer.send(any()) }
        }
    }
}

// ✓✓ Even better — unit-test the listener directly
class OrderEmailNotifierUnitTest {
    private val emailer = mockk<Emailer>(relaxed = true)
    private val notifier = OrderEmailNotifier(emailer)

    @Test fun `it sends email on OrderSubmitted`() {
        notifier.on(OrderSubmitted(OrderId("123")))
        verify { emailer.send("Order 123 submitted") }
    }
}
```

For listeners with non-trivial logic, write the **unit test** against the listener. The integration test verifies the wiring fires *once*; the unit tests cover the listener's branches.

### 10c. JPA flush vs commit

```kotlin
@DataJpaTest
class FlushBehaviourTest {
    @Autowired lateinit var orders: OrderRepository
    @Autowired lateinit var em: EntityManager

    @Test
    fun `flushing publishes the entity to the DB`() {
        val order = orders.save(anOrderEntity())   // staged in the persistence context
        em.flush()                                  // ← INSERT actually runs
        em.clear()                                  // ← purge the persistence context

        val reloaded = orders.findById(order.id).orElseThrow()
        assertThat(reloaded.status).isEqualTo(OrderStatus.DRAFT)
    }
}
```

Without `flush()`, the `INSERT` may not run until commit. Combined with rollback, you may see the row in the persistence context but not at the DB layer. Use `flush(); clear()` to round-trip a write and assert on the committed state.

### House rule

`@Transactional` on tests is great for **read-side** assertions (repository queries that don't span tx boundaries). For **write-side** flows with events / async / `REQUIRES_NEW`, prefer **explicit cleanup** (truncate) over auto-rollback.

---

## 11. MockMvc Kotlin DSL

For `@WebMvcTest` and `@SpringBootTest(MOCK)`, Spring ships a Kotlin DSL — much cleaner than the Java-fluent `MockMvcRequestBuilders` chain.

### Java-fluent (don't)

```kotlin
mockMvc.perform(get("/api/v1/orders/123").accept(APPLICATION_JSON))
    .andExpect(status().isOk())
    .andExpect(content().contentType(APPLICATION_JSON))
    .andExpect(jsonPath("$.id").value("123"))
```

### Kotlin DSL (do)

```kotlin
mockMvc.get("/api/v1/orders/123") {
    accept = APPLICATION_JSON
}.andExpect {
    status { isOk() }
    content { contentType(APPLICATION_JSON) }
    jsonPath("$.id") { value("123") }
}
```

### POST with body

```kotlin
mockMvc.post("/api/v1/orders") {
    contentType = MediaType.APPLICATION_JSON
    content = """{"customerId":"$customerId","items":[]}"""
}.andExpect {
    status { isCreated() }
    header { string("Location", "/api/v1/orders/$expectedId") }
    jsonPath("$.orderId") { value(expectedId.toString()) }
}
```

### Auth (with JWT / mock user)

```kotlin
mockMvc.get("/api/v1/me") {
    with(jwt().jwt { it.subject("user-123") })
}.andExpect {
    status { isOk() }
    jsonPath("$.userId") { value("user-123") }
}
```

`with(...)` is the Kotlin DSL bridge to `MockMvcRequestBuilders` post-processors.

### `andDo` for debugging

```kotlin
mockMvc.get("/api/v1/orders/123").andDo {
    print()        // dumps the full request/response on failure
}.andExpect {
    status { isOk() }
}
```

Useful when a test is mysteriously failing — `print()` shows headers, body, status as MockMvc sees them.

---

## 12. WebTestClient for `@SpringBootTest(RANDOM_PORT)`

When the test must go through real HTTP (TLS, connector behaviour, real timeouts), use `WebTestClient` against a running server:

```kotlin
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@Testcontainers
class ApplicationSmokeTest {

    companion object {
        @Container @ServiceConnection
        val postgres = PostgreSQLContainer("postgres:16-alpine")
    }

    @LocalServerPort private var port: Int = 0

    @Test
    fun `actuator health is UP`() {
        val client = WebTestClient.bindToServer().baseUrl("http://localhost:$port").build()

        client.get().uri("/actuator/health")
            .exchange()
            .expectStatus().isOk
            .expectBody().jsonPath("$.status").isEqualTo("UP")
    }
}
```

Reserve `WebTestClient` against `RANDOM_PORT` for:

- True smoke tests (does the app start and respond).
- TLS / cert validation tests.
- Real-network behaviour (timeouts, connection reuse).
- Tests that legitimately exercise the connector (Tomcat / Jetty / Netty).

For everything else, `MockMvc` over `@WebMvcTest` is faster and equally informative.

### TestRestTemplate alternative

`TestRestTemplate` exists for backward compatibility with non-reactive setups; `WebTestClient` is the preferred default since Spring Boot 2.4.

---

## 13. WireMock-as-Testcontainer for outbound HTTP

For `@SpringBootTest`-level outbound HTTP integration (the production code's HTTP client wired up via the full Spring context, talking to a stubbed external service), WireMock as a Testcontainer is the cleanest pattern:

```kotlin
@SpringBootTest
@Testcontainers
class OrderToInventoryIntegrationTest {

    companion object {
        @Container
        val wiremock: GenericContainer<*> = GenericContainer("wiremock/wiremock:3.9.2")
            .withExposedPorts(8080)
            .waitingFor(Wait.forHttp("/__admin/health"))

        @JvmStatic
        @DynamicPropertySource
        fun props(registry: DynamicPropertyRegistry) {
            registry.add("integrations.inventory.url") {
                "http://${wiremock.host}:${wiremock.firstMappedPort}"
            }
        }
    }

    @Autowired private lateinit var orderService: OrderService

    @Test
    fun `submit checks inventory`() {
        // stub the inventory endpoint via WireMock admin API
        WireMock.configureFor(wiremock.host, wiremock.firstMappedPort)
        WireMock.stubFor(
            WireMock.get(WireMock.urlPathEqualTo("/inventory/SKU-001/availability"))
                .willReturn(WireMock.okJson("""{"available": 12}"""))
        )

        val result = orderService.submit(aSubmitOrder(sku = "SKU-001"))

        assertThat(result).isInstanceOf(OrderResult.Submitted::class.java)
        WireMock.verify(WireMock.getRequestedFor(WireMock.urlPathEqualTo("/inventory/SKU-001/availability")))
    }
}
```

When to use this vs `@RestClientTest` + inline WireMock:

- `@RestClientTest` — fast slice, the *client class* is under test; no other Spring beans loaded.
- WireMock-as-Testcontainer — `@SpringBootTest`, the *whole flow* is under test (controller → service → outbound client → external API).

Both are valid; the latter is slower but covers more.

---

## 14. OAuth2 / JWT testing in slices

When Spring Security is on the classpath, `@WebMvcTest` engages security by default. Without configuration, all endpoints return 401.

### Option A: permissive test security

```kotlin
@TestConfiguration
class SecurityTestConfiguration {
    @Bean
    fun testSecurityFilterChain(http: HttpSecurity): SecurityFilterChain =
        http.csrf { it.disable() }
            .authorizeHttpRequests { it.anyRequest().permitAll() }
            .build()
}

@WebMvcTest(OrderController::class)
@Import(SecurityTestConfiguration::class)
class OrderControllerTest { /* ... */ }
```

Good for tests that don't care about security; bad for tests that should verify endpoint protection.

### Option B: mock JWT / authenticated user

```kotlin
@WebMvcTest(OrderController::class)
class OrderControllerTest {
    @Autowired lateinit var mvc: MockMvc
    @MockkBean lateinit var jwtDecoder: JwtDecoder

    @Test
    fun `authenticated user can list their orders`() {
        mvc.get("/api/v1/orders") {
            with(jwt().jwt { it.subject("user-123") })
        }.andExpect {
            status { isOk() }
        }
    }

    @Test
    fun `unauthenticated request returns 401`() {
        mvc.get("/api/v1/orders").andExpect {
            status { isUnauthorized() }
        }
    }
}
```

`jwt()` is from `org.springframework.security:spring-security-test`. The mock JWT is injected into the `SecurityContext` without going through the real decoder — so you test the *authorisation* logic without standing up a real JWT issuer.

### `@WithMockUser` for username/password auth

```kotlin
@Test
@WithMockUser(username = "ada", roles = ["ADMIN"])
fun `admin can delete an order`() {
    mvc.delete("/api/v1/orders/123").andExpect { status { isNoContent() } }
}
```

### House rule

Test both the **happy path** (authenticated) and **the protection** (401 / 403). A controller test without a 401-on-missing-auth case is missing half its security contract.

---

## 15. `@Sql` for fixtures / cleanup

`@Sql` runs an SQL script against the test datasource at a configurable point in the test lifecycle:

```kotlin
@SpringBootTest
@Sql(
    scripts = ["/fixtures/seed-customer-with-three-orders.sql"],
    executionPhase = BEFORE_TEST_METHOD,
)
@Sql(
    scripts = ["/fixtures/cleanup.sql"],
    executionPhase = AFTER_TEST_METHOD,
)
class OrderQueryTest {
    @Autowired lateinit var orders: OrderRepository

    @Test
    fun `returns three orders for the canonical customer`() {
        assertThat(orders.findByCustomerId(canonicalCustomerId)).hasSize(3)
    }
}
```

### When `@Sql` over a builder helper

- **Large fixtures** (50+ rows) — script is more readable than a builder loop.
- **Many tests share the scenario** — defining once vs in every test class.
- **Tests need a fixed, named scenario** ("a customer with three orders, two submitted, one cancelled").

### When NOT `@Sql`

- The fixture varies per test (use builder).
- The fixture is small (1-3 rows) — builder is clearer.
- The fixture requires programmatic logic (random data, derived FKs) — builder.

### Cleanup scripts

```sql
-- src/test/resources/fixtures/cleanup.sql
TRUNCATE TABLE order_lines, orders, customers RESTART IDENTITY CASCADE;
```

Run as `executionPhase = AFTER_TEST_METHOD`. Faster than DELETE; `RESTART IDENTITY` resets sequences.

### Pitfalls

- `@Sql` scripts that aren't idempotent (assume empty starting state) — fragile under reused containers.
- Many one-off scripts scattered across the suite — consolidate; one `cleanup.sql` + one `seed-<scenario>.sql` per common scenario.
- `@Sql` + `@Transactional` rollback — the script's writes are committed *before* the test's tx starts; rollback covers the test's writes, not the script's. The cleanup script handles the rest.

---

## 16. `OutputCaptureExtension` for log-contract tests

When the log line itself is part of a contract (audit logs, structured event logs parsed by downstream systems), capture and assert:

```kotlin
@ExtendWith(OutputCaptureExtension::class)
class AuditLoggerTest {
    @Test
    fun `submit emits an audit log line with the order id`(output: CapturedOutput) {
        AuditLogger().logSubmitted(OrderId("123"))

        assertThat(output.out).contains(""""event":"OrderSubmitted"""", """"orderId":"123"""")
    }
}
```

`CapturedOutput` is injected by the extension; `output.out` is stdout, `output.err` is stderr.

### When to use

- Audit logs that are part of a contract (downstream SIEM, compliance).
- Structured event logs consumed by another service.
- Logs that show up in dashboards / alerting rules.

### When NOT to use

- "Just to make sure something logged" — that's not a contract; assert on the behaviour instead.
- Debug logs — not part of the public surface; change at will.
- Replacing real assertions with log inspection — anti-pattern.

---

## 17. Test profiles — `@ActiveProfiles("test")`

Profiles control which `application-*.yml` files are loaded.

```kotlin
@SpringBootTest
@ActiveProfiles("test")
class XTest { /* application-test.yml is loaded */ }
```

`src/test/resources/application-test.yml`:

```yaml
features:
  kafka-enabled: false       # disable async pipelines in tests that don't exercise them

spring:
  task:
    execution:
      pool:
        core-size: 0          # disable async executor for deterministic tests

retry:
  max-attempts: 1             # fast-fail instead of long retries

external:
  api:
    timeout: 100ms            # short timeouts; WireMock responds instantly anyway
```

### House rule

- **One `test` profile**; avoid creating `test-postgres`, `test-mongo`, `test-fast`. Many profiles fragment the suite.
- **Per-test overrides via `@TestPropertySource`** when one test needs a different value.
- **Test config diverges from prod only where necessary** — same retries, same timeouts, same defaults; only disable async / Kafka where they'd make the test slow or flaky.

---

## 18. The Spring slice test pyramid — concrete shape

For a typical Spring Boot service of moderate complexity:

| Layer | Annotation | Count | % of suite | Time per test |
|---|---|---|---|---|
| Pure domain unit | none | 150 | 60% | ~ 10 ms |
| `@JsonTest` / `@RestClientTest` | slice | 30 | 12% | ~ 100-150 ms |
| `@WebMvcTest` | slice | 25 | 10% | ~ 800 ms |
| `@DataJpaTest` (Testcontainers) | slice | 25 | 10% | ~ 200-400 ms (shared container) |
| `@SpringBootTest` integration | full | 15 | 6% | ~ 2-5 s |
| `@SpringBootTest` end-to-end | full | 5 | 2% | ~ 5-10 s |

Total: ~250 tests, ~60-90s locally with reuse, ~3-5 min cold CI run.

A suite that's 80% `@SpringBootTest` will take 20× longer and break far more often for non-behavioural reasons. A suite that's 0% `@SpringBootTest` will miss integration regressions that only show up across layers.

Where does each test belong:

- **Pure domain rule** (`Order.submit(emptyLines)` rejects) → unit. No Spring.
- **Query method on a repository** → `@DataJpaTest` + Testcontainers Postgres.
- **JSON serialisation contract** → `@JsonTest`.
- **Controller request/response shape, validation, error mapping** → `@WebMvcTest`.
- **Outbound HTTP client class** → `@RestClientTest` (inline WireMock).
- **Cross-slice flow** (controller → service → repo → DB → event publisher) → `@SpringBootTest` + Testcontainers.
- **App starts at all (smoke)** → one `@SpringBootTest` + `WebTestClient` on `/actuator/health`.

---

## 19. Smell → fix (Spring-specific)

| Smell | Fix |
|---|---|
| `@SpringBootTest` on a controller test | `@WebMvcTest(Controller::class)` |
| `@SpringBootTest` on a repository test | `@DataJpaTest` + `@AutoConfigureTestDatabase(replace = NONE)` + Testcontainers |
| `@DataJpaTest` without `@AutoConfigureTestDatabase(replace = NONE)` | Add it; Spring is silently using H2 |
| Java-fluent MockMvc chain in Kotlin | Kotlin DSL: `mockMvc.get { ... }.andExpect { ... }` |
| Test calls real third-party API | `@RestClientTest` or WireMock |
| `@DirtiesContext` on most tests | Root-cause the leak; remove `@DirtiesContext` |
| `Thread.sleep(N)` in an async test | Awaitility `await atMost ... untilAsserted { ... }` |
| `@MockBean` next to `@MockkBean` in the same project | Standardise on `@MockkBean` (MockK) |
| `@WebMvcTest` returns 401 on every test | Add `@Import(SecurityTestConfiguration::class)` or use `with(jwt())` |
| `@SpringBootTest(properties = ["lots of overrides"])` to make the test pass | Test isn't testing the system that ships; use `@ActiveProfiles("test")` and minimal divergence |
| Test asserts on log content unintentionally | Either remove the assertion or use `OutputCaptureExtension` deliberately |
| Hand-rolled `@ContextConfiguration` to bend Spring | Wrong slice; step back and pick a slice that fits |
| 30 `@Sql` scripts in 30 different shapes | Consolidate; one `cleanup.sql` + one `seed-<scenario>.sql` per scenario |
| `@DataJpaTest` + `@Transactional` listener test that never fires | Remove `@Transactional`; use truncate cleanup; or unit-test the listener |
| Container per test class | Singleton container in base / `@ImportTestcontainers` |
| `@AutoConfigureMockMvc(addFilters = false)` everywhere | Fix the slice with a proper test security configuration |
| Reusing one `@SpringBootTest` base class because "it works" | Audit; downgrade most cases to slices |

---

## 20. Summary — Spring integration discipline

- **Slices over `@SpringBootTest`.** The narrower the slice, the faster the test and the more focused the failure signal.
- **`@AutoConfigureTestDatabase(replace = NONE)` whenever Testcontainers is in play.** Otherwise Spring silently uses H2.
- **`@ServiceConnection` over `@DynamicPropertySource`** (Spring Boot 3.1+). One line vs eight.
- **`@MockkBean` for Kotlin services.** Pick one; don't mix.
- **`@TestConfiguration` for deterministic beans** (`Clock`, `IdGenerator`, `Random` seeded).
- **`@Transactional` on tests for read-side only.** For write-side / events / async, use explicit cleanup (truncate).
- **Listeners fire on commit.** A rolled-back test sees no `AFTER_COMMIT` listener call. Either don't roll back, or unit-test the listener.
- **JPA flush vs commit.** `em.flush(); em.clear()` to round-trip a write.
- **MockMvc Kotlin DSL** — `mockMvc.get { … }.andExpect { … }`.
- **`WebTestClient` against `RANDOM_PORT`** only when you need real-network fidelity.
- **WireMock for any outbound HTTP**, inline (`@RestClientTest`) or as a Testcontainer (`@SpringBootTest`).
- **Security: test both authenticated and protection paths.** `with(jwt())`, `@WithMockUser`, or a permissive `@TestConfiguration`.
- **`@Sql` for large shared fixtures; builders for everything else.**
- **`OutputCaptureExtension` for log contracts**; don't fake assertion via log inspection elsewhere.
- **One `test` profile**; minimal divergence from prod.

The integration tier is where Spring's test infrastructure earns its keep. Use it well — slice everything, real-infra everywhere, no shortcuts on isolation.
