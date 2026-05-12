---
name: spring-validation
description: "Bean Validation (Jakarta Validation 3.x, `jakarta.validation`) for Kotlin / Spring Boot 3+ services — validation as a boundary concern (input shape at the controller, domain invariants inside aggregates), the `spring-boot-starter-validation` dependency that pulls in Hibernate Validator as the JSR-380 reference implementation, the `@Valid` vs `@Validated` distinction (`@Valid` is Jakarta — triggers cascade on a parameter or field; `@Validated` is Spring — adds validation **groups** and **method-level validation** via AOP proxy), built-in constraints (`@NotNull`, `@NotBlank`, `@NotEmpty`, `@Size`, `@Min`, `@Max`, `@Positive`, `@Negative`, `@Email`, `@Pattern`, `@Past`, `@Future`, `@AssertTrue`, `@AssertFalse`, `@DecimalMin`, `@DecimalMax`, `@Digits`, `@URL`), validation in three places (`@RequestBody` DTO → `MethodArgumentNotValidException`; `@PathVariable` / `@RequestParam` with `@Validated` on the controller → `ConstraintViolationException`; service-method validation with `@Validated` on the service → `ConstraintViolationException`), validation groups (`OnCreate` / `OnUpdate` interfaces for shared DTOs with different required-ness), custom constraints (`@Constraint(validatedBy = [MyValidator::class])` + `ConstraintValidator<MyConstraint, T>`, class-level cross-field validation, composition with `@ReportAsSingleViolation`), nested + collection cascade with `@Valid` on a field or `List<@Valid Item>`, **the Kotlin `@field:NotNull` site-target gotcha** (primary-constructor property annotations default to `param:`, but Bean Validation needs `field:` — without it the annotation is silently ignored), programmatic validation via injected `Validator`, `MessageSource` i18n with `{javax.validation.constraints.NotNull.message}` placeholders, error-response mapping to `ProblemDetail` (RFC 7807) via `@ExceptionHandler(MethodArgumentNotValidException::class)` and `@ExceptionHandler(ConstraintViolationException::class)` with a `List<FieldError>` extension, anti-patterns (validating shape in business logic that should be at the boundary, trusting Bean Validation as authorisation, swallowing `ConstraintViolationException` with `runCatching`, using `@Validated` and `@Valid` interchangeably, forgetting `@field:`, method validation on a non-Spring-managed class with no AOP proxy, missing `@Valid` on a nested field), and testing validation (pure unit via injected `Validator`, slice-level via `@WebMvcTest`). Use when adding validation to a new DTO, debugging 'why doesn't `@NotNull` fire on my Kotlin `data class`?', mapping validation errors to `ProblemDetail`, writing a custom constraint, picking between controller-layer and service-layer validation, designing validation groups for shared create/update DTOs, or reviewing a PR where validation annotations are inconsistent. Controller wiring / `ProblemDetail` mapping deep is `spring-web-mvc`; the `@Validated` AOP-proxy mechanics are `spring-aop`; aggregate invariants enforced via `require` / `check` are `ddd-tactical-patterns`; authorisation is `spring-security`."
risk: safe
source: "custom — Bean Validation for Kotlin / Spring Boot 3+"
date_added: "2026-05-12"
---

# Spring Validation (Kotlin / Spring Boot 3+)

> Bean Validation is for the shape of input crossing a boundary. Authorisation is not validation. Domain invariants enforced inside an aggregate are not validation. Know which boundary you're defending and the rest of the design falls out.

## Use this skill when

- Adding validation to a new request DTO or `@ConfigurationProperties` class
- Debugging "the `@NotBlank` on my Kotlin `data class` doesn't fire" — almost always the missing `@field:` site-target
- Mapping `MethodArgumentNotValidException` / `ConstraintViolationException` to a consistent `ProblemDetail` error response
- Picking between controller-layer validation (`@Valid @RequestBody`) and service-layer method validation (`@Validated` on the service class)
- Designing validation groups (`OnCreate` / `OnUpdate`) for a DTO shared between create and update endpoints
- Writing a custom `ConstraintValidator` — single-field or cross-field — and registering it
- Cascading validation into nested objects (`@Valid` on a field) or collections (`List<@Valid Item>`)
- Reviewing a PR where `@Valid` and `@Validated` are mixed without an obvious reason
- Choosing whether something is a Bean Validation constraint or a domain invariant inside an aggregate

