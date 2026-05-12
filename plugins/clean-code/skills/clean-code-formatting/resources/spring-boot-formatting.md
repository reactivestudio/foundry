# Spring Boot Formatting

Layout decisions specific to Spring Boot / Kotlin applications. These cover the **constructs Spring brings** — controllers, services, configuration, JPA entities, tests — and how Martin's Ch. 5 rules apply (or get reshaped) when those constructs dominate a file. For pure Kotlin syntax conventions see `kotlin-specific-formatting.md`; for universal rules see `general-formatting-rules.md`.

---

## 1. Controllers — thin, stepdown, one transaction per use case

### 1a. Class layout

```kotlin
@RestController
@RequestMapping("/api/v1/orders")
class OrderController(
    private val orderService: OrderService,
    private val orderQueries: OrderQueries,
) {

    // 1. Read endpoints first (GET) — they're typically simpler
    @GetMapping
    fun list(@RequestParam status: OrderStatus?): List<OrderSummary> =
        orderQueries.list(status)

    @GetMapping("/{id}")
    fun get(@PathVariable id: OrderId): OrderResponse =
        orderQueries.findById(id) ?: throw OrderNotFoundException(id)

    // 2. Write endpoints (POST, PUT, PATCH, DELETE) — usually orchestrate the service
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    fun submit(@Valid @RequestBody request: SubmitOrderRequest): OrderResponse {
        val order = orderService.submit(request.toCommand())
        return OrderResponse.from(order)
    }

    @PostMapping("/{id}/cancel")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun cancel(@PathVariable id: OrderId) {
        orderService.cancel(id)
    }
}
```

**Conventions**:
- **HTTP-verb stepdown order**: GET → POST → PUT → PATCH → DELETE. Within a verb group, order by URL path: collection (`/orders`) before resource (`/orders/{id}`) before sub-resource (`/orders/{id}/cancel`).
- **One blank line between handler methods** — every method is a separate concept.
- **Annotation stack**: route annotation (`@GetMapping` / `@PostMapping`) **above** behaviour annotations (`@PreAuthorize`, `@Transactional`, `@ResponseStatus`). The route is the headline.
- **Each handler ≤ 5–10 lines** — controllers are thin. If a handler grows, the logic belongs in a service.

### 1b. Constructor injection — primary constructor, properties trailing-comma

```kotlin
@RestController
@RequestMapping("/api/v1/orders")
class OrderController(
    private val orderService: OrderService,
    private val orderQueries: OrderQueries,
    private val orderMapper: OrderMapper,
) { ... }
```

**Don't** mix field injection (`@Autowired private lateinit var x`) with constructor injection. Don't put non-injected state on a controller (controllers are stateless singletons).

### 1c. Don't bury request validation in the handler body

```kotlin
// ✗ Validation tangled with orchestration
@PostMapping
fun submit(@RequestBody request: SubmitOrderRequest): OrderResponse {
    if (request.customerId.isBlank()) throw IllegalArgumentException("customerId required")
    if (request.lines.isEmpty()) throw IllegalArgumentException("lines required")
    if (request.lines.any { it.quantity <= 0 }) throw IllegalArgumentException("quantity > 0")
    val order = orderService.submit(request.toCommand())
    return OrderResponse.from(order)
}

// ✓ @Valid + Bean Validation annotations push validation to the boundary
data class SubmitOrderRequest(
    @field:NotBlank val customerId: String,
    @field:NotEmpty val lines: List<OrderLineRequest>,
)

data class OrderLineRequest(
    @field:NotBlank val productId: String,
    @field:Positive val quantity: Int,
)

@PostMapping
fun submit(@Valid @RequestBody request: SubmitOrderRequest): OrderResponse {
    val order = orderService.submit(request.toCommand())
    return OrderResponse.from(order)
}
```

---

## 2. Services — `@Transactional` boundary as natural vertical separator

### 2a. One transaction per use case

