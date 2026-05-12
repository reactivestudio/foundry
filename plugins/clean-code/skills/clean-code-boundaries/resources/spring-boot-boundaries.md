# Spring Boot / JPA Boundary Conventions

Spring Boot lives at boundaries — between HTTP and your code, between your code and the database, between your code and every SaaS vendor on the planet. This file maps Martin's boundary rules onto Spring's specific seams.

## The Spring layers and what types are allowed at each

A workable rule: every Spring type stays inside the layer that owns it. The layer below sees only domain types.

| Layer | Allowed types coming in | Allowed types going out | Forbidden |
|---|---|---|---|
| Controller (`@RestController`) | `@RequestBody Request`, `@PathVariable`, `@RequestParam`, `Authentication`, `MultipartFile` | `ResponseEntity<Response>`, `Response`, `ProblemDetail` | Returning a JPA `@Entity`. Accepting one as a request body. |
| Service (`@Service`) | Domain types, primitive IDs, validated commands | Domain types, DTOs | `HttpServletRequest`, `Pageable`, `ResponseEntity`, `Authentication`, `MultipartFile`. |
| Repository (`@Repository`, `JpaRepository`) | Domain IDs, query parameters (primitives or value classes) | Domain aggregates *or* projection DTOs | Returning `@Entity` to anything other than the aggregate's own package. |
| Boundary adapter (`@Component` wrapping AWS/Stripe/Slack/...) | Vendor SDK types (private) | Domain types | Vendor types in public method signatures. |

If a `Pageable` reaches the service layer, the controller didn't do its job. If an `@Entity` reaches the controller, the repository didn't.

## Controllers — thin, mapping-only

The controller's job is: receive an HTTP-shaped thing, translate it to a domain-shaped thing, call the service, translate the result back, return an HTTP-shaped response.

```kotlin
@RestController
@RequestMapping("/orders")
class OrderController(private val orders: OrderService) {

    @PostMapping
    fun submit(@Valid @RequestBody request: SubmitOrderRequest): ResponseEntity<OrderResponse> {
        val orderId = orders.submit(request.toCommand())     // ← service speaks domain
        return ResponseEntity
            .status(HttpStatus.CREATED)
            .body(OrderResponse(id = orderId.value))
    }

    @GetMapping("/{id}")
    fun byId(@PathVariable id: String): OrderResponse =
        orders.byId(OrderId(id)).toResponse()
}

data class SubmitOrderRequest(
    @field:NotBlank val customerId: String,
    @field:Min(1) val itemCount: Int
) {
    fun toCommand() = SubmitOrderCommand(CustomerId(customerId), itemCount)
}
```

**Rules at the controller:**

- `@RequestBody` is a *request DTO*, never an `@Entity`.
- Returned shape is a *response DTO*, never an `@Entity`.
- `Pageable` / `Sort` / `Authentication` are extracted here; the service sees plain values (page number, principal id, role set).
- Validation lives here (`@Valid` + Bean Validation) — the service trusts validated commands.
- Exceptions translate here via `@RestControllerAdvice` (see below).

## `@RestControllerAdvice` — translate exceptions, don't `try/catch` in controllers

Vendor exceptions, domain exceptions, validation failures all map to `ProblemDetail` (RFC 7807) in one place:

```kotlin
@RestControllerAdvice
class ErrorHandler {

    @ExceptionHandler(CardDeclined::class)
    fun cardDeclined(ex: CardDeclined): ProblemDetail =
        ProblemDetail.forStatusAndDetail(HttpStatus.PAYMENT_REQUIRED, ex.code).apply {
            type = URI.create("https://errors.example.com/card-declined")
        }

    @ExceptionHandler(MethodArgumentNotValidException::class)
    fun validation(ex: MethodArgumentNotValidException): ProblemDetail = ...

    @ExceptionHandler(GatewayUnreachable::class)
    fun gatewayUnreachable(ex: GatewayUnreachable): ProblemDetail =
        ProblemDetail.forStatus(HttpStatus.SERVICE_UNAVAILABLE)
}
```

The service throws **domain** exceptions (`CardDeclined`, `GatewayUnreachable`); the controller advice maps them to HTTP. No `try/catch` in the controller, no vendor exception types in domain code. See `clean-code-error-handling` for the broader pattern.

## JPA entities never leave the persistence package

The most common boundary leak in a Spring codebase: a `@Entity` returned from a repository, used by a service, serialised by a controller. This produces:

- **Open Session in View** anti-pattern (lazy loading triggers DB calls during JSON serialisation).
- **Coupling** between the HTTP contract and the persistence schema. Every column rename breaks the API.
- **Tests that need a database** (or a heavy mock) to run.

The fix: project at the repository edge, with a DTO type per use case.