## Do not use this skill when

- The question is about **`@RestController` mapping, `@ControllerAdvice`, the global error-handler structure, content negotiation, `ResponseEntity`** — that's `spring-web-mvc`. This skill points at `ProblemDetail` and the validation-specific exception handlers; the controller layer deep is there.
- The question is about **AOP proxy mechanics** — why `@Validated` on a service requires `open` classes, self-invocation, `final` methods, JDK vs CGLIB proxies — that's `spring-aop`.
- The question is about **aggregate invariants** — "an Order must always have at least one line" enforced inside the domain model, `require(...)` / `check(...)`, private constructors and factories — that's `ddd-tactical-patterns`. Bean Validation lives at the input boundary; invariants live inside the aggregate. Different layer, different tool.
- The question is about **authorisation** — "can this user do this?" — that's `spring-security`. Validation says "the request shape is well-formed"; authorisation says "you are allowed to issue this request". A request with valid shape can still be forbidden.
- The question is about **REST contract design** — 400 vs 422, error-response shape, RFC 7807 conventions — that's `api-design-principles`. This skill produces `ProblemDetail`; that skill owns the contract.
- The question is about **typed `@ConfigurationProperties` with `@Validated`** — startup-time config validation — that's `spring-boot`. This skill mentions the pattern; the deep treatment is there.

## Core principles

1. **Validation is a boundary concern.** Input crossing into the system from JSON / form / path / query gets validated at the boundary (`@RestController` parameter). Domain invariants stay inside the aggregate. Mixing the two leaks framework annotations into the domain and scatters shape-checking across business logic.
2. **`@Valid` triggers cascade; `@Validated` enables groups and method-level validation.** Two distinct features. Don't use them interchangeably — see the table below.
3. **Validation says shape. Authorisation says permission.** A constraint annotation on a field is not a security check. `@Pattern(regexp = "[A-Z0-9-]+")` doesn't stop an attacker — it stops a malformed request. See `spring-security`.
4. **Validate once, at the entrypoint.** A request body validated by `@Valid @RequestBody` doesn't need re-validation in the service. If the service is the entrypoint (called from `@RabbitListener` or a `@Scheduled` job), validate there with `@Validated` method-level.
5. **Fail fast, fail loud.** `MethodArgumentNotValidException` becomes a `400 Bad Request` with a `ProblemDetail` describing every field that failed. Don't swallow validation exceptions with `runCatching` or generic catch blocks — the consumer needs to know what to fix.
6. **`400` for malformed (cannot parse / wrong type / missing required); `422` for semantically invalid (parses fine, fails a business rule).** Bean Validation produces 400 by default — fine for most "request shape" problems. Reserve 422 for "the request is well-formed but violates a domain rule we couldn't express as a constraint annotation". See `api-design-principles`.
7. **Kotlin `data class` requires `@field:` site-targets for Bean Validation.** This single rule produces more silent bugs than the rest of the skill combined. The annotation defaults to `param:` site, Hibernate Validator reads the `field:` site — annotation is silently ignored, no compile error, no runtime warning. See the dedicated section below.

## `@Valid` vs `@Validated` — the actual difference

| Feature | `@Valid` (`jakarta.validation.Valid`) | `@Validated` (`org.springframework.validation.annotation.Validated`) |
|---|---|---|
| Source | Jakarta Bean Validation (JSR-380) | Spring Framework |
| Triggers **cascade** into a nested object or collection | **Yes** — `@Valid` on a field validates the nested type | No (use `@Valid` inside) |
| Triggers DTO validation on a controller parameter | Yes (`@Valid @RequestBody`) | Yes — equivalent for this use case |
| Enables **validation groups** | No (all default-group constraints fire) | **Yes** — `@Validated(OnCreate::class)` |
| Enables **method-level validation** on a Spring bean | No | **Yes** — put on the class, then `@Valid` / `@NotNull` on method params and return types fires |
| Throws | `MethodArgumentNotValidException` (when on controller `@RequestBody`) | `ConstraintViolationException` (when from method-level validation on path/query params or service methods) |

Practical rule:

- **`@Valid` on the parameter and on nested fields** — for cascade into request bodies and nested DTOs.
- **`@Validated` on the class** — when you need groups, when you need method-level validation on `@PathVariable` / `@RequestParam`, when you need validation on service-layer method parameters / return types.

