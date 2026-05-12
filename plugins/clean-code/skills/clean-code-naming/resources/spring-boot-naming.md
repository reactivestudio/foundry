# Spring Boot Naming Conventions

Spring Boot has both *mandatory* naming (the framework introspects names) and *conventional* naming (community standard, no enforcement). This file separates the two and adds opinionated rules for places Spring leaves open.

For universal rules, see `general-naming-rules.md`. For Kotlin idioms, see `kotlin-specific-naming.md`. For DDD names, see `ddd-naming.md`.

---

## Framework-mandated suffixes (Spring needs these)

| Suffix | Required for | Notes |
|---|---|---|
| `*Application` | Main class with `@SpringBootApplication` | One per service |
| `*Configuration` / `*Config` | `@Configuration`-annotated classes | `*Config` shorter and equally readable; pick one team-wide |
| `*Controller` | `@Controller` / `@RestController` | Universal convention, even if Spring scans by stereotype |
| `*Exception` | Custom exceptions | Enforced by JDK convention, not Spring specifically |
| `*Properties` | `@ConfigurationProperties` data class | Strong convention; carries the YAML namespace |

These are the only suffixes where the framework or universal convention is the authority. Everything else is open to opinion.

---

## Semi-conventional suffixes (Spring tolerates anything, community uses these)

| Suffix | Convention | When NOT to use |
|---|---|---|
| `*Service` | Service-layer orchestrator class | When the class is a domain service (use `*er` from `ddd-naming.md`) or a Pure Fabrication with a meaningful name. Don't default to `*Service` for any class that "does something." |
| `*Repository` | Spring Data `Repository` interface | Always use it for repository interfaces |
| `*Component` | Generic `@Component` | Never as a suffix — `@Component` is a stereotype, not a name. If you can't name the class better than `*Component`, the class lacks a purpose. |

**House rule on `*Service`**: it's the most-abused suffix in Spring. Reserve it for classes that *orchestrate* — load aggregate, call domain method, save, publish event. Anything else gets a real name.

---

## DTO naming — purpose-specific, never generic

**Principle**: A DTO has a *purpose* (request body, response body, projection for a specific query). Name it for the purpose, not for its DTO-ness.

**Bad**:
```kotlin
data class OrderDto(...)
data class OrderRequestDto(...)
data class OrderResponseDto(...)
```

**Good**:
```kotlin
// Request shapes
data class OrderSubmission(val customerId: UUID, val items: List<LineSubmission>)
data class OrderCancellation(val reason: String)

// Response shapes
data class OrderView(val id: UUID, val status: String, val total: BigDecimal)
data class OrderSnapshot(...)        // historical / point-in-time
data class OrderSummary(val id: UUID, val total: BigDecimal)
```

**Why**: `OrderDto` says nothing about what it carries. `OrderSubmission` vs `OrderView` carries the use case in the name — the caller knows immediately which one to use.

**Common purpose-suffix vocabulary**:

| Suffix | Use |
|---|---|
| `*Submission` / `*Request` | Inbound write payload |
| `*View` / `*Response` | Outbound read payload |
| `*Summary` | Reduced / aggregated view |
| `*Snapshot` | Point-in-time copy |
| `*Projection` | CQRS read-side projection |
| `*Patch` | PATCH payload (partial update) |

`*Request` / `*Response` are acceptable when they're balanced (`OrderRequest` + `OrderResponse`); `OrderSubmissionRequest` is redundant — pick `OrderSubmission` or `OrderRequest`, not both.

---

## JPA entity vs domain class — different files, different names

**Principle**: The JPA-mapped class and the domain class are different things in different layers. They should not share a name.

**Bad**:
```kotlin
// One class doing both jobs
@Entity
data class Order(
    @Id val id: UUID,
    var status: Status,
    @OneToMany var items: MutableList<OrderItem>,
)
```

