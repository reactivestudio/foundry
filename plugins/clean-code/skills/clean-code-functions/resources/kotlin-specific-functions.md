# Kotlin-Specific Function Patterns

Kotlin features that change which Clean Code Ch. 3 rules still bite, which become trivial, and which need a new idiom. Each section identifies a Martin rule, explains what Kotlin does about it, and shows the resulting style.

> "Half the battle is choosing a name. The other half is letting the language help." — paraphrase of the Kotlin design ethos.

## Quick map — which Kotlin feature attacks which rule

| Martin rule (Ch. 3) | Kotlin feature | Effect |
|---|---|---|
| §"Few arguments" | Named & default arguments | Most triads become monads at the call site; no argument-object cheat needed for optional params. |
| §"Few arguments" | Data classes / `@JvmInline value class` | Trivial argument objects; one-field value classes carry domain meaning at zero cost. |
| §"Few arguments" / "Dyads" | Extension functions | The "receiver-or-method" advice happens by default — write `buf.appendFooter()` from anywhere. |
| §"Switch Statements" | `sealed class` + exhaustive `when` | Polymorphism with compile-time exhaustiveness; the factory pattern shrinks to one `when`. |
| §"Have No Side Effects" | `val` everywhere, immutable defaults | Default to no mutation; side effects must be opted into. |
| §"Output Arguments" | Receiver style + return values | Output arguments are nearly unidiomatic — extensions or returns replace them. |
| §"CQS" | Expression bodies for queries | `fun isAdmin() = role == ADMIN` reads as a query; commands return `Unit`. |
| §"Exceptions over codes" | `Result<T>` / `runCatching` | Exception ↔ value bridge at clearly-defined seams without leaking try/catch through layers. |
| §"DRY" | Extension functions, top-level functions | Reuse without a Helper class. |
| §"Small" | Single-expression functions, scope functions | One-liners replace 3-line statement-body functions. |
| §"Do One Thing" | `suspend` + structured concurrency | Async still respects "do one thing"; `coroutineScope { ... }` keeps the seam visible. |

---

## 1. Named & default arguments — kill most triads at the call site

Martin's argument-count discipline assumes that the caller has to remember positional order. Kotlin's named arguments turn that cost into zero.

```kotlin
// Three positional args — Martin would push for an argument object
fun assertEquals(expected: Double, actual: Double, delta: Double = 0.0)

// Call site reads itself
assertEquals(expected = 1.0, actual = result, delta = 0.001)
```

Default values let one function cover what Java would model with overload chains:

```kotlin
fun render(
    pageData: PageData,
    mode: RenderMode = RenderMode.SingleTest,
    encoding: Charset = Charsets.UTF_8,
    pretty: Boolean = false,
): String
```

**The rule is *not* repealed**. Five named arguments still make the body hard to reason about — fewer is still better. But "ordering ambiguity" is no longer the argument *against* dyads/triads in Kotlin; the argument is now purely cognitive load.

**House rule**:
- 1 positional arg is fine.
- ≥ 2 args: require named at the call site if the args don't form a single value (Detekt has `kotlin.style.RequireNamedArguments`-style rules; turn them on for ≥ 3).
- Default-argument values must be **sensible domain defaults** (`pretty = false`, `encoding = UTF_8`), not "I didn't decide" stand-ins. If there's no good default, it's a required arg.

---

## 2. Data classes and `@JvmInline value class` — free argument objects

Martin's "argument object" advice in Java required a new class with constructor, getters, equals, hashCode, toString. In Kotlin it's one line:

```kotlin
// ✓ Argument object — one line
data class Circle(val centre: Point, val radius: Double)
data class Point(val x: Double, val y: Double)

fun makeCircle(circle: Circle) { ... }
```

For **single-field** wrappers (the "primitive obsession" anti-smell), use `@JvmInline value class` — zero allocation, full type safety:

