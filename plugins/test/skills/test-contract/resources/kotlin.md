# Pact JVM in Kotlin — Idioms, Setup, Examples

Pact JVM is the JVM implementation of the Pact specification. It works for any JVM consumer/provider, integrates with JUnit 5, and supports both `RequestResponsePact` (REST) and `MessagePact` (Kafka / async). This document covers the Kotlin-idiomatic patterns and gotchas.

> The Pact-JVM Kotlin DSL is fluent-Java under the hood. It works, but it has rough edges in Kotlin — particularly around `Map<String, Any>` body literals and the lambda-vs-Consumer mismatch. The patterns below sidestep the rough edges.

---

## 1. Gradle setup

```kotlin
// build.gradle.kts (consumer side)
plugins {
    id("au.com.dius.pact") version "4.6.14"
}

dependencies {
    testImplementation("au.com.dius.pact.consumer:junit5:4.6.14")
    testImplementation("org.junit.jupiter:junit-jupiter:5.10.2")
    testImplementation("org.assertj:assertj-core:3.25.3")
}

pact {
    publish {
        pactBrokerUrl = "https://pacts.example.com"
        pactBrokerUsername = providers.gradleProperty("pact.broker.user").orNull
        pactBrokerPassword = providers.gradleProperty("pact.broker.password").orNull
        consumerVersion = providers.gradleProperty("git.sha").orElse("0.0.0").get()
        consumerBranch = providers.gradleProperty("git.branch").orElse("main").get()
    }
}

tasks.test {
    useJUnitPlatform()
    systemProperty("pact.rootDir", "${layout.buildDirectory.get()}/pacts")
}
```

```kotlin
// build.gradle.kts (provider side)
plugins {
    id("au.com.dius.pact") version "4.6.14"
}

dependencies {
    testImplementation("au.com.dius.pact.provider:junit5:4.6.14")
    testImplementation("au.com.dius.pact.provider:junit5spring:4.6.14")
    testImplementation("org.springframework.boot:spring-boot-starter-test")
}

pact {
    serviceProviders {
        register("order-service") {
            providerVersion = providers.gradleProperty("git.sha").orElse("0.0.0")
            providerBranch = providers.gradleProperty("git.branch").orElse("main")

            fromPactBroker {
                selectors = latestTags("main", "prod")
                url = "https://pacts.example.com"
            }
        }
    }
}
```

The `pactPublish` task (consumer) and `pactVerify` task (provider) are wired by the plugin.

---

## 2. Consumer-side test (REST)

The consumer writes a JUnit 5 test annotated with `@ExtendWith(PactConsumerTestExt::class)`. The DSL describes the expected interaction; Pact spins up a mock HTTP server on a random port; the consumer's HTTP client points at that mock; the assertions are on the consumer's *own* behaviour after receiving the response.

```kotlin
@ExtendWith(PactConsumerTestExt::class)
@PactTestFor(providerName = "order-service", pactVersion = PactSpecVersion.V3)
class OrderClientPactTest {

    @Pact(consumer = "shipment-service")
    fun `pact for fetching a paid order`(builder: PactDslWithProvider): RequestResponsePact =
        builder
            .given("a paid order with id 11111111-1111-1111-1111-111111111111")
            .uponReceiving("a request to fetch a paid order")
                .path("/api/v1/orders/11111111-1111-1111-1111-111111111111")
                .method("GET")
                .headers("Accept", "application/json")
            .willRespondWith()
                .status(200)
                .headers(mapOf("Content-Type" to "application/json"))
                .body(newJsonBody {
                    it.stringValue("id", "11111111-1111-1111-1111-111111111111")
                    it.stringValue("status", "PAID")
                    it.numberValue("totalAmountMinor", 15000)
                    it.stringValue("currency", "EUR")
                    it.array("lines") { lines ->
                        lines.`object` { line ->
                            line.stringValue("productId", "p-1")
                            line.numberValue("quantity", 2)
                        }
                    }
                }.build())
            .toPact()

    @Test
    fun `client deserialises and exposes a paid order`(mockServer: MockServer) {
        val client = OrderClient(baseUrl = mockServer.getUrl())

        val order = client.fetchOrder(UUID.fromString("11111111-1111-1111-1111-111111111111"))

        assertThat(order.status).isEqualTo(OrderStatus.PAID)
        assertThat(order.totalAmount).isEqualTo(Money(15000, "EUR"))
        assertThat(order.lines).hasSize(1)
        assertThat(order.lines.single().quantity).isEqualTo(2)
    }
}
```

