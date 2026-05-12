# Architecture Patterns Implementation Playbook

Detailed patterns, Kotlin/Spring code samples, and pitfalls referenced by the `architecture-patterns` skill.

Stack assumption: **Kotlin + Spring Boot + Spring Data JPA + PostgreSQL** (other stores as needed).

---

## Pattern selection cheatsheet

| Pattern | When | Avoid when | Complexity |
|---|---|---|---|
| **Layered (MVC-style)** | Simple CRUD, MVP, small team, short horizon | Rich domain logic, multiple bounded contexts | Low |
| **Onion** | Rich domain, DDD-leaning, dependency-inward discipline | Pure CRUD without invariants | Medium |
| **Clean** | Same as Onion + strict use-case isolation, testing without Spring | Small/simple services (overkill) | Medium-High |
| **DDD (tactical)** | Real business rules, invariants, ubiquitous language | CRUD with no domain logic | High (overlay on Onion/Clean) |

> Hexagonal (Ports & Adapters) is intentionally omitted. Use Clean Architecture for the same isolation goals — it gives you the same ports concept under a clearer name (interface in `domain`, adapter in `adapter`).

---

## 1. Layered (MVC-style) — the default Spring Boot pattern

The simplest sane layout for a Spring Boot service. Four layers, top depends on bottom:

```
@RestController  →  @Service  →  @Repository (JpaRepository)  →  @Entity
   web/HTTP        application      persistence                  domain shape
```

### Directory layout

```
src/main/kotlin/com/example/user/
├── UserController.kt        // @RestController — HTTP
├── UserService.kt           // @Service — orchestration
├── UserRepository.kt        // : JpaRepository<UserEntity, UUID>
├── UserEntity.kt            // @Entity
└── dto/
    ├── CreateUserRequest.kt
    └── UserResponse.kt
```

### Example

```kotlin
// UserEntity.kt — JPA-mapped, NOT a data class
@Entity
@Table(name = "users")
class UserEntity(
    @Id val id: UUID = UUID.randomUUID(),
    @Column(nullable = false, unique = true) var email: String,
    var name: String,
    @Column(name = "is_active") var isActive: Boolean = true,
    @Column(name = "created_at") val createdAt: Instant = Instant.now(),
) {
    // equals/hashCode by id only (see Vlad Mihalcea's pattern)
    override fun equals(other: Any?) = other is UserEntity && other.id == id
    override fun hashCode() = id.hashCode()
}

// UserRepository.kt
interface UserRepository : JpaRepository<UserEntity, UUID> {
    fun findByEmail(email: String): UserEntity?
}

// UserService.kt
@Service
@Transactional
class UserService(private val repo: UserRepository) {
    fun create(req: CreateUserRequest): UserResponse {
        require(repo.findByEmail(req.email) == null) { "Email already exists" }
        val saved = repo.save(UserEntity(email = req.email, name = req.name))
        return UserResponse(saved.id, saved.email, saved.name)
    }
}

// UserController.kt
@RestController
@RequestMapping("/users")
class UserController(private val service: UserService) {
    @PostMapping
    fun create(@RequestBody req: CreateUserRequest): UserResponse = service.create(req)
}
```

### When NOT to use

- Business rules grow inside `@Service` — service becomes a god-class.
- You want unit tests for business logic **without** Spring context.
- Multiple bounded contexts share entities by accident.

→ Move to **Onion** when any of these hit.

---

## 2. Onion Architecture

Dependencies point **inward toward the domain core**. Same idea as Clean, less prescriptive about use cases vs. services.

### Layers (outer depends on inner)

```
┌─────────────────────────────────────────────┐
│ Infrastructure (Spring, JPA, HTTP, Kafka)   │  ← outermost
├─────────────────────────────────────────────┤
│ Application Services (orchestration)         │
├─────────────────────────────────────────────┤
│ Domain Services (logic spanning entities)    │
├─────────────────────────────────────────────┤
│ Domain Model (entities, VOs, events)         │  ← center
└─────────────────────────────────────────────┘
```

### Directory layout

