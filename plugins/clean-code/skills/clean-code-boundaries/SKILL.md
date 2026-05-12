---
name: clean-code-boundaries
description: "Boundary discipline for Kotlin/Spring Boot code — practices for keeping third-party libraries, vendor SDKs, framework types, and not-yet-built collaborators on the *other* side of a thin seam you own. Adapted from R. Martin's Clean Code Ch. 8 'Boundaries' and extended with Kotlin (read-only `Map` / `List` views, the `typealias` trap, `@JvmInline value class` wrappers, `Result<T>` and `runCatching` translation, sealed 'wishful' interfaces, extension-function adapters, coroutine seams) and Spring/JPA (no `ResponseEntity` / `Pageable` / `HttpServletRequest` / JPA entities leaking out of their layer, wrapping AWS / Stripe / Slack / Feign / `WebClient` behind a domain port, `@ConfigurationProperties` over raw `Environment`, Testcontainers and `WireMock` as learning-test harnesses). Covers Wrap-Don't-Pass (don't expose third-party types in public APIs — wrap `Map`, `JsonNode`, vendor responses behind a class you own), Learning Tests (controlled experiments against an unfamiliar SDK that double as regression tests on upgrade), Wishful Interface + Adapter (define the interface you'd like and code against it now; bridge later when the real collaborator arrives), and clean Anti-Corruption Layer placement at bounded-context edges. Use when integrating a third-party SDK / vendor API / external service for the first time, wrapping a library that leaks types through your domain (`Map<String, Any?>`, `Pageable`, `JsonNode`, `ResponseEntity`, `MultipartFile`, `Mono`/`Flux` escaping the reactive seam, JPA entities crossing into controllers), refactoring a service that depends directly on an external concrete type (AWS S3 client, Stripe API, Slack SDK, raw `RestTemplate` response), preparing for a third-party library version bump (write learning tests first, run them in CI), designing code against a collaborator that doesn't exist yet (a teammate's service, an unbuilt subsystem, a vendor with no SDK), reviewing a PR where `Authentication` / `HttpServletRequest` / a JPA entity has leaked into the service layer, deciding where the ACL seam belongs between your domain and an external system, or auditing a module for direct vendor-SDK references that should be behind a single Adapter."
risk: safe
source: "Adapted from R. Martin, Clean Code (2008), ch. 8 'Boundaries' by James Grenning, filtered for Kotlin/Spring + house rules"
date_added: "2026-05-12"
---

# Clean Code: Boundaries

> "It's better to depend on something you control than on something you don't control, lest it end up controlling you." — J. Grenning
>
> "Code at the boundaries needs clear separation and tests that define expectations." — J. Grenning

A boundary is wherever your code meets code you don't control — a third-party library, a vendor SDK, a teammate's service that doesn't exist yet, a framework whose types you'd rather not braid into your domain. Providers of those interfaces optimise for broad applicability; you, the consumer, want a narrow shape tailored to your problem. That tension is permanent, and the only durable answer is **a thin seam, owned by you, that translates between the two**.

This skill is the opinionated catalog of boundary discipline: wrap-don't-pass for third-party types, learning tests to pin down unfamiliar APIs and catch breaking upgrades, the Wishful Interface + Adapter combo for collaborators that haven't been built yet, and where the seam goes in a Spring Boot application.

## Use this skill when
- Integrating a third-party SDK / vendor API / external service for the first time — design the seam before the second `import`.
- Wrapping a library whose types are leaking into your domain (`Map<String, Any?>`, `JsonNode`, `ResponseEntity`, `Pageable`, `MultipartFile`, `Mono`/`Flux` escaping the reactive layer, JPA entities reaching the controller).
- Refactoring a service that directly names a vendor concrete type — `AmazonS3`, `StripeClient`, `SlackApi`, `RestTemplate.exchange(...).body`.
- Preparing for a third-party library version bump — write the learning tests first; they double as regression tests for the bump.
- Designing code against a collaborator that doesn't exist yet (a teammate's service, an undelivered subsystem, a vendor with no public SDK) — define the interface you'd like and code against it now.
- Reviewing a PR where `Authentication`, `HttpServletRequest`, or a JPA entity has leaked out of its proper layer.
- Deciding where the Anti-Corruption Layer (ACL) belongs between your domain and an external system.
- Auditing a module for vendor-SDK references that should be behind a single Adapter.

