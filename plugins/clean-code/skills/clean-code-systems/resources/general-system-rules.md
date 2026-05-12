# General System Rules

Universal system-level rules adapted from R. Martin / K. D. Wampler's *Clean Code* Ch. 11 "Systems". Rules where Spring or Kotlin radically changed the mechanics (XML wiring → annotations / `beans { }` DSL, JNDI → Spring `ApplicationContext`, JDK dynamic proxies → Spring AOP, EJB2 → POJOs everywhere) are summarised here and deepened in `kotlin-specific-systems.md`, `spring-boot-systems.md`, and `ddd-systems.md`.

> "Software systems should separate the startup process, when the application objects are constructed and the dependencies are 'wired' together, from the runtime logic that takes over after startup." — Wampler

## How to read this file

Each rule has:
- **Principle** — the one-sentence rule.
- **Bad / Good** — Kotlin snippets (Martin's Java examples re-cast where useful).
- **Why** — the failure mode the rule prevents.
- **Exception** — when the rule legitimately bends.
- **House extension** (where applicable) — Spring/Kotlin specifics.

---

## Rule 1: Separate Constructing a System from Using It

**Source**: Wampler Ch. 11 §"Separate Constructing a System from Using It"
**Principle**: The startup phase — where objects are created and wired — is a different concern from the runtime phase — where the wired-up objects do work. Mixing them violates SRP at the system scale and makes both phases harder to test and evolve.

**Bad** (the canonical Lazy-Init in business code):
```kotlin
class OrderService {
    private var repository: OrderRepository? = null

    fun submit(command: SubmitOrder): OrderId {
        if (repository == null) {
            repository = OrderRepositoryImpl(DataSource(...))   // ← bootstrap inside runtime
        }
        return repository!!.save(Order.from(command)).id
    }
}
```

**Good**:
```kotlin
// Composition root
@Configuration
class OrderModuleConfig {
    @Bean
    fun orderRepository(ds: DataSource): OrderRepository = JpaOrderRepository(ds)

    @Bean
    fun orderService(repo: OrderRepository): OrderService = OrderService(repo)
}

// Runtime
@Service
class OrderService(private val repository: OrderRepository) {
    fun submit(command: SubmitOrder): OrderId =
        repository.save(Order.from(command)).id
}
```

**Why**:
- **Hard-coded dependency** — the bad version couples `OrderService` to `OrderRepositoryImpl`. It can't compile without it; it can't be tested without it.
- **Test pollution** — testing the `null` branch is its own concern, unrelated to the business behaviour.
- **No global strategy** — many such idioms scattered through the system produce zero consistency and double-init bugs.
- **SRP violation in miniature** — the method does runtime work *and* makes a wiring decision.

**Exception**: A small CLI tool or script with no framework may build its object graph at the top of `main()` and pass collaborators downward. That's still "separate construction from use", just without a DI container.

**House extension**: In Spring Boot, the composition root is `@SpringBootApplication` + `@Configuration` classes + auto-configuration. **Business code never calls `new` on a collaborator** that has dependencies of its own. POJOs and value objects can be constructed freely; *services, repositories, clients, gateways* must come from the composition root.

---

## Rule 2: Separation of `main` — the composition-root pattern

**Source**: Wampler Ch. 11 §"Separation of Main"
**Principle**: All construction logic lives in `main` or in modules called from `main`. The dependency arrow goes one way: `main` → application; never application → `main`.

**Anti-pattern (god `main`)**:
```kotlin
fun main(args: Array<String>) {
    val dataSource = HikariDataSource().apply { ... }
    val orderRepo = JpaOrderRepository(dataSource)
    val emailGateway = SmtpGateway(System.getenv("SMTP_HOST"), ...)
    val orderService = OrderService(orderRepo, emailGateway)
    val controller = OrderController(orderService)
    val server = NettyHttpServer(controller)
    if (System.getenv("ENABLE_AUDIT") == "true") {
        AuditAspect.install(orderService)
    }
    server.start()
}
```

**Good** (Spring Boot composition root):
```kotlin
@SpringBootApplication
@EnableConfigurationProperties(OrderProperties::class)
class OrderServiceApplication

fun main(args: Array<String>) {
    runApplication<OrderServiceApplication>(*args)
}
```

The wiring is decomposed into `@Configuration` classes (one per module/concern), profile-scoped beans, and `@ConfigurationProperties` for typed config. `main` is two lines.

**Why**: The application — controllers, services, repositories — has zero knowledge of how it was wired. The wiring is one concern owned by one module. Re-wiring (different profile, different test setup, different deployment) doesn't require touching application code.

**House extension**: Keep one `@Configuration` per module, not one mega-config. Name it `<Module>Config`. Co-locate with the module's source, not in a global `config/` package.

---

## Rule 3: Factories — when the application controls the *when* of creation

**Source**: Wampler Ch. 11 §"Factories"
**Principle**: Some objects must be created during runtime by the application itself (e.g., `OrderLine` instances added to an `Order`). The application controls *when*, but the *how* lives behind a factory interface owned by the composition root.

**Bad**:
```kotlin
class OrderApplicationService(...) {
    fun submit(command: SubmitOrder): OrderId {
        val lines = command.lines.map { LineItemImpl(it.productId, it.quantity, fetchPriceFor(it.productId)) }
        // ← service knows how a LineItem is built and where prices come from
    }
}
```

**Good** (Abstract Factory):
```kotlin
interface LineItemFactory {
    fun create(productId: ProductId, quantity: Quantity): LineItem
}

@Component
class StandardLineItemFactory(private val prices: PriceCatalog) : LineItemFactory {
    override fun create(productId: ProductId, quantity: Quantity): LineItem =
        LineItem(productId, quantity, prices.priceFor(productId))
}

class OrderApplicationService(
    private val lineItems: LineItemFactory,
    ...,
) {
    fun submit(command: SubmitOrder): OrderId {
        val lines = command.lines.map { lineItems.create(it.productId, it.quantity) }
        ...
    }
}
```

**Why**: The application decides *when* a line item is created. The factory decides *how* — and the composition root decides *which* factory implementation (standard, discount-aware, test-stub). Same application code; different wiring per environment.

**Exception**: When the construction logic is trivial (a data class with no dependencies), inlining the constructor is fine — a factory adds ceremony without insulation. Factories pay off when **construction has dependencies of its own**.

**Cross-link**: `gof-patterns` covers Abstract Factory in depth; `ddd-tactical-patterns` covers aggregate factories.

---

## Rule 4: Dependency Injection — IoC applied to dependency management

**Source**: Wampler Ch. 11 §"Dependency Injection"
**Principle**: A class should not take responsibility for instantiating its dependencies. It declares what it needs (typically as constructor parameters); a DI container or composition root provides them. The class becomes **completely passive** in dependency resolution.

**Spectrum of approaches**:

| Approach | Class actively resolves? | Notes |
|---|---|---|
| `new MyServiceImpl()` inside class | Yes | Tightest coupling. Avoid. |
| `MyServiceFactory.create()` static call | Yes | Indirection without insulation. Slightly better; still coupled. |
| JNDI / Service Locator (`ctx.lookup("MyService")`) | Yes (lookup) | Class knows it lives in a container. Better than `new`, worse than DI. |
| `@Autowired` field / setter | Partial | Spring injects; class is passive. Hides cycles, hurts testability without Spring. |
| Constructor injection | No | Class is fully passive. Tests can construct directly. Recommended. |

**Bad (Service Locator)**:
```kotlin
class OrderApplicationService(private val ctx: ApplicationContext) {
    fun submit(command: SubmitOrder): OrderId {
        val repository = ctx.getBean<OrderRepository>()        // ← active lookup
        val mailer = ctx.getBean<Mailer>()
        ...
    }
}
```

**Good (Constructor DI)**:
```kotlin
@Service
class OrderApplicationService(
    private val repository: OrderRepository,
    private val mailer: Mailer,
) {
    fun submit(command: SubmitOrder): OrderId { ... }
}
```

**Why**:
- **SRP** — the class focuses on its job; wiring is someone else's.
- **Testability** — write `OrderApplicationService(fakeRepo, fakeMailer)` in a unit test; no container needed.
- **Composability** — different profiles, different deployments, different test setups all reuse the same class with different collaborators.

**House extension** (Kotlin specifics):
```kotlin
// ✓ Idiomatic — primary-constructor `val` properties, no `@Autowired` needed
@Service
class OrderApplicationService(
    private val orders: OrderRepository,
    private val clock: Clock = Clock.systemUTC(),   // ← default for genuinely optional collaborators
)
```

The Spring constructor-injection convention in Kotlin: **primary constructor only**, **all `val`**, **no `@Autowired`** (single constructor is auto-detected since Spring 4.3).

---

## Rule 5: Plain-Old [Kotlin] Objects at the core

**Source**: Wampler Ch. 11 §"Pure Java AOP Frameworks" — argues for POJOs as the heart of an application
**Principle**: The domain — entities, value objects, services with business logic — should be **plain Kotlin classes with no framework imports**. The framework attaches at the edge.

**Bad (EJB2-style, framework-coupled domain)**:
```kotlin
@Entity
@Table(name = "ORDERS")
class Order : Serializable {
    @Id @GeneratedValue
    var id: Long = 0

    @Column @Convert(...)
    var status: String = ""

    @OneToMany(...) @JoinColumn(...)
    var lines: MutableList<OrderLineEntity> = mutableListOf()

    @PreUpdate fun preUpdate() { ... }
    @PostLoad  fun postLoad()  { ... }
    @Component @Autowired lateinit var publisher: ApplicationEventPublisher   // ← domain depending on Spring
    @Autowired lateinit var pricing: PricingService                            // ← domain depending on a service

    fun submit() {
        // mixed: invariants + persistence triggers + Spring events + pricing recompute
    }
}
```

**Good** (POJO domain + persistence adapter):
```kotlin
// Domain — pure Kotlin, no framework imports
class Order private constructor(
    val id: OrderId,
    private val lines: MutableList<OrderLine>,
    private var status: OrderStatus,
) {
    private val events = mutableListOf<DomainEvent>()
    fun events(): List<DomainEvent> = events.toList()
    fun submit(at: Instant) { /* invariants + state change + event */ }
    fun totalAmount(): Money = lines.fold(Money.zero) { acc, line -> acc + line.subtotal() }
}

// Persistence adapter — knows JPA, translates to/from domain
@Entity @Table(name = "orders")
class OrderRow(
    @Id val id: UUID,
    @Column val status: String,
    @OneToMany(cascade = [ALL], mappedBy = "order") val lines: MutableList<OrderLineRow>,
) {
    fun toDomain(): Order = ...
    companion object { fun from(order: Order): OrderRow = ... }
}
```

**Why**:
- **Test the domain in milliseconds.** No Spring context to start, no database to provision.
- **Survive framework upheaval.** When JPA → R2DBC, when Spring Boot 4 → 5, the domain doesn't move.
- **Reuse outside this app.** A POJO domain can be embedded in a batch job, a CLI, a different service.

**Exception**: Spring annotations on **edge classes** (controllers, repositories, configuration classes) are fine — that's where the framework lives. The line is: the domain `Order.kt` has no `org.springframework.*` import.

**Cross-link**: `clean-code-objects-and-data` for the anemic-domain anti-pattern (POJO domain with no behaviour is just as bad as framework-coupled domain).

---

## Rule 6: Cross-cutting concerns belong to aspects, not business code

**Source**: Wampler Ch. 11 §"Cross-Cutting Concerns" / §"Pure Java AOP Frameworks"
**Principle**: Persistence, security, transactions, caching, retry, metrics, audit — these concerns cut across many objects and would otherwise be duplicated everywhere. They belong to **aspects** (annotations + interceptors) that attach at the seam, not to the business code itself.

**Bad** (persistence + transaction + audit + metric all hand-coded):
```kotlin
class OrderApplicationService(private val txManager: TransactionManager, ...) {
    fun submit(command: SubmitOrder): OrderId {
        val timer = meter.startTimer()
        val tx = txManager.begin()
        try {
            audit.log("submit", command)
            val order = Order.submit(command)
            connection.prepareStatement("INSERT INTO orders ...").use { it.execute() }
            audit.log("submitted", order.id)
            tx.commit()
            return order.id
        } catch (e: Exception) {
            tx.rollback()
            audit.log("submit failed", e)
            throw e
        } finally {
            timer.stop()
        }
    }
}
```

**Good** (concerns declared, not coded):
```kotlin
@Service
class OrderApplicationService(private val orders: OrderRepository) {

    @Transactional
    @Timed("orders.submit")
    @Audited
    fun submit(command: SubmitOrder): OrderId {
        val order = Order.submit(command)
        return orders.save(order).id
    }
}
```

**Why**: The business logic is two lines. Each cross-cutting policy lives in **one place** (the aspect implementation); changing it changes every call site uniformly. The function reads as the verb it represents.

**Caveat**: Aspects accumulate. A method with `@Transactional`, `@Cacheable`, `@PreAuthorize`, `@Retry`, `@Timed`, `@Audited` is doing six things behind one signature. Apply aspects like spices, not soup base — only when a concern qualifies (≥ 3 places, uniform policy, not call-specific).

**House extension**:
| Concern | Spring affordance |
|---|---|
| Transactions | `@Transactional` |
| Security | `@PreAuthorize` / `@Secured` |
| Caching | `@Cacheable` / `@CacheEvict` |
| Retry | `@Retry` (Resilience4j) |
| Circuit breaker | `@CircuitBreaker` |
| Metrics (timer/counter) | `@Timed`, `@Counted` (Micrometer) |
| Audit | custom `@Aspect` `@Around` |
| Tracing | auto by OpenTelemetry agent / Spring Boot Actuator |

---

## Rule 7: Java Proxies — the mechanism that made POJOs work

**Source**: Wampler Ch. 11 §"Java Proxies"
**Principle**: Spring's AOP works by wrapping POJOs in a proxy that intercepts method calls and adds the cross-cutting behaviour. You don't write the proxy — the framework generates it (JDK dynamic proxy for interfaces, CGLIB for classes).

**Implications for your code**:

1. **`@Transactional` (and any aspect) only intercepts calls *through the proxy*.** Self-invocation (`this.otherMethod()`) bypasses the proxy. To get the aspect, call the method on a bean injected from elsewhere.
2. **Final classes / final methods** were a problem with CGLIB (it subclasses) — in Kotlin, mark Spring-managed classes `open` (or use the `kotlin-spring` Gradle plugin which does this automatically).
3. **Proxied beans have an extra layer** — debugging stack traces will show `OrderApplicationService$$EnhancerBySpringCGLIB$$...`. Not your bug.

**Bad** (self-invocation killing `@Transactional`):
```kotlin
@Service
class OrderApplicationService {
    fun submit(command: SubmitOrder): OrderId {
        return doSubmit(command)   // ← `this.doSubmit()` — bypasses proxy
    }

    @Transactional
    fun doSubmit(command: SubmitOrder): OrderId = ...   // ← aspect never fires
}
```

**Good** (call goes through Spring):
```kotlin
@Service
class OrderApplicationService(private val workflow: OrderWorkflow) {
    fun submit(command: SubmitOrder): OrderId = workflow.doSubmit(command)
}

@Service
class OrderWorkflow {
    @Transactional
    fun doSubmit(command: SubmitOrder): OrderId = ...   // ← aspect fires
}
```

**Why**: Proxies are why POJOs can opt into framework behaviour by annotation alone — without the EJB2-style invasive base classes. The cost is the self-invocation gotcha; the benefit is everything else.

**Cross-link**: `spring-boot-mastery` covers AOP mechanics in depth.

---

## Rule 8: Test-drive the system architecture; no Big Design Up Front (BDUF)

**Source**: Wampler Ch. 11 §"Test Drive the System Architecture"
**Principle**: It's a myth that we can get systems "right the first time". Start with a naïvely simple, well-decoupled design that delivers today's stories. Add infrastructure (caches, projections, event bus, separate services) as later stories demand. **Iterative > BDUF**.

**Bad (BDUF)**:
- Pre-design 4 microservices, an event bus, a CQRS projection store, an OAuth2 IdP, an API gateway, a service mesh — for a 2-engineer team's MVP.
- Architectural diagrams that the team can't change without 6 weeks of effort.
- Patterns introduced "because we'll need them" — pre-emptively.

**Good (iterative)**:
- Week 1: Single Spring Boot app, in-memory repository, plain controllers, vertical slice working end-to-end.
- Week 3: A query gets complex; add Testcontainers + Postgres.
- Week 6: Two stories now need to coordinate without HTTP coupling; add Spring Modulith events.
- Month 3: Read-side query is 5 joins; add a denormalised projection (still in-process, still Modulith).
- Month 6: Search needs Elasticsearch; add it as a projection consumer.
- Month 12: Reporting workload has a different scaling profile; split it into a separate service.

Each step is **additive** — provided the previous step kept seams clean (events, ports, interfaces).

**Why**:
- A premature decision is made with the least information. You don't know which read queries will dominate, which writes will spike, which integrations will partner-fail.
- Software's economic shape rewards deferral when seams are clean — radical architectural change is feasible *if* coupling is loose. BDUF locks the structure before the information arrives.

**Exception**: Some decisions are expensive to walk back — public API contracts, the choice of primary data store, the wire-level event schema. Decide *those* early, with the best info you have, and version them. The "defer" rule applies to *tactical* decisions, not the foundational ones.

**Cross-link**: `architecture` for the front-of-funnel "should we even be designing this much" decision.

---

## Rule 9: Optimise decision making — defer to the last responsible moment

**Source**: Wampler Ch. 11 §"Optimize Decision Making"
**Principle**: Give responsibility to the most qualified person, and postpone the decision until the **last responsible moment** — when not deciding starts costing more than deciding wrong.

**Bad**:
- Picking a logging format in week 1 because "we need to decide".
- Choosing between Kafka and RabbitMQ before knowing the throughput shape.
- Deciding the read-model store before the first read endpoint exists.

**Good**:
- Logging: use Logback's default; revisit if structured logs are required.
- Messaging: start with in-process events (`ApplicationEventPublisher` / Modulith); split out when distribution is needed.
- Read store: denormalise in Postgres; add Elasticsearch when a search use case appears.

**Why**: The decision deferred is the decision made with the most context. The cost of "we'll decide later" is bounded by the cost of *not* making a decision; the cost of deciding wrong early can be a rewrite.

**Caveat**: Deferral has a half-life. After "later" comes too many times, it becomes avoidance. The team should know **what's deferred and what triggers the decision** (the "last responsible moment" — e.g., "when we hit 1000 writes/sec we revisit the queue choice").

---

## Rule 10: Use standards wisely, when they add demonstrable value

**Source**: Wampler Ch. 11 §"Use Standards Wisely, When They Add Demonstrable Value"
**Principle**: Standards exist for good reasons (interoperability, hiring, encapsulating community wisdom). But adopting a standard for the standard's sake — without a problem it solves — adds complexity for no benefit.

**Examples of standards adopted prematurely**:
- **EJB2** (Wampler's own example) — heavy, invasive, used by teams that needed only a transactional service.
- **GraphQL** — adopted for a service with one consumer that needed three queries.
- **OAuth2** for an internal service-to-service call where mTLS would have been simpler.
- **gRPC** for an API consumed by 5 endpoints with no shared schema discipline.

**Examples of standards earning their place**:
- **REST + RFC 7807 (ProblemDetail)** — every Spring service uses it; tooling is universal; no compelling alternative.
- **JPA** for transactional SQL — survives across vendors; everyone hires for it.
- **OpenTelemetry** for distributed tracing — vendor-neutral, agent-driven.

**Test**: "Does this standard solve a real problem we have *now*, or one we plausibly will in 6 months, with less effort than the alternative?" If yes, adopt. If no, defer.

**Cross-link**: `architecture-decision-records` for capturing *why* a standard was chosen — future readers must see the reason, not just the choice.

---

## Rule 11: Systems need Domain-Specific Languages (DSLs)

**Source**: Wampler Ch. 11 §"Systems Need Domain-Specific Languages"
**Principle**: A DSL — a small, focused language (internal API or external) — minimises the gap between the domain expert's vocabulary and the code. When the domain has rich, expert-recognised structure (build pipelines, pricing rules, routing, eligibility), a DSL lets the code read like the prose the expert writes.

**Bad (no DSL, business rule buried in Java-style branching)**:
```kotlin
fun discountFor(order: Order): Money {
    var discount = Money.zero
    if (order.customer.tier == GOLD) {
        discount = discount + order.subtotal() * 0.10.toBigDecimal()
    }
    if (order.subtotal() > Money(1000)) {
        discount = discount + Money(50)
    }
    if (order.lines.size >= 10) {
        discount = discount + order.subtotal() * 0.05.toBigDecimal()
    }
    return discount
}
```

**Good (a small Kotlin DSL)**:
```kotlin
val standardDiscount = discountRules {
    forTier(GOLD)    rebate 10.percent of subtotal
    overSubtotal(Money(1000)) rebate Money(50)
    forLines(10..) rebate 5.percent of subtotal
}

fun discountFor(order: Order): Money = standardDiscount.apply(order)
```

The DSL reads like the spec. A pricing analyst can read it and confirm.

**Why**: Less translation between domain and code → fewer mis-translations → faster iteration with domain experts → tests written in the domain's language.

**Caveat**: A DSL has cost — it has to be designed, documented, maintained, and learned. A DSL for code with two callers and no domain expert reading it is overhead.

**When a DSL earns its place**:
- The domain has rich structure that experts speak.
- There are ≥ 5 distinct uses, or non-engineers will read/write the DSL.
- The structure changes more often than the implementation (rules, routing, pipeline stages, build config).

**Kotlin DSL primitives** that make small DSLs cheap:
- Type-safe builders (receiver-with-block lambdas).
- Infix functions.
- Operator overloading (used judiciously).
- Extension functions.

**Cross-link**: `kotlin-specific-systems.md` for examples; `spring-boot-systems.md` for Spring's `beans { }` and Security `http { }` DSLs.

---

## Summary table — rules at a glance

| # | Rule | One-line test |
|---|---|---|
| 1 | Separate construction from use | No `new`/`lazy-init` for collaborators in business code. |
| 2 | Separation of main | `main` is two lines; wiring is in `@Configuration` modules. |
| 3 | Factories when application controls creation | If construction has dependencies, hide it behind a factory interface. |
| 4 | Dependency Injection | Class is passive; constructor params carry collaborators. |
| 5 | POJOs at the core | Domain has zero framework imports. |
| 6 | Cross-cutting concerns are aspects | Transactions / security / metrics / retry are annotations, not code. |
| 7 | Mind the proxy | No self-invocation if you want the aspect; mark classes `open` (or use kotlin-spring). |
| 8 | Test-drive architecture, no BDUF | Today's stories first; add infra when next story needs it. |
| 9 | Defer decisions to last responsible moment | "We'll decide when X happens" — name X. |
| 10 | Standards when they add demonstrable value | "What problem does it solve *now*?" — answer it before adopting. |
| 11 | DSLs at the domain boundary | A DSL earns its place when experts read/write it and the structure varies. |

---

## A worked example — incremental architectural evolution

A 1-service Spring Boot app evolving over 12 months, each step keeping the previous seams clean:

```
Month 0 — POJO domain + in-memory repos + REST controllers
└── Boot, deploy, ship feature 1.

Month 1 — add Postgres via JPA
└── Replace in-memory repo with JpaOrderRepository; domain unchanged.

Month 2 — security
└── @PreAuthorize on application-service methods + Spring Security filter chain.

Month 3 — events
└── ApplicationEventPublisher + @TransactionalEventListener for receipt emails.

Month 4 — second module (Inventory)
└── Spring Modulith; new package, new @Configuration; events flow between modules.

Month 5 — read model
└── Projection table populated by @ApplicationModuleListener; query layer reads denormalised view.

Month 7 — async outbound to a partner API
└── Resilience4j @Retry + @CircuitBreaker on a domain client port.

Month 9 — Modulith → Kafka outbox
└── Modulith's event_publication table is forwarded by an outbox dispatcher to Kafka.

Month 11 — Reporting moves out
└── Reporting consumer becomes a separate service consuming the same Kafka events.
```

At every step the **domain didn't move** (Rule 5), the **bootstrap was the only place that changed** (Rule 1), and the **decisions were made when the cost of not deciding became real** (Rule 9). No BDUF (Rule 8). That's the destination Wampler's chapter points at.