```kotlin
@JvmInline value class UserId(val value: UUID)
@JvmInline value class Email(val value: String) {
    init { require("@" in value) { "Email must contain @" } }
}

fun findUser(id: UserId): User?   // ← can't pass an OrderId by mistake
```

Together: most "polyad" arguments in business code collapse to 1-2 typed value classes plus 1 data-class aggregate.

---

## 3. Extension functions — dyads become monads by default

Martin's advice for `writeField(outputStream, name)` was: make `outputStream` a member, or extract a `FieldWriter` class. Kotlin offers a third path that Java didn't: an extension.

```kotlin
// ✗ Dyad — which goes first?
fun writeField(outputStream: OutputStream, name: String) { ... }

// ✓ Monad — receiver moved to extension
fun OutputStream.writeField(name: String) { ... }

// Call site is natural prose
outputStream.writeField("user.email")
```

**When to use extensions for this**:
- The receiver is a *general* type you don't own (`List`, `String`, `OutputStream`) and the verb makes sense as a method on it.
- You'd otherwise create a `Helper` class with a single static method.

**When NOT to use extensions**:
- The verb belongs to a domain object you own — make it a member. (Aggregate methods on `Order` go *on* `Order`, not as `fun Order.submit()`. See `ddd-functions.md`.)
- The extension is doing more than one thing — extension or not, "do one thing" still applies.

**Anti-pattern (extension as escape hatch from the type system)**:
```kotlin
// ✗ Extension on a type you control just to hide that this should be a member
fun Order.submit() { /* mutates internal state */ }   // ← put it on Order
```

---

## 4. `sealed class` + exhaustive `when` — switch retired

Martin's "switch in a factory" remains the only tolerated `when (type)`. Kotlin's sealed hierarchies make this idiomatic and compile-time-checked:

```kotlin
// Sealed hierarchy: the closed set of subtypes is part of the type
sealed class Employee {
    abstract fun calculatePay(): Money
    abstract fun isPayDay(today: LocalDate): Boolean
}
class Commissioned(val rate: BigDecimal, val sales: BigDecimal) : Employee() { ... }
class Hourly(val rate: BigDecimal, val hours: BigDecimal) : Employee() { ... }
class Salaried(val annual: BigDecimal) : Employee() { ... }

// Factory — the only `when` over Employee subtypes in the codebase
class EmployeeFactory {
    fun from(record: EmployeeRecord): Employee = when (record.type) {
        EmployeeType.COMMISSIONED -> Commissioned(record.rate, record.sales)
        EmployeeType.HOURLY       -> Hourly(record.rate, record.hours)
        EmployeeType.SALARIED     -> Salaried(record.salary)
    }
}
```

**Exhaustiveness as a function-level safety net**: `when (e: Employee)` over a sealed root is **required** to be exhaustive (when used as an expression). Adding a new subclass produces a compile error at every `when` — exactly the OCP/SRP discipline Martin asks for, enforced by the compiler.

```kotlin
// when as an expression — exhaustive check enforced
val description = when (employee) {
    is Commissioned -> "Commissioned at ${employee.rate}"
    is Hourly       -> "Hourly at ${employee.rate}"
    is Salaried     -> "Salaried at ${employee.annual}"
    // adding `class Contractor : Employee()` — compile error here
}
```

**House rule**: prefer `when` as expression (forces exhaustiveness) over `when` as statement (silent on new subtypes).

### Tolerated non-factory `when`

A `when` over a **closed enum of states** that *derives* (not dispatches behaviour) is fine:

```kotlin
fun OrderState.isTerminal(): Boolean = when (this) {
    SUBMITTED, PAID, SHIPPED -> false
    DELIVERED, CANCELLED      -> true
}
```

That's not the polymorphism case; it's a pure value-derivation.

---

## 5. Expression bodies — single-expression functions

A 3-line function with a return statement collapses to a 1-line expression-body. This is **Kotlin's default for small functions**:

