# Kotlin & Spring Comment Patterns

Modern conventions that *replace* many of Martin's commenting patterns. The general rule: prefer **machine-readable annotations** over free-form comments wherever the toolchain understands them. For Martin's universal rules see `when-comments-earn-their-keep.md` and `comment-anti-patterns.md`.

---

## KDoc — the Kotlin Javadoc

KDoc replaces Javadoc and uses **Markdown**, not HTML. Default block style:

```kotlin
/**
 * One-sentence summary on the first line.
 *
 * Longer description here. Supports Markdown:
 * - bullets
 * - **bold** and *italic*
 * - `inline code` and code fences
 *
 * Cross-reference other declarations with brackets: [OrderRepository], [Order.submit].
 *
 * @param orderId the identity of the order
 * @return the loaded [Order], or `null` if not found
 * @throws OrderNotFoundException if `failOnMissing` is `true` and the order is absent
 * @sample com.example.samples.findOrderSample
 * @see OrderRepository.save
 */
fun findOrder(orderId: OrderId, failOnMissing: Boolean = false): Order? = ...
```

**Common tags**:

| Tag | Use |
|---|---|
| `@param name` | Document a parameter (when not self-evident from the name + type) |
| `@return` | Document the return value (when not self-evident) |
| `@throws ExceptionType` | Document conditions producing this exception |
| `@property name` | For a primary-constructor property of a class (instead of `@param`) |
| `@sample fqn` | Link to a sample function — appears in Dokka output |
| `@see [Target]` | Link to a related declaration |
| `@suppress` | Hide from generated docs |
| `@since 1.2.0` | Version added |

**Don't repeat tag info that the signature already conveys.** If `@param orderId` says "the order id", delete it.

---

## Visibility gate — when KDoc earns its keep

| Visibility | KDoc policy |
|---|---|
| `public` API on a *published library / SDK / module* | **Required.** Full tags. Used by consumers. |
| `public` inside an *internal* service | **Optional.** KDoc for non-obvious *why*; skip otherwise. |
| `internal` | **Default off.** Only when an invariant or gotcha needs explanation. |
| `private` | **Almost never.** Small enough to read; if not, split. |

This gate is the strongest single rule against KDoc bloat. See `comment-anti-patterns.md` §B18.

---

## `@Deprecated` over deprecation comments

**Bad**:
```kotlin
/**
 * @deprecated use [submit] instead. Will be removed in 2.0.
 */
fun submitOrder(order: Order): Order = submit(order)
```

**Good** — annotation is machine-readable, IDE-actionable, and tools enforce the timeline:
```kotlin
@Deprecated(
    message = "Use submit(order) instead",
    replaceWith = ReplaceWith("submit(order)"),
    level = DeprecationLevel.WARNING,   // or ERROR before removal
)
fun submitOrder(order: Order): Order = submit(order)
```

The IDE warns on every call site, suggests the replacement, and `DeprecationLevel.ERROR` blocks compilation when you're ready to remove.

**Levels**:
- `WARNING` — soft deprecation, still compiles
- `ERROR` — compile failure, callers must migrate
- `HIDDEN` — invisible to source code, retained for binary compatibility

---

## `@Suppress` with mandatory rationale

**Bad** (suppression with no reason):
```kotlin
@Suppress("UNCHECKED_CAST")
val typed = raw as List<Order>
```

**Good** (suppression with the *why*):
```kotlin
@Suppress("UNCHECKED_CAST")  // Jackson erases the generic; the type is asserted upstream by the schema validator.
val typed = raw as List<Order>
```

**House rule**: every `@Suppress` must be paired with a comment explaining *why* the suppression is safe. A suppression without rationale is technical debt with no payback plan.

---

## `TODO()` function vs `// TODO` comment

Kotlin's stdlib `TODO()` is a **function** that throws `NotImplementedError` at runtime. Use it for stubs that should fail loudly if hit.

**Good**:
```kotlin
fun applyDiscount(order: Order, code: DiscountCode): Money =
    TODO("DEV-1234: discount engine not yet wired")
```