```kotlin
@Service
class OrderService(
    private val orderRepository: OrderRepository,
    private val paymentGateway: PaymentGateway,
    private val stockReservation: StockReservation,
    private val events: ApplicationEventPublisher,
) {

    @Transactional
    fun submit(command: SubmitOrderCommand): Order {
        val order = Order.fromCommand(command)
        orderRepository.save(order)
        paymentGateway.charge(order)
        stockReservation.reserve(order)
        events.publishEvent(OrderSubmitted(order.id, Instant.now()))
        return order
    }

    @Transactional
    fun cancel(id: OrderId) {
        val order = orderRepository.findById(id) ?: throw OrderNotFoundException(id)
        order.cancel()
        events.publishEvent(OrderCancelled(order.id, Instant.now()))
    }
}
```

**The `@Transactional` annotation is the headline**: each transactional method is one business use case. Multiple use cases = multiple top-level methods, each with its own `@Transactional`, each separated by a blank line.

### 2b. `@Transactional` placement

- **Class-level** when *every* method is transactional (rare; common only for `readOnly = true` query classes).
- **Method-level** otherwise.
- **`readOnly = true`** on query methods — formatters won't enforce this, but the convention helps the reader.

```kotlin
@Service
@Transactional(readOnly = true)              // ← class-level for query service
class OrderQueries(
    private val orderRepository: OrderRepository,
) {
    fun list(status: OrderStatus?): List<OrderSummary> = ...
    fun findById(id: OrderId): OrderResponse? = ...
    fun count(): Long = ...
}
```

### 2c. Don't nest `@Transactional` methods within the same class

`self.submit()` from inside the same class **bypasses Spring's proxy**, so the inner method's `@Transactional` is ignored. Either extract to a separate bean, or use `TransactionTemplate` / `TransactionalEventListener`. Layout-wise: never have two `@Transactional` methods where one calls the other internally.

---

## 3. `application.yml` — structure and sectioning

### 3a. Section by concern, alphabetical within section

```yaml
spring:
  application:
    name: order-service
  datasource:
    driver-class-name: org.postgresql.Driver
    password: ${DB_PASSWORD}
    url: jdbc:postgresql://${DB_HOST:localhost}:${DB_PORT:5432}/orders
    username: ${DB_USER}
  jpa:
    hibernate:
      ddl-auto: validate
    properties:
      hibernate:
        format_sql: false
        jdbc.batch_size: 50
  kafka:
    bootstrap-servers: ${KAFKA_BROKERS}
    consumer:
      group-id: order-service

server:
  port: ${SERVER_PORT:8080}
  shutdown: graceful

management:
  endpoints:
    web:
      exposure:
        include: health,info,prometheus
  metrics:
    export:
      prometheus:
        enabled: true

logging:
  level:
    com.example.order: DEBUG
    org.springframework.web: INFO

# Application-specific configuration last
order:
  payment:
    timeout: 30s
    retries: 3
  stock:
    reservation-ttl: 5m
```

**Conventions**:
- Top-level keys: `spring` → `server` → `management` → `logging` → app-specific. Blank line between top-level sections.
- 2-space indent (YAML standard).
- Alphabetical within each nested section.
- Environment variables: `${VAR_NAME:default}` for those with sensible defaults; bare `${VAR_NAME}` for those that **must** be set.
- Use durations / sizes with units (`30s`, `5m`, `512MB`), not raw numbers.

### 3b. Profile-specific files

```
src/main/resources/
├── application.yml              ← shared defaults
├── application-local.yml        ← local dev only
├── application-test.yml         ← test profile
├── application-prod.yml         ← production
└── application-prod-eu.yml      ← multi-profile activation
```

Each profile file only overrides what differs from `application.yml`. Don't duplicate full config across profiles.

### 3c. `application.properties` — only when forced

If the project's standard is YAML, use YAML throughout. Mixed `.yml` + `.properties` is the smell — pick one.

