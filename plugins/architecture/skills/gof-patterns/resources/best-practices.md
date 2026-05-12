# GoF — Best Practices

How to use the GoF vocabulary well in Kotlin/Spring. The patterns are valuable as *names*; they're a vocabulary for design conversations and a mental library of recurring shapes. They're dangerous when applied mechanically. This file: heuristics for picking, applying, and naming patterns.

For pattern definitions, see `theory.md`. For Kotlin idioms, see `kotlin.md`. For Spring usage, see `spring-boot.md`. For specific anti-patterns, see `bad-practices.md`.

---

## The 70/30 rule

Roughly 70% of GoF patterns are subsumed by Kotlin language features:

| Pattern | Kotlin feature |
|---|---|
| Singleton | `object` |
| Strategy | function type / lambda |
| Observer | `Flow` / `ApplicationEventPublisher` |
| Composite | sealed hierarchy |
| Visitor | sealed + exhaustive `when` (replaces it) |
| Prototype | `data class.copy()` |
| Decorator | `by` delegation |
| Iterator | `Iterable<T>` / `Sequence<T>` |
| State | sealed + `when` |
| Memento | `data class` snapshot |
| Command | sealed interface |

The remaining ~30% (Adapter, Bridge, Facade, Abstract Factory, Mediator, Template Method, Interpreter, plus Proxy via Spring AOP) still apply but with leaner forms than Java versions.

**Implication:** if you're writing more than a few lines of code to implement a 70%-subsumed pattern, you're probably reaching for ceremony Kotlin already provides. (See `bad-practices.md`.)

---

## Patterns are diagnostic, not prescriptive

The wrong question: *"where can I add a Strategy pattern?"*

The right question: *"this code has a recurring shape — what's it called?"*

Pattern application starts from a concrete problem (variation by type, scattered `new`, fat coupling, a hierarchy that needs new operations) and reaches for the pattern that fits. Reversing the direction — scanning code for "where can I apply X?" — is the source of the over-engineered Java enterprise code from the 2000s.

In code review: name the problem, not the pattern. "I'm worried about coupling between A and B — let's discuss" beats "use Mediator".

---

## Names matter for communication

Even when the implementation is one line of Kotlin (`Singleton = object`, `Strategy = (Money) -> Money`), the *name* of the pattern accelerates conversation:

- "This is a Facade" — the reviewer knows you're hiding subsystem complexity.
- "This is Decorator via `by` delegation" — the reviewer knows you're wrapping behaviour without modifying the interface.
- "This is Observer via Spring events" — the reviewer knows the publisher doesn't know its consumers.

Use the names in design discussions, code comments (sparingly), commit messages, ADRs. They're shorthand.

What you should *not* do: use pattern names as part of class names. `OrderFacade`, `OrderMediator`, `OrderVisitor` — these violate the weasel-suffix rule (`clean-code-naming`). Use domain names: `OrderCheckout`, `CheckoutOrchestrator`, `OrderRenderer`.

---

## When each pattern still earns its keep in Kotlin

Patterns where the mechanism (not the name) is genuinely useful:

| Pattern | Earns its keep when |
|---|---|
| Singleton | Always — `object` is the mechanism |
| Builder | Wrapping a fluent Java API (use `apply`); building an HTML/Gradle/Ktor DSL |
| Factory Method | Aggregate creation with invariant enforcement (`Order.create(...)`) |
| Abstract Factory | Multiple consistent product families (e.g., per-tenant theming); use `@Profile` in Spring |
| Prototype | Always — `data class.copy()` is the mechanism |
| Adapter | Wrapping a vendor SDK (ACL); converting between layer types (entity ↔ DTO) |
| Decorator | Adding cross-cutting behaviour (caching, logging, retry) to one method without touching the inner; use `by` delegation |
| Facade | Hiding a complex subsystem behind a simple operation (most `@Service` beans) |
| Composite | Recursive structures (file trees, ASTs, organisational charts) — use sealed hierarchy |
| Bridge | Two genuinely independent variation axes (rare; often misapplied) |
| Proxy | Cross-cutting concerns via Spring AOP (`@Transactional`, `@Cacheable`, `@Async`) |
| Flyweight | Massive number of fine-grained objects sharing intrinsic state (rare in business code; use `value class`) |
| Strategy | Multiple algorithms selectable per call — function type for stateless, sealed type for named/DI'd |
| Observer | Cross-cutting reactions to state changes — use `Flow` / Spring events |
| Command | Capturing requests as data (CQRS write side) — use sealed interface |
| Iterator | Custom iteration over your own structure (rare — `Iterable` and `Sequence` cover most cases) |
| Template Method | Algorithm with fixed protocol and overridable steps; usually composition + Strategy is better |
| Chain of Responsibility | Pipeline of handlers, first-match dispatch — use `List<Handler>` + first-not-null |
| State | Behaviour varies by state, with explicit transitions — use sealed + `when` |
| Mediator | Several collaborators that would otherwise know each other — orchestrator service |
| Memento | Snapshot for undo — use `data class` |
| Visitor | Almost never — replaced by sealed + `when` in Kotlin |
| Interpreter | A small DSL with grammar and evaluation — heavy machinery, build only when DSL is the deliverable |