```kotlin
override fun renderReport(): Report = TODO("v2 reporting — see ADR-0042")
```

**vs `// TODO` comment** — text-only, no runtime enforcement:
```kotlin
// TODO(DEV-1234): switch to keyset pagination once result sets exceed 10k rows
fun listOrders(offset: Int, limit: Int): Page<Order> = ...
```

| When | Use |
|---|---|
| The code path is unimplemented and must crash if executed | `TODO("reason")` |
| The code path works but is acknowledged as suboptimal | `// TODO(owner/issue): ...` |
| Deferred work, not on a runtime path | `// TODO(owner/issue): ...` |

**House rule**: every `// TODO` includes either an issue ID (`DEV-1234`) or an owner (`@username`). Orphan TODOs get swept.

---

## IntelliJ language injection — legitimate comment use

IntelliJ recognises `// language=<X>` hints to inject syntax highlighting and validation into string literals.

**Good**:
```kotlin
// language=SQL
private val FIND_ORDER_BY_ID = """
    SELECT o.*, c.email
    FROM orders o
    JOIN customers c ON c.id = o.customer_id
    WHERE o.id = :id
""".trimIndent()

// language=JSON
val schemaJson = """
    { "type": "object", "properties": { "orderId": { "type": "string" } } }
""".trimIndent()
```

These comments aren't documentation — they're **tooling instructions**. Legitimate exception to "default no comments".

Other recognised language hints: `RegExp`, `XML`, `HTML`, `JavaScript`, `Groovy`, `Kotlin`, `PostgreSQL`, `MongoDB`, etc.

---

## `// region` folding — banned in regular code

IntelliJ supports `// region <name>` / `// endregion` for code folding.

**Bad**:
```kotlin
class OrderService {
    // region: dependencies
    private val repo: OrderRepository
    private val publisher: EventPublisher
    // endregion

    // region: public API
    fun submit(...) { ... }
    fun cancel(...) { ... }
    // endregion

    // region: private helpers
    private fun validate(...) { ... }
    // endregion
}
```

**House rule**: regions signal the class is too big to navigate without folding. **Split the class** (or use the stepdown rule — `clean-code-functions` §"Stepdown").

**Exception**: generated code where size is acceptable and structure is fixed (e.g., generated DTOs, protobuf classes).

---

## OpenAPI annotations — documentation as data

For REST endpoints documented in OpenAPI / Swagger, prefer **annotations** over comments. Annotations are picked up by `springdoc-openapi` and rendered in the live spec; comments are not.

**Bad** (Javadoc-style commentary):
```kotlin
/**
 * Submits an order.
 *
 * The order must be in DRAFT state. Returns the submitted order with its assigned ID.
 */
@PostMapping("/orders")
fun submitOrder(@RequestBody submission: OrderSubmission): OrderView = ...
```

**Good** (machine-readable annotations):
```kotlin
@Operation(
    summary = "Submit a draft order",
    description = "The order must be in DRAFT state. Returns the submitted order with its assigned ID.",
)
@ApiResponses(
    value = [
        ApiResponse(responseCode = "201", description = "Order submitted"),
        ApiResponse(responseCode = "409", description = "Order already submitted"),
    ],
)
@PostMapping("/orders")
fun submitOrder(@RequestBody submission: OrderSubmission): OrderView = ...
```

For DTO field documentation:
```kotlin
data class OrderSubmission(
    @field:Schema(description = "Customer placing the order", example = "550e8400-e29b-41d4-a716-446655440000")
    val customerId: UUID,

    @field:Schema(description = "Line items; at least one required", minLength = 1)
    val items: List<LineSubmission>,
)
```

The generated OpenAPI spec gets the descriptions; tooling can consume them; nothing duplicates between KDoc and `@Schema`.

---

## `@DisplayName` for test intent

JUnit 5 supports `@DisplayName` for test class / method labels.

**Good** (sentence-style with backticks — preferred for Kotlin):
```kotlin
@Test
fun `given empty cart, when submitting order, then throws EmptyOrderException`() { ... }
```