Often both appear on the same controller: `@Validated` on the class (for `@PathVariable` constraints) and `@Valid` on the body parameter (for the DTO cascade). That combination is correct, not redundant.

## Built-in constraints — what each one does

The full catalogue from `jakarta.validation.constraints` plus the one Hibernate-validator extension you actually use:

| Annotation | Applies to | Checks |
|---|---|---|
| `@NotNull` | Any reference type | Value is not `null` |
| `@NotBlank` | `String` | Not `null` AND `trim().isNotEmpty()` |
| `@NotEmpty` | `String`, `Collection`, `Map`, array | Not `null` AND `size > 0` (does **not** trim — empty string fails, blank does not) |
| `@Size(min = …, max = …)` | `String`, `Collection`, `Map`, array | Size is in range (inclusive) |
| `@Min` / `@Max` | Numeric (`Int`, `Long`, `BigDecimal`, …) | Value is `≥ min` / `≤ max` |
| `@Positive` / `@Negative` | Numeric | `> 0` / `< 0` |
| `@PositiveOrZero` / `@NegativeOrZero` | Numeric | `≥ 0` / `≤ 0` |
| `@DecimalMin(value)` / `@DecimalMax(value)` | Numeric / `String` | Value `≥` / `≤` the string-encoded decimal (handles `BigDecimal` precision) |
| `@Digits(integer, fraction)` | Numeric / `String` | At most `integer` digits before, `fraction` after the decimal point |
| `@Email` | `String` | Matches an email-shaped regex (RFC-flavoured, not strict) |
| `@Pattern(regexp = "…")` | `String` | Matches the regex |
| `@Past` / `@PastOrPresent` | `java.time.*` | Strictly before / not after now |
| `@Future` / `@FutureOrPresent` | `java.time.*` | Strictly after / not before now |
| `@AssertTrue` / `@AssertFalse` | `Boolean` | Value is `true` / `false` |
| `@URL` (Hibernate Validator extension) | `String` | Parses as a URL |

Notes:

- `@NotNull` and `@NotBlank` are not interchangeable. `@NotBlank("  ")` fails; `@NotNull("  ")` passes. For user-typed strings, `@NotBlank` is almost always what you want.
- `@Size` works on collections too — `@field:Size(min = 1, max = 10) val items: List<Item>` caps the list length.
- `@Email` is permissive; for stricter validation use `@Pattern` with your own regex or a custom constraint.
- Bean Validation does not unwrap Kotlin `@JvmInline value class` wrappers — see the Kotlin specifics section.

## Where validation runs — three places

### 1. Controller `@RequestBody` — `@Valid` on the parameter

The DTO is validated when Jackson finishes deserialising. Failure throws `MethodArgumentNotValidException`, mapped by Spring 6 to `400 Bad Request`.

```kotlin
data class CreateUserRequest(
    @field:NotBlank @field:Size(min = 2, max = 50) val name: String,
    @field:NotBlank @field:Email val email: String,
    @field:Min(value = 18) val age: Int,
    @field:Valid val address: AddressDto,                          // cascade into nested
    @field:Size(min = 1, max = 10) val tags: List<@NotBlank String> = emptyList(),
)

data class AddressDto(
    @field:NotBlank val street: String,
    @field:NotBlank @field:Size(min = 2, max = 2) val countryCode: String,
)

@RestController
@RequestMapping("/api/v1/users")
class UserController(private val users: UserService) {
    @PostMapping
    fun create(@Valid @RequestBody req: CreateUserRequest): UserResponse =
        users.create(req).toResponse()
}
```

No `@Validated` needed for `@RequestBody` validation — `@Valid` on the parameter is the trigger.

### 2. `@PathVariable` / `@RequestParam` — `@Validated` on the controller class

Constraints on individual method parameters require **method-level validation**, which requires `@Validated` on the **class** (not the method). The class then gets wrapped in a Spring AOP proxy that validates parameters on every call. Throws `ConstraintViolationException` — different exception than `@RequestBody` validation.

```kotlin
@RestController
@RequestMapping("/api/v1/users")
@Validated                                                            // class-level
class UserController(private val users: UserService) {
    @GetMapping("/{id}")
    fun get(
        @PathVariable @Min(1) id: Long,
        @RequestParam @Size(max = 100) search: String?,
    ): UserResponse = users.findById(id).toResponse()
}
```

