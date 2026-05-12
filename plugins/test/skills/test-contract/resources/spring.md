# Spring Cloud Contract — Patterns, Examples, and the OpenAPI Alternative

Spring Cloud Contract (SCC) is the Spring team's house tool for consumer-driven contracts. It differs from Pact in two important ways:

1. **Contracts are written by hand**, by convention in the **provider** repo (`src/test/resources/contracts/`), in Groovy / YAML / Kotlin DSL.
2. **Consumer stubs and provider tests are generated** — the SCC plugin compiles each contract into (a) a WireMock stub the consumer downloads and runs against, and (b) a JUnit test class the provider runs to verify itself against the contract.

This document covers SCC patterns, the SCC vs Pact tradeoff, the Kotlin DSL form of contracts, SCC + Kafka, and OpenAPI-driven contract testing as a third option.

---

## 1. SCC at a glance

```
   ┌──────────────────┐   contract DSL        ┌──────────────────────┐
   │  Provider repo   ├──────────────────────▶│  SCC Gradle plugin   │
   │                  │                       │                      │
   │  contracts/      │                       │  Generates:          │
   │   getOrder.yml   │                       │  - WireMock stubs    │
   │                  │                       │  - Provider tests    │
   └──────────────────┘                       └──────┬───────────────┘
                                                     │
                ┌────────────────────────────────────┼─────────────────┐
                │                                    │                 │
                ▼                                    ▼                 ▼
   ┌──────────────────────┐         ┌──────────────────────┐   ┌─────────────────┐
   │  Stubs JAR published │         │  Provider tests run   │   │  Consumer pulls │
   │  to Artifactory      │         │  against real         │   │  stubs JAR,     │
   │  /Nexus              │         │  provider, asserts    │   │  runs WireMock  │
   │                      │         │  contract             │   │                 │
   └──────────────────────┘         └──────────────────────┘   └─────────────────┘
```

The two-side flow is the same as Pact (consumer pulls something, provider proves it satisfies something), but the artefact ownership is inverted: the contract lives in the provider's repo, written by the provider team **in consultation with consumers**.

SCC's design assumes a Spring-only estate where teams communicate well and the provider can reasonably author contracts on the consumers' behalf. In a multi-team polyglot setup this assumption fails; in a Spring-monorepo or Spring-multi-repo where teams sit nearby, it works fine.

---

## 2. A contract in Kotlin DSL

The Kotlin DSL is the most readable form for Spring teams. (Groovy DSL is older and still common; YAML is more limited.)

```kotlin
// src/test/resources/contracts/orders/get_paid_order.kts
import org.springframework.cloud.contract.spec.ContractDsl.Companion.contract
import org.springframework.cloud.contract.spec.internal.HttpMethods

contract {
    name = "GET paid order by id"
    description = "Returns a paid order with id 11111111-1111-1111-1111-111111111111"

    request {
        method = HttpMethods.GET
        url = url("/api/v1/orders/11111111-1111-1111-1111-111111111111")
        headers {
            accept = applicationJson
        }
    }

    response {
        status = OK
        headers {
            contentType = applicationJson
        }
        body(mapOf(
            "id" to "11111111-1111-1111-1111-111111111111",
            "status" to "PAID",
            "totalAmountMinor" to 15000,
            "currency" to "EUR",
            "lines" to listOf(mapOf(
                "productId" to "p-1",
                "quantity" to 2,
            )),
        ))
        bodyMatchers {
            jsonPath("$.id", byRegex("^[0-9a-f-]{36}$"))
            jsonPath("$.totalAmountMinor", byType())
        }
    }
}
```

Key points:

- **Contracts live under `src/test/resources/contracts/`** in the provider repo. SCC discovers them at build time.
- **`bodyMatchers` decouples the stub from exact values** — the stub returns the literal body to the consumer, but the *provider verification* uses the matchers (regex / type) to assert it. The same contract therefore satisfies both sides without over-specifying.
- **The contract name and description** appear in generated test names and in the broker (if you publish to Pact Broker via Pactflow's bidirectional contract feature; otherwise they're just documentation).
- **No HTTP server starts here** — the contract is a declarative artefact. The SCC plugin compiles it into runnable tests / stubs.