If `.properties` is used, the same alphabetical-within-section rule applies, with blank lines between sections:

```properties
# Spring
spring.application.name=order-service
spring.datasource.url=jdbc:postgresql://localhost/orders

# Server
server.port=8080

# Application
order.payment.timeout=30s
```

---

## 4. `@ConfigurationProperties` — data class layout

```kotlin
@ConfigurationProperties(prefix = "order")
data class OrderProperties(
    val payment: PaymentProperties,
    val stock: StockProperties,
) {

    data class PaymentProperties(
        val timeout: Duration = Duration.ofSeconds(30),
        val retries: Int = 3,
    )

    data class StockProperties(
        val reservationTtl: Duration = Duration.ofMinutes(5),
    )
}
```

**Conventions**:
- Top-level config is a data class with the `prefix` on the annotation.
- Nested config groups are nested data classes — keep them in the same file, in the same sequence as their fields appear in the parent.
- Provide defaults at the property level — they document expected values.
- One blank line between nested data classes.

---

## 5. JPA `@Entity` — field ordering

```kotlin
@Entity
@Table(name = "orders")
class OrderRow(

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    val id: UUID,

    @Column(name = "customer_id", nullable = false)
    val customerId: UUID,

    @Column(name = "status", nullable = false)
    @Enumerated(EnumType.STRING)
    var status: OrderStatus,

    @Column(name = "placed_at", nullable = false)
    val placedAt: Instant,

    @OneToMany(mappedBy = "order", cascade = [CascadeType.ALL], orphanRemoval = true)
    val lines: MutableList<OrderLineRow> = mutableListOf(),

    @Version
    var version: Long = 0,
)
```

**Conventions**:
- **One blank line between fields** when annotations are multi-line.
- **Annotation order per field**: identity (`@Id`, `@GeneratedValue`) → column (`@Column`) → type extras (`@Enumerated`, `@Convert`, `@Temporal`) → relationship (`@OneToMany`, `@ManyToOne`).
- **Field order**: identity first, business columns by domain meaning, relationships, audit/version last.
- **No `@Column(name = "...")` if name matches the property** — only specify when it differs from the default snake_case derivation.

**House note**: JPA `@Entity` is a *persistence shape*, not the domain aggregate. See `clean-code-naming` for the naming convention (`OrderRow` over `OrderEntity`) and `ddd-tactical-patterns` for the separation between persistence row and domain aggregate.

---

## 6. Spring Modulith / event listeners

### 6a. Listener method shape

```kotlin
@Component
class OrderShippingListener(
    private val shippingService: ShippingService,
) {

    @ApplicationModuleListener
    fun onOrderSubmitted(event: OrderSubmitted) {
        shippingService.scheduleDelivery(event.orderId)
    }

    @ApplicationModuleListener
    fun onOrderCancelled(event: OrderCancelled) {
        shippingService.cancelDelivery(event.orderId)
    }
}
```

**Conventions**:
- One listener method per event type.
- Method name: `on<EventName>` (past-tense — events are facts, not commands).
- Body: thin orchestration; delegate to the service.
- One blank line between listener methods.

### 6b. `@TransactionalEventListener` vs. `@ApplicationModuleListener`

- `@TransactionalEventListener(phase = AFTER_COMMIT)` for raw Spring projects.
- `@ApplicationModuleListener` for Spring Modulith — implies `@Async` + `@Transactional(REQUIRES_NEW)` + outbox publication.

Pick one and use it consistently across the module. Mixed is the smell.

---

## 7. Spring Security DSL — declarative, stepdown by chain

```kotlin
@Configuration
@EnableMethodSecurity
class SecurityConfig {

    @Bean
    fun filterChain(http: HttpSecurity): SecurityFilterChain = http
        .csrf { it.disable() }
        .sessionManagement { it.sessionCreationPolicy(STATELESS) }
        .authorizeHttpRequests {
            it.requestMatchers("/actuator/health", "/actuator/info").permitAll()
            it.requestMatchers("/api/v1/orders/**").hasRole("USER")
            it.requestMatchers("/api/v1/admin/**").hasRole("ADMIN")
            it.anyRequest().authenticated()
        }
        .oauth2ResourceServer { it.jwt(Customizer.withDefaults()) }
        .build()
}
```