```kotlin
// Statement body
fun isAdmin(): Boolean {
    return role == Role.ADMIN
}

// Expression body — what the function *is*, not what it *does*
fun isAdmin() = role == Role.ADMIN

// when as expression
fun describe(state: OrderState) = when (state) {
    SUBMITTED -> "waiting for payment"
    PAID      -> "ready to ship"
    SHIPPED   -> "in transit"
    DELIVERED -> "complete"
    CANCELLED -> "voided"
}
```

**Rules of thumb**:
- One expression (possibly multi-line) → expression body.
- Side effect (`println`, mutation, IO) → block body. Expression body for a function that mutates lies about being pure.
- A `when` that branches between expressions → expression body. A `when` that branches between blocks of statements → block body, or extract each branch.

---

## 6. Scope functions — `let` / `run` / `also` / `apply` / `with`

Scope functions can shrink five-line functions to one. They can also hide intent — apply with discipline.

| Scope fn | Receiver | Returns | Use when |
|---|---|---|---|
| `let` | `it` | lambda result | Null-safe transform, scope-narrow rename. |
| `run` | `this` | lambda result | Compute from receiver's properties without naming `it`. |
| `also` | `it` | the receiver | Side effect that returns the original (log, assert). |
| `apply` | `this` | the receiver | Mutating configuration of a builder. |
| `with` | `this` | lambda result | Group multiple ops on a non-null receiver. |

**Good uses**:
```kotlin
// let — narrows scope, makes null safety obvious
findUser(id)?.let { user ->
    notifier.notify(user.email)
}

// also — side effect that doesn't change the value
fun load(): Config = readConfig().also { logger.info("loaded ${it.size} entries") }

// apply — configuring a builder
val request = HttpRequest.newBuilder().apply {
    uri(URI(url))
    header("Authorization", "Bearer $token")
    timeout(Duration.ofSeconds(5))
}.build()
```

**Bad uses** — scope-function golf:
```kotlin
// ✗ Chained scope functions hide the abstraction levels
user.let { it.account }.run { balance }.also { logger.info("$it") }.let { it - fee }
// reads as five different concepts on one line

// ✓ Plain code is clearer
val newBalance = user.account.balance - fee
logger.info("balance: $newBalance")
```

**House rule**:
- One scope function per expression usually. Two if the second is `also` for a side effect.
- If you want a name for the intermediate value, use a `val`, not a scope function.
- Avoid `with(thing) { foo(); bar(); baz() }` when `thing.foo(); thing.bar(); thing.baz()` reads the same — explicit receiver is clearer.

---

## 7. `Result<T>` and `runCatching` — value-bridge at seams

Martin prefers exceptions. Kotlin's stdlib gives a value-shaped alternative, useful at well-defined seams (boundaries between layers, RPC handlers, where the caller wants to *deliberately* handle errors without try/catch).

```kotlin
// Computing with potential failure as a value
fun loadConfig(path: Path): Result<Config> = runCatching {
    Config.parse(path.readText())
}

// Caller chains in `Result`-space
loadConfig(path)
    .map { it.normalised() }
    .onFailure { logger.error("config load failed", it) }
    .getOrDefault(Config.defaults())
```

**House rules** (important — `Result` is often misused):

1. **Pick one boundary**. Either a function returns `Result<T>` or it throws. Don't mix both shapes through a layer. (Recommendation: throw inside one bounded context; return `Result` at the integration seam to another context.)
2. **Don't use `Result<Unit>`**. If there's nothing to return on success, a thrown exception is clearer.
3. **`Result.getOrThrow()` immediately after `runCatching` is a smell** — you just wrapped to unwrap. Use a plain try-block.
4. **Avoid `Result<Result<T>>`** — flatten with `mapCatching` / `recover`.
5. **Don't return `Result` from a domain aggregate method.** Domain invariant violations are exceptional; throw a `DomainError`. Keep `Result` for *expected* error paths at integrations.

### `Either` (Arrow) for richer error sums