A few Kotlin-specific notes:

- **Backtick test names work** — they survive Pact's reflection-based pact-file generation. Use them for readability. The pact file `description` field is taken from the `uponReceiving(...)` string, not from the test method name; both should be human-readable.
- **`PactDslWithProvider` is fluent-Java**; the builder pattern reads cleanly enough in Kotlin without further wrapping.
- **The mock server is injected** as a `MockServer` parameter. Its `getUrl()` returns the random-port URL; configure the HTTP client to use it.
- **The assertions are on the *consumer's* behaviour** — not on the pact's request shape. The pact captures the request automatically; the test asserts on `order.status`, `order.totalAmount` — i.e., does the consumer correctly *use* the response?

### `newJsonBody` vs `LambdaDsl.newJsonBody`

The `newJsonBody { ... }` form above uses `LambdaDsl.newJsonBody`, the lambda-friendly Pact body builder. The older form `PactDslJsonBody().stringValue(...).numberValue(...)` works too, but reads less well in Kotlin. Pick one and stay consistent. The lambda form has the additional advantage of nested-scope syntax for arrays and objects.

### Matching rules — match what the consumer actually reads

The consumer should not over-specify. If the consumer reads only `.status` and `.totalAmountMinor`, the pact should only assert those. Pact's `like()`, `eachLike()`, `stringType()`, `numberType()` matchers allow type-only matching for fields the consumer reads but does not care about specific values:

```kotlin
.body(newJsonBody {
    it.stringMatcher("id", "^[0-9a-f-]{36}$")    // any UUID
    it.stringValue("status", "PAID")             // exact — the consumer branches on this
    it.numberType("totalAmountMinor", 15000)     // any number — only the type matters
}.build())
```

The discipline: `stringValue` / `numberValue` (exact) for fields the consumer branches on; type matchers (`stringType` / `numberType` / `like`) for fields the consumer merely passes through; **don't specify** fields the consumer does not read at all.

---

## 3. Consumer-side test (Kafka / message)

For asynchronous messaging, Pact uses `MessagePact` instead of `RequestResponsePact`. There is no mock HTTP server — instead, the test feeds a pact-defined message into the consumer's handler and asserts on the handler's behaviour.

```kotlin
@ExtendWith(PactConsumerTestExt::class)
@PactTestFor(providerName = "order-service", providerType = ProviderType.ASYNCH)
class OrderEventHandlerPactTest {

    @Pact(consumer = "inventory-service")
    fun `pact for OrderPaid event`(builder: MessagePactBuilder): MessagePact =
        builder
            .hasPactWith("order-service")
            .given("an order has been paid")
            .expectsToReceive("an OrderPaid event")
                .withMetadata(mapOf(
                    "kafka_topic" to "order.paid.v1",
                    "contentType" to "application/json",
                ))
                .withContent(newJsonBody {
                    it.stringMatcher("orderId", "^[0-9a-f-]{36}$")
                    it.stringValue("eventType", "OrderPaid")
                    it.array("lines") { lines ->
                        lines.`object` { line ->
                            it.stringValue("productId", "p-1")
                            it.numberValue("quantity", 2)
                        }
                    }
                }.build())
            .toPact()

    @Test
    fun `handler decrements stock for each ordered line`(messages: List<Message>) {
        val handler = OrderPaidHandler(stockService = stockServiceStub)

        val message = messages.single()
        handler.handle(OrderPaidEvent.fromJson(message.contentsAsString()))

        verify(stockServiceStub).decrement("p-1", quantity = 2)
    }
}
```

Key points:

- **`providerType = ProviderType.ASYNCH`** in `@PactTestFor` switches from HTTP-mock semantics to message semantics.
- **The test parameter is `List<Message>`**, not a `MockServer`. Each element corresponds to one `expectsToReceive` block.
- **The handler is exercised directly** — Pact does not start Kafka. The contract captures the message shape and topic metadata; the actual broker is tested in integration tests.
- **`kafka_topic`** in metadata is convention. The provider's verification will check the produced message's topic matches.

---

## 4. Publishing pacts to the broker

Running `./gradlew test` generates pact files in `build/pacts/`. Running `./gradlew pactPublish` uploads them to the broker:

```bash
./gradlew test pactPublish \
  -Pgit.sha=$GIT_SHA \
  -Pgit.branch=$GIT_BRANCH \
  -Ppact.broker.user=$PACT_USER \
  -Ppact.broker.password=$PACT_PASSWORD
```

The `consumerVersion` defaults to the git SHA; the `consumerBranch` defaults to the git branch. Both are queryable in the broker — the matrix view groups pacts by `(consumer, version, branch)`.