**Good**:
```kotlin
// domain layer — pure Kotlin, no JPA
class Order private constructor(...) {
    fun submit() { ... }
    // invariants enforced here
}

// persistence layer — JPA-mapped row
@Entity
@Table(name = "orders")
class OrderRow(                           // ← Row, not Entity
    @Id val id: UUID,
    var status: String,
    @OneToMany var items: MutableList<OrderItemRow>,
)
```

Notes:
- `*Row` is the recommended suffix for JPA-mapped persistence shapes — it says "a row in a table" without leaking ORM vocabulary into the domain.
- `*Entity` is the historical Java convention; avoid it because "Entity" in DDD means something different (an aggregate's identity-bearing object).
- The mapper that translates lives in the persistence module: `OrderMapper { fun toDomain(row: OrderRow): Order; fun toRow(order: Order): OrderRow }`.

See `database-design` and `ddd-tactical-patterns` for the design rationale.

---

## `@ConfigurationProperties` — `*Properties` data class

**Principle**: Typed configuration binding uses a data class with `*Properties` suffix matching the YAML namespace.

**Good**:
```kotlin
@ConfigurationProperties(prefix = "checkout.payment")
data class CheckoutPaymentProperties(
    val timeout: Duration = Duration.ofSeconds(5),
    val maxRetries: Int = 3,
    val vendor: VendorProperties,
) {
    data class VendorProperties(
        val baseUrl: URI,
        val apiKey: String,
    )
}
```

Matches:
```yaml
checkout:
  payment:
    timeout: 5s
    max-retries: 3
    vendor:
      base-url: https://api.stripe.com
      api-key: ${STRIPE_KEY}
```

**Rules**:
- The class is `*Properties`, plural.
- Nested data classes use `*Properties` if they bind a sub-namespace.
- YAML keys are `kebab-case`; Kotlin properties are `camelCase`; Spring Boot bridges automatically.

---

## Spring bean names

**Principle**: Spring derives bean names from class names (first letter lowercased). Override explicitly only when the implicit name would clash or mislead.

**Good**:
```kotlin
@Component
class JpaOrderRepository(...) : OrderRepository      // bean name: "jpaOrderRepository"

@Bean("postgresDataSource")                          // explicit because there's also "redisDataSource"
fun postgresDataSource(...): DataSource = ...
```

**Bad**:
```kotlin
@Bean("dataSource")                                  // default name; no need to specify
fun dataSource(): DataSource = ...
```

If you're specifying an explicit name that matches what Spring would derive anyway, remove the redundancy.

---

## Profile names

**Principle**: Spring profiles are kebab-case, short, and describe an *environment* or *capability* — not a technology.

**Good**:
```yaml
spring.profiles.active: prod
# or
spring.profiles.active: local,with-fakes
# or
spring.profiles.active: e2e-test
```

**Bad**:
```yaml
spring.profiles.active: production          # use 'prod', shorter and equally clear
spring.profiles.active: PROD                # case
spring.profiles.active: local_dev           # underscore
spring.profiles.active: postgresql          # technology, not environment
```

**Standard profile vocabulary**:
- `local` — developer machine
- `dev` — shared development environment
- `test` — automated test runs
- `e2e-test` — end-to-end test runs (heavier than `test`)
- `staging` — pre-production
- `prod` — production
- Feature toggles: `with-fakes`, `read-only`, `migration` — describe the *capability* enabled

---

## Test class naming

**Principle**: The suffix tells the reader what *kind* of test it is.

| Suffix | Kind | Boots |
|---|---|---|
| `*Test` | Unit test | No Spring context |
| `*Test` (with `@WebMvcTest` / `@DataJpaTest`) | Slice test | Partial Spring context |
| `*IT` or `*IntegrationTest` | Integration test | Real Spring + Testcontainers |
| `*E2ETest` or `*EndToEndTest` | End-to-end | Full stack |
| `*ArchitectureTest` | ArchUnit / Modulith verifier | No runtime |

**Good**:
```kotlin
class OrderTest                            // pure unit
class OrderControllerTest                  // @WebMvcTest slice
class OrderRepositoryTest                  // @DataJpaTest slice
class OrderSubmissionIT                    // full Spring + Testcontainers
class CheckoutE2ETest                      // browser / HTTP smoke
class OrderModuleArchitectureTest          // Modulith verification
```

Some teams use `*Should` instead of `*Test` (`OrderShould`) — both are fine; pick one team-wide.

---

## Test method naming

Two conventions; either is fine, pick consistently.

**Style 1 — given-when-then with backticks**:
```kotlin
@Test
fun `given empty cart, when submitting order, then throws EmptyOrderException`() { ... }
```

**Style 2 — should* prose**:
```kotlin
@Test
fun `should throw EmptyOrderException when submitting order with empty cart`() { ... }
```

**Bad**:
```kotlin
@Test fun test1() { ... }
@Test fun testSubmitOrder() { ... }              // tests... what about submitting?
@Test fun submitOrder_emptyCart_throws() { ... } // unreadable
```

---

## Spring Modulith — event listener method naming

**Principle**: `@ApplicationModuleListener` methods are named after the *event* received, not after what they do — there's exactly one listener per event per class.

**Good**:
```kotlin
@Component
class OrderSearchProjection(...) {
    @ApplicationModuleListener
    fun on(event: OrderCreated) { ... }

    @ApplicationModuleListener
    fun on(event: OrderSubmitted) { ... }
}
```

**Bad**:
```kotlin
class OrderSearchProjection {
    @ApplicationModuleListener
    fun handleOrderCreatedEvent(event: OrderCreated) { ... }     // 'handle' + 'Event' redundant

    @ApplicationModuleListener
    fun processOrderSubmitted(event: OrderSubmitted) { ... }     // 'process' meaningless

    @ApplicationModuleListener
    fun updateProjectionWhenOrderCreated(event: OrderCreated) { ... }  // imperative reads weird
}
```

**Why `on(event:)`**: the *event class name* already says what happened; the listener name says *that we react to it*. Adding "handle" or "process" is filler.

---

## REST endpoint URL naming

**Principle**: Plural resource nouns, kebab-case, no verbs. See `api-design-principles` for the full HTTP semantic guidance.

**Good**:
```
GET    /api/v1/orders
GET    /api/v1/orders/{id}
POST   /api/v1/orders
PATCH  /api/v1/orders/{id}
DELETE /api/v1/orders/{id}
POST   /api/v1/orders/{id}/cancellations          # sub-resource for a state change
GET    /api/v1/customers/{id}/shipping-addresses  # nested resource, kebab-case
```

**Bad**:
```
POST /api/v1/createOrder                          # verb in URL
POST /api/v1/order/new                            # singular + new
GET  /api/v1/order_list                           # snake_case
GET  /api/v1/CustomerOrders                       # PascalCase
```

---

## Actuator and custom endpoints

**Principle**: Spring Actuator endpoints are kebab-case (`/actuator/health`, `/actuator/health-readiness`). Custom endpoints follow the same.

**Good**:
```kotlin
@Endpoint(id = "feature-flags")
class FeatureFlagsEndpoint(...)
```

---

## Summary checklist (Spring-specific)

- [ ] Framework-mandated suffixes used where required (`*Application`, `*Configuration`, `*Controller`, `*Exception`, `*Properties`).
- [ ] `*Service` only for orchestrator classes, not as a default.
- [ ] DTO classes named for their purpose (`OrderSubmission`, `OrderView`), not generic `*Dto`.
- [ ] JPA entity uses `*Row` (or its own name), not the domain class name.
- [ ] `@ConfigurationProperties` class uses `*Properties` suffix and matches the YAML namespace.
- [ ] Profile names: kebab-case, short, environment-or-capability-oriented.
- [ ] Test classes: `*Test` (unit/slice), `*IT` (integration), `*E2ETest` (e2e), `*ArchitectureTest` (Modulith/ArchUnit).
- [ ] Modulith listeners named `on(event: X)`.
- [ ] REST URLs: plural nouns, kebab-case, no verbs.
- [ ] Bean names: implicit (from class) unless explicitly disambiguated.