When the error type matters at the call site (so generic `Throwable` from `Result` is too weak), use Arrow's `Either<E, A>`:

```kotlin
fun authenticate(token: String): Either<AuthError, Principal>
```

That choice is a project-level convention. Use it consistently; don't sprinkle.

---

## 8. `inline` and higher-order functions — small functions without allocation cost

Higher-order functions are central to Kotlin. They look like passing a "function" as a "value" — and naively that allocates a closure per call. `inline` removes the cost so small higher-order helpers stay cheap:

```kotlin
// Inline higher-order helper — caller pays no function-call overhead
inline fun <T, R> Iterable<T>.firstAs(block: (T) -> R?): R? {
    for (item in this) {
        block(item)?.let { return it }
    }
    return null
}
```

**Rule**: small (`< 5` line body) higher-order functions taking a lambda → use `inline`. Large ones, or those used in many places, → not inline (binary size matters).

**Subtle**: `inline` allows non-local returns from the lambda — sometimes desirable, sometimes confusing. Use `crossinline` to forbid; `noinline` for individual lambdas you want to keep as objects.

---

## 9. `suspend` functions — small still wins; structured concurrency keeps seams visible

A `suspend fun` is still a function. Rules of size, one-thing, and CQS apply unchanged.

```kotlin
// ✓ One thing: load + validate are separate suspends, composed in coroutineScope
suspend fun activateUser(id: UserId): User = coroutineScope {
    val user = async { repository.findById(id) }
    val perms = async { permissions.fetch(id) }
    user.await().withPermissions(perms.await()).also { it.activate() }
}
```

**Watch for**:
- **Suspend lying about CQS**: `suspend fun findUser(id): User` that *also* refreshes a cache is a query that commands. Same rule applies.
- **Long suspend functions**: easy to write because `async`/`await` lets you compose many calls on one line. Resist — extract intermediate suspends with names.
- **Cancellation cooperation**: every IO/CPU-heavy step in a suspend chain should suspend or call `yield()`. Not strictly a Clean Code rule, but it lives at function level.

---

## 10. Top-level functions vs class methods — same rules, choose the right home

Kotlin allows functions outside classes. They follow the same rules:

```kotlin
// Utility extension — natural at file top-level
fun String.toEmail(): Email = Email(this)

// Pure function — no state needed, top-level is fine
fun normaliseWhitespace(input: String): String = input.trim().replace(Regex("\\s+"), " ")
```

**House rule**:
- **Domain behaviour goes on the domain type.** `Order.submit()` is a method, not `fun submit(order: Order)`.
- **Generic helpers go top-level** (or as extensions on a general type).
- **A growing collection of top-level helpers in a `Util.kt` file is the same anti-pattern as a `Helper` class.** Split by topic, name by domain.

---

## 11. Function references and lambdas — `::name` vs `{ it.name }`

```kotlin
// Lambda — fine for one-offs
users.map { it.email }

// Function reference — better when the function exists and is named
users.map(User::email)

// Constructor reference
records.map(::Email)
```

Function references read closer to declarative code. Use them when the named function exists; don't *create* one-line wrapper methods just to enable a `::ref`.

---

## 12. Builders, DSLs, and trailing lambdas — small + readable

Kotlin's trailing-lambda syntax + receiver-with-block produces "build" DSLs:

```kotlin
// HTTP request DSL (hypothetical)
val req = httpRequest {
    url("https://api.example.com/v1/orders")
    header("Authorization", "Bearer $token")
    body { json(order) }
}
```

**Function-shape rules still apply**: each block is a function call configuring one thing. If `httpRequest { ... }` grows to 40 lines, the same "small / one thing" pressure pushes you to extract sub-blocks.

---

## 13. Multi-return — `Pair`, `Triple`, data classes, destructuring

A function "returning two things" is often two things. But sometimes one *concept* has two parts:

```kotlin
// ✓ A data class — names what's returned
data class ParseResult(val value: Int, val charactersConsumed: Int)
fun parseInt(input: String, offset: Int): ParseResult

// ✗ Pair — anonymous; the caller has to know what `.first` is
fun parseInt(input: String, offset: Int): Pair<Int, Int>
```

**Rule**: `Pair`/`Triple` is acceptable for genuinely transient internal returns. For anything crossing a public surface, use a named data class.

Destructuring at the call site is the readability payoff:

```kotlin
val (value, consumed) = parser.parseInt(input, offset)
```

---

## 14. Operator overloading — name follows convention, body still small

When implementing `plus`, `minus`, `compareTo`, etc., the function body is one expression in most cases. Keep it that way — if your `Money.plus` is 10 lines, you've put business logic in an operator. Lift it out.

```kotlin
// ✓ One-expression operator
@JvmInline value class Money(val amount: BigDecimal) {
    operator fun plus(other: Money) = Money(amount + other.amount)
}

// ✗ Operator with business rules — name it instead
operator fun Money.plus(other: Money): Money {
    if (currency != other.currency) throw IllegalArgumentException(...)
    // currency conversion
    return Money(amount + converted.amount)
}
// Better:
fun Money.addInSameCurrency(other: Money): Money = ...
fun Money.addConverting(other: Money): Money = ...
```

---

## 15. `tailrec` — recursion without the stack cost

When a recursive function is naturally written but you fear stack overflow:

```kotlin
tailrec fun gcd(a: Long, b: Long): Long =
    if (b == 0L) a else gcd(b, a % b)
```

Conditions: the function is tail-recursive (recursive call is the last thing). Kotlin compiles to a loop. Small + recursive is fine; the compiler does the unrolling.

---

## 16. Common Kotlin anti-patterns in function shape

| Anti-pattern | Why bad | Fix |
|---|---|---|
| `fun foo(): Result<Unit>` | Result has no success info to carry. | Throw or return `Unit`. |
| `?.let { } ?: run { }` for if/else | Loses readability of the conditional. | Use `if (x != null) ... else ...`. |
| `apply { }` returning `this` *and* mutating outer state | Two effects from one block. | Split: `apply` for config; `also` (or plain block) for side effect. |
| `var` inside a function with three reassignments | Mutable state in a small function is a smell. | Express as fold / map / chained `let`. |
| `lateinit var` for "argument I'll set later" | Reorders construction; subverts non-null safety. | Constructor injection or a builder. |
| Extension on a type you control, just to "look fluent" | Hides that the verb belongs to the type. | Put it on the type as a member. |
| Returning `Pair<T, U>` across a public boundary | Anonymous result. | Named data class. |
| `runCatching { ... }.getOrThrow()` | Wraps and immediately unwraps. | Just throw. |
| Long block inside `with(x) { ... }` to avoid `x.` | Reader has to remember the receiver. | Use the explicit receiver or extract. |
| `sealed class Result { ... }` reinventing stdlib `Result` | Confuses readers; conflicts at name resolution. | Use `Result<T>` or Arrow `Either`. |

---

## 17. Checklist before you call a Kotlin function "clean"

1. **Single expression body** if the function is one expression. (No needless `{ return ... }`.)
2. **Args ≤ 2 positional, or named-only.** Triads use a data class or named-only at call sites.
3. **No `Boolean` flag** — split or use a sealed mode type.
4. **No mutation hidden in an expression-bodied function.** Expression body promises a pure derivation.
5. **`when` over sealed root** is the only tolerated polymorphism-by-type-discrimination, and only in a factory.
6. **Side effects named** (`also`, `apply` for builders, a verb-named function for the rest).
7. **`Result<T>` only at boundaries**, not threaded through every layer.
8. **No `Util.kt` dumping ground** — extensions colocated with the type they extend or the use case they serve.
9. **`suspend` functions still small** — `coroutineScope { async / async / await; await }` is the seam, not an excuse to inline four concerns.
10. **Multi-return is a data class** when it crosses a public surface.