## Do not use this skill when
- The boundary already exists and works fine — don't refactor for theology. The signal to act is *leakage* or *upcoming change*, not "could be cleaner".
- You're inside an integration test deliberately reaching into a vendor SDK to verify wire behaviour — that's where the vendor types belong.
- The task is wire-level contract design (REST/gRPC) — use `api-design-principles`.
- The task is mapping the relationship *between* bounded contexts you both own — use `ddd-context-mapping` for Customer-Supplier / OHS / Shared Kernel patterns.
- The "boundary" is a one-line dependency on a stable standard-library type (`java.time.Instant`, `java.util.UUID`) — wrapping `Instant` is overkill, not discipline.

## Core principles (the ten)

1. **Tension is inherent.** Vendors maximise generality (`Map` has 19 methods); you want a narrow shape. The seam is where you reconcile the two — and **you own the seam, not the vendor**.
2. **Wrap, don't pass.** Don't expose a third-party type in your public API. Keep `Map<String, Sensor>`, `JsonNode`, `Stripe.Charge`, `S3Object`, `ResponseEntity<T>` *inside* a class or close family of classes that own the boundary. Public methods take and return *your* types.
3. **Depend on what you control.** Every file that names a vendor type is a point of damage when the vendor's API changes. Concentrate references into one Adapter; let the rest of the code depend on **your interface**.
4. **One seam, one responsibility.** The Adapter does translation — types, errors, units, semantics — and **nothing else**. Domain logic does not live inside the Adapter; framework details do not live outside it.
5. **Wishful Interface for unknown collaborators.** When a dependency doesn't exist yet, define the interface you wish you had and code against it. Substitute a Fake in tests; bridge to the real implementation later with an Adapter. This keeps you unblocked *and* keeps client code clean.
6. **Learning Tests to pin down APIs.** Write a small test that calls the third-party SDK the way you intend to use it. The test verifies your mental model, costs nothing extra (you'd have read the docs anyway), and re-runs on every SDK upgrade to catch behavioural drift.
7. **Domain types out, vendor types in.** Across an Adapter's public methods, vendor types never appear. The Adapter accepts vendor inputs only at its private edges and emits your domain types (or vice versa).
8. **Exceptions translate at the seam.** `StripeException`, `JedisConnectionException`, `IOException`, `WebClientResponseException` become *your* domain exception (or `Result<T>` / sealed `Either` cases) inside the Adapter. The rest of the code never `catch`es a vendor type.
9. **Tests via Fakes, not vendor mocks.** Mocking a sprawling vendor SDK (every overload, every header, every error code) is brittle. A Fake of *your* interface — written once, used by every test — is faster, more accurate, and survives SDK upgrades.
10. **The boundary aligns with the context edge.** When the boundary is between your domain and another team / vendor / legacy system, the Adapter *is* the Anti-Corruption Layer. See `ddd-context-mapping` for the relationship-level pattern; this skill is the code-level discipline that implements it.

## Wrap-Don't-Pass — the core rule

The chapter's foundational example: a raw `Map` is too powerful, too liberal, and **always wrong** to pass through public APIs.

```kotlin
// ✗ Leaks Map into every caller. Each caller carries the cast.
//    Mutation is unprotected; Map's 19 methods (incl. clear()) are all reachable.
class SensorRegistry {
    val sensors: MutableMap<String, Sensor> = mutableMapOf()
}

val sensor = registry.sensors[sensorId] as? Sensor    // cast at every call site
registry.sensors.clear()                              // any caller can wipe the registry

// ✓ Map is hidden. The class enforces the rules.
class SensorRegistry {
    private val sensors: MutableMap<String, Sensor> = mutableMapOf()

    fun byId(id: SensorId): Sensor? = sensors[id.value]
    fun register(sensor: Sensor) { sensors[sensor.id.value] = sensor }
}
```

The rule applies far beyond `Map`. **Replace the type on the left with anything from the right column:** `JsonNode`, `Stripe.Charge`, `S3Object`, `WebClient.ResponseSpec`, `ResponseEntity<UserDto>`, `Page<UserEntity>`, `MultipartFile`. The same rule answers all of them: keep the foreign type inside the wrapper; expose your own.

> **Kotlin nuance.** Read-only `Map<K, V>` (vs `MutableMap<K, V>`) closes Martin's specific worry — there is no `clear()` on the read-only view. But the *encapsulation* argument still stands: if you pass `Map<SensorId, Sensor>` through your public API, you've committed to that representation forever. Wrap it. See `resources/kotlin-specific-boundaries.md`.

## Wishful Interface + Adapter — for code that doesn't exist yet

When a dependency hasn't been built — a teammate's subsystem, an unbuilt vendor SDK, a service whose API is still in flight — define the interface **you wish you had** and code against it now. Adapt later.

```kotlin
// 1. The wishful interface — what client code wants to say
interface Transmitter {
    fun key(frequency: Frequency, stream: AudioStream)
}

// 2. Client code today — depends on YOUR interface, fully testable
class CommunicationsController(private val transmitter: Transmitter) {
    fun broadcast(channel: Channel, audio: AudioStream) =
        transmitter.key(channel.frequency, audio)
}

// 3. Tomorrow — when the real subsystem ships, write the Adapter once
@Component
class TransmitterAdapter(private val vendor: TransmitterSdkClient) : Transmitter {
    override fun key(frequency: Frequency, stream: AudioStream) {
        val response = vendor.tune(frequency.hz, stream.toBytes())  // vendor types live here
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

Three things this buys you:

- **You stop being blocked** by an unfinished dependency.
- **Client code stays readable** — it speaks domain (`transmitter.key(frequency, stream)`), not vendor (`vendor.tune(...)`).
- **One place changes** when the real vendor SDK lands or evolves: the `TransmitterAdapter`.

This is the Adapter pattern, applied to the seam between *you* and *not-you-yet*. It is also exactly the Hexagonal "port + adapter" pair — see `resources/ddd-boundaries.md`.

## Learning Tests — pin the third-party API

You have to learn an SDK before you use it. Do that learning **in a test**, not in production code.

```kotlin
// resources/scratch/StripeLearningTest.kt
class StripeLearningTest {

    @Test fun `creating a charge returns a charge id`() {
        val charge = StripeClient(testKey).charges.create(
            ChargeCreateParams.builder()
                .setAmount(100)
                .setCurrency("usd")
                .setSource("tok_visa")
                .build()
        )
        assertThat(charge.id).startsWith("ch_")
        assertThat(charge.status).isEqualTo("succeeded")
    }

    @Test fun `creating a charge with no source throws InvalidRequest`() {
        assertThrows<InvalidRequestException> {
            StripeClient(testKey).charges.create(
                ChargeCreateParams.builder().setAmount(100).setCurrency("usd").build()
            )
        }
    }
}
```

Why this earns its keep:

- **You were going to read the docs anyway.** Encoding what you learned as tests costs almost nothing extra.
- **Free regression suite.** When you bump Stripe SDK 24 → 25, run the learning tests in CI. If behaviour changed, you find out immediately, in isolation, with a clear error.
- **Shrinks debugging surface.** When your business code fails, you already know the vendor's behaviour is as expected — you can focus on your own code.

In a Spring Boot codebase the learning test often becomes an **outbound boundary test** that exercises *your* Adapter against a real (or close-to-real) vendor — Testcontainers for databases / Kafka, WireMock for HTTP vendors. See `resources/spring-boot-boundaries.md` for the wiring.

## Smell → fix quick reference

| Smell | Fix |
|---|---|
| Public method returns `Map<String, Any?>` / `JsonNode` / vendor DTO | Wrap in a domain type the method returns. |
| Controller's `@RequestBody` is a JPA `@Entity` | Introduce a `Request`/`Response` data class; map at the controller. |
| Service signature includes `Pageable`, `Authentication`, `HttpServletRequest` | Extract what's needed (page number, principal id, header) at the controller; pass primitives or domain types into the service. |
| `Mono<T>` / `Flux<T>` appears in domain interfaces of an otherwise imperative service | Convert at the reactive seam (`block()` / `awaitSingle()`); keep reactive types inside the adapter. |
| `catch (e: VendorException)` in business code | Translate inside the Adapter to a domain exception (or `Result<T>` case); business code catches only domain exceptions. |
| Repeated direct calls to `RestTemplate` / `WebClient` / vendor SDK across services | Extract a `*Client` interface + Adapter; let services depend on the interface. |
| Mock of a vendor SDK (`mock<StripeClient>()`) appears in many tests | Define a domain interface; substitute a Fake in tests. |
| A 4-line `typealias VendorOrder = stripe.com.Charge` "wraps" the vendor type | `typealias` is *not* encapsulation — it's an alias. Wrap with a class / value class instead. |
| Two teams write parallel Adapters for the same vendor | Consolidate into one boundary module; both depend on it. |
| Vendor SDK upgrade causes diff in 30 files | Adapter wasn't thin enough. After unbundling, the diff should fit one file. |

## Selective Reading Rule

| File | When to read |
|---|---|
| `resources/general-boundaries-rules.md` | Martin Ch. 8 rules as a foundation — Wrap-Don't-Pass for boundary types, Learning Tests for unfamiliar APIs and SDK upgrades, Wishful Interface + Adapter for unbuilt collaborators, the four properties of a clean boundary (separation, fewer references, tests at the seam, expectations encoded). Read first. |
| `resources/kotlin-specific-boundaries.md` | What Kotlin solves *out of the box* and what it doesn't: read-only `Map`/`List` views vs the encapsulation argument, the `typealias` trap, `@JvmInline value class` for thin wrapping of vendor IDs, `Result<T>` / `runCatching` for error translation, extension functions as cheap adapters, sealed "wishful" interfaces, coroutine seams (`suspendCoroutine` / `Mono.awaitSingle()`), companion `from(...)` factories for inbound translation. |
| `resources/spring-boot-boundaries.md` | Spring/Spring Boot conventions: controllers as the only place that touches `ResponseEntity` / `Pageable` / `HttpServletRequest` / `MultipartFile`; JPA entities never crossing the repository edge (project to DTOs / use `@Query` projections / MapStruct); `WebClient` / `RestTemplate` / OpenFeign behind a `*Client` interface + `@Component` adapter; AWS / Stripe / Slack SDK wrapping; `@ConfigurationProperties` over raw `Environment`; reactive ↔ imperative seams; Testcontainers + WireMock as learning-test harnesses; Spring Modulith `NamedInterface` as a module boundary. |
| `resources/ddd-boundaries.md` | DDD applications: the Adapter as the implementation of an Anti-Corruption Layer; Hexagonal ports & adapters (inbound vs outbound ports); aggregate boundary vs. system boundary; where the seam belongs relative to the bounded-context map; when to escalate to `ddd-context-mapping` for the relationship-level pattern. |

## Anti-patterns in boundary work itself

- **Wrapping for the sake of wrapping.** A 1:1 passthrough adapter that adds zero translation is dead weight. Either translate types / errors / semantics, or just call the vendor.
- **`typealias` as fake encapsulation.** `typealias OrderId = String` doesn't wrap anything — it's a compile-time alias. The compiler still accepts any `String` everywhere `OrderId` is expected. Use `@JvmInline value class OrderId(val value: String)` if you want type safety.
- **Adapter that leaks vendor types out the back.** An interface that returns `WebClientResponseException` or `ResponseEntity<*>` hasn't created a boundary, it's just moved the leak by one method. Vendor types stop at the Adapter's private members.
- **Mocking the vendor SDK in unit tests.** Mocking `WebClient`'s fluent chain (`.get().uri().retrieve().bodyToMono()`) couples tests to the SDK's structure; the test breaks on every SDK upgrade. Mock *your* interface instead, and verify the Adapter once with a real integration test (WireMock / Testcontainers).
- **Adapter and domain logic in the same class.** When an `@Component` named `OrderService` also calls `webClient.post(...)`, you've conflated translation and orchestration. Extract a `PaymentClient` interface and let `OrderService` depend on it.
- **Premature seam.** Drawing an Adapter around a stable JDK type (`java.time.Instant`, `java.util.UUID`) or your own internal class adds ceremony without benefit. Seams earn their cost at *external* edges.
- **Refactoring across an unstable seam without learning tests.** Bumping the vendor SDK *and* refactoring your Adapter in the same PR removes the safety net. Write learning tests first; bump second; refactor third.
- **The kitchen-sink Adapter.** One `IntegrationsService` that adapts Stripe, Slack, Twilio, and S3 is a god class, not a boundary. One Adapter per vendor (or vendor concern).
- **Sealing the seam too tight.** When the vendor offers a useful capability *and* it maps naturally to your domain, expose it through the Adapter rather than reinventing. Discipline isn't asceticism.
- **Pretending you can hide a chatty vendor.** Some SDKs (e.g., AWS S3) leak performance characteristics through their shape — pagination, eventual consistency, throttling. The Adapter can't pretend these don't exist; surface them as domain concepts (`Page<T>`, retry hooks).

## Related skills

| Skill | This not that |
|---|---|
| `ddd-context-mapping` | Relationship-level patterns *between* bounded contexts (ACL, OHS, Customer-Supplier, Conformist). This skill is the **code-level Adapter** that implements an ACL once the relationship is chosen. |
| `architecture-patterns` | Hexagonal / Onion / Clean as a *module layout*. This skill is the per-seam discipline inside that layout. |
| `clean-code-functions` | The function-level shape inside an Adapter — small, one level of abstraction, exceptions over error codes. Apply both. |
| `clean-code-naming` | Names for adapters, ports, gateways (`OrderRepository` not `OrderRepositoryImpl`, `PaymentGateway` not `StripeClientWrapper`). Apply both. |
| `testing-strategy-kotlin-spring` | The slices and tools (`@WebClientTest`, Testcontainers, WireMock) that learning and boundary tests run on. |
| `gof-patterns` | The Adapter pattern (GoF) is the underlying mechanism; this skill is the boundaries-specific application. |
| `solid-principles` | Dependency Inversion (the "D" in SOLID) is the underlying principle; this skill applies it at the vendor seam. |
| `api-design-principles` | The wire-level contract (REST / gRPC) at *your* outward-facing edges. This skill is about *consuming* contracts you don't own. |
| `architect-review` | Catches "vendor leakage", "missing seam", "no ACL" as architectural smells; this skill provides the criteria the review applies. |
| `karpathy-guidelines` | §3 surgical changes — introduce the Adapter without rewriting the world. §6 verify before claim — every Adapter ships with a learning / boundary test. |

## Limitations

- **Adapters cost.** Every boundary adds an interface, a class, mapping code, and a Fake. Pay that cost where change is likely (vendor SDKs, unstable subsystems) and skip it where the cost outweighs the benefit (stable JDK types, internal modules with one consumer).
- **Some leaks are structural, not stylistic.** If 80% of your code reads / writes Postgres-shaped rows, the right boundary may be the repository, not a per-table Adapter. Apply judgement.
- **Reactive ↔ imperative seams are unavoidable.** A WebFlux app talking to a JDBC database has *two* seams: at the controller boundary and at the repository boundary. Make them explicit; don't sprinkle `.block()` across the service layer.
- **Vendor SDKs sometimes ARE your domain language.** Building a developer tool for AWS users? The S3 abstraction may be the right shape across your code. Wrap to gain testability, not to disguise the domain.
- **Learning tests against paid vendors cost money.** Use sandbox keys, recorded fixtures (WireMock recordings), or contract-test stubs (Pact, Spring Cloud Contract) — see `resources/spring-boot-boundaries.md`.
- **Team consistency wins.** If the codebase has a strict ACL convention, conform. A single hand-rolled Adapter in a sea of generated Feign clients is friction for every reviewer who follows you.
