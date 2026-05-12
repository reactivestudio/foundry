---
name: clean-code-classes
description: "Class-design discipline for Kotlin/Spring code — opinionated rules for class organisation (Kotlin primary-constructor properties at the top, stepdown private utilities right after their callers), encapsulation by default (visibility loosened only as a last resort, `internal` over `protected` for test seams), small-by-responsibility sizing (mandatory `25-word, no-and/or/but` description test, weasel-suffix ban — Manager, Helper, Util, Processor, Super), Single Responsibility Principle (one reason to change per class), high cohesion (every method touches most fields; falling cohesion is the signal to split), the Many-Small-Classes rule (extracting big methods grows fields → grow new classes), Open-Closed via sealed hierarchies and Strategy beans (extend by adding a subclass / `@ConditionalOnProperty` bean, not by editing the existing class), and Dependency Inversion via constructor-injected interfaces (`Portfolio(StockExchange)` not `Portfolio(TokyoStockExchange)`, with a fake `StockExchange` for tests). Adapted from R. Martin's Clean Code Ch. 10 'Classes', filtered for what Kotlin already solves (primary constructor + properties replace the Java field-at-top convention, `internal` visibility for module-scoped test access, `sealed class`/`sealed interface` as built-in OCP closure, `object` and `companion object` over static utility classes, `data class` for value-shaped classes, `@JvmInline value class` against primitive obsession, extension functions to keep behaviour out of god classes, `by` delegation as composition-over-inheritance) and extended with Spring/JPA conventions (constructor injection as practical DIP, thin `@RestController` delegating to use-case-narrow services, `FooService` god-class split by use case or CQRS command-handler, `@ConfigurationProperties` data class as small cohesive class, Spring Modulith application modules as SRP enforcement at module scope, JPA `@Entity` as persistence shape ≠ aggregate, factory beans / `@ConditionalOnProperty` / `@Profile` for OCP-style swap-in, wrapping external integrations behind a port interface — TokyoStockExchange becomes the adapter behind a StockExchange port). Use this skill whenever the user designs or reviews a *class* and the question is 'should this be one class or several, how big is too big, what does it depend on, how will it change' — including: naming a new class and deciding what belongs in it vs. on a separate class, refactoring a god service / SuperDashboard / FooManager into single-responsibility units, applying the 25-word description test to spot weasel responsibilities, splitting a class whose private methods touch only a subset of fields, deciding whether to extend an existing class or add a new sealed subtype / Strategy bean (OCP), wrapping a concrete `TokyoStockExchange`-style dependency behind an interface for testability (DIP), reviewing a class with 70 public methods or 30 instance variables, auditing a Spring service that grew to handle five unrelated use cases, distinguishing 'class' concerns (shape, responsibility, dependencies) from 'function' concerns (covered by clean-code-functions) and 'data vs. behaviour' concerns (covered by clean-code-objects-and-data). Apply it proactively any time a class exceeds one screen, accumulates a fifth instance variable used by only one method, or has a name ending in Manager/Helper/Util/Processor/Super — even if the user hasn't named it as a class-design problem."
risk: safe
source: "Adapted from R. Martin, Clean Code (2008), ch. 10 'Classes', filtered for Kotlin/Spring + house rules"
date_added: "2026-05-12"
---

# Clean Code: Classes

> "The first rule of classes is that they should be small. The second rule of classes is that they should be smaller than that." — R. Martin
>
> "We want our systems to be composed of many small classes, not a few large ones. Each small class encapsulates a single responsibility, has a single reason to change, and collaborates with a few others to achieve the desired system behaviours." — R. Martin

A class is a noun in the system's story. If a function is a paragraph, a class is a chapter — and a chapter with seventy headings, half-related, half-unrelated, is unreadable no matter how clean each paragraph is. Most of what makes long-lived codebases painful lives at the *class* level: god services that grew one method at a time, `*Manager` aggregations of unrelated responsibilities, anaemic data holders next to a separate-but-equal procedural service, and concrete cross-module dependencies that turn every test into a rebuild of the world.