AOP-proxy rules apply (see `spring-aop`):
- The class must be `open` (the `kotlin-spring` compiler plugin handles this for `@RestController`)
- Self-invocation skips the proxy → no validation
- Calling a method on a non-Spring-managed instance → no proxy, no validation

### 3. Service-layer method validation — `@Validated` on the service class

When the service is the entrypoint (called from a `@RabbitListener`, a `@Scheduled` job, or a non-validated source), put `@Validated` on the class and constraints on method parameters / return types.

```kotlin
@Service
@Validated
class UserService(private val users: UserRepository) {
    fun create(@Valid request: CreateUserRequest): @NotNull User {
        // request validated on entry; return value validated on exit
        return users.save(User.from(request))
    }
}
```

This throws `ConstraintViolationException` — same exception type as path/query validation. Your `@ControllerAdvice` needs handlers for **both** `MethodArgumentNotValidException` (from `@RequestBody`) and `ConstraintViolationException` (from method-level).

Service-layer validation is most useful for non-HTTP entrypoints. For HTTP, the controller layer is the right boundary — validating again in the service is duplication.

## Validation groups — same DTO, different required-ness

Groups let one DTO express "field X is required on create, optional on update". Define marker interfaces and tag constraints with the groups they belong to.

```kotlin
interface OnCreate
interface OnUpdate

data class UserDto(
    @field:Null(groups = [OnCreate::class])              // server-assigned on create
    @field:NotNull(groups = [OnUpdate::class])           // required on update
    val id: Long?,

    @field:NotBlank(groups = [OnCreate::class, OnUpdate::class])
    val name: String,

    @field:NotBlank(groups = [OnCreate::class])          // required on create only
    @field:Email(groups = [OnCreate::class, OnUpdate::class])
    val email: String?,
)

@PostMapping
fun create(@Validated(OnCreate::class) @RequestBody req: UserDto): UserResponse = ...

@PutMapping("/{id}")
fun update(@PathVariable id: Long, @Validated(OnUpdate::class) @RequestBody req: UserDto): UserResponse = ...
```

Notes:
- At the call site use `@Validated(OnCreate::class)` — `@Valid` does **not** support groups.
- A constraint without `groups` belongs to the **default** group only — it does **not** fire when a named group is active. To always fire, list explicitly: `groups = [Default::class, OnCreate::class, OnUpdate::class]`.
- Groups are a power tool. For unrelated create/update shapes, two `data class`es are clearer. Use groups when shapes are the same modulo a few required-ness differences.

## Custom constraints — when built-ins aren't enough

Two pieces: the annotation (`@Constraint(validatedBy = …)`) and the `ConstraintValidator<MyConstraint, T>` implementation.

```kotlin
@MustBeAfter(of = "startDate", value = "endDate")
data class DateRangeRequest(
    @field:NotNull val startDate: LocalDate,
    @field:NotNull val endDate: LocalDate,
)

// Cross-field constraint — class-level
@Target(AnnotationTarget.CLASS)
@Retention(AnnotationRetention.RUNTIME)
@Constraint(validatedBy = [MustBeAfterValidator::class])
annotation class MustBeAfter(
    val of: String,
    val value: String,
    val message: String = "{constraint.MustBeAfter.message}",
    val groups: Array<KClass<*>> = [],
    val payload: Array<KClass<out Payload>> = [],
)

class MustBeAfterValidator : ConstraintValidator<MustBeAfter, Any> {
    private lateinit var ofField: String
    private lateinit var valueField: String

    override fun initialize(annotation: MustBeAfter) {
        ofField = annotation.of; valueField = annotation.value
    }

    override fun isValid(target: Any?, ctx: ConstraintValidatorContext): Boolean {
        if (target == null) return true                              // @NotNull's job
        val of = readField(target, ofField) as? LocalDate ?: return true
        val value = readField(target, valueField) as? LocalDate ?: return true
        return value.isAfter(of)
    }

    private fun readField(target: Any, name: String): Any? =
        target::class.java.getDeclaredField(name).apply { isAccessible = true }.get(target)
}
```