---

## 3. Provider side — generated tests

The SCC Gradle plugin generates a JUnit test class per contract directory:

```kotlin
// build/generated-test-sources/contractTest/.../OrdersTest.kt (generated, do not edit)
class OrdersTest : OrderServiceContractTestBase() {

    @Test
    fun validate_get_paid_order_by_id() {
        val request = given()
            .header("Accept", "application/json")
            .`when`()
            .get("/api/v1/orders/11111111-1111-1111-1111-111111111111")

        val response = request.then()
            .statusCode(200)
            .header("Content-Type", "application/json")

        val responseBody = response.extract().body().asString()
        assertThat(JsonPath(responseBody).get<String>("$.id")).matches("^[0-9a-f-]{36}$")
        assertThat(JsonPath(responseBody).get<Any>("$.totalAmountMinor")).isInstanceOf(Number::class.java)
        // ... etc, generated from the contract
    }
}
```

You write the **base class** that the generated tests extend. The base class is where the real provider gets stood up:

```kotlin
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@Testcontainers
@AutoConfigureMockMvc
abstract class OrderServiceContractTestBase {

    companion object {
        @Container
        @ServiceConnection
        val postgres = PostgreSQLContainer("postgres:16-alpine")
    }

    @Autowired
    private lateinit var orderRepository: OrderRepository

    @LocalServerPort
    private var port: Int = 0

    @BeforeEach
    fun setUp() {
        RestAssured.port = port
        seedPaidOrder()
    }

    private fun seedPaidOrder() {
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
}
```

`build.gradle.kts` (provider):

```kotlin
plugins {
    id("org.springframework.cloud.contract") version "4.1.4"
}

contracts {
    testFramework = "JUNIT5"
    baseClassMappings {
        baseClassMapping(".*orders.*", "com.example.order.OrderServiceContractTestBase")
    }
    contractsDslDir = file("src/test/resources/contracts")
}

dependencies {
    testImplementation("org.springframework.cloud:spring-cloud-starter-contract-verifier:4.1.4")
}
```

Running `./gradlew check`:

1. SCC plugin reads contracts from `src/test/resources/contracts/`.
2. Generates JUnit tests under `build/generated-test-sources/contractTest/`.
3. Generates WireMock stub mappings under `build/stubs/`.
4. Runs the generated tests against the real provider.
5. Packages the stubs into a `stubs` classifier JAR.
6. `./gradlew publish` publishes the JAR (typically with classifier `stubs`) to Nexus / Artifactory.

---

## 4. Consumer side — stub-runner

Consumers pull the stubs JAR and run it via SCC's stub-runner. WireMock starts on a port; the consumer's HTTP client points at it.

```kotlin
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.NONE)
@AutoConfigureStubRunner(
    ids = ["com.example:order-service:+:stubs:8090"],
    stubsMode = StubRunnerProperties.StubsMode.LOCAL,
)
class OrderClientContractTest {

    private lateinit var client: OrderClient

    @BeforeEach
    fun setUp() {
        client = OrderClient(baseUrl = "http://localhost:8090")
    }

    @Test
    fun `client deserialises a paid order from the stub`() {
        val order = client.fetchOrder(UUID.fromString("11111111-1111-1111-1111-111111111111"))

        assertThat(order.status).isEqualTo(OrderStatus.PAID)
        assertThat(order.totalAmount).isEqualTo(Money(15000, "EUR"))
    }
}
```

Key points:

- **`ids = ["com.example:order-service:+:stubs:8090"]`** — Maven coordinates of the stubs JAR; `+` means latest; `8090` is the WireMock port.
- **`StubsMode.LOCAL`** uses the local Maven cache; `REMOTE` pulls from a repository; `CLASSPATH` finds them on the test classpath.
- **The test asserts on the consumer's own behaviour** — `client.fetchOrder(...)` returns an `Order`; assert on `Order` properties, not on the stub's response.