This skill is the opinionated catalogue of class-level discipline: classical rules from Martin's Ch. 10 (organisation, SRP, cohesion, OCP, DIP), adapted for Kotlin's machinery (primary-constructor properties, `internal` visibility, `sealed` hierarchies, `object`, `companion object`, `data class`, `value class`, `by` delegation) and Spring's idioms (constructor injection, thin controllers, use-case-narrow services, Modulith modules, configuration-property classes, port/adapter for integrations).

## Use this skill when
- Designing a new class — before the first member is written. The first question is "what is this class's *one* responsibility?"
- Reviewing a class that grew past one screen — measure responsibilities, not lines.
- A class name ends in `Manager`, `Helper`, `Util`, `Processor`, `Super`, `Service` (with no domain qualifier), or you can't describe it in 25 words without `and` / `or` / `but`.
- Private methods of a class are only called by a subset of its public methods, and touch only a subset of its fields — there's another class trying to get out.
- A change to one feature forces you to also edit unrelated code in the same class (SRP violation by symptom).
- Adding a new variant (statement type, payment method, employee type) means editing an existing class instead of adding a new one (OCP violation).
- The class directly imports a concrete external API (`TokyoStockExchange`, `StripeClient`, `AwsS3Client`) and you can't unit-test the surrounding logic without a network (DIP violation).
- A Spring `@Service` handles five unrelated use cases (`OrderService` with `submit`, `cancel`, `refund`, `exportToCsv`, `recomputeStats`).
- A JPA `@Entity` has both `var` fields (for the ORM) *and* business methods that mutate them — the aggregate is hiding behind the persistence shape.
- Auditing a module before merging — does each class have one reason to change?

## Do not use this skill when
- The shape is enforced by a framework contract — Spring `@ConfigurationProperties`, JPA `@Entity`, Jackson DTO, gRPC stub, Servlet API. Apply where you can, accept the shape where you can't.
- The task is **inside** a single function — use `clean-code-functions` instead. This skill is class-shape; that one is function-shape.
- The task is **between** modules / bounded contexts — use `architecture-patterns`, `ddd-tactical-patterns`, or `architect-review`. This skill stops at the class boundary.
- The task is data-vs-behaviour ("should this class have methods or just hold fields?") — that's `clean-code-objects-and-data`, which is a strict prerequisite for some decisions here.
- The class is a one-line value wrapper (`@JvmInline value class OrderId(val value: UUID)`) — the rules don't fight there.
- The class is generated (MapStruct, KSP processor, JOOQ record) — the generator owns the shape.

## Core principles (the ten)

1. **Organise the class as a newspaper.** Public-static constants → private-static / instance state → constructors → public API → private utilities each placed **directly after their first public caller** (stepdown rule). The reader descends through the file as through a TO-paragraph narrative. In Kotlin, the primary constructor's `val`/`var` parameters *are* the field list — they go at the top, in the constructor itself; explicit `private val` properties for derived/internal state follow inside the body.
2. **Encapsulate by default; loosen only for tests, and only as a last resort.** Private is the starting point. If a test needs access, prefer **changing the test** (drive through the public API), then **`internal` visibility** (module-scoped — perfect for in-module tests with Kotlin), then `protected` / package-scope, never `public`. Encapsulation is not negotiable for invariants; it is negotiable for visibility seams.
3. **Classes should be small — measured by responsibilities, not lines.** Class size is "how many distinct reasons does this have to change?" — not "how many methods" and not "how many lines". A 5-method class with two unrelated responsibilities is bigger than a 30-method class with one.
4. **The 25-word, no-and/or/but description test.** You should be able to describe the class in **about 25 words, without using "if", "and", "or", "but"**. Every `and` is a hint that two responsibilities are pretending to be one. Run this test on the name first, then on a written sentence.
5. **Weasel suffixes are smells.** Names ending in `Manager`, `Processor`, `Helper`, `Util`, `Super`, or `Service` (with no domain qualifier — `OrderService` is fine, plain `Service` is not) almost always hide aggregated responsibilities. The vague name is a *consequence* of the vague responsibility — fix the responsibility, the name follows.
6. **Single Responsibility Principle — one reason to change.** A class should have exactly one *axis of change*. `SuperDashboard` that tracks both version info **and** Swing components has two: version updates and UI changes. Two axes = two classes. SRP is the *most abused* OO principle because "getting it to work" and "making it clean" are different concerns and most code only ships the first.
7. **High cohesion — every method touches most fields.** When most methods of a class touch most of its fields, the class hangs together as a logical whole. When you see fields used only by a subset of methods, that subset is a class trying to escape. Extracting big methods into small ones promotes locals to fields → cohesion drops → that's the **signal to split**, not the problem.
8. **Many small classes, not a few large ones.** A system with many small, well-named classes has the same total complexity as one with a few big ones, but you only have to understand *the part you're working on*. Small classes are toolboxes with labelled drawers; large classes are one drawer with everything in it.
9. **Open-Closed Principle — open for extension, closed for modification.** Adding a new variant (new SQL statement type, new payment method, new employee category) should mean **adding a new class**, not **editing an existing one**. In Kotlin: `sealed class` hierarchy + per-subtype behaviour replaces a `when (type)` ladder. In Spring: a new `Strategy` bean implementing a port interface, picked up automatically via DI, replaces editing a router.
10. **Dependency Inversion Principle — depend on abstractions, not concretions.** `Portfolio(exchange: StockExchange)` not `Portfolio()` with `TokyoStockExchange()` newed up inside. Concrete dependencies (live external APIs, framework clients, file systems, clocks) make code untestable, brittle to upstream changes, and impossible to swap. Wrap them behind a port interface you own. In Spring, **constructor injection is the practical form of DIP**; field/setter injection is not.