```
src/main/kotlin/com/example/billing/
├── domain/                       // pure Kotlin, no Spring/JPA imports
│   ├── model/
│   │   ├── Invoice.kt
│   │   └── InvoiceLine.kt
│   ├── vo/
│   │   ├── Money.kt
│   │   └── InvoiceId.kt
│   ├── event/
│   │   └── InvoicePaid.kt
│   └── service/
│       └── InvoicePricingService.kt   // domain logic spanning entities
├── application/                  // use cases / orchestration
│   ├── IssueInvoice.kt
│   └── MarkInvoicePaid.kt
└── infrastructure/               // Spring + JPA + HTTP
    ├── persistence/
    │   ├── InvoiceJpaEntity.kt
    │   ├── InvoiceJpaRepository.kt
    │   └── InvoiceRepositoryAdapter.kt   // implements domain interface
    └── web/
        └── InvoiceController.kt
```

### Example

```kotlin
// domain/vo/Money.kt — data class is OK for VOs
data class Money(val amountMinor: Long, val currency: String) {
    operator fun plus(other: Money): Money {
        require(currency == other.currency) { "currency mismatch" }
        return Money(amountMinor + other.amountMinor, currency)
    }
}

// domain/model/Invoice.kt — domain entity, no JPA annotations
class Invoice(
    val id: InvoiceId,
    val customerId: CustomerId,
    private val lines: MutableList<InvoiceLine> = mutableListOf(),
    var status: InvoiceStatus = InvoiceStatus.DRAFT,
) {
    fun addLine(line: InvoiceLine) {
        check(status == InvoiceStatus.DRAFT) { "cannot edit issued invoice" }
        lines += line
    }

    fun total(): Money = lines.map { it.subtotal() }
        .reduceOrNull(Money::plus) ?: Money(0, "EUR")

    fun issue(): InvoiceIssued {
        check(lines.isNotEmpty()) { "empty invoice" }
        status = InvoiceStatus.ISSUED
        return InvoiceIssued(id)
    }
}

// domain/InvoiceRepository.kt — interface owned by domain
interface InvoiceRepository {
    fun findById(id: InvoiceId): Invoice?
    fun save(invoice: Invoice): Invoice
}

// application/IssueInvoice.kt
@Service
@Transactional
class IssueInvoice(
    private val invoices: InvoiceRepository,
    private val events: ApplicationEventPublisher,
) {
    operator fun invoke(id: InvoiceId): Money {
        val invoice = invoices.findById(id) ?: error("not found")
        val event = invoice.issue()
        invoices.save(invoice)
        events.publishEvent(event)
        return invoice.total()
    }
}

// infrastructure/persistence/InvoiceRepositoryAdapter.kt
@Component
class InvoiceRepositoryAdapter(
    private val jpa: InvoiceJpaRepository,
) : InvoiceRepository {
    override fun findById(id: InvoiceId) = jpa.findById(id.value).map { it.toDomain() }.orElse(null)
    override fun save(invoice: Invoice): Invoice = jpa.save(InvoiceJpaEntity.fromDomain(invoice)).toDomain()
}
```

### Key rules

- `domain/` must not import `org.springframework.*`, `jakarta.persistence.*`, `org.hibernate.*`.
- The repository **interface** lives in `domain/`. The **implementation** lives in `infrastructure/persistence/`.
- JPA entity is a separate class from the domain entity (`InvoiceJpaEntity` ≠ `Invoice`). The adapter maps between them.
- Verify with ArchUnit or Spring Modulith `ApplicationModuleTest`.

---

## 3. Clean Architecture

Same dependency-inward rule as Onion, with a sharper distinction between **entities**, **use cases**, **interface adapters**, **frameworks**.

### Four circles (outer depends on inner)

1. **Entities** — enterprise-wide business rules (`Invoice`, `Money`)
2. **Use Cases** — application-specific business rules (`IssueInvoice`)
3. **Interface Adapters** — controllers, presenters, gateways, repositories
4. **Frameworks & Drivers** — Spring, JPA, web, message brokers

### Difference from Onion

- Clean elevates **use cases** as first-class citizens (one class per use case).
- Repositories and gateways are explicitly "interface adapters", not "domain interfaces".
- The dependency rule is the same; the vocabulary is different.

### When to pick Clean over Onion

- You want the codebase to be **completely Spring-free** in `domain/` and `usecase/`.
- You're building a library or an engine that may be consumed outside Spring.
- Strict use-case-per-class testing without `@SpringBootTest`.

### Example use-case class