For pre-merge CI: publish with branch `pr-NNNN`. For main branch: publish with branch `main` (the broker tags it accordingly). The provider verifies against `selectors = latestTags("main", "prod")` — only the latest main and the latest prod pacts.

---

## 5. Provider verification

The provider side replays each consumer pact against the **real** provider, with the data the contract requires set up by **provider state handlers**.

```kotlin
@Provider("order-service")
@PactBroker(
    host = "pacts.example.com",
    scheme = "https",
    authentication = PactBrokerAuth(username = "\${pact.broker.user}", password = "\${pact.broker.password}"),
)
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@Testcontainers
class OrderServicePactVerificationTest {

    companion object {
        @Container
        @ServiceConnection
        val postgres = PostgreSQLContainer("postgres:16-alpine")
    }

    @LocalServerPort
    private var port: Int = 0

    @Autowired
    private lateinit var orderRepository: OrderRepository

    @BeforeEach
    fun setUp(context: PactVerificationContext) {
        context.target = HttpTestTarget("localhost", port)
    }

    @TestTemplate
    @ExtendWith(PactVerificationInvocationContextProvider::class)
    fun verify(context: PactVerificationContext) {
        context.verifyInteraction()
    }

    @State("a paid order with id 11111111-1111-1111-1111-111111111111")
    fun setUpPaidOrder() {
        orderRepository.save(
            OrderEntity(
                id = UUID.fromString("11111111-1111-1111-1111-111111111111"),
                status = OrderStatus.PAID,
                totalAmountMinor = 15000,
                currency = "EUR",
                lines = listOf(OrderLineEntity(productId = "p-1", quantity = 2)),
            )
        )
    }

    @State("an order has been paid")
    fun setUpOrderPaidEvent(): Map<String, Any> {
        // For message pacts, the @State handler returns the payload context the
        // pact framework feeds into the producer.
        return mapOf(
            "orderId" to "11111111-1111-1111-1111-111111111111",
            "lines" to listOf(mapOf("productId" to "p-1", "quantity" to 2)),
        )
    }
}
```

Key points:

- **`@Provider("order-service")`** matches the `providerName` in consumer pacts.
- **`@PactBroker(...)`** points the verification job at the broker. Selectors / version / branch are configured via the Gradle `pact { }` block or system properties.
- **`@TestTemplate` + `PactVerificationInvocationContextProvider`** generates one JUnit test per interaction in the matched pacts. Each test runs the request, replays the response, asserts shape.
- **`@State("...")`** handlers match the `.given(...)` strings in consumer pacts. The handler sets up the data the contract requires. The matched string is the contract's *contract* — change either side and the verification stops finding a state handler (a fast feedback signal).
- **State handlers should be self-contained** — set up fresh data each time; do not depend on test ordering or shared fixtures.

### Message provider verification

For `MessagePact` interactions, the provider doesn't expose an HTTP endpoint — it produces a message. The `@PactVerifyProvider("<description>")` annotation marks the method whose return value is the produced message:

```kotlin
@PactVerifyProvider("an OrderPaid event")
fun produceOrderPaidEvent(): String {
    val event = OrderPaidEvent(
        orderId = UUID.fromString("11111111-1111-1111-1111-111111111111"),
        eventType = "OrderPaid",
        lines = listOf(OrderLine("p-1", 2)),
    )
    return objectMapper.writeValueAsString(event)
}
```

Pact compares the returned JSON against the contract's expected message body. **Don't actually publish to Kafka here** — the test exercises the serialisation contract, not the broker integration. Kafka integration belongs in slice tests.

---

## 6. The CI wiring

```yaml
# .github/workflows/consumer-ci.yml (excerpt)
- name: Consumer test + publish pact
  run: ./gradlew test pactPublish -Pgit.sha=${{ github.sha }} -Pgit.branch=${{ github.ref_name }}

- name: can-i-deploy
  if: github.ref == 'refs/heads/main'
  run: |
    pact-broker can-i-deploy \
      --pacticipant shipment-service \
      --version ${{ github.sha }} \
      --to-environment production

- name: deploy
  if: success() && github.ref == 'refs/heads/main'
  run: ./deploy.sh
```

```yaml
# .github/workflows/provider-ci.yml (excerpt)
- name: Provider verification
  run: ./gradlew pactVerify -Pgit.sha=${{ github.sha }} -Pgit.branch=${{ github.ref_name }}

- name: Tag provider version in broker (after deploy)
  if: github.ref == 'refs/heads/main'
  run: |
    pact-broker record-deployment \
      --pacticipant order-service \
      --version ${{ github.sha }} \
      --environment production
```