**Conventions**:
- One `.method { ... }` block per security concern, in this canonical order: `csrf` → `sessionManagement` → `authorizeHttpRequests` → `oauth2ResourceServer` → `exceptionHandling` → `headers`.
- Each block on its own line.
- Within `authorizeHttpRequests`, matchers in order: public (`permitAll`) → role-restricted (most-specific → most-general) → `anyRequest()`.
- Use `Customizer.withDefaults()` when no per-block configuration is needed.

---

## 8. Tests — Given-When-Then blank-line discipline

### 8a. Three sections, blank lines between them

```kotlin
class OrderServiceTest {

    @Test
    fun `submit charges payment and reserves stock`() {
        // given
        val command = SubmitOrderCommand(
            customer = aCustomer().id,
            lines = listOf(anOrderLine()),
        )
        every { paymentGateway.charge(any()) } returns Charged
        every { stockReservation.reserve(any()) } returns Reserved

        // when
        val order = orderService.submit(command)

        // then
        assertThat(order.status).isEqualTo(SUBMITTED)
        verify { paymentGateway.charge(order) }
        verify { stockReservation.reserve(order) }
    }
}
```

**Conventions**:
- **Blank line between Given / When / Then** — the three blocks are three concepts (per Ch. 5 Rule 3, Vertical Openness).
- **Optional `// given` / `// when` / `// then` comments** — useful when blocks have multiple lines; redundant for trivial tests.
- **One assertion concept per test** (but multiple AssertJ chains for the *same* concept is fine).

### 8b. Test name as backtick-quoted sentence

```kotlin
@Test
fun `submit fails when payment gateway rejects the charge`() { ... }

@Test
fun `cancel releases reserved stock and refunds the customer`() { ... }
```

Sentence-style names beat `submit_failsWhenPaymentRejected()`. The IDE shows them as-is; CI report shows them as-is; the test is documentation.

### 8c. AssertJ chain layout

```kotlin
// ✓ One assertion per line for multi-property checks
assertThat(order)
    .isNotNull()
    .extracting(Order::status, Order::placedAt)
    .containsExactly(SUBMITTED, fixedInstant)

// ✓ One-line for trivial single-property check
assertThat(order.status).isEqualTo(SUBMITTED)
```

When chain length > 2 calls, break each onto its own line with the `.method` at the start. The reader sees the assertion as a sequence of refinements.

### 8d. Mockk / when-then layout

```kotlin
// ✓ Stubs grouped at top of given
every { paymentGateway.charge(any()) } returns Charged
every { stockReservation.reserve(any()) } returns Reserved
every { orderRepository.save(any()) } answers { firstArg() }

// then ...

verify(exactly = 1) { paymentGateway.charge(order) }
verify(exactly = 1) { stockReservation.reserve(order) }
verifyOrder {
    paymentGateway.charge(order)
    stockReservation.reserve(order)
    events.publishEvent(any<OrderSubmitted>())
}
```

Stubs together, verifications together. Don't interleave them — they belong to different sections.

---

## 9. Test slices — keep the annotation block tight

```kotlin
@WebMvcTest(OrderController::class)
@Import(TestSecurityConfig::class)
@ActiveProfiles("test")
class OrderControllerTest(
    @Autowired private val mockMvc: MockMvc,
    @Autowired private val objectMapper: ObjectMapper,
) {

    @MockkBean
    private lateinit var orderService: OrderService

    @MockkBean
    private lateinit var orderQueries: OrderQueries

    @Test
    fun `POST returns 201 with order details`() { ... }
}
```