## Size & shape — quick targets

| Metric | Target | Action when exceeded |
|---|---|---|
| Reasons to change | exactly 1 | Split the class along the axis of change. |
| 25-word description | no `and`/`or`/`but` | Each `and` is a separate class. Pull it out. |
| Public methods | usually < 10 (heuristic, not a rule) | If far more, look for cohesion subsets — they're separate classes. |
| Instance variables | usually < 7 (heuristic, not a rule) | If far more, look for a value object trying to escape (`Address`, `MoneyRange`, `Period`). |
| Cohesion: methods using each field | ≥ ~50% | Falling cohesion ⇒ subset = a new class. |
| Lines of file (Kotlin) | ≤ ~500 (see `clean-code-formatting`) | Long files almost always contain multiple classes. |
| Direct concrete dependencies on external systems | 0 | Wrap behind a port interface; inject via constructor. |

## The 25-word test in practice

> *"The SuperDashboard provides access to the component that last held the focus, **and** it also allows us to track the version and build numbers."*

The first **and** is the verdict: two responsibilities. The fix is mechanical — extract a `Version` class with `getMajorVersionNumber()`, `getMinorVersionNumber()`, `getBuildNumber()`, leave the focus tracking on `SuperDashboard`. `Version` then becomes reusable across the system precisely because it has *one* job.

```kotlin
// ✗ Two responsibilities — focus tracking AND version info, in 5 methods that look "small enough"
class SuperDashboard : JFrame(), MetaDataUser {
    fun getLastFocusedComponent(): Component = ...
    fun setLastFocused(c: Component) { ... }
    fun getMajorVersionNumber(): Int = ...
    fun getMinorVersionNumber(): Int = ...
    fun getBuildNumber(): Int = ...
}

// ✓ Two single-responsibility classes — Version is now reusable, SuperDashboard has one axis of change
class Dashboard : JFrame(), MetaDataUser {
    fun lastFocusedComponent(): Component = ...
    fun lastFocused(c: Component) { ... }
}

data class Version(val major: Int, val minor: Int, val build: Int)
```

The number of methods didn't matter. The number of *reasons to change* did.

## Cohesion — the practical test

Cohesion measures how tightly a class's methods and fields belong together. The simplest probe: **for each instance field, count the methods that use it**. If most methods use most fields, the class is cohesive. If half the methods only use one or two fields and the other half only use the remaining ones, you have **two classes wearing one trench coat**.