**Good** (when backticks don't render well in your reporter):
```kotlin
@Test
@DisplayName("given empty cart, when submitting order, then throws EmptyOrderException")
fun submitOrderEmptyCart() { ... }
```

**Don't add comments** — the test name *is* the documentation.

---

## JPA `@Comment` for schema-level docs

Hibernate ORM 6+ supports `@Comment` on JPA entities, generating `COMMENT ON` statements in the schema.

**Good**:
```kotlin
@Entity
@Comment("Submitted orders awaiting fulfilment")
class OrderRow(
    @Id val id: UUID,

    @Comment("Stripe charge ID; null before payment authorisation")
    val stripeChargeId: String?,
    ...
)
```

These end up in the database schema as actual `COMMENT` statements — visible to DBAs running `\d+ orders` in psql.

**House rule**: use `@Comment` for *DBA-visible* documentation (the rationale behind a column, the unit of a number). Don't duplicate the same content as KDoc — they serve different audiences.

For Flyway migrations, the equivalent is SQL `COMMENT ON COLUMN`:
```sql
COMMENT ON COLUMN orders.stripe_charge_id IS 'Stripe charge ID; null before payment authorisation';
```

---

## `@Schema(description = ...)` on configuration properties

For `@ConfigurationProperties` data classes, the `@Schema` annotation generates `spring-boot-configuration-processor` metadata that powers IDE autocomplete and inline help.

**Good**:
```kotlin
@ConfigurationProperties("checkout.payment")
data class CheckoutPaymentProperties(
    @field:Schema(description = "Per-call timeout for the payment gateway", example = "5s")
    val timeout: Duration = Duration.ofSeconds(5),

    @field:Schema(description = "Maximum retry attempts before failing the charge", minimum = "0", maximum = "10")
    val maxRetries: Int = 3,
)
```

The IDE shows these descriptions on hover when editing `application.yml`.

---

## Quick reference — annotation > comment

| Old comment shape | Modern annotation |
|---|---|
| `// deprecated; use X` | `@Deprecated(message, replaceWith, level)` |
| `// suppress: unchecked cast — reason` | `@Suppress("UNCHECKED_CAST")` + paired reason comment |
| `// not implemented` (with crash) | `TODO("reason")` |
| `// skipping test — slow` | `@Disabled("Takes 5 min — perf regression only")` |
| `// nullable for legacy reasons` | `val x: String? = null` (the type is the comment) |
| `// only auto-submit if condition` | `@Cacheable(condition = "...")`, `@Scheduled(...)` |
| `// description for API docs` | `@Operation`, `@Schema(description = ...)` |
| `// description for DB schema` | `@Comment(...)` on JPA / `COMMENT ON COLUMN ...` in Flyway |
| `// thread-unsafe — see below` | `@NotThreadSafe` (jcip-annotations) or KDoc `@implNote` |
| `// since version 1.2.0` | KDoc `@since` |

When the toolchain understands the metadata, prefer the annotation. Free-form comments are the last resort.

---

## Summary checklist (Kotlin/Spring specific)

- [ ] KDoc only on `public` API boundaries; default off for `internal` / `private`.
- [ ] KDoc uses Markdown, not HTML; cross-refs via `[ClassName]`.
- [ ] `@param` / `@return` only when they add information beyond the signature.
- [ ] `@Deprecated(message, replaceWith, level)` instead of "deprecated" comments.
- [ ] Every `@Suppress` paired with a comment explaining why the suppression is safe.
- [ ] `TODO("reason")` function for unimplemented stubs that should crash on hit.
- [ ] `// TODO(OWNER-or-ISSUE-ID): ...` for documented deferred work.
- [ ] `// language=SQL` / `// language=JSON` injection hints are legitimate.
- [ ] No `// region` folding in regular code; split classes instead.
- [ ] OpenAPI annotations on REST controllers, not Javadoc-style commentary.
- [ ] `@Schema(description = ...)` on DTO fields, not parallel KDoc.
- [ ] `@DisplayName` or backticked names for tests — no comments.
- [ ] JPA `@Comment` for schema-level documentation (DBA audience).