In CI:

```yaml
# Consumer CI
- name: Resolve provider stubs
  run: ./gradlew test  # downloads stubs JAR from Artifactory automatically
```

The dependency on the provider's stubs JAR is just a Gradle dependency. Versioning, caching, and resolution are standard Gradle — no extra infrastructure.

---

## 5. SCC + Kafka — message contracts

SCC supports message contracts via `input` (consumer triggers a function that publishes a message) and `outputMessage` (the message the producer is expected to produce):

```kotlin
// src/test/resources/contracts/order_paid_event.kts
import org.springframework.cloud.contract.spec.ContractDsl.Companion.contract

contract {
    name = "OrderPaid event"
    description = "Published when an order transitions to PAID"

    label = "trigger_order_paid"   // referenced by the consumer test

    input {
        triggeredBy("triggerOrderPaidEvent()")   // calls a Kotlin method in the base class
    }

    outputMessage {
        sentTo("order.paid.v1")
        body(mapOf(
            "orderId" to "11111111-1111-1111-1111-111111111111",
            "eventType" to "OrderPaid",
            "lines" to listOf(mapOf("productId" to "p-1", "quantity" to 2)),
        ))
        headers {
            header("contentType", "application/json")
        }
        bodyMatchers {
            jsonPath("$.orderId", byRegex("^[0-9a-f-]{36}$"))
        }
    }
}
```

Provider base class:

```kotlin
abstract class OrderEventContractTestBase {

    @Autowired
    private lateinit var orderEventPublisher: OrderEventPublisher

    fun triggerOrderPaidEvent() {
        orderEventPublisher.publish(
            OrderPaidEvent(
                orderId = UUID.fromString("11111111-1111-1111-1111-111111111111"),
                lines = listOf(OrderLine("p-1", 2)),
            )
        )
    }
}
```

SCC intercepts the published message (via a `MessageVerifier` configured per binder — Kafka, RabbitMQ, JMS, Camel) and asserts it matches the contract's `outputMessage`. **The Kafka container is not started for this test** — SCC tests the *production-path serialisation*, not the broker integration. Kafka integration belongs in slice tests with a `KafkaContainer`.

Consumer side for message contracts:

```kotlin
@SpringBootTest
@AutoConfigureStubRunner(ids = ["com.example:order-service:+:stubs"])
class OrderEventHandlerContractTest {

    @Autowired
    private lateinit var stubTrigger: StubTrigger

    @Autowired
    private lateinit var stockService: StockService

    @Test
    fun `handler decrements stock when OrderPaid event is triggered`() {
        stubTrigger.trigger("trigger_order_paid")    // the contract's `label`

        verify(stockService, timeout(1000)).decrement("p-1", quantity = 2)
    }
}
```

The `stubTrigger` injects the contract's `outputMessage` into the consumer's message-handling infrastructure (the Spring messaging channel / Kafka listener container), bypassing the actual broker. The consumer's handler runs; `stockService.decrement` is invoked; the test asserts.

---

## 6. SCC vs Pact — the decision

| Dimension | SCC | Pact |
|---|---|---|
| Contract authoring | Provider writes by hand (Groovy / YAML / Kotlin DSL) | Generated from consumer test, by construction |
| "Who owns the contract" | Provider, with consumer input | Consumer |
| Storage | Maven / Gradle artifact (`stubs` JAR) | Pact Broker / Pactflow |
| can-i-deploy | Not native; can be approximated with version selectors | First-class CLI command + UI |
| Polyglot consumers | JVM-only in practice | First-class (Ruby, JS, Go, Python, .NET, Rust) |
| Provider-side test generation | Yes — generates JUnit tests from contracts | No — provider writes one `@TestTemplate` invocation |
| Consumer-side stub | WireMock stub | Pact-generated HTTP mock |
| Message contracts | Yes (`input` / `outputMessage`) | Yes (`MessagePact`) |
| Broker UI / matrix view | No (use the JAR repository) | Yes |
| Webhook-driven CI | Possible via JAR repo events | First-class |
| Maintenance burden | Lower if Spring-only and provider authors contracts well | Higher infrastructure (broker), lower discipline cost |
| Right when | Single team or close-cooperating teams, Spring-only, no broker appetite | Multi-team, polyglot, broker-as-source-of-truth |