```kotlin
// ✗ Low cohesion — `cache` and `mailer` form one cluster of methods; `auditLog` and `clock` form a different cluster
class CustomerService(
    private val cache: Cache,
    private val mailer: Mailer,
    private val auditLog: AuditLog,
    private val clock: Clock,
) {
    fun warmCache(id: CustomerId) { cache.put(id, load(id)) }
    fun sendWelcome(id: CustomerId) { mailer.send(load(id).email, "Welcome") }
    fun recordSignup(id: CustomerId) { auditLog.write(SignupEvent(id, clock.now())) }
    fun recordCancellation(id: CustomerId) { auditLog.write(CancelEvent(id, clock.now())) }
}

// ✓ Two cohesive classes
class CustomerNotifier(private val cache: Cache, private val mailer: Mailer) { ... }
class CustomerAuditor(private val auditLog: AuditLog, private val clock: Clock) { ... }
```

The signal in real code is usually subtler: a class accumulates a sixth field used by exactly one method. That field, that method, and the bits of related state are usually a new class.

## Class organisation — Kotlin variant of the stepdown rule

```kotlin
class OrderProjectionUpdater(
    // 1. Primary-constructor properties — top of the class, replacing the Java "private fields at top" rule
    private val projections: OrderProjections,
    private val clock: Clock,
) {

    // 2. Companion constants — when needed
    companion object {
        private const val MAX_BATCH = 500
    }

    // 3. Public API — in narrative order, what readers want to find first
    fun apply(event: OrderEvent) {
        val current = loadProjection(event.orderId)
        val next = current.apply(event, clock.now())
        save(next)
    }

    // 4. Private helpers — each placed RIGHT AFTER its first caller (stepdown)
    private fun loadProjection(id: OrderId): OrderProjection =
        projections.findById(id) ?: OrderProjection.empty(id)

    private fun save(projection: OrderProjection) {
        projections.save(projection)
    }
}
```

**Rules:**
- Primary-constructor properties at the top — they *are* the field list in Kotlin. No separate "fields" section underneath.
- `companion object` after the constructor — class-level constants go here, not as Java-style `public static final`.
- Public methods next, in **narrative** order — the most important entry point first, then its collaborators.
- Each private helper immediately after the public method that first calls it. The reader can stop reading when they've understood the public API.

This is the same stepdown rule as `clean-code-functions`, applied at class scope.

## Encapsulation — the visibility decision tree

When a test needs access:

1. **Can the test drive through the public API?** If yes — stop. This is the right answer in 80% of cases.
2. **If not, is it a Kotlin codebase where the test lives in the same module?** Use **`internal`** (module-scoped). This is the strongest seam available short of public and is invisible to other modules.
3. **Only if (2) doesn't apply** (cross-module tests, Java-Kotlin mix where `internal` doesn't help): `protected` or package-private. Document why.
4. **Never make a field `public` for testing.** That's not loosening — that's discarding the invariant.

```kotlin
// ✓ Public API hides invariants; `internal` factory lets the test build instances directly
class Order private constructor(
    val id: OrderId,
    private val lines: MutableList<OrderLine>,
    private var status: OrderStatus,
) {
    fun submit() { require(status == DRAFT); status = SUBMITTED }
    fun cancel(reason: CancelReason) { ... }

    companion object {
        fun draft(id: OrderId, lines: List<OrderLine>): Order =
            Order(id, lines.toMutableList(), OrderStatus.DRAFT)

        // for tests in this module only — builds an Order in any state without going through the public lifecycle
        internal fun rehydrate(id: OrderId, lines: List<OrderLine>, status: OrderStatus): Order =
            Order(id, lines.toMutableList(), status)
    }
}
```

## OCP — closed by sealing, open by adding

A `when (type)` ladder that returns behaviour by type is a god-class in slow motion: every new variant edits the same class, every new operation re-edits it.

```kotlin
// ✗ Editing the class every time SQL grows a new statement type
class Sql(...) {
    fun create(): String = ...
    fun insert(fields: Array<Any>): String = ...
    fun selectAll(): String = ...
    fun findByKey(...): String = ...
    fun select(criteria: Criteria): String = ...
    fun preparedInsert(): String = ...
    private fun selectWithCriteria(...) = ...
    private fun valuesList(...) = ...
}

// ✓ Sealed root; each statement type its own closed class; UpdateSql added without touching the others
sealed class Sql(protected val table: String, protected val columns: Array<Column>) {
    abstract fun generate(): String
}
class CreateSql(table: String, columns: Array<Column>) : Sql(table, columns) {
    override fun generate(): String = ...
}
class InsertSql(table: String, columns: Array<Column>, private val fields: Array<Any>) : Sql(table, columns) {
    override fun generate(): String = ...
}
class SelectWithCriteriaSql(...) : Sql(...) { ... }
// later: class UpdateSql(...) : Sql(...) — no existing class changes
```

