# Smells Catalog — Symptom → Diagnosis → Fix → Owner

Use this when you've identified that something is wrong with messy code and want to name the smell precisely and know which resource owns the deep dive.

For each smell: **Symptom** (what you see) → **Diagnosis** (the underlying problem) → **Fix sketch** (one paragraph) → **Owner** (resource for the deep dive).

---

### Primitive obsession

- **Symptom:** `String` for `Email`, `Long` for both cents and milliseconds. Compiler can't distinguish `userId` from `orderId` when both are `UUID`.
- **Diagnosis:** The domain has named concepts; code carries them as raw primitives, so the type system can't help.
- **Fix:** `@JvmInline value class` per concept. Validation in `init`.
- **Not a fix when:** one-off scripts, single-use parameters.
- **Owner:** `objects-and-data.md` (5-form table).

### Train wreck / Demeter violation

- **Symptom:** `a.b().c().d().e()` — the caller drills through three classes' internals.
- **Diagnosis:** Caller knows too much about `a`'s internal structure.
- **Fix:** Tell, don't ask — put the operation on `a`. If `a` isn't yours, an extension function. Splitting into temporaries is the same violation spelled out longer.
- **Not a fix when:** plain data structures (DTOs), fluent builders, stdlib collection pipelines.
- **Owner:** `objects-and-data.md`.

### Feature envy

- **Symptom:** A method in class `A` reads/uses fields and methods of class `B` far more than its own.
- **Diagnosis:** Method is in the wrong class.
- **Fix:** Move it to `B`. If `B` is a `data class` or vendor type you don't own, an extension function on `B`.
- **Owner:** `objects-and-data.md`.

### Anemic domain / hybrid class

- **Symptom:** A JPA `@Entity` with only `var` fields and bean accessors, all logic living in a service. Or a class with both public mutable fields *and* business methods.
- **Diagnosis:** Anemic = data without behaviour. Hybrid = behaviour without encapsulation. Either way, invariants live elsewhere and aren't really enforced.
- **Fix:** Pick one shape — pure data (read-only `data class`, no methods beyond mappers) or behaviour-rich aggregate (private mutable state, public methods enforcing invariants). Never both.
- **Owner:** `objects-and-data.md`.

### `data class` for a JPA `@Entity`

- **Symptom:** `@Entity data class User(...)`.
- **Diagnosis:** Hibernate proxies break field-based `equals`/`hashCode` (lazy loading triggers at the wrong moment). State-based equality is wrong for entities — identity is the `id`, not the state. `hashCode` over fields changes when state changes → breaks `HashSet` / `HashMap` membership.
- **Fix:** Regular `class` with `id`-based equality for JPA entities. `data class` stays for VOs, DTOs, domain events.
- **Owner:** `objects-and-data.md`.

### `!!` everywhere

- **Symptom:** Code peppered with `!!` non-null assertions.
- **Diagnosis:** The type system was right (`T?`); the author overrode it. Every `!!` is a potential NPE in production with an unhelpful stack trace.
- **Fix:** `?:` with a meaningful default, or `requireNotNull(x) { "..." }` with a real error message, or restructure so the value is non-null by construction.
- **Owner:** `error-handling.md`.

### Mutable state where immutable would do

- **Symptom:** `var` everywhere; `MutableList` exposed publicly from a class.
- **Diagnosis:** Mutation is an escape route around the aggregate's invariants — anyone holding the list can corrupt state.
- **Fix:** Prefer `val` and read-only collection types (`List<T>`, not `MutableList<T>`) on public APIs. Aggregate keeps mutable state private; mutation through methods that enforce invariants.
- **Owner:** `objects-and-data.md` + `classes.md` (encapsulation).

### Switch on type / `when` chains repeated

- **Symptom:** `when (event) { is OrderCreated -> ...; is OrderPaid -> ...; else -> error("unknown") }` repeated in three different places.
- **Diagnosis:** Open hierarchy where it should be closed. New variant means hunting every `when`; `else` branch hides the bugs you missed.
- **Fix:** `sealed interface` / `sealed class`. The `when` becomes exhaustive — no `else` needed; compiler errors when a new variant isn't handled.
- **Not a fix when:** truly open extension points (plugin systems, third-party variants).
- **Owner:** `functions.md`.

### Comment-as-failed-name

- **Symptom:** A comment explaining *what* non-obvious code does, immediately above it.
- **Diagnosis:** The names failed; the code can't speak for itself.
- **Fix:** Rename or extract a helper so the comment becomes redundant; delete the comment. Comments documenting *why* (non-obvious business rule, legal note, performance trick) stay.
- **Owner:** `comments.md`.

### Premature abstraction

- **Symptom:** Strategy pattern with one implementation. Factory wrapping a single constructor. Interface with one implementer. Generic type parameter only ever substituted with `Any`.
- **Diagnosis:** Abstraction built for a future that never came. Cost paid every day; benefit never used.
- **Fix:** Inline. Make it concrete. Extract the abstraction *when* the second case shows up — you'll know what its real shape should be at that point.
- **Owner:** `classes.md` (OCP misuse); `systems.md` (DI overuse).

### God class / fat service

- **Symptom:** `UserService` with 30 methods doing CRUD + auth + profile + notifications + audit + billing.
- **Diagnosis:** Multiple responsibilities — multiple reasons to change.
- **Fix:** Split by responsibility. In Spring, multiple small `@Service` classes is fine — DI keeps wiring cheap.
- **Owner:** `classes.md` (+ `classes-practices.md` for worked OrderService split).

### Vendor types leaking into domain

- **Symptom:** Domain service method signature includes `JsonNode`, `Stripe.Charge`, `ResponseEntity<T>`, `Page<UserEntity>`.
- **Diagnosis:** No boundary between your code and the vendor; every file is coupled to the SDK shape.
- **Fix:** Port interface + adapter. Vendor types stop at the adapter; domain speaks its own vocabulary.
- **Owner:** `boundaries.md`.

### Service-locator usage

- **Symptom:** `ApplicationContext.getBean(...)` inside business code; or class injecting `ApplicationContext` instead of specific collaborators.
- **Diagnosis:** Class actively resolving its own dependencies — anti-DI.
- **Fix:** Constructor injection of the specific bean.
- **Owner:** `systems.md`.

### Field injection (`@Autowired var`)

- **Symptom:** `@Autowired lateinit var foo: FooClient` in Kotlin.
- **Diagnosis:** Defeats `val` immutability, hides cycles, requires Spring to test.
- **Fix:** Move to constructor injection (`class X(private val foo: FooClient)`).
- **Owner:** `systems.md`.

### Inline cross-cutting

- **Symptom:** `try { auditLog.write(...); metric.start() } catch { ... }` at the top of every business method.
- **Diagnosis:** Cross-cutting policy duplicated across N call sites; one rule change = N edits.
- **Fix:** Annotation or aspect (`@Transactional`, `@Cacheable`, `@PreAuthorize`, `@Timed`, `@Aspect @Around`).
- **Owner:** `systems.md` (cross-cutting table).

## How to use this catalog

1. Match the **Symptom** to what you see in messy code.
2. Confirm with the **Diagnosis** — does the code have the underlying problem, or just look superficially similar?
3. Follow **Owner** for the deep dive with thresholds and lookup tables.
4. Apply **one smell, one fix, one commit** (cadence rules in `../SKILL.md`).
5. Re-read the diff before merge: is the change *only* about this smell?