**Rule of thumb**: if the team is asking "do we need a broker?" the answer for SCC is "no, you have one already (Artifactory)" and for Pact is "yes, that's the point". For most Spring-house multi-team estates, Pact pays back the broker cost. For Spring-monorepo single-team estates, SCC is friction-free.

**Don't run both for the same pair of services**. The artefacts will diverge and neither will be trustworthy.

---

## 7. OpenAPI-driven contract testing — the lighter option

A third option, often underrated:

- The provider's OpenAPI spec is **generated from the controllers** (Springdoc, `springdoc-openapi-starter-webmvc-ui`).
- The OpenAPI spec is **published as an artefact** (versioned).
- The consumer uses a tool — `spring-cloud-contract-openapi`, `swagger-request-validator`, `assertj-swagger`, or a custom checker — to verify its calls and parsing match the spec.
- The provider verifies its responses match the spec (typically via `MockMvc` + a request/response validator filter).

What you get:

- **Schema and types** are pinned down.
- **Status codes** are pinned down.
- **Required fields** are pinned down.

What you don't get:

- **Per-scenario** assertions (Pact `given(...)` semantics). The OpenAPI spec says "this endpoint can return 200 or 422"; it does not say "given a paid order, the response is X".
- **Provider state setup discipline.**
- **can-i-deploy.**

**When OpenAPI-driven is enough**:

- The provider's API is fundamentally CRUD-shaped, with no rich per-scenario behaviour worth pinning.
- The team has discipline about keeping the OpenAPI spec accurate (it's generated, so it almost can't drift).
- The cross-service incompatibility risk is "wrong type / removed field" rather than "different semantics".

**When OpenAPI-driven is not enough**: anything with state-dependent responses, where the consumer cares about a specific scenario, where conditional 200/422 branches matter, where async / Kafka contracts are part of the picture. Use Pact or SCC.

A pragmatic hybrid: OpenAPI as the **schema floor** for every endpoint (cheap, generated, exhaustive); Pact / SCC for the **load-bearing scenarios** where the consumer's logic branches on the response. This combination is often the right shape for a Spring service with 20 endpoints, 3 of which are critically depended on.

---

## 8. A small end-to-end SCC example — `OrderService`

The provider `order-service` exposes one endpoint and one Kafka event. The consumer `shipment-service` reads the endpoint and consumes the event.

**Provider contracts** (`src/test/resources/contracts/orders/`):

```kotlin
// get_paid_order.kts
contract {
    name = "GET paid order by id"
    request {
        method = GET
        url = url("/api/v1/orders/11111111-1111-1111-1111-111111111111")
    }
    response {
        status = OK
        body(mapOf(
            "id" to "11111111-1111-1111-1111-111111111111",
            "status" to "PAID",
            "totalAmountMinor" to 15000,
            "currency" to "EUR",
        ))
        bodyMatchers {
            jsonPath("$.id", byRegex("^[0-9a-f-]{36}$"))
            jsonPath("$.totalAmountMinor", byType())
        }
    }
}
```

```kotlin
// order_paid_event.kts
contract {
    name = "OrderPaid event"
    label = "trigger_order_paid"
    input {
        triggeredBy("triggerOrderPaidEvent()")
    }
    outputMessage {
        sentTo("order.paid.v1")
        body(mapOf("orderId" to "11111111-1111-1111-1111-111111111111", "eventType" to "OrderPaid"))
    }
}
```

**Provider base classes**: one for the REST contract (Spring Boot + Testcontainers + seeded paid order), one for the message contract (publisher + message verifier).