Notes:
- For **single-field** constraints, place the annotation on the field — `ConstraintValidator<MyAnnotation, String>`.
- For **cross-field** constraints, target the class and read fields via reflection.
- `@ReportAsSingleViolation` on a composed constraint hides inner violations — useful when "valid X" means "passes A and B and C" but the consumer just wants "X is invalid".
- For i18n, use a placeholder message (`{constraint.MustBeAfter.message}`) and define the key in `ValidationMessages.properties`.

## Nested + collection validation — `@Valid` cascades

Without `@Valid` on a field, Bean Validation does **not** recurse into the nested object. The annotation is the cascade switch.

```kotlin
data class OrderRequest(
    @field:NotNull
    @field:Valid                                          // cascade into Customer
    val customer: CustomerDto,

    @field:Size(min = 1, max = 100)
    val items: List<@Valid OrderItemDto>,                 // cascade into each item

    @field:NotEmpty
    val tags: Map<String, @NotBlank String>,              // validate each map value
)
```

Notes:
- `List<@Valid Item>` validates each element. `@field:Valid` on the list itself would do nothing useful — the cascade has to be on the element type.
- Type-use annotations (the `@NotBlank` inside the generic on `List<@NotBlank String>`) require Hibernate Validator's type-use support, which is on by default.
- A `null` element in a `List<@Valid Item>` is **not** caught by `@Valid` — add `@field:NotNull` to the elements (`List<@Valid @NotNull Item>`) or `@field:NotEmpty` on the list and validate inside the item.

## The Kotlin `@field:` site-target gotcha

This is the single biggest source of "why doesn't my validation fire?" in Kotlin Spring code.

### The problem

Kotlin's primary-constructor properties have multiple annotation targets — `param:`, `property:`, `field:`, `get:`, `set:`. When you write a bare `@NotBlank val name: String`, Kotlin applies the annotation to the **first applicable target in priority order** — for Bean Validation annotations that's `param:`. Hibernate Validator reads `field:`. Result: silently ignored.

### The fix

Add `@field:` explicitly on every Bean Validation annotation on a `data class` property:

```kotlin
// WRONG — annotation goes to param, Hibernate reads field, validation never fires
data class CreateUserRequest(
    @NotBlank val name: String,             // silently ignored
    @Email val email: String,               // silently ignored
)

// RIGHT — explicit @field: site-target
data class CreateUserRequest(
    @field:NotBlank val name: String,
    @field:Email val email: String,
)
```

No warning. No error. Tests that exercise the controller with bad input pass with `200 OK` and your code happily processes garbage. The only signal is "validation isn't firing" reported by a downstream consumer — or worse, a security issue.

### The team rule

Every Bean Validation annotation on a `data class` property uses `@field:`. Enforce in code review or with a Detekt rule. The cost of getting this wrong is silently-ignored validation — worse than a noisy failure. `@property:` works with the right Hibernate value-extractor wiring but isn't portable; `@field:` is the always-works target.

For mutable properties (`var`), `@field:` works the same way. For computed `val`s with no backing field, use `@get:NotBlank` so Bean Validation reads via the getter. Rare on request DTOs.

## Programmatic validation

Inject the `Validator` bean and call it directly when you're outside Spring's auto-magic (bulk imports, CLI tools, ad-hoc checks):

```kotlin
@Service
class BulkImportService(private val validator: Validator) {
    fun importAll(rows: List<UserDto>): ImportResult {
        val (valid, invalid) = rows.partition { validator.validate(it).isEmpty() }
        return ImportResult(valid, invalid)
    }
}
```

`Set<ConstraintViolation<T>>` — empty means valid; each violation carries property path, invalid value, message, annotation.

## `MessageSource` integration — i18n

Constraint messages support `{...}` placeholders resolved against `ValidationMessages.properties` (default) or Spring's `MessageSource` wired as the `MessageInterpolator`. Built-in constraints already have keys like `{jakarta.validation.constraints.NotBlank.message}` — override in `messages_<locale>.properties` for localisation. Custom constraints should always use a placeholder key, not a hard-coded message, so they can be translated. Wire with `LocalValidatorFactoryBean().setValidationMessageSource(messageSource)`.

## Error response mapping to `ProblemDetail`

Spring 6 ships `ProblemDetail` (RFC 7807). The default `MethodArgumentNotValidException` → `400` mapping produces a minimal body; for a useful contract, write a `@RestControllerAdvice` that adds an `errors: List<FieldError>` extension. **Both** exception types must be handled — `@RequestBody` validation throws one, method-level validation the other.

