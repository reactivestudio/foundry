# GoF — Spring Boot

Patterns Spring provides for free, and Spring features that act as the canonical implementation of certain GoF patterns. The framework handles much of the wiring; your code uses the resulting beans.

For pattern definitions, see `theory.md`. For pure Kotlin idioms, see `kotlin.md`. For misapplications, see `bad-practices.md`.

---

## Spring-provided patterns

### Singleton — default Spring bean scope

Every `@Component`, `@Service`, `@Repository`, `@Controller` is a Singleton by default in Spring. The container guarantees one instance per `ApplicationContext`.

```kotlin
@Service
class PricingService(...) { ... }
```

Single instance, lazily constructed (with default eager init in production, or lazy via `@Lazy`). DI provides explicit dependency declaration — better than the classical Singleton's hidden global access.

Use `@Scope("prototype")` only when you genuinely need a new instance per injection point — rarely.

---

### Proxy — `@Transactional` / `@Cacheable` / `@Async` / `@Retryable`

Spring's AOP infrastructure wraps your beans in CGLIB / JDK dynamic proxies that intercept method calls and add cross-cutting behaviour:

```kotlin
@Service
class OrderService(...) {
    @Transactional
    fun placeOrder(req: PlaceOrderRequest): Order {
        // proxy opens transaction → method runs → proxy commits or rolls back
        ...
    }

    @Cacheable("orders", key = "#id")
    fun get(id: OrderId): Order? {
        // proxy checks cache → if miss, runs method → proxy populates cache
        ...
    }
}
```

Don't write Proxy by hand for these concerns; use the annotation.

