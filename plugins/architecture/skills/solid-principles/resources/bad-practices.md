# SOLID — Bad Practices Catalogue

Diagnostic file. Each entry: the smell, why it's a violation, the fix. Use during code review or pre-merge audit when you suspect a SOLID violation but want to name and confirm it.

Organised by principle, with cross-cutting "compound violations" at the end.

---

## SRP violations

### S-1: God service

**Smell.** A single `@Service` handles registration, authentication, profile updates, deactivation, audit logs, and email sending. Six unrelated dependencies in the constructor. Methods cluster into disjoint groups that share no fields.

**Why it's wrong.** Six different stakeholders (security, UX, ops, legal, product, compliance) can ask for changes to the same class. Six reasons to change ⇒ six responsibilities ⇒ test setup pulls in everything every time, merge conflicts multiply, the class becomes a dependency magnet.

**Fix.** Split by reason-to-change. One focused service per concern. Spring's DI cost of having six classes is zero; testing cost drops ~5×.

```kotlin
// before
@Service class UserService(
    private val users: UserRepository,
    private val email: EmailClient,
    private val hasher: PasswordHasher,
    private val auth: AuthTokenService,
    private val audit: AuditLog,
) { fun register(...); fun login(...); fun resetPassword(...); fun update(...); fun deactivate(...); fun audit(...) }

// after — six focused services
@Service class UserRegistration(...)   { fun register(...) }
@Service class Authentication(...)     { fun login(...); fun resetPassword(...) }
@Service class UserProfile(...)        { fun update(...) }
@Service class UserDeactivation(...)   { fun deactivate(...) }
@Service class UserAudit(...)          { fun audit(...) }
@Service class WelcomeEmailNotifier(...) { fun send(...) }
```

### S-2: Util / Helper / Manager class

**Smell.** A class named `OrderUtils`, `OrderHelper`, or `OrderManager` collects unrelated functions: `calculateTotal`, `formatForEmail`, `exportToCsv`, `retryFailedOrders`, `cleanupOldOrders`. The only thing in common is the word "Order" in the name.

**Why it's wrong.** The class has as many responsibilities as it has methods. The name is a smell — `Util` / `Helper` / `Manager` are the surest signs that the author couldn't articulate one responsibility. (See `clean-code-naming` for the weasel-suffix ban.)

**Fix.** One class per responsibility, named by what it does:

```kotlin
class OrderPricing       { fun total(order: Order): Money }
class OrderEmailFormat   { fun format(order: Order): String }
class OrderCsvExport     { fun export(orders: List<Order>): ByteArray }
class OrderRetryJob      { fun run(): Int }
class OrderCleanupJob    { fun run(): Int }
```

### S-3: Anaemic domain hybrid

**Smell.** An `@Entity` class has both database-mapping fields and business methods that touch external services (e.g. `Order.placeOrder()` that calls `EmailService` and `PaymentGateway`).

**Why it's wrong.** The class is two things at once: a JPA persistence shape (one reason to change: schema) and a domain operation (another: business rules). Persistence and orchestration are separate responsibilities.

**Fix.** Keep the entity narrow (data + invariants); push orchestration to a service. Or use proper aggregate-root design from `ddd-tactical-patterns` where the entity owns *domain* invariants and the application service owns *infrastructure orchestration*.

---

## OCP violations

### O-1: `when (type)` chain repeated across methods

**Smell.** The same `when` on a `PaymentMethod` enum appears in `process()`, `fee()`, `supports()`, `formatReceipt()`. Adding a fifth payment method requires editing four files.

**Why it's wrong.** The class is closed for extension and open for modification — the inverse of OCP. Each addition is a chance to forget a branch; each refactor risks breaking unrelated code.

**Fix.** Push behaviour onto the type with a sealed hierarchy:

```kotlin
sealed interface PaymentMethod {
    fun process(amount: Money): Result
    fun fee(amount: Money): Money
    fun supports(country: Country): Boolean

    data object Card : PaymentMethod { ... }
    data object BankTransfer : PaymentMethod { ... }
    data object PayPal : PaymentMethod { ... }
}
```

Adding `Crypto` is one new `data object`. The compiler enforces exhaustiveness; nothing else needs editing.

### O-2: Premature OCP — sealing a one-variant case

**Smell.** A `sealed interface PaymentMethod` with exactly one implementation, "in case we add another later". A Strategy bean abstraction over a single concrete that has been there for two years.

**Why it's wrong.** OCP optimises for *anticipated* change. Without a second concrete case, the abstraction is overhead — a hierarchy with one branch, an interface no test can substitute, an extra layer between caller and behaviour.

**Fix.** Inline. Wait for the second concrete case before extracting. The cost of removing premature OCP is one IDE refactor; the cost of leaving it is permanent friction.

### O-3: Adding a feature requires editing a switch *and* a config *and* a test fixture

**Smell.** Onboarding a new payment method touches `PaymentService.process`, `PaymentConfig.SUPPORTED_METHODS`, `PaymentTestFixtures.allMethods`. Three edits across three files just to add a variant.

**Why it's wrong.** The "list of variants" is encoded in three places that have to be kept in sync manually. Each addition is a chance to drift.

**Fix.** A sealed hierarchy gives you the variants in one place; reflection or `enumValues<>().toList()` produces the list elsewhere. Or: a Spring DI strategy pattern where each variant is a `@Component` and the orchestrator depends on `List<PaymentMethod>` (Spring auto-collects).

---

## LSP violations

### L-1: Subclass throws `UnsupportedOperationException`

**Smell.** `Penguin : Bird` overrides `fly()` to throw. `ReadOnlyList : MutableList` overrides `add` to throw.

**Why it's wrong.** The subclass advertises a contract it doesn't honour. Any code accepting the base type will crash for the subtype. The hierarchy is wrong — the base contract included a method not all subtypes can perform.

**Fix.** Split the abstraction. `Bird` (no `fly`), `FlyingBird : Bird` (has `fly`), `Penguin : Bird`. The compiler now enforces the rule.

### L-2: Override narrows preconditions (nullability tightening)

**Smell.**

```kotlin
open class Greeter { open fun greet(name: String?): String = "Hello, ${name ?: "stranger"}" }
class ShoutyGreeter : Greeter() { override fun greet(name: String?): String = name!!.uppercase() }
```

The base accepts `name: String?`; the override crashes on `null`. Type system is satisfied; runtime breaks for any caller using the base type with `null`.

**Why it's wrong.** Subtype demands more from the input than the supertype does. Any code that worked against `Greeter` may break against `ShoutyGreeter`.

**Fix.** Don't narrow preconditions. Either widen the base contract, or split the type so each variant honours its own contract.

### L-3: Override strengthens postconditions invisibly

**Smell.** `open fun findOrder(id: OrderId): Order?` (base may return `null`). Override: `override fun findOrder(id: OrderId): Order` (always returns non-null, lying about the contract via lateinit / `!!`).

This is harder to spot in Kotlin because the type system catches some of it; but if the override does `!!` internally and treats `null` as an exception case, callers depending on the optional behaviour break.

**Fix.** Honour the base return type's nullability. If you can prove non-null statically, narrow the *return* type — Kotlin allows this. If only sometimes, return optional.

### L-4: Override throws an exception not in the base contract

**Smell.** `open fun save(order: Order)` in the base; the JPA implementation throws `OptimisticLockException` on retry; the in-memory test impl never throws. Code paths handling the exception only run in JPA mode.

**Why it's wrong.** New exception ⇒ new precondition on the caller. Code substituting the JPA impl for the in-memory impl will break.

**Fix.** Document exceptions in the base contract; or wrap implementation-specific exceptions into a shared domain exception declared in the interface; or use `Result<T>` to make failure modes explicit in the type.