```kotlin
data class FieldError(val field: String, val rejectedValue: Any?, val message: String)

@RestControllerAdvice
class ValidationExceptionHandler {

    @ExceptionHandler(MethodArgumentNotValidException::class)        // from @Valid @RequestBody
    fun handleBodyValidation(ex: MethodArgumentNotValidException): ProblemDetail {
        val errors = ex.bindingResult.fieldErrors.map {
            FieldError(it.field, it.rejectedValue, it.defaultMessage ?: "invalid")
        }
        return problemDetail(errors)
    }

    @ExceptionHandler(ConstraintViolationException::class)            // from @Validated method-level
    fun handleParamValidation(ex: ConstraintViolationException): ProblemDetail {
        val errors = ex.constraintViolations.map {
            FieldError(it.propertyPath.toString(), it.invalidValue, it.message)
        }
        return problemDetail(errors)
    }

    private fun problemDetail(errors: List<FieldError>): ProblemDetail =
        ProblemDetail.forStatus(HttpStatus.BAD_REQUEST).apply {
            type = URI.create("https://api.example.com/problems/validation-failed")
            title = "Validation failed"
            detail = "Request has ${errors.size} validation error(s)"
            setProperty("errors", errors)
        }
}
```

The response body:

```json
{
  "type": "https://api.example.com/problems/validation-failed",
  "title": "Validation failed",
  "status": 400,
  "detail": "Request has 2 validation error(s)",
  "instance": "/api/v1/users",
  "errors": [
    { "field": "email", "rejectedValue": "bad",  "message": "must be a well-formed email address" },
    { "field": "age",   "rejectedValue": 12,     "message": "must be greater than or equal to 18" }
  ]
}
```

`400` is the right status for "validation failed on shape". Some teams prefer `422 Unprocessable Entity` for "syntactically valid JSON that fails a domain rule" — pick one per service. See `spring-web-mvc` for the exception-handler structure and `api-design-principles` for the `ProblemDetail` contract.

## Anti-patterns

| Anti-pattern | Why it's wrong | Fix |
|---|---|---|
| Bean Validation annotation without `@field:` on a Kotlin `data class` | Annotation goes to `param:`, Hibernate reads `field:` — silently ignored | `@field:NotBlank` unconditionally |
| Validating in business logic that belongs at the boundary | Scatters shape-checking; mixes layers | Validate at the controller; the service trusts its inputs |
| Trusting validation as authorisation | `@Pattern` doesn't stop an attacker | Validate shape; authorise with `@PreAuthorize` |
| Swallowing `ConstraintViolationException` with `runCatching` | Hides failures; returns garbage | Let it propagate to the `@RestControllerAdvice` |
| `@Valid` when groups are needed | `@Valid` doesn't read groups | Use `@Validated(OnCreate::class)` |
| `@Validated` on a non-Spring-managed class | No AOP proxy → never fires | Make it a `@Component` / `@Service` |
| Self-invocation of a method-validated method | `this.foo(...)` skips the proxy | Inject the bean reference (see `spring-aop`) |
| Missing `@Valid` on a nested field | Cascade doesn't happen | Add `@field:Valid` on the nested field |
| Generic `@ExceptionHandler(Exception::class)` ahead of validation handlers | Wins over specific handlers → 500 instead of 400 | Order specific handlers first |
| Validating the same DTO at controller AND service | Duplicate work; drift | Validate at the entrypoint only |

## Testing validation

Two layers — pure unit and slice.

**Pure unit — inject `Validator`.** Fastest possible, no Spring context, one constraint per test:

```kotlin
class CreateUserRequestValidationTest {
    private val validator = Validation.buildDefaultValidatorFactory().validator

    @Test
    fun `email must be well-formed`() {
        val violations = validator.validate(
            CreateUserRequest(name = "ok", email = "bad", age = 30, address = ..., tags = listOf("t"))
        )
        assertThat(violations).hasSize(1)
        assertThat(violations.first().propertyPath.toString()).isEqualTo("email")
    }
}
```

**Slice — `@WebMvcTest`** boots validation infrastructure, the `@RestControllerAdvice`, and the controller — verifying the full request → validation → `ProblemDetail` path:

```kotlin
@WebMvcTest(UserController::class)
class UserControllerValidationTest(@Autowired val mvc: MockMvc) {
    @MockBean lateinit var users: UserService

    @Test
    fun `400 when email is malformed`() {
        mvc.post("/api/v1/users") {
            contentType = MediaType.APPLICATION_JSON
            content = """{"name":"ok","email":"bad","age":30,...}"""
        }.andExpect {
            status { isBadRequest() }
            jsonPath("$.errors[?(@.field == 'email')]") { exists() }
        }
    }
}
```

Deep treatment of slice testing in `test-integration` / `testing-strategy-kotlin-spring`.

## Kotlin specifics

- **`@field:` site-target is non-negotiable** on `data class` properties — covered above; the highest-leverage gotcha in this skill.
- **`data class` for request/response DTOs is idiomatic** — immutable, structural equality, plays well with Jackson + Kotlin module.
- **Nullable types vs `@NotNull`.** Kotlin's `name: String` is already non-null at the type level. Adding `@field:NotNull` isn't redundant — Jackson with lenient deserialisation can produce `null` for a missing JSON field **before** Kotlin's null check fires, producing an opaque `HttpMessageNotReadableException` instead of a clean field error. Keep `@field:NotNull` on non-nullable properties; use `String?` for genuinely optional fields.
- **`@JvmInline value class` wrappers.** Bean Validation does not unwrap value classes — `@field:Min(1)` on a `UserId(val value: Long)` validates the wrapper, not the `Long`. Either validate the raw primitive at the boundary and wrap inside, or write a custom `ConstraintValidator<MyConstraint, UserId>`. Often the right answer is "the value class enforces the invariant in its own constructor".
- **`runCatching` swallows `ConstraintViolationException`.** Common Kotlin pattern, dangerous in a service that should fail loudly. Let it propagate, or pattern-match explicitly.
- **`require(...)` / `check(...)` are not Bean Validation.** Use Bean Validation for input shape at the boundary; use `require(...)` inside aggregate constructors / factories for domain invariants. Different layer, different tool. See `ddd-tactical-patterns`.
- **`kotlin-spring` (`all-open`) plugin** is required for `@Validated` to work via AOP proxy — opens `@RestController` / `@Service` automatically. Without it, CGLIB errors at startup. See `spring-aop`.
- **`@ConfigurationProperties` with `@Validated`.** Typed config validated at startup, not at first request. `@ConfigurationProperties("app.feature")` + `@Validated` + `@field:NotBlank` = boot fails clearly on missing config. Deep treatment in `spring-boot`.

## Related skills

- `spring` — router; cross-cutting principles
- `spring-web-mvc` — `@RestController` wiring, `ProblemDetail` mapping, `@ControllerAdvice` structure
- `spring-aop` — AOP proxy mechanics behind `@Validated`; when method-level validation silently doesn't fire
- `spring-bean` — bean lifecycle; why a non-bean instance can't be `@Validated`
- `spring-boot` — `@ConfigurationProperties` with `@Validated` for startup-time config validation
- `spring-security` — authorisation as a separate concern; validation is not a security check
- `ddd-tactical-patterns` — aggregate invariants via `require(...)` / `check(...)` inside the domain
- `api-design-principles` — `ProblemDetail` (RFC 7807) contract, 400 vs 422 semantics
- `testing-strategy-kotlin-spring`, `test-integration` — `@WebMvcTest` slice; pure-unit `Validator`
- `clean-code-error-handling` — when `ConstraintViolationException` is API contract vs programmer error
- `methodology` — always before code; `methodology-verification` for proving validation actually fires

## Limitations

- Targets Jakarta Validation **3.x** (`jakarta.validation`) on Spring Boot 3+ / Kotlin 2.x / JVM 21+. Pre-Jakarta `javax.validation` works almost identically — one-line import change.
- Doesn't cover the **full Hibernate Validator extension catalogue** beyond `@URL` (`@CreditCardNumber`, `@LuhnCheck`, `@ScriptAssert`) — reach for them only when standard constraints can't express the rule.
- Doesn't cover **reactive validation** in WebFlux, **GraphQL** or **gRPC `protovalidate`** — different ecosystems with their own conventions.
- Assumes Hibernate Validator as JSR-380 provider. Apache BVal works for the API surface but specific behaviours (value-extractor wiring, type-use) may differ.
