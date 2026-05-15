# Boundaries — wrap third-party types behind a seam you own

A boundary is wherever your code meets code you don't control (third-party library, vendor SDK, an unbuilt teammate's service, a framework whose types you'd rather not braid into your domain). The thin seam you own translates between the two.

## Output template — when reviewing boundary code

1. **Where's the boundary?** Identify the third-party type entering / leaving.
2. **Is the seam thin?** Vendor types stop at the adapter; the rest of the code speaks your domain.
3. **Smells found.** Vendor types in domain code, no Adapter, no Learning Test on SDK upgrade.
4. **Action plan.** Introduce port → adapter → translate exceptions → fake for tests.

## Wrap-Don't-Pass — the core rule

Don't expose a third-party type in your public API. Keep `Map<String, X>`, `JsonNode`, `Stripe.Charge`, `S3Object`, `ResponseEntity<T>`, `Page<UserEntity>`, `MultipartFile` *inside* a class that owns the boundary. Public methods take and return *your* types.

```kotlin
// ✗ Leaks Map into every caller; cast at each site; mutation unprotected
class SensorRegistry {
    val sensors: MutableMap<String, Sensor> = mutableMapOf()
}
registry.sensors.clear()  // any caller can wipe the registry

// ✓ Map is hidden; the class enforces the rules
class SensorRegistry {
    private val sensors: MutableMap<String, Sensor> = mutableMapOf()
    fun byId(id: SensorId): Sensor? = sensors[id.value]
    fun register(sensor: Sensor) { sensors[sensor.id.value] = sensor }
}
```

The rule applies to every foreign type: `JsonNode`, vendor DTOs, framework response wrappers, ORM page results.

## Wishful Interface + Adapter — for collaborators that don't exist yet

When a dependency hasn't been built (teammate's subsystem, unbuilt vendor SDK, service whose API is still in flight), define the interface you **wish you had** and code against it now. Adapt later.

```kotlin
// 1. Wishful interface — what client code wants to say
interface Transmitter {
    fun key(frequency: Frequency, stream: AudioStream)
}

// 2. Client code today — depends on YOUR interface, fully testable
class CommunicationsController(private val transmitter: Transmitter) {
    fun broadcast(channel: Channel, audio: AudioStream) =
        transmitter.key(channel.frequency, audio)
}

// 3. Tomorrow — when the real subsystem ships, write the adapter once
class TransmitterAdapter(private val vendor: TransmitterSdkClient) : Transmitter {
    override fun key(frequency: Frequency, stream: AudioStream) {
        val response = vendor.tune(frequency.hz, stream.toBytes())
        if (response.status != Ok) throw TransmitterUnreachable(response.code)
    }
}

// 4. Tests — substitute a Fake of YOUR interface; never mock the vendor SDK
class FakeTransmitter : Transmitter {
    val keyed = mutableListOf<Pair<Frequency, AudioStream>>()
    override fun key(frequency: Frequency, stream: AudioStream) {
        keyed += frequency to stream
    }
}
```

Three wins: you're not blocked, client code stays readable, one place changes when the real vendor arrives.

## Learning Tests — pin the third-party API in a test

You have to learn an SDK before you use it. Do that learning in a **test**, not in production.

```kotlin
class StripeLearningTest {
    @Test fun `creating a charge returns a charge id`() {
        val charge = StripeClient(testKey).charges.create(
            ChargeCreateParams.builder().setAmount(100).setCurrency("usd").setSource("tok_visa").build()
        )
        assertThat(charge.id).startsWith("ch_")
        assertThat(charge.status).isEqualTo("succeeded")
    }
}
```

Earns its keep three ways:
- You were going to read the docs anyway — encode what you learned as a test.
- **Free regression suite** on SDK upgrade. Bump v24 → v25, run the learning tests, find behavioural drift immediately.
- Shrinks debugging surface — when business code fails, you already know the vendor behaves as expected.

In Spring Boot, the learning test often becomes an **outbound boundary test** that exercises *your* adapter against the real (or close-to-real) vendor — Testcontainers for databases / Kafka, WireMock for HTTP.

## `typealias` is NOT encapsulation

```kotlin
// ✗ Type alias is a compile-time rename, not a wrapper
typealias OrderId = String
fun ship(id: OrderId) { ... }
ship("any-string-still-fine")  // compiler accepts; no type safety
```

Use `@JvmInline value class` if you want type safety:

```kotlin
@JvmInline value class OrderId(val value: UUID)
```

## Smell → fix lookup

| Smell | Fix |
|---|---|
| Public method returns `Map<String, Any?>` / `JsonNode` / vendor DTO | Wrap in a domain type. |
| Controller `@RequestBody` is a JPA `@Entity` | Introduce a `Request` / `Response` data class; map at the controller. |
| Service signature includes `Pageable`, `Authentication`, `HttpServletRequest` | Extract what's needed at the controller; pass primitives/domain types into the service. |
| `Mono<T>` / `Flux<T>` in domain interfaces of an imperative service | Convert at the reactive seam; keep reactive types inside the adapter. |
| `catch (e: VendorException)` in business code | Translate inside the adapter to a domain exception. Business code catches only domain exceptions. |
| Repeated direct calls to `RestTemplate` / `WebClient` / vendor SDK across services | Extract a `*Client` interface + adapter; services depend on the interface. |
| Mock of a vendor SDK in many tests | Define a domain interface; substitute a Fake. |
| `typealias VendorOrder = stripe.com.Charge` "wraps" the vendor type | Not encapsulation. Wrap with a class / value class. |
| Two teams write parallel adapters for the same vendor | Consolidate into one boundary module; both depend on it. |
| Vendor SDK upgrade causes diff in 30 files | Adapter wasn't thin enough. After unbundling, diff should fit one file. |

## Anti-patterns in boundary work itself

- **Wrapping for the sake of wrapping.** A 1:1 passthrough adapter that adds zero translation is dead weight.
- **Adapter that leaks vendor types out the back.** An interface returning `WebClientResponseException` hasn't created a boundary; it moved the leak by one method.
- **Mocking the vendor SDK in unit tests.** Mocking `WebClient`'s fluent chain breaks on every SDK upgrade. Mock *your* interface instead; verify the adapter with one integration test.
- **Adapter and domain logic in the same class.** When an `@Component` is also calling `webClient.post(...)`, translation and orchestration are conflated.
- **Premature seam.** Drawing an adapter around a stable JDK type (`java.time.Instant`) or your own internal class adds ceremony without benefit.
- **Refactoring across an unstable seam without learning tests.** Bumping the SDK *and* refactoring the adapter in the same PR removes the safety net.
- **The kitchen-sink adapter.** One `IntegrationsService` adapting Stripe, Slack, Twilio, and S3 is a god class. One adapter per vendor.