```kotlin
// ✓ Spring Data projection — repository returns a domain type, not an entity
interface OrderRepository : JpaRepository<OrderEntity, UUID> {

    @Query("""
        select new com.acme.orders.OrderView(o.id, o.customerId, o.status, o.totalCents)
        from OrderEntity o where o.id = :id
    """)
    fun viewById(id: UUID): OrderView?

    @Query("""
        select new com.acme.orders.OrderSummary(o.id, o.status)
        from OrderEntity o where o.customerId = :customerId
    """)
    fun summariesByCustomer(customerId: UUID): List<OrderSummary>
}

data class OrderView(val id: UUID, val customerId: UUID, val status: String, val totalCents: Long)
data class OrderSummary(val id: UUID, val status: String)
```

Or use **MapStruct** / a hand-written mapper at the repository boundary:

```kotlin
@Component
class OrderRepositoryAdapter(
    private val jpa: OrderJpaRepository,
    private val mapper: OrderEntityMapper
) : OrderRepository {
    override fun byId(id: OrderId): Order? =
        jpa.findById(id.value).orElse(null)?.let(mapper::toDomain)
}
```

The aggregate (`Order`) lives in the domain package and knows nothing about JPA. The `OrderEntity` lives in the persistence package and is invisible outside it. See `clean-code-objects-and-data` for the data-vs-object split and the Active Record anti-pattern.

## `WebClient` / `RestTemplate` / OpenFeign behind a `*Client` interface

Direct calls to `webClient.get().uri(...).retrieve().bodyToMono(SomeResponse::class.java).block()` scattered across services is the textbook boundary leak. Wrap once.

```kotlin
// Port — interface owned by your domain
interface PaymentGateway {
    fun charge(amount: Money, source: CardToken): Charge
    fun refund(chargeId: ChargeId, amount: Money): Refund
}

// Adapter — Spring component, uses WebClient under the hood
@Component
class StripeGateway(
    private val client: WebClient,
    private val properties: StripeProperties     // @ConfigurationProperties, not raw env
) : PaymentGateway {

    override fun charge(amount: Money, source: CardToken): Charge =
        client.post()
            .uri("/v1/charges")
            .body(BodyInserters.fromFormData(LinkedMultiValueMap<String, String>().apply {
                add("amount", amount.cents.toString())
                add("currency", amount.currency.code)
                add("source", source.value)
            }))
            .retrieve()
            .onStatus(HttpStatusCode::is4xxClientError) { res ->
                res.bodyToMono(StripeError::class.java).flatMap { Mono.error(it.toDomain()) }
            }
            .bodyToMono(StripeChargeResponse::class.java)
            .map { it.toDomain() }
            .block()
            ?: throw GatewayUnreachable()
    ...
}
```

**Rules:**

