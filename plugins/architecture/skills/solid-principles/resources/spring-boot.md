# SOLID — Spring Boot

How Spring Boot conventions implement each SOLID principle. The framework rewards SOLID — most idiomatic Spring code IS SOLID by construction. Most violations come from fighting Spring rather than using it.

For the principles themselves, see `theory.md`. For Kotlin idioms independent of Spring, see `kotlin.md`.

---

## S — SRP through Spring's bias toward many small beans

Spring is happy with 100 small `@Service` beans. The DI container has constant cost regardless of count; the JVM doesn't care; you should not either.

### Use the framework to make splitting cheap

```kotlin
@Service class UserRegistration(...) { fun register(...): User }
@Service class Authentication(...) { fun login(...); fun resetPassword(...) }
@Service class UserNotifications(...) { fun sendWelcomeEmail(...) }
@Service class UserProfile(...) { fun update(...) }
@Service class UserDeactivation(...) { fun deactivate(...) }
@Service class UserAudit(...) { fun audit(...) }
```

Each bean is a stereotype'd class; Spring autowires them where needed. Cost of having six beans vs one: zero in DI, ~5× less in test setup and mental load.

### Use Spring Modulith to enforce SRP at module scale

Spring Modulith treats each top-level package as a module with explicit boundaries. SRP at the module level: each module owns one bounded context. Cross-module calls go through `@ApplicationModuleListener` events, not direct method invocation.

The `ApplicationModuleTest` (or `ArchUnit` rule) enforces that no module imports another's internals. SRP at architectural scale, mechanically verified.

### Don't fight `@Service` count

Reviewers sometimes object: "we have too many services". The right metric is *reasons to change per service*, not service count. A service with one reason to change is correct, regardless of how many siblings it has.

---

## O — OCP through Spring extension points

Spring exposes a long catalogue of extension points, each an OCP enabler — add new behaviour without editing existing code.

### `@RestControllerAdvice` for cross-cutting error handling

```kotlin
@RestControllerAdvice
class ApiExceptionHandler {
    @ExceptionHandler(NotFoundException::class)
    fun onNotFound(ex: NotFoundException): ProblemDetail =
        ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, ex.message ?: "")
}
```

Add a new `@ExceptionHandler` method or a new `@RestControllerAdvice` class. No controller is touched.

### Spring Modulith events for OCP across modules

```kotlin
@Service
class PlaceOrderHandler(private val events: ApplicationEventPublisher) {
    fun handle(cmd: PlaceOrderCommand): OrderId {
        ...
        events.publishEvent(OrderPlaced(order.id, order.total))
        return order.id
    }
}

@Component
class OrderEmailNotifier {
    @ApplicationModuleListener
    fun on(event: OrderPlaced) { ... }
}

@Component
class OrderAnalyticsRecorder {
    @ApplicationModuleListener
    fun on(event: OrderPlaced) { ... }
}
```

Add a new listener to react to `OrderPlaced`. The publisher is untouched. Add an SMS notifier next month — same story.

### Spring Cache `@Cacheable` for cross-cutting caching

```kotlin
@Service
class ProductCatalog(private val repo: ProductRepository) {
    @Cacheable("products")
    fun byId(id: ProductId): Product = repo.findById(id) ?: throw NotFoundException()
}
```

Caching policy added without touching the calling code. Adding a per-tenant key generator or TTL = configuration, not code.

### `@ConditionalOnProperty` and `@Profile` for OCP via configuration

Swap an implementation per environment without editing the consumer:

```kotlin
@Component
@Profile("!test")
class StripePaymentGateway(...) : PaymentGateway { ... }

@Component
@Profile("test")
class FakePaymentGateway : PaymentGateway { ... }
```

Adding a "sandbox" profile = adding a new bean. No edits.

### What NOT to extend with edits

If a feature requires editing five Spring services, the OCP boundary is in the wrong place. Look for the missing extension point: an event, a strategy bean, a `@ConditionalOnProperty`, an additional `@RestControllerAdvice`.

---

## L — LSP and Spring's substitution surface

Spring leans heavily on LSP via interface-typed beans. The LSP rules from `theory.md` apply normally; Spring adds two specifics worth calling out.

### `@Profile` swaps must remain LSP-substitutable

```kotlin
interface PaymentGateway { fun charge(amount: Money, customer: Customer): Result<TransactionId> }

@Component @Profile("prod")
class StripePaymentGateway(...) : PaymentGateway { ... }

@Component @Profile("test")
class FakePaymentGateway : PaymentGateway {
    override fun charge(amount: Money, customer: Customer): Result<TransactionId> =
        Result.success(TransactionId("test-${UUID.randomUUID()}"))
}
```

Both impls must satisfy the same contract. If the test fake silently returns success on amounts a real Stripe call would reject — LSP violation. Tests pass; production breaks.

### Bean post-processing and AOP weakening

Spring's CGLIB / JDK proxies wrap your beans for `@Transactional`, `@Cacheable`, `@Async`. The proxy IS-A your class via type substitution. Constraints:

- A `final` method on a proxied class won't be intercepted (CGLIB can't override `final`).
- A self-call (`this.method()` from inside the same bean) bypasses the proxy entirely.
- Both behaviours can violate LSP-of-the-proxy-contract: `@Transactional` silently doesn't apply.

Lean on Kotlin's `open` keyword discipline (Kotlin classes are `final` by default; Spring AOP needs `open`) and the `kotlin-spring` Gradle plugin which auto-opens Spring stereotypes. Otherwise verify proxied behaviour in integration tests.

---

## I — ISP through Spring Data and stereotype interfaces

Spring Data's repository hierarchy IS canonical ISP:

```
Repository<T, ID>                    (marker — no methods)
   ↑
CrudRepository<T, ID>                (CRUD: save / findById / findAll / delete)
   ↑
PagingAndSortingRepository<T, ID>    (adds pagination and sorting)
   ↑
JpaRepository<T, ID>                 (adds flush, batch, JPA specifics)
```

Pick the smallest interface that covers your client's need:

```kotlin
interface ProductReadOnly : Repository<ProductEntity, ProductId> {
    fun findByCategory(category: Category): List<ProductEntity>
}

interface UserCrud : CrudRepository<UserEntity, UserId>

interface OrderJpa : JpaRepository<OrderEntity, OrderId>
```

A read-side projection handler depends on `ProductReadOnly` — not `JpaRepository`. ISP at construction time.

### Compose interfaces for cross-cutting needs

```kotlin
interface UserCustom {
    fun findActiveSince(since: Instant): List<UserEntity>
}

interface UserRepository :
    CrudRepository<UserEntity, UserId>,
    UserCustom
```

Each layer is independently testable; the consumer depends on what it actually uses.

### Don't stuff every method into one fat repository

The anti-pattern here is `OrderRepository : JpaRepository<...>` with 30 custom methods, half of which are read-only projections, the other half being write-side operations. Split into `OrderQueryRepository` (reads / projections) and `OrderRepository` (writes / aggregate persistence).

---

## D — DIP through constructor injection

Spring's primary DI mechanism IS DIP. Use it correctly and DIP is automatic.

### Constructor injection (the recommended)

```kotlin
@Service
class OrderService(
    private val repository: OrderRepository,         // interface in domain/
    private val notifications: NotificationService,  // interface in domain/
) {
    fun place(req: PlaceOrderRequest): Order { ... }
}
```

Properties of constructor injection vs field injection:

| Property | Constructor | Field (`@Autowired lateinit var`) |
|---|---|---|
| Dependencies are explicit | yes (visible in primary constructor) | hidden inside class body |
| Immutability | yes (`val`) | no (`lateinit var`) |
| Testability without Spring | yes | no (need reflection or `@MockBean`) |
| DIP enforced at compile time | yes | no |

Field injection breaks DIP in practice — the class can't be constructed by a test without firing up Spring.

### Domain depends on interfaces; infrastructure provides them

```kotlin
// domain/OrderRepository.kt
interface OrderRepository {
    fun findById(id: OrderId): Order?
    fun save(order: Order): Order
}

// infrastructure/JpaOrderRepository.kt
@Repository
class JpaOrderRepository(...) : OrderRepository { ... }
```

The `domain/` package has no `org.springframework.*` or `org.hibernate.*` imports. The `infrastructure/` package depends on the domain interface and provides the impl. Spring `@Repository` autowires it where the domain interface is requested.

### Enforce the dependency direction with ArchUnit / Modulith tests

```kotlin
@AnalyzeClasses(packagesOf = [Application::class])
class ArchitectureTest {
    @ArchTest
    val domainHasNoSpring = noClasses()
        .that().resideInAPackage("..domain..")
        .should().dependOnClassesThat().resideInAPackage("org.springframework..")
}
```

DIP becomes a CI gate, not a discipline.

### `@Configuration` + `@Bean` for explicit wiring

When you need to construct a third-party type that isn't a Spring stereotype, expose it as a `@Bean` in a `@Configuration` class:

```kotlin
@Configuration
class GatewayConfig {
    @Bean
    fun paymentGateway(props: GatewayProps): PaymentGateway =
        StripeGateway(apiKey = props.apiKey, baseUrl = props.baseUrl)
}
```

The consumer depends on `PaymentGateway` (interface). The factory wires the concrete. Nobody sees Stripe's classes in business code.

---

## Spring features that implement SOLID at a glance

| Spring feature | Principle | How it satisfies it |
|---|---|---|
| Constructor injection | DIP | Class declares interfaces; container provides impls |
| `@Profile` / `@ConditionalOnProperty` | DIP, OCP | Swap implementations per environment without code edits |
| `@RestControllerAdvice` | OCP | Add cross-cutting error handlers without touching controllers |
| Spring Modulith events | OCP, Low Coupling | Add reactions to domain events without touching publishers |
| Spring Data interface hierarchy | ISP | Pick the smallest repository capability your client needs |
| `@Cacheable` / `@Transactional` AOP | OCP | Add cross-cutting concerns declaratively, not in code |
| `@Bean` in `@Configuration` | DIP | Construct third-party types behind interfaces; consumers don't see vendor classes |
| `@ApplicationModuleListener` | OCP, SRP | Each listener is a focused class reacting to one event |
| ArchUnit + Modulith fitness tests | DIP, SRP | Make architectural rules executable in CI |

---

## Common Spring traps that violate SOLID

These earn dedicated treatment in `bad-practices.md`; flagged here as Spring-specific:

- **`@Autowired` field injection** — breaks DIP in practice (can't construct without Spring)
- **`@Component` god services** — Spring lets you, but SRP says split
- **Self-call bypassing `@Transactional` proxy** — not strictly LSP, but a substitution-surprise that breaks the implicit contract
- **Domain code with `@Entity`, `@Transactional`, `@Service`** — DIP violation at architectural scale
- **`final` methods on proxied beans** — silently bypassed, an LSP-of-the-proxy violation
- **Eager dependency on a concrete `@Service`** — request the interface, not `JpaUserRepository`

---

## Where to learn the specifics

- `clean-code-systems` — composition root, IoC discipline, where construction happens
- `spring-boot-mastery` — bean lifecycle, AOP, Modulith depth
- `architecture-patterns` — Onion / Clean / Hexagonal as DIP at module scale
- `testing-strategy-kotlin-spring` — how to test SOLID-shaped code (slice tests, Testcontainers, the substitution surface)