**Conventions**:
- Test-slice annotations (`@WebMvcTest`, `@DataJpaTest`, `@JsonTest`) on top.
- Constructor injection for the slice's primary bean (`MockMvc`, `TestEntityManager`).
- `@MockkBean` properties **after** primary constructor, separated by blank lines (each is a distinct collaborator).
- Don't mix `@MockkBean` and constructor-injected mocks — pick one style per project.

---

## 10. OpenAPI / Swagger annotations

If using `springdoc-openapi`:

```kotlin
@RestController
@RequestMapping("/api/v1/orders")
@Tag(name = "Orders", description = "Order management endpoints")
class OrderController(...) {

    @PostMapping
    @Operation(summary = "Submit a new order")
    @ApiResponses(
        ApiResponse(responseCode = "201", description = "Order created"),
        ApiResponse(responseCode = "400", description = "Invalid request"),
        ApiResponse(responseCode = "402", description = "Payment failed"),
    )
    @ResponseStatus(HttpStatus.CREATED)
    fun submit(@Valid @RequestBody request: SubmitOrderRequest): OrderResponse = ...
}
```

**Conventions**:
- `@Tag` on the class.
- `@Operation` summary on each handler — keep it under 80 chars; details live in the request/response schema annotations.
- `@ApiResponses` lists explicit status codes; don't document the framework's auto-handled cases (e.g., `401` from Spring Security).
- One blank line between annotation block and method signature.

---

## 11. Liquibase / Flyway migration formatting

### 11a. Flyway SQL

```sql
-- V20250512_1530__add_order_table.sql

CREATE TABLE orders (
    id            UUID PRIMARY KEY,
    customer_id   UUID NOT NULL,
    status        VARCHAR(32) NOT NULL,
    placed_at     TIMESTAMPTZ NOT NULL,
    total_amount  NUMERIC(15, 2) NOT NULL,
    currency      CHAR(3) NOT NULL,
    version       BIGINT NOT NULL DEFAULT 0
);

CREATE INDEX idx_orders_customer_id ON orders (customer_id);
CREATE INDEX idx_orders_placed_at   ON orders (placed_at DESC);
```

**Conventions**:
- File name: `V<UTC timestamp>__<snake_case description>.sql`.
- SQL keywords uppercase; identifiers lowercase snake_case.
- One blank line between statements.
- **One concern per migration** — adding a table is one file, adding an index is one file. Don't bundle.

### 11b. Liquibase XML — minimal, one changeSet per file

Same rule: one logical change per file. The file name encodes intent.

---

## 12. Logging — slf4j fluent vs. printf

### 12a. Use slf4j fluent API (or extension function)

```kotlin
// ✓ Structured logging — each key-value visible
log.atInfo()
    .addKeyValue("orderId", order.id)
    .addKeyValue("customerId", order.customer.id)
    .addKeyValue("amount", order.total.amount)
    .setMessage("Order submitted")
    .log()
```

```kotlin
// ✓ Or kotlin-logging extension
log.info { "Order submitted: id=${order.id} customer=${order.customer.id}" }
```

### 12b. Don't concatenate

```kotlin
// ✗ Eager string construction, even if log level is off
log.info("Order submitted: id=" + order.id + " customer=" + order.customer.id)

// ✗ String template inside non-lazy slf4j call
log.info("Order submitted: id=${order.id}")
```

The kotlin-logging library makes the lambda-form free at the call site.

---

## Cross-references

| Need | File |
|---|---|
| Universal vertical / horizontal rules | `general-formatting-rules.md` |
| Kotlin syntax conventions (expression bodies, `when`, scope fns) | `kotlin-specific-formatting.md` |
| ktlint vs. ktfmt, EditorConfig, CI gate | `tooling-formatting.md` |
| When to thin a controller / split a service | sibling skill `clean-code-functions` |
| Test strategy (what to test at which slice) | sibling skill `testing-strategy-kotlin-spring` |
| Spring Modulith application module structure | sibling skill `spring-boot-mastery` |