---

## ISP violations

### I-1: Fat repository forcing implementers to throw or stub

**Smell.** A `UserRepository` with `findById`, `findAll`, `findByEmail`, `save`, `delete`, `bulkInsert`, `count`, `exists`, `stream`, `pageBy`. The in-memory test fake throws `UnsupportedOperationException` on `stream` and `pageBy` because they don't make sense.

**Why it's wrong.** Implementers are forced to lie about their capabilities. Clients depending on `UserRepository` for one method drag in nine more they'll never call.

**Fix.** Split into role interfaces:

```kotlin
interface UserReader   { fun findById(id: UserId): User?; fun findByEmail(email: Email): User? }
interface UserWriter   { fun save(user: User): User; fun delete(id: UserId) }
interface UserBulkOps  { fun bulkInsert(users: List<User>); fun pageBy(...) }
```

Each implementer implements only the roles it fulfils. Clients depend on what they actually call.

### I-2: Marker / stub methods because "the interface requires it"

**Smell.** Override that does nothing, returns a fixed value, or throws. The class clearly doesn't fit the interface; the interface clearly demanded too much.

**Fix.** Either move the method off the interface (often it should be a strategy injected from outside), or split the interface so the implementer doesn't have to implement what it can't.

### I-3: One Spring `@Repository` interface with 30 methods

**Smell.** A Spring Data repository extending `JpaRepository` with 30 query methods covering reads, writes, projections, batch operations.

**Why it's wrong.** Every consumer (a query handler that needs one read, a write-side service that needs one write) drags in all 30. Test mocks have to be huge.

**Fix.** `OrderQueryRepository : Repository<...>` for reads, `OrderRepository : JpaRepository<...>` for writes. Compose for actual use only when needed. Spring Data hierarchy itself models ISP — use it.

---

## DIP violations

### D-1: Concrete-class injection instead of interface

**Smell.** `class OrderService(private val email: SmtpEmailClient)` — the high-level service depends on a low-level concrete.

**Why it's wrong.** Can't swap providers without editing `OrderService`. Tests need a real `SmtpEmailClient` or a mocking framework. The dependency arrow points the wrong way.

**Fix.** Define an interface in the domain (`EmailSender` or `NotificationService`), depend on it, place the SMTP impl in `infrastructure/`.

### D-2: Domain code imports framework / vendor packages

**Smell.** A class in `domain/` imports `org.springframework.transaction.annotation.Transactional`, `org.hibernate.annotations.*`, `software.amazon.awssdk.*`, or `com.stripe.model.*`.

**Why it's wrong.** The most stable code (domain) depends on the most volatile (framework, vendor SDK). When the framework or SDK changes, the domain breaks.

**Fix.** Move framework annotations to the application service / repository adapter layer. Wrap vendor SDKs behind a domain port (`PaymentGateway` interface; `StripeGateway` adapter in `infrastructure/`). Verify with ArchUnit / Modulith fitness tests.

### D-3: `@Autowired` field injection

**Smell.**

```kotlin
@Service
class OrderService {
    @Autowired private lateinit var repository: OrderRepository
    @Autowired private lateinit var notifications: NotificationService
}
```

**Why it's wrong.** Dependencies are hidden inside the class body, not declared at construction. Class can't be constructed in a test without firing up Spring (no constructor to call). DIP is technically present but practically broken.

**Fix.** Constructor injection:

```kotlin
@Service
class OrderService(
    private val repository: OrderRepository,
    private val notifications: NotificationService,
) { ... }
```

Now the test can `OrderService(fakeRepo, fakeNotifications)` — pure DIP.

### D-4: Service locator / `ApplicationContext.getBean()` pulls

**Smell.** Code that reaches into `ApplicationContext` to fetch a dependency at runtime instead of having it injected.

**Why it's wrong.** Hides dependencies, breaks testability, and inverts DIP back to direct dependency on the container.