The provider's `pactVerify` task publishes verification results back to the broker automatically (the plugin handles it). The broker's matrix is updated; the next consumer's can-i-deploy will see the new compatibility data.

---

## 7. Kotlin-specific gotchas

- **`Map<String, Any?>` literals vs `mapOf(...)`.** Pact's body builders sometimes expect a Java `Map`; Kotlin's `mapOf(...)` returns `kotlin.collections.Map` which inherits from Java's `Map` — it works, but mixing nullable values (`"foo" to null`) inside a Pact body produces unhelpful runtime errors. Use the lambda DSL (`newJsonBody { ... }`) which is type-safe.
- **`PactDslJsonBody` mutates in place.** The Java-fluent DSL returns the same instance from every method. Don't try to "share" a `PactDslJsonBody` across two pacts — copy or rebuild.
- **`@State` handlers run inside the SpringBootTest context.** They have access to `@Autowired` beans, but they run *before each interaction*. If a state handler modifies global state (e.g. inserts rows), clean up between tests — the provider verification does not roll back.
- **Database state.** A common pattern: `@BeforeEach` truncates relevant tables; each `@State` handler inserts fresh data. Don't rely on `@Transactional` rollback — Pact's invocation context is outside Spring's test transaction semantics.
- **Coroutines and async clients.** If the consumer uses a coroutine HTTP client (Ktor, Spring's `WebClient` with `awaitBody`), `runBlocking { ... }` inside the test works fine — Pact's mock server is HTTP, not API-aware.
- **Data classes as fixtures.** Define a `data class OrderResponse(...)` matching the consumer's view of the provider's response; deserialise the pact's mock response into it and assert with AssertJ / Kotest matchers. The data class is the consumer's *internal* representation, not the pact contract.
- **Backtick test names** are kept verbatim by Pact in the pact file's `description` field if you don't set `uponReceiving` — but you *should* set `uponReceiving` explicitly, because it's the human-readable label in the broker UI.

---

## 8. A realistic end-to-end shape

Two services: `shipment-service` (consumer) needs to know when an order is paid; `order-service` (provider) exposes a REST endpoint and publishes a Kafka event.

**Consumer side**:

- `OrderClientPactTest` — REST pact for `GET /api/v1/orders/{id}` returning a paid order. Asserts that `OrderClient.fetchOrder(...)` correctly parses status and total.
- `OrderPaidEventHandlerPactTest` — message pact for `order.paid.v1` topic. Asserts that the handler decrements stock correctly.

Both publish to the broker as `shipment-service` consumer pacts against `order-service` provider.

**Provider side**:

- `OrderServicePactVerificationTest` — `@Provider("order-service")`, Spring Boot test with Testcontainers Postgres. State handlers for both the REST and message pacts. The same test class verifies both — Pact JVM groups them by provider name, not by sync/async.

**Broker view**:

- 2 pacts under `(shipment-service, order-service)` — one HTTP, one async.
- Provider verification results keyed by `(consumer-version, provider-version)`.
- can-i-deploy queries answer either side.

The deploy gate on `shipment-service` prevents deploys that would require a provider version not yet in production. The deploy gate on `order-service` prevents deploys that break any currently-deployed consumer. Both teams ship independently.

---

## 9. Anti-patterns specific to Pact JVM in Kotlin

- **Using `@PactTestFor` without `providerName`.** The provider name links the pact to the right provider in the broker. Without it, the pact is published under "unknown" — confusing and easy to miss.
- **Forgetting `pactVersion = PactSpecVersion.V3`.** V3 supports provider states with parameters, message pacts, and matching rules properly. V2 is legacy.
- **Returning Kotlin `Map` from a `@State` handler when the consumer used `MessagePact`.** The map is the producer's *parameter context* — typed as `Map<String, Any>` by Pact. Match keys exactly to what the contract's `given(...)` parameters reference.
- **Asserting the full response body in the consumer test.** Assert only what the consumer reads. Use type matchers for everything else. Over-specification is the #1 cause of brittle provider verifications.
- **One pact class per endpoint.** A pact class per *consumer use case* is the right granularity. One use case may exercise two endpoints; one endpoint may serve two use cases — each is a separate pact interaction, but they can co-exist in one test class.
- **Sharing a `@State` handler across unrelated interactions.** State handlers should be small and specific. A single "set up the world" state handler used by 12 interactions makes failures hard to localise.