```kotlin
// usecase/CreateUser.kt — pure Kotlin, no Spring
class CreateUser(
    private val users: UserRepository,         // port (interface)
    private val clock: Clock,
    private val ids: IdGenerator,
) {
    data class Request(val email: String, val name: String)
    data class Response(val id: UUID)

    operator fun invoke(req: Request): Response {
        require(users.findByEmail(req.email) == null) { "email taken" }
        val user = User(id = ids.next(), email = req.email, name = req.name, createdAt = clock.instant())
        users.save(user)
        return Response(user.id)
    }
}
```

Notice: no `@Service`, no `@Transactional`, no `@Autowired`. Spring wires this up in a config class in the `frameworks` layer.

### Common pitfall

Building Clean for a service that's really just CRUD. Cost: 3× the files for 1× the value. **If you'd write 5 trivial use cases that all just delegate to a repository, use Layered instead.**

---

## 4. Domain-Driven Design (tactical) — overlay on Onion/Clean

DDD tactical patterns overlay on top of Onion or Clean when the **domain has real business rules**. This section covers only **how DDD concepts map onto the layered architecture**; for the actual tactical patterns (designing aggregates, value objects, events, repositories, invariants), see the canonical skill.

### Quick mapping — DDD concept → Kotlin shape in this architecture

| Concept | Kotlin shape | Where it lives |
|---|---|---|
| **Entity** | `class Order(val id: OrderId, ...) { ... }` — identity-based equality, **not** a `data class` | `domain/model/` |
| **Value Object** | `data class Money(...)` or `@JvmInline value class Email(...)` | `domain/vo/` |
| **Aggregate Root** | Entity that owns children and enforces invariants | `domain/model/` |
| **Domain Event** | Past-tense `data class OrderShipped(...)` | `domain/event/` (or `contract/event/<ctx>/` if cross-context) |
| **Repository (interface)** | Owned by domain | `domain/` |
| **Repository (adapter)** | JPA / store-specific implementation | `infrastructure/persistence/` |
| **Domain Service** | Stateless, logic spanning multiple aggregates | `domain/service/` (or `application/`) |

### Canonical skills for tactical depth

- **`ddd-tactical-patterns`** — aggregate design, invariants, value objects, repositories, domain events. The full pattern catalogue with Kotlin examples and checklists.
- **`database-design`** (specifically `resources/schema-design.md` §1) — JPA persistence shape of an aggregate, including why `data class` for `@Entity` is a Hibernate footgun.
- **`cqrs-implementation`** (specifically `resources/write-side-patterns.md` §4) — how the aggregate publishes events through `ApplicationEventPublisher` in a CQRS write-side handler.
- **`ddd-strategic-design`** — for the bounded context and ubiquitous language **above** tactical patterns.
- **`ddd-context-mapping`** — for relationships **between** contexts (ACL, OHS, Published Language).

---

## Best practices

1. **Dependency rule**: dependencies always point inward; verify with ArchUnit.
2. **Domain stays Spring-free** in Onion/Clean. No `@Service`, no `@Entity` in `domain/`.
3. **Repositories belong to the domain** (interface), with JPA adapters in `infrastructure/`.
4. **Rich domain models** over anemic ones — behavior with data.
5. **Thin controllers** — they translate HTTP to use-case calls, nothing else.
6. **One aggregate per repository** — don't reach into child entities from outside.
7. **Domain events for cross-aggregate effects** — publish via `ApplicationEventPublisher` or Spring Modulith.
8. **Ubiquitous language** — package names mirror domain terms.

## Common pitfalls

- **Anemic domain** — entities are bags of getters/setters, all logic in `@Service`. Move logic into entities.
- **Framework leakage** — `domain/` imports Spring/JPA. Break it; add an ArchUnit rule to keep it broken.
- **Fat controllers** — controllers contain business logic. Push it into use cases.
- **Exposing JPA entities** — REST endpoints return `*JpaEntity`. Use a DTO at the boundary.
- **Over-engineering** — Clean for a 3-endpoint CRUD service. Drop down to Layered.
- **Using `data class` for JPA entities** — causes Hibernate proxy bugs. Don't.
- **One giant aggregate** — "Order owns Customer owns ShippingAddress owns…". Aggregates should be small consistency boundaries.

## Verification

- **ArchUnit**: enforce package dependency rules.
  ```kotlin
  noClasses().that().resideInAPackage("..domain..")
      .should().dependOnClassesThat().resideInAnyPackage("org.springframework..", "jakarta.persistence..")
  ```
- **Spring Modulith**: `ApplicationModuleTest` validates module boundaries.
- **Test domain without Spring**: pure JUnit, no `@SpringBootTest` for domain/use-case tests.