**Fix.** Inject what you need via the constructor. If you need a *family* of beans, inject `List<Strategy>` or `Map<String, Strategy>` (Spring auto-collects).

### D-5: New-ing a concrete inside a service

**Smell.**

```kotlin
@Service
class OrderService {
    private val email = SmtpEmailClient(host = "smtp.example.com", port = 587)
}
```

**Why it's wrong.** Bypasses DI entirely. Hard-codes the implementation. Configuration is lost. Tests are stuck.

**Fix.** Inject the abstraction; let Spring construct the concrete.

---

## Compound violations

### Compound-1: God service + concrete deps + fat interface

A god `UserService` directly news up `SmtpEmailClient`, depends on a fat `UserRepository`, and has methods touching unrelated concerns. Three principles violated at once: SRP, DIP, ISP.

**Fix order** (per `best-practices.md`): SRP first (split). Then DIP (introduce interfaces). Then ISP (segregate the interfaces by what each split needs). Often once you've split, each piece needs only a small interface, and ISP solves itself.

### Compound-2: Inheritance with overrides that throw

A `BaseRepository` with `find / save / delete / stream / batchInsert`, an `InMemoryRepository` overriding `stream / batchInsert` to throw. LSP and ISP violated together; usually SRP too (the base class has too many responsibilities to be "the repository contract").

**Fix.** Split the base into role interfaces; the in-memory impl picks only the roles it can honour.

### Compound-3: `when` chain on enum + each branch news up vendor classes

```kotlin
fun process(method: PaymentMethod, amount: Money) = when (method) {
    CARD -> StripeClient(apiKey).charge(amount)
    BANK -> AdyenClient(apiKey).transfer(amount)
}
```

OCP and DIP violated together. Each new method requires editing the `when` AND adding a vendor SDK directly.

**Fix.** Sealed `PaymentMethod` with a domain `PaymentGateway` interface; one Spring bean per provider implementing the interface; orchestrator depends on `Map<PaymentMethod, PaymentGateway>`.

---

## Spring-specific anti-patterns

### Spring-1: `@Component` as a place to dump cross-cutting concerns

`@Component class CommonStuff(...)` with a grab-bag of unrelated helpers. Use AOP / `@RestControllerAdvice` / Modulith events for cross-cutting concerns; they belong to specific patterns, not a junk-drawer bean.

### Spring-2: `@Transactional` on a private method

Doesn't work — Spring's proxy can't intercept private methods. Silent LSP-of-the-proxy violation: behaves as if the annotation is missing.

### Spring-3: Self-call bypassing `@Cacheable` / `@Transactional`

```kotlin
@Service
class Foo {
    @Cacheable("x") fun cached(): String = ...
    fun caller(): String = cached()   // doesn't go through proxy — caching skipped
}
```

Self-calls bypass the AOP proxy. Refactor to call through an injected reference, or split into two beans.

### Spring-4: `final` methods on `@Service` (no `kotlin-spring` plugin)

Kotlin classes are `final` by default. Spring AOP needs `open` to subclass. With the `kotlin-spring` Gradle plugin, Spring stereotypes are auto-`open`'d; without it, `@Transactional` silently doesn't apply. Add the plugin.

---

## How to use this catalogue in code review

1. **Scan the diff for the smells.** `Util` / `Helper` / `Manager` in a class name? S-2. New `when (type)` branch added in three files? O-1. Override that throws? L-1. Constructor with seven dependencies? S-1. Domain class importing `org.springframework`? D-2.
2. **Name the violation.** "This is S-1 (god service)" gives the discussion a precise frame instead of "this feels off".
3. **Apply the fix.** The fix per entry is the standard refactor; read the entry, apply it.
4. **Check for compound violations.** S-1 usually drags D-1 along; L-1 usually means split the hierarchy. Refactor in the order from `best-practices.md` (SRP → DIP → ISP → OCP → LSP).