---

## Picking between similar patterns

### Strategy vs Template Method

- **Strategy** — algorithm varies; use composition (function type or interface).
- **Template Method** — algorithm protocol is fixed; specific steps vary; use abstract class with `final` skeleton + `open` hooks.

Default to Strategy. Use Template Method when the steps share state through `protected` fields (rare).

### Decorator vs Proxy

- **Decorator** — adds behaviour visible to the client.
- **Proxy** — controls access transparently (the client doesn't know it's not the real object).

In Spring, AOP-driven `@Transactional` / `@Cacheable` are Proxies (transparent). A `LoggingRepository` wrapper that explicitly logs is Decorator (visible).

### Strategy vs State

- **Strategy** — algorithm varies based on caller's choice; the strategy doesn't change between calls.
- **State** — behaviour varies based on the object's *internal* state; transitions are explicit.

`PaymentMethod` is Strategy (caller picks). `OrderStatus.cancel()` is State (the order knows its own state).

### Facade vs Mediator

- **Facade** — simplifies *client access* to a subsystem (one operation hides several).
- **Mediator** — encapsulates *interaction between collaborators* (they don't know each other directly).

Most `@Service` classes are both. Don't sweat the distinction in conversation; use whichever names the intent clearer.

### Adapter vs Bridge vs Decorator

- **Adapter** — converts an interface to one a client expects (the adaptee already exists).
- **Bridge** — decouples abstraction from implementation up front (both vary independently).
- **Decorator** — adds behaviour transparently around an object that implements the same interface.

Adapter is "I don't control this thing, wrap it"; Bridge is "I'm designing two axes of variation"; Decorator is "I want to add behaviour around method calls".

### Observer vs Mediator

- **Observer** — many subscribers react to a subject's events; subject doesn't know subscribers.
- **Mediator** — collaborators interact through a central coordinator.

Spring events ARE Observer (subscribers register via `@EventListener`); a `CheckoutOrchestrator` is Mediator (collaborators are injected, the orchestrator drives them).

---

## Decision rules: write the pattern, or use the framework?

In a Spring project:

- **Singleton** → use Spring beans (default scope).
- **Proxy** → use `@Transactional`, `@Cacheable`, `@Async`, `@Retryable`, `@Validated`, `@PreAuthorize`. Don't hand-roll.
- **Observer** → use `ApplicationEventPublisher` + `@ApplicationModuleListener`. Don't hand-roll.
- **Abstract Factory** → use `@Profile` / `@ConditionalOnProperty` for environment switching.
- **Strategy with named DI'd impls** → use `Map<String, T>` / `List<T>` injection.
- **Mediator / Facade** → just write a `@Service`.
- **Chain of Responsibility** → use `OncePerRequestFilter` for HTTP; for in-process, a `List<Handler>` + first-not-null is fine.

If Spring provides the pattern, use it. Hand-rolled equivalents are smell.

---

## Heuristic: "is this pattern worth the abstraction?"

Pattern application has cost:

- A new class per pattern variant (Strategy interface, Decorator wrapper, Adapter, Bridge `Implementor`).
- An extra indirection in stack traces.
- Mental overhead for readers who have to follow the indirection.
- DI complexity if the pattern uses Spring beans.

Apply when the cost clears the benefit:

- **Genuine variation** (≥ 2 concrete cases or one with strong reason for the second).
- **Substitutability** (tests substitute, environment swaps, future migration likely).
- **Decoupling** (current direct dependency causes real coupling pain).
- **Communication** (the pattern name will help your team understand the design).

Don't apply when:

- One variant exists with no plan for the second.
- "In case we need it" is the justification.
- The mechanism is one line of Kotlin and the name doesn't help the conversation.

---

## Refactor recipes

### Recipe: Java-style fluent Builder → named arguments

1. List the Builder's setter methods.
2. Convert each to a constructor parameter with a sensible default.
3. Remove the Builder class.
4. Update call sites: `MyType.Builder().setX(...).setY(...).build()` becomes `MyType(x = ..., y = ...)`.
5. Verify: the Kotlin form is shorter; default values express what the Builder previously hid; immutability is preserved.

### Recipe: classical Visitor → sealed + exhaustive `when`

1. Convert the base `Element` to a `sealed class` / `sealed interface`.
2. Convert each subtype to a regular subclass / `data class` / `data object`.
3. Remove the `accept(visitor)` machinery from each subtype.
4. Replace each Visitor implementation with a top-level function over the sealed type using `when`.
5. Verify: the compiler enforces exhaustiveness; adding a new subtype causes compile errors in every relevant `when`.

### Recipe: hand-rolled Singleton → `object`

1. Identify the `private constructor() + companion val INSTANCE` Singleton.
2. Replace with `object Singleton { ... }`.
3. Update call sites: `Singleton.INSTANCE.method()` becomes `Singleton.method()`.
4. If the singleton has dependencies, promote to a Spring `@Component` and inject — don't keep the manual singleton.

### Recipe: hand-rolled Observer → Spring events

1. Identify the `Observable` / list-of-observers class.
2. Define a domain event (`OrderPlaced` data class).
3. Inject `ApplicationEventPublisher` into the publisher; replace `observers.forEach { it.onX(...) }` with `events.publishEvent(OrderPlaced(...))`.
4. Convert each observer into a `@Component` with `@ApplicationModuleListener fun on(event: OrderPlaced)`.
5. Remove the observer-registration ceremony.

### Recipe: hand-rolled Proxy → Spring AOP

1. Identify the manual proxy (transactional wrapper, cache wrapper, retry wrapper).
2. Add the corresponding annotation (`@Transactional`, `@Cacheable`, `@Retryable`) to the inner method.
3. Verify the `kotlin-spring` Gradle plugin is enabled (so Spring stereotypes are auto-`open`).
4. Verify with an integration test that the AOP behaviour applies (e.g., transactional rollback on exception).
5. Delete the manual proxy class.

### Recipe: scattered `if/when (type)` → sealed dispatch

1. Identify all `when (x.type)` chains on the same enum / type discriminator.
2. Convert the type to a `sealed interface` or `sealed class`.
3. For each method that varied by type, push the variant body into the corresponding `data object` / `class` as an override.
4. Replace each `when` chain at call sites with `x.method(...)`.
5. Verify: adding a new variant requires only a new `data object`; all callers pick up the new variant via the sealed type.

---

## When the pattern name itself is the value

Many "patterns" in Kotlin/Spring are one-liners or framework features. The implementation costs nothing; the *name* is the only deliverable. Use the name when:

- Onboarding teammates: "the `OrderProcessor` is a Mediator over the checkout subsystem" frames the design instantly.
- Code review: "this is becoming a Decorator chain" warns the reviewer to think about the chain order, the wrapper count, the ceremony.
- ADR / RFC: "we're applying Abstract Factory via `@Profile` to support multi-tenant theming" is precise documentation.
- Refactoring discussion: "let's pull this into a Strategy injected as a function type" is concrete and actionable.

Skip the name when:

- The implementation is so minimal that naming it adds nothing (a one-line `object`, a lambda parameter).
- The pattern doesn't quite fit and you're stretching to make it apply (call it what it is, not what it almost is).

---

## Team conventions worth standardising

- **Banned: Java-flavoured ceremony.** No `private constructor() + companion val INSTANCE`; no fluent Builder for what named arguments cover; no classical Visitor; no hand-rolled Observable.
- **Spring's pattern features mandatory.** No hand-rolled transaction wrapper; no manual event-listener registration; no service-locator pulls.
- **`kotlin-spring` plugin enabled** so AOP works on Kotlin classes.
- **Pattern names in class names banned.** `*Util`, `*Manager`, `*Helper`, `*Pattern`, `*Visitor` (when not Visitor), `*Factory` (when just a constructor wrapper).
- **PR template prompts** for "is this pattern necessary?" on any new abstraction layer.

---

## When GoF actively misleads

Three places where mechanical pattern application is the wrong call:

- **Performance-critical hot paths.** Polymorphic dispatch, indirection layers, AOP proxies all cost cycles. For hot paths, prefer concrete types and inlined logic — and document why.
- **One-off scripts and migrations.** A 200-line script that runs once doesn't need a Strategy interface or a Factory. Inline.
- **Genuinely simple CRUD.** A controller that delegates to a single repository for one endpoint doesn't need a Mediator, doesn't need a Facade, doesn't need a Strategy.

The bias is toward *recognising* GoF shapes in the wild. The discipline is in *not adding* them when the problem doesn't call for them.