**Trap: Self-call bypassing the proxy.** A method on the same bean calling another method on `this` bypasses the proxy entirely (the call doesn't go through the wrapper). The result: `@Transactional` silently doesn't apply.

```kotlin
@Service
class Foo {
    @Transactional fun outer() { inner() }   // inner() bypasses proxy
    @Transactional fun inner() { ... }
}
```

Fix: split into two beans, or call through an injected reference to `this`.

**Trap: Kotlin classes are `final` by default.** Spring AOP needs `open` to subclass for CGLIB proxies. The `kotlin-spring` Gradle plugin auto-`open`s Spring stereotypes; without it, `@Transactional` silently doesn't apply. Add the plugin.

---

### Observer — `ApplicationEventPublisher` + `@ApplicationModuleListener`

```kotlin
@Service
class PlaceOrderHandler(private val events: ApplicationEventPublisher) {
    fun handle(cmd: PlaceOrderCommand): OrderId {
        val order = ...
        orders.save(order)
        events.publishEvent(OrderPlaced(order.id, order.customerEmail, order.total()))
        return order.id
    }
}

@Component
class OrderEmailNotifier(private val email: EmailSender) {
    @ApplicationModuleListener
    fun on(event: OrderPlaced) {
        email.send(event.customerEmail, "Your order #${event.orderId}")
    }
}
```

Spring Modulith's `@ApplicationModuleListener` (preferred over plain `@EventListener` for module-internal events) handles the transactional handoff: publishes after commit, retries on failure, persists undelivered events to the outbox.

Don't write `Observable` / `Observer` interfaces by hand.

---

### Abstract Factory — `@Profile` / `@ConditionalOnProperty`

```kotlin
interface PaymentGateway {
    fun charge(amount: Money, customer: Customer): Result<TransactionId>
}

@Component @Profile("!test")
class StripePaymentGateway(...) : PaymentGateway { ... }

@Component @Profile("test")
class FakePaymentGateway : PaymentGateway { ... }
```

Spring picks the bean based on the active profile. Migration Stripe → Adyen: add `@Component @Profile("adyen")` adapter; switch profile.

For finer-grained switching:

```kotlin
@Component
@ConditionalOnProperty("payment.provider", havingValue = "stripe", matchIfMissing = true)
class StripePaymentGateway(...) : PaymentGateway { ... }
```

Switches via `application.yml`: `payment.provider: stripe`.

---

### Facade / Mediator — `@Service` orchestration

Most `@Service` classes are Facades or Mediators. The pattern is so embedded in Spring practice that it's rarely named.

```kotlin
@Service
class CheckoutOrchestrator(
    private val pricing: PricingService,
    private val tax: TaxCalculator,
    private val inventory: InventoryService,
    private val payment: PaymentGateway,
    private val notifications: NotificationService,
) {
    fun checkout(cart: Cart, paymentMethod: PaymentMethod): CheckoutResult { ... }
}
```

The orchestrator IS the Mediator (collaborators don't reference each other directly) AND a Facade (clients call one method to trigger the whole subsystem).

---

### Strategy — bean injection of `List<T>` / `Map<String, T>`

```kotlin
interface PaymentGateway {
    fun supports(method: PaymentMethod): Boolean
    fun charge(amount: Money, customer: Customer): Result<TransactionId>
}

@Component class StripeGateway(...) : PaymentGateway { ... }
@Component class AdyenGateway(...) : PaymentGateway { ... }
@Component class PayPalGateway(...) : PaymentGateway { ... }

@Service
class PaymentProcessor(private val gateways: List<PaymentGateway>) {
    fun process(method: PaymentMethod, amount: Money, customer: Customer) =
        gateways.first { it.supports(method) }.charge(amount, customer)
}
```

Spring auto-collects all `PaymentGateway` beans into the `List`. Adding `BraintreeGateway` is one new bean; `PaymentProcessor` finds it at startup.

Or by name:

```kotlin
@Service
class PaymentProcessor(private val gateways: Map<String, PaymentGateway>) {
    fun process(provider: String, amount: Money, customer: Customer) =
        (gateways[provider] ?: throw UnknownProvider(provider)).charge(amount, customer)
}
```

Bean name (lowercased class name by default) is the key.

---

### Chain of Responsibility — Servlet filter chain / `OncePerRequestFilter`

Spring Security and Spring Web filter chains ARE Chain of Responsibility:

```kotlin
@Component
class TenantContextFilter : OncePerRequestFilter() {
    override fun doFilterInternal(req: HttpServletRequest, res: HttpServletResponse, chain: FilterChain) {
        val tenant = req.getHeader("X-Tenant-Id")
        TenantContext.set(tenant)
        try {
            chain.doFilter(req, res)
        } finally {
            TenantContext.clear()
        }
    }
}
```

Each filter handles or passes; the chain orders them via `@Order` or via `SecurityFilterChain` configuration.

---

### Decorator — `BeanPostProcessor` and explicit `@Primary` wrappers

You can wrap an existing bean by registering a wrapper as `@Primary`:

```kotlin
@Component
class CachingOrderRepository(
    @Qualifier("jpaOrderRepository") private val inner: OrderRepository,
    private val cache: Cache<OrderId, Order>,
) : OrderRepository by inner {
    override fun findById(id: OrderId): Order? = cache.get(id) { inner.findById(id) }
}

// JpaOrderRepository is annotated normally; the caching wrapper is @Primary
```

Consumers depending on `OrderRepository` get the caching wrapper; the inner repository is reachable via `@Qualifier` if needed.

Or use `BeanPostProcessor` for cross-cutting wrapping at startup — heavier machinery, rarely needed.

---

### Template Method — `*Template` classes (`RestTemplate`, `JdbcTemplate`, `RedisTemplate`)

Spring's `*Template` classes implement Template Method: a fixed protocol skeleton with overridable hooks.

```kotlin
@Component
class StripeAdapter(private val rest: RestTemplate) {
    fun charge(req: ChargeRequest): ChargeResponse =
        rest.exchange("/charges", HttpMethod.POST, ...).body!!
}
```

You don't subclass `RestTemplate`; you use it. The "template" framing is historical — modern usage is composition, not inheritance.

---

### Iterator — `Iterable<T>` returns from Spring Data + `Page<T>`

```kotlin
interface OrderRepository : CrudRepository<Order, OrderId> {
    fun findByCustomerId(id: CustomerId): Iterable<Order>
    fun findByStatus(status: OrderStatus, page: Pageable): Page<Order>
}
```

`Iterable<Order>` for streaming results; `Page<Order>` for paginated results with metadata. Custom Iterator implementation is never needed.

---

## Spring features that act as multiple GoF patterns at once

Spring's design itself is heavily pattern-driven. Many features serve multiple GoF patterns simultaneously:

| Spring feature | GoF patterns served |
|---|---|
| `@Service` / `@Component` | Facade, Mediator, Pure Fabrication, Singleton scope |
| Constructor injection | Dependency Injection (a meta-pattern), Strategy (when injecting interfaces) |
| `@Bean` in `@Configuration` | Factory Method, Abstract Factory, Builder (for complex construction) |
| `@Profile` / `@ConditionalOnProperty` | Abstract Factory, Strategy |
| `@Transactional` / `@Cacheable` / `@Async` | Proxy (Decorator at the AOP level) |
| `ApplicationEventPublisher` + `@ApplicationModuleListener` | Observer, Mediator |
| `Map<String, T>` / `List<T>` injection | Strategy (orchestrator + family of variants) |
| `@RestControllerAdvice` + `@ExceptionHandler` | Chain of Responsibility (advice precedence), Decorator (wraps the handler) |
| `OncePerRequestFilter` | Chain of Responsibility |
| `RestTemplate` / `WebClient` | Template Method (protocol skeleton with hooks) |
| Spring Modulith application modules | Mediator (events between modules), Facade (module-public API) |

---

## Spring traps that misapply or hide patterns

### Trap-1: Reinventing what Spring provides

Hand-writing an `Observer` interface when `ApplicationEventPublisher` exists. Hand-writing a Singleton when Spring beans are singletons. Hand-writing a fluent Builder when named arguments + `@Bean` config suffices.

If Spring provides the pattern, use it. Hand-rolled equivalents are smell.

### Trap-2: Self-call bypassing AOP proxy

A `@Transactional` or `@Cacheable` method called from another method *on the same bean* via `this` doesn't go through the proxy. The annotation silently doesn't apply.

Fix: split into two beans, OR call through an injected `ApplicationContext.getBean(this::class.java)`, OR refactor to constructor-inject a self-reference (`@Lazy private val self: Foo`) — but the cleanest fix is splitting.

### Trap-3: Final Kotlin methods on AOP-proxied beans

Kotlin classes and methods are `final` by default. CGLIB can't override `final`. The `kotlin-spring` Gradle plugin auto-`open`s Spring stereotypes — without it, `@Transactional` silently fails.

Always use `kotlin-spring`. (Also `kotlin-jpa` for `@Entity` classes.)

### Trap-4: Premature `@Profile` / `@ConditionalOnProperty` for Abstract Factory

Adding `@Profile` for "in case we need a different impl" without an actual second impl is overhead. Each profile is a CI matrix dimension; each conditional is mental overhead. Apply when the second impl is real.

### Trap-5: Service-locator (`ApplicationContext.getBean()`) instead of injection

Reaching into the context to fetch a bean at runtime defeats DI. The bean's dependencies become hidden; testing requires firing up Spring; Strategy / Abstract Factory should be expressed via injection, not lookup.

```kotlin
// bad
class Foo(private val ctx: ApplicationContext) {
    fun act() = ctx.getBean(Bar::class.java).doSomething()
}

// good
class Foo(private val bar: Bar) {
    fun act() = bar.doSomething()
}
```

### Trap-6: Using `@Component` to dump a junk-drawer of helpers

`@Component class CommonStuff(...)` violates High Cohesion (GRASP) and SRP (SOLID). Cross-cutting concerns belong to specific patterns: AOP for observability/transactions, `@RestControllerAdvice` for error handling, Modulith events for inter-module reactions, configuration beans for setup.

---

## When to skip Spring's pattern features

Spring's pattern features cost: AOP makes stack traces deeper; `@Profile` bean wiring adds startup-time logic; events introduce eventual consistency.

Skip when:

- The behaviour is intrinsic to the operation (transaction always required, retry always needed) — inline it.
- The proxy / event indirection makes debugging materially harder than the cost of duplication.
- One-shot scripts where setup overhead exceeds benefit.

The bias is toward *using* Spring's pattern features (they're the path of least friction for most applications), but the discipline is in *recognising* when not to.

---

## Quick lookup: "which Spring feature implements this GoF pattern?"

| GoF pattern | Spring feature(s) |
|---|---|
| Singleton | Default bean scope |
| Builder | `@Bean` factory, `@ConfigurationProperties` |
| Factory Method | `@Bean` in `@Configuration` |
| Abstract Factory | `@Profile`, `@ConditionalOnProperty`, `@ConditionalOnClass`, `@ConditionalOnBean` |
| Adapter | Custom `@Component` wrapping a third-party SDK; `HandlerMethodArgumentResolver` for HTTP request adaptation |
| Decorator | `@Primary` wrapper bean using `by` delegation; `BeanPostProcessor` |
| Facade | `@Service` |
| Bridge | Interface + multiple `@Component` impls + `@Qualifier` |
| Proxy | `@Transactional`, `@Cacheable`, `@Async`, `@Retryable`, `@Validated`, `@PreAuthorize` |
| Flyweight | (No specific Spring feature; rarely needed) |
| Strategy | `@Component` impl + `List<T>` / `Map<String, T>` injection |
| Observer | `ApplicationEventPublisher` + `@EventListener` / `@ApplicationModuleListener` |
| Command | (Express as sealed Kotlin types; Spring not directly involved — see `cqrs-implementation`) |
| Iterator | `Iterable<T>` / `Page<T>` from Spring Data |
| Template Method | `RestTemplate`, `JdbcTemplate`, `RedisTemplate` (mostly historical) |
| Chain of Responsibility | `OncePerRequestFilter` chain, `SecurityFilterChain` |
| State | (No specific Spring feature; for heavy FSMs, Spring State Machine) |
| Mediator | `@Service` orchestrator |
| Memento | (No specific Spring feature; `data class` snapshot in pure Kotlin) |
| Visitor | (Don't — use sealed + `when` in Kotlin) |
| Interpreter | (No specific Spring feature; build a DSL in pure Kotlin) |