In Spring, the same pattern with beans:

```kotlin
interface PaymentMethod {
    fun supports(request: PaymentRequest): Boolean
    fun charge(request: PaymentRequest): PaymentResult
}

@Component class CardPayment : PaymentMethod { ... }
@Component class SepaPayment : PaymentMethod { ... }
// later: @Component class CryptoPayment : PaymentMethod — picked up by DI without touching the dispatcher

@Service
class PaymentDispatcher(private val methods: List<PaymentMethod>) {
    fun charge(request: PaymentRequest): PaymentResult =
        methods.first { it.supports(request) }.charge(request)
}
```

**OCP is not a license to wrap everything in an interface up front.** Apply it where the axis of change is real and recurring (statement types, payment methods, employee types). Inside a class that hasn't changed in a year, OCP machinery is dead weight — see `karpathy-guidelines` on premature abstraction.

## DIP — invert the integration

Concrete dependencies are the most common testability failure in Spring codebases. The fix is identical to Martin's example: introduce a port interface you own; the concrete adapter implements it.

```kotlin
// ✗ Concrete dependency on Tokyo exchange — every test needs network or extensive mocking of internals
class Portfolio {
    private val exchange = TokyoStockExchange()  // newed up, untestable
    fun value(): Money = positions.sumOf { exchange.currentPrice(it.symbol) * it.shares }
}

// ✓ Depend on an abstraction the domain owns; the concrete adapter is just one implementation
interface StockExchange {
    fun currentPrice(symbol: String): Money
}

class Portfolio(private val exchange: StockExchange) {
    fun value(): Money = positions.sumOf { exchange.currentPrice(it.symbol) * it.shares }
}

// production adapter
@Component
class TokyoStockExchangeAdapter(private val client: TokyoApiClient) : StockExchange {
    override fun currentPrice(symbol: String): Money = client.price(symbol).toMoney()
}

// test fake — trivially constructed, deterministic
class FixedStockExchange(private val prices: Map<String, Money>) : StockExchange {
    override fun currentPrice(symbol: String): Money = prices.getValue(symbol)
}
```

In Spring, this is the everyday shape: **the port interface lives in the domain layer, the adapter lives in the infrastructure layer, the constructor of every domain/service class takes the port, not the adapter.** Constructor injection makes DIP automatic; field/setter injection breaks it.

## SuperDashboard / FooManager / EverythingService — splitting a god class

The recipe is mechanical:

1. **List every public method.**
2. **Cluster them by which fields they touch.** Each cluster is a candidate class.
3. **Re-read each cluster with the 25-word test** — is the clustered name actually a single responsibility?
4. **Extract** — move the cluster's methods and the fields they touch into a new class.
5. **Re-name** — when the extracted class has a focused responsibility, its name shouldn't end in `Manager` / `Helper`.
6. **Re-test** — characterisation tests around the original class first (see `clean-code-unit-tests`), then each tiny extraction is verified.

Repeat until each class passes the 25-word test.

## Smell → fix quick reference