**Build**: `./gradlew check` runs SCC's generated tests + your normal tests. `./gradlew publish` ships the `order-service-1.2.3-stubs.jar` to Artifactory.

**Consumer stubs**:

```kotlin
@SpringBootTest
@AutoConfigureStubRunner(
    ids = ["com.example:order-service:+:stubs:8090"],
    stubsMode = StubRunnerProperties.StubsMode.LOCAL,
)
class ShipmentServiceContractTest {

    @Autowired
    private lateinit var stubTrigger: StubTrigger

    @Autowired
    private lateinit var orderClient: OrderClient

    @Autowired
    private lateinit var stockService: StockService

    @Test
    fun `fetches a paid order from the stub`() {
        val order = orderClient.fetchOrder(UUID.fromString("11111111-1111-1111-1111-111111111111"))
        assertThat(order.status).isEqualTo(OrderStatus.PAID)
    }

    @Test
    fun `decrements stock on triggered OrderPaid event`() {
        stubTrigger.trigger("trigger_order_paid")
        verify(stockService, timeout(1000)).decrement(any(), anyInt())
    }
}
```

**CI**: consumer CI depends on the provider's published stubs JAR; provider CI runs `./gradlew check` and publishes new stubs. No broker. The Maven version of the stubs JAR is the "version" of the contract; the consumer can pin (`:1.2.3:stubs`) or float (`:+:stubs`).

---

## 9. Anti-patterns specific to SCC

- **Hand-editing the generated tests.** They are regenerated on every build; edits are lost. Modify the contract, not the test.
- **Contracts written entirely by the provider with no consumer input.** SCC's design assumes the conversation happens; if it doesn't, the contracts drift into "provider's internal idea of the API" and lose the consumer-driven property.
- **One mega-contract per endpoint.** Each meaningful scenario is its own contract. A test that covers "paid order" + "draft order" + "missing order" in one contract is harder to maintain than three small ones.
- **No `bodyMatchers`.** Without matchers, the stub returns literal values *and* the provider verification asserts exact equality on every field. Use matchers for fields the provider can legitimately vary (UUIDs, timestamps, generated sequences).
- **Stubs JAR published without versioning.** A consumer pinned to `latest` will pick up breaking changes silently. Always version (git SHA or semver).
- **Skipping `triggeredBy` for message contracts.** The contract becomes purely declarative; the provider's *real* publish path is not exercised. The whole point of the message contract is to test that the real production code path produces the right message — `triggeredBy` is what links them.
- **Mixing SCC stubs and real Kafka in the same test.** SCC's message contracts use a mock message verifier; running `KafkaContainer` in the same test creates two competing pipelines and confusing failures. Test SCC contracts in isolation; test broker integration in a separate `@SpringBootTest` with `KafkaContainer`.
- **Pact and SCC for the same pair of services.** Pick one. Both produce contract artefacts and verify them; running both produces two sources of truth and an inevitable divergence.

---

## 10. Practical guidance for choosing in a Spring estate

A decision tree for a Spring team starting fresh:

1. **One team, both sides of the contract, deployed together?** → No contract test. Slice tests + shared types module.
2. **Spring-only estate, all teams co-located or close, no polyglot consumers?** → SCC. Lower setup cost; the stubs-as-Maven-artifact model fits the existing tooling.
3. **Multi-team, multi-language, want a broker for centralised visibility and can-i-deploy as a deploy gate?** → Pact. The broker cost is real, but the operational guarantees pay back.
4. **20-endpoint CRUD service, no rich per-scenario behaviour, want minimum-viable cross-service safety?** → OpenAPI-generated spec + a spec-validator filter on both sides. Add Pact or SCC only for the 2-3 load-bearing scenarios that justify it.

Don't over-engineer this. Most Spring services need *some* form of cross-service safety; few need the full Pact-Broker-with-webhooks-and-can-i-deploy machinery. Honest pragmatism here saves the team months of contract-tooling maintenance.