- Service code injects `PaymentGateway`, never `WebClient`.
- `StripeChargeResponse` is a private wire-shape data class; not exposed outside the adapter package.
- Errors translate inside the Adapter — `onStatus` catches 4xx, maps to domain exceptions.
- `block()` (if used) lives at the adapter; reactive types do not leak. (If your service is fully reactive, the Adapter's interface uses `suspend` or returns `Mono<T>` consistently.)

The same pattern applies to OpenFeign:

```kotlin
@FeignClient(name = "stripe", url = "\${stripe.url}")
internal interface StripeFeignClient {     // ← internal, never injected outside the boundary package
    @PostMapping("/v1/charges") fun createCharge(...): StripeChargeResponse
}

@Component
class StripeGateway(private val feign: StripeFeignClient) : PaymentGateway { ... }
```

## AWS / Stripe / Slack / Twilio — one Adapter per vendor concern

Each vendor SDK gets its own boundary package and Adapter. **Don't bundle vendors** into a generic `IntegrationsService`.

```
com.acme.payments/
├── domain/
│   ├── PaymentGateway.kt           (port)
│   ├── Charge.kt
│   └── ChargeId.kt
└── stripe/
    ├── StripeGateway.kt             (adapter)
    ├── StripeChargeResponse.kt      (private wire DTO)
    ├── StripeProperties.kt          (@ConfigurationProperties)
    └── StripeMappers.kt             (extension fns)
```

The service package depends on `PaymentGateway`. The `stripe` package depends on the Stripe SDK and on the service package (for the domain types it produces). The dependency points inward — see `architecture-patterns` for the Hexagonal / Onion layout rules.

## `@ConfigurationProperties` over raw `Environment` / `@Value`

The boundary between config and code is also a boundary. `@Value("\${stripe.url}")` scattered across the codebase ties every place that reads a config to a string key.

```kotlin
@ConfigurationProperties(prefix = "stripe")
data class StripeProperties(
    val url: String,
    val apiKey: String,
    val timeout: Duration = Duration.ofSeconds(10)
)
```

One class owns the schema. Type errors at startup, not in production. The vendor adapter injects `StripeProperties`, not `Environment`.

## `MultipartFile`, `HttpServletRequest`, `Authentication` — controller-only

These are HTTP-layer types. They do not appear in service signatures.

```kotlin
// ✗ Service speaks HTTP — boundary leaked
@Service
class UploadService {
    fun handle(file: MultipartFile, principal: Authentication) { ... }
}

// ✓ Controller extracts; service speaks domain
@RestController
class UploadController(private val uploads: UploadService) {
    @PostMapping("/upload")
    fun upload(@RequestPart file: MultipartFile, auth: Authentication): UploadResponse {
        val payload = FileUpload(
            bytes = file.bytes,
            filename = file.originalFilename ?: "untitled",
            uploader = UserId.from(auth)
        )
        return UploadResponse(uploads.handle(payload).value)
    }
}

@Service
class UploadService {
    fun handle(upload: FileUpload): UploadId { ... }
}
```

Same rule for `Pageable`: the controller turns it into a `Page` value class (page number + size + sort), the service speaks the domain shape.

## Reactive ↔ imperative seam

In a WebFlux app talking to JDBC (or vice versa), you have two seams: at the controller and at the repository. **Make them explicit; don't sprinkle `.block()` through the service layer.**

- Inbound: controller uses `suspend` (Kotlin) or `Mono<T>` (Reactor). It converts at the call into the service.
- Outbound: the JPA repository call happens in a dedicated dispatcher (`Dispatchers.IO`); the result is yielded back through the suspend chain.

If a `Mono` shows up in the middle of a non-reactive service, refactor it back to the boundary.

## Spring Modulith `NamedInterface` — boundary inside the monolith

Within a Spring Modulith application, the boundary between modules is enforced by `package-info.java` / `package-info.kt` and `@NamedInterface`. A module exposes a published interface; the rest is internal.

```
com.acme.payments/
├── package-info.kt                   // @ApplicationModule(allowedDependencies = {"orders::events"})
├── api/                              // @NamedInterface — public to other modules
│   ├── PaymentGateway.kt
│   └── PaymentEvents.kt
└── internal/                         // not exported
    ├── StripeGateway.kt
    └── StripeChargeResponse.kt
```

`ApplicationModuleTest` in CI fails the build if another module imports `internal.*`. This is the same boundary discipline as for external vendors, applied to module boundaries inside one app.

## Learning tests in Spring Boot — Testcontainers and WireMock

Learning tests in a Spring codebase usually run against:

- **Testcontainers** for databases, Kafka, Elasticsearch, S3 (LocalStack), Redis. Real engine, hermetic per test run.
- **WireMock** for HTTP-based vendor SDKs (Stripe, Slack, Twilio). Records / replays / stubs without hitting the vendor's sandbox.
- **MockServer** as a heavier WireMock alternative when you need RAW TCP.

```kotlin
@Tag("learning")
@SpringBootTest(classes = [StripeGateway::class, StripeProperties::class, WebClientConfig::class])
@AutoConfigureWireMock(port = 0)
class StripeGatewayLearningTest {

    @Autowired lateinit var gateway: PaymentGateway

    @Test fun `charge with valid token succeeds`() {
        stubFor(post("/v1/charges").willReturn(okJson(loadFixture("stripe/charge-ok.json"))))

        val charge = gateway.charge(Money(100, USD), CardToken("tok_visa"))

        assertThat(charge.status).isEqualTo(ChargeStatus.Succeeded)
    }

    @Test fun `4xx response throws CardDeclined`() {
        stubFor(post("/v1/charges").willReturn(aResponse().withStatus(402)
            .withBody(loadFixture("stripe/card-declined.json"))))

        assertThatThrownBy { gateway.charge(Money(100, USD), CardToken("tok_chargeDeclined")) }
            .isInstanceOf(CardDeclined::class.java)
    }
}
```

Run learning tests with a JUnit tag in CI on every dependency bump. See `testing-strategy-kotlin-spring` for the broader testing layout.

## Quick reference — Spring boundary checklist

| Check | Rule |
|---|---|
| Service signature takes `Pageable`? | No — extract at the controller. |
| Service signature takes `Authentication`? | No — extract principal id / roles at the controller. |
| Service returns `ResponseEntity<T>`? | No — that's a controller-only type. |
| Repository returns `@Entity` outside its package? | No — project to a DTO or domain type. |
| Direct `webClient.get()...` in a service? | No — wrap in a `*Client` interface + Adapter. |
| Vendor SDK exception type caught in business code? | No — translate to domain exception in the Adapter. |
| `@Value("\${...}")` scattered across the codebase? | No — `@ConfigurationProperties`. |
| Same `@Entity` used as request DTO, response DTO, and persistence row? | No — one shape per layer. |
| `Mono<T>` in a non-reactive service signature? | No — translate at the reactive seam. |
| `MultipartFile` reaches the service layer? | No — controller extracts bytes + metadata into a domain type. |
| Two `@Component`s wrap the same vendor SDK? | No — consolidate to one Adapter. |
| Learning tests run on dependency upgrade in CI? | Yes — they pay for themselves the first time a vendor breaks behaviour. |