| Smell | Fix |
|---|---|
| Class with 70 public methods (`SuperDashboard`) | Cluster methods by field usage; extract each cluster. |
| Name ends in `Manager` / `Helper` / `Util` / `Processor` / `Super` | Find the real responsibility; rename to that domain noun. If no single one, split. |
| 25-word description needs `and` / `or` | One class per `and`. |
| 5 methods, 2 unrelated responsibilities | Still too big. Split. |
| Field used by only one method | Either the field belongs in a value object, or the method belongs on another class. Investigate. |
| Private helper used only by 2 of 7 public methods, touching its own subset of fields | Those 2 methods + their fields are a separate class. |
| `when (type)` ladder repeated across multiple methods | Sealed hierarchy with behaviour on each subtype; one tolerated `when` in a factory. |
| `class Foo { val client = SomeConcreteApi() }` | Inject `SomeApiPort` via primary constructor; concrete adapter implements the port. |
| Test needs a `@VisibleForTesting public` field | Either change the test (use public API), or use `internal` visibility, or extract a class that exposes what's needed legitimately. |
| `@Service class FooService` with `submit`, `cancel`, `refund`, `exportToCsv` | Split by use case: `SubmitFoo`, `CancelFoo`, `RefundFoo`, `FooReporter`. Or move to CQRS handlers — see `cqrs-implementation`. |
| `@Entity` with `var` fields **and** business methods that mutate them | Entity is the persistence shape; the domain aggregate is a separate class — see `clean-code-objects-and-data` and `ddd-tactical-patterns`. |
| New variant means editing existing class | Refactor to sealed hierarchy / Strategy bean — open for extension via subclass, closed for modification. |
| 30 instance variables | Group related ones into a value object (`Address`, `Period`, `MoneyRange`). |
| Subclass overrides 6 of 8 parent methods | Inheritance is the wrong tool. Use composition via Kotlin `by` delegation, or just plain field + forwarding. |

## Selective Reading Rule

| File | When to read |
|---|---|
| `resources/general-classes-rules.md` | Martin Ch. 10 as a foundation — class organisation, encapsulation, smallness measured by responsibility, the 25-word test, SRP, cohesion, the many-small-classes consequence, OCP, DIP, and the *Sql* + *Portfolio* worked examples in language-agnostic form. Read first if you want the canon. |
| `resources/kotlin-specific-classes.md` | What Kotlin solves out of the box: primary-constructor properties replacing field-at-top, `internal` visibility for module-scoped test seams, `sealed class` / `sealed interface` for built-in OCP closure, `object` & `companion object` over static-utility classes, `data class` for the value-shaped end of the spectrum, `@JvmInline value class` against primitive obsession, extension functions instead of growing classes with helpers, `by` delegation as practical composition-over-inheritance, the `lateinit var` and `init` block traps for class size. |
| `resources/spring-boot-classes.md` | Spring/Spring Boot applications: constructor injection as the practical DIP, thin `@RestController` delegating to use-case-narrow services, `FooService` god-class split (by use case, or via CQRS command handlers), `@ConfigurationProperties` data class as a tiny cohesive class, Spring Modulith application modules enforcing SRP at module scope, JPA `@Entity` as persistence shape vs. domain aggregate, `@ConditionalOnProperty` / `@Profile` / `@Primary` for OCP-style bean variants, wrapping external integrations behind a port interface, ArchUnit / Modulith fitness tests guarding the design. |
| `resources/ddd-classes.md` | Domain-Driven Design applications of these rules: aggregate roots as cohesive small classes (one transaction, one invariant boundary, one reason to change), value objects against primitive obsession, repositories as DIP ports at the aggregate boundary (one per root, not per entity), domain services for behaviour that doesn't belong on a single aggregate, ACL translator classes as OCP-friendly seams to external contexts, factory methods replacing constructor-overload explosions. |

## Anti-patterns in class-refactoring work itself

- **Refactoring without tests.** Splitting a god class is a multi-step transformation; every step needs a green test run. **Add the characterisation test first; refactor second.** (See `methodology-verification`.)
- **Splitting by file, not by responsibility.** Moving 30 methods into 6 files of 5 methods each, with all fields still shared via `internal`, achieves nothing. Split by *cohesion cluster*, not by line count.
- **OCP machinery for a `when` with two cases.** Two variants is fine as a `when`. Sealed-hierarchy-plus-Strategy-bean is overkill until you have three variants and a real axis of change.
- **DIP-ing every dependency.** A pure utility (`UUID.randomUUID()`, `Math.floor(x)`, `String::trim`) doesn't need an injected port. Apply DIP at the **trust / change boundary** — external systems, time, randomness, IO — not at every method call.
- **Renaming `FooManager` to `FooService` and declaring victory.** The name was a symptom; the responsibility hadn't moved. Renaming without splitting is theatre.
- **Extracting a class with no behaviour, just to "make it small".** `OrderIdHolder` wrapping a single `UUID` field is not a class — it's a value object (`@JvmInline value class`) or it doesn't exist. Don't extract for the sake of extraction.
- **`@VisibleForTesting public` everywhere.** Loose visibility is the *last* resort, not the *first* (see Encapsulation tree above). Prefer rewriting the test to drive through the public API, or using `internal`.
- **God interfaces.** A `class XService` split into `interface IXService` + `class XServiceImpl` with the exact same 70 methods is still a god — the interface inherits the SRP violation. Split first, then introduce ports where DIP is actually required.
- **Inheritance to share state.** A parent `AbstractFooService` with shared fields and template methods is usually 1990s OO. Kotlin: prefer composition via `by` delegation or plain constructor injection.
- **One class per file dogma applied without judgement.** Two tightly-coupled small classes that always change together (a sealed root and its 3 subclasses) belong in one Kotlin file. The rule is *separate axes of change*, not *separate files*.

## Related skills

| Skill | This not that |
|---|---|
| `clean-code-functions` | Function-level shape and responsibility — `do one thing` for a verb. This skill is the same idea for a noun: `be one thing`. The two are paired — apply both. |
| `clean-code-naming` | Names of classes, methods, fields. This skill is class shape & responsibility; name follows from responsibility. |
| `clean-code-objects-and-data` | "Should this class hold data or expose behaviour?" — that's a prerequisite *decision*. Then this skill answers "how big should it be, what does it depend on, how does it change?" |
| `clean-code-formatting` | Vertical/horizontal layout, file size. This skill is responsibility, not aesthetics. |
| `clean-code-boundaries` | Wrap third-party libraries behind a port. This skill applies DIP; that skill teaches the port-wrapping idioms. |
| `solid-principles` | SOLID at the level of principles. This skill is the Kotlin/Spring-flavoured how-to for SRP/OCP/DIP at the class scope. |
| `gof-patterns` | GoF patterns as concrete realisations of SOLID-driven refactors (Strategy, Decorator, Adapter). |
| `ddd-tactical-patterns` | Aggregates, value objects, repositories — the *domain shapes* this skill's rules apply to. |
| `architecture-patterns` | Layout pattern of a whole module (Layered / Onion / Clean). This skill applies *inside* whatever layout is chosen. |
| `architect-review` | God-class smells during a structural audit. This skill is the criteria the review applies. |
| `cqrs-implementation` | One pattern for splitting an oversized service: a handler-per-command instead of methods-per-use-case. |
| `spring-boot-mastery` | Modulith, configuration, bean lifecycle. This skill cross-refs that one when a Spring mechanism is the lever for SRP/OCP. |
| `karpathy-guidelines` | §1 surgical changes — don't refactor classes you weren't asked to. §3 avoid speculative abstractions — don't OCP-ify until the axis of change is real. |
| `methodology-verification` | After splitting a class: re-run the proving command before claiming it's done. |

## Limitations

- **Numbers are heuristics, not laws.** "< 7 fields" and "< 10 public methods" are starting points; a well-cohesive `Order` aggregate may legitimately have 15 fields and 20 methods that all touch a clear invariant. Apply judgement against the *real* tests: SRP and cohesion.
- **Framework shape can override.** Spring `@ConfigurationProperties`, JPA `@Entity`, gRPC service stubs, JMS listener beans are shape-constrained by the framework. Apply the rules where you can; accept the shape where you can't, and isolate the framework-shaped class behind something cleaner.
- **DIP is a trust-boundary tool, not a universal pattern.** Wrapping `kotlin.math.PI` behind an interface is silly. Apply DIP at boundaries that *can change independently* — external APIs, time, randomness, IO, vendor SDKs.
- **OCP requires a real axis of change.** Without one, sealed hierarchies and Strategy beans are speculative complexity. Prefer the simple class today; refactor to OCP when the second or third variant lands.
- **Team consistency wins over the rules.** If the codebase uses anaemic services + transaction scripts everywhere, a single Onion-shaped service swimming against the tide is worse than a consistent style. Change the convention deliberately, not file-by-file.
- **Class shape isn't fixed forever.** Responsibilities migrate. A class that was SRP-clean a year ago may have grown an `and` since — periodic re-audits are the only defence.
