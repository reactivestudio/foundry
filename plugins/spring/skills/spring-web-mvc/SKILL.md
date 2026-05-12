---
name: spring-web-mvc
description: "Server-side Spring MVC (synchronous, NOT WebFlux) for Kotlin / Spring Boot 3+ services — the `DispatcherServlet` pipeline, `@RestController` and the `@RequestMapping` family, parameter binding (`@PathVariable`, `@RequestParam`, `@RequestBody`, `@RequestHeader`, `@RequestPart`, `MultipartFile`), response shape (`ResponseEntity<T>` vs direct return vs `@ResponseStatus`), `@Valid` validation triggering `MethodArgumentNotValidException` → 400, global exception handling via `@RestControllerAdvice` mapping every domain exception to `ProblemDetail` (RFC 7807), content negotiation with `MediaType` constants, the filter-vs-interceptor decision (servlet `Filter` for transport-level, `HandlerInterceptor` for handler-aware), CORS via `@CrossOrigin` or global `WebMvcConfigurer.addCorsMappings(...)`, `WebMvcConfigurer` extension points, custom `HandlerMethodArgumentResolver` for typed tenant / current-user injection, async return types (`Callable<T>` / `CompletableFuture<T>` / `StreamingResponseBody` / `SseEmitter`), and Kotlin specifics (`data class` DTOs, default arguments, `suspend fun` controllers, sealed response types). Use when defining or refactoring controllers, designing an error-handling advice, picking between filter and interceptor, wiring CORS, customising the MVC layer, or debugging 400 / 415 / 422 and `ProblemDetail` shape. Outbound HTTP lives in `spring-rest-clients`; auth filter chain in `spring-security`; deep validation in `spring-validation`; REST contract design in `api-design-principles`."
risk: safe
source: "custom — Spring Web MVC (sync) for Kotlin / Spring Boot 3+"
date_added: "2026-05-12"
---

# Spring Web MVC (Kotlin / Spring Boot 3+)

> Spring MVC is a request pipeline. Every annotation on a controller is metadata that some stage of the pipeline reads. Knowing the pipeline is the difference between "Spring magically returns JSON" and "I can debug a 415 in two minutes."

## Use this skill when

- Writing a new `@RestController` — picking mappings, binding parameters, shaping the response
- Designing the error surface: one `@RestControllerAdvice` mapping domain exceptions to `ProblemDetail`
- Choosing `ResponseEntity<T>` vs returning the body directly vs `@ResponseStatus`
- Wiring `@Valid` on `@RequestBody` and handling `MethodArgumentNotValidException`
- Deciding between a servlet `Filter` and a Spring MVC `HandlerInterceptor` for cross-cutting work
- Configuring CORS — per-controller `@CrossOrigin` or global `WebMvcConfigurer.addCorsMappings(...)`
- Customising the MVC layer through `WebMvcConfigurer` — argument resolvers, message converters, interceptors, formatters
- Writing a custom `HandlerMethodArgumentResolver` to inject a typed `TenantContext` / current-user DTO
- Debugging 400 vs 415 vs 422, empty `ProblemDetail` bodies, "why isn't this content-type matched", or wrong status codes on validation failures
- Streaming a large response, serving a file, or pushing SSE events from a controller

## Do not use this skill when

- The task is **outbound HTTP** — `RestClient` (Boot 3.2+), `RestTemplate`, `WebClient`, `HttpExchange`, OpenFeign — that's `spring-rest-clients`. This skill is server-side only.
- The task is **WebFlux / reactive** — `Mono<T>` / `Flux<T>` controllers, R2DBC. Out of scope here. Brief decision: WebMVC is the default for Boot 3+; virtual threads (`spring.threads.virtual.enabled: true` on JVM 21) close most of the reactive-throughput gap with imperative ergonomics. Full WebMVC-vs-WebFlux framing lives in `architecture`.
- The task is **the Spring Security filter chain, JWT validation, `@PreAuthorize`** — that's `spring-security`. The MVC filter / interceptor split here is for non-security cross-cutting work.
- The task is **deep Bean Validation** — `@Valid` groups, custom constraints, `ConstraintValidator` — that's `spring-validation`. This skill points at `MethodArgumentNotValidException` → `ProblemDetail` and stops.
- The task is **`@Transactional` discipline** — propagation, isolation, the AOP proxy gotchas. The rule "no `@Transactional` on controllers" lives here as an anti-pattern; the depth lives in `spring-transactions`.
- The task is **REST contract design** — resource modelling, status codes as semantics, idempotency keys, versioning strategy, pagination shape (offset vs cursor), `ProblemDetail` `type` URIs as a vocabulary — that's `api-design-principles`. This skill is the Spring-side wiring of contracts that `api-design-principles` defines.
- The task is **module layout, ArchUnit rules, Spring Modulith boundaries** — that's `architecture-patterns` / `spring-modulith` / `test-architecture`.

## Core principles

1. **The controller is a thin translation layer.** Convert HTTP → domain command, call one service, convert domain result → HTTP response. No business logic. No `@Transactional`. No JPA entities crossing the boundary.
2. **One error format across the surface — `ProblemDetail` (RFC 7807).** All `4xx` / `5xx` responses share the same JSON shape: `type` / `title` / `status` / `detail` / `instance` + extensions. Different shapes per endpoint multiply client complexity.
3. **One `@RestControllerAdvice` per service.** Every domain exception is mapped there to a `ProblemDetail`. Controllers don't `try { ... } catch (e) { return 400 }`. If a controller catches a business exception, the advice is incomplete.
4. **Status codes mean what they say.** `2xx` only when the operation succeeded. `4xx` only when the caller can fix the request. `5xx` only when the server failed. Never `200 OK` with `{"error": ...}` — that breaks every generic HTTP client. See `api-design-principles`.
5. **Use `MediaType` constants, not strings.** `MediaType.APPLICATION_JSON_VALUE` over `"application/json"`. Typo-proof, IDE-navigable, refactor-safe.
6. **Validate at the boundary.** `@Valid @RequestBody Foo` and `@Validated` on controllers for path / query bind validation. Bad input becomes a `400` automatically — let Spring do its job.
7. **Filter for transport-level concerns, interceptor for handler-aware concerns.** Filter sees the raw servlet request before MVC dispatch. Interceptor sees the resolved handler method and can introspect annotations on it. Pick by what information you actually need.

## The request pipeline (servlet stack)

Once a request enters Tomcat:

```
HTTP request
  ↓
[Servlet filter chain]                 ← jakarta.servlet.Filter — pre-DispatcherServlet
  ↓ (Spring Security filter chain lives here too — see spring-security)
DispatcherServlet
  ↓
HandlerMapping                         ← URL → controller method (HandlerMethod)
  ↓
HandlerInterceptor#preHandle           ← can short-circuit here
  ↓
HandlerAdapter (RequestMappingHandlerAdapter)
  ↓
ArgumentResolvers                      ← @PathVariable, @RequestParam, @RequestBody, custom resolvers
  ↓
Controller method invocation
  ↓
ReturnValueHandlers                    ← ResponseEntity<T> / @ResponseBody / @ResponseStatus / async types
  ↓
HttpMessageConverter (Jackson)         ← Kotlin object → JSON
  ↓
HandlerInterceptor#postHandle (before render) / afterCompletion (after)
  ↓
HTTP response
```

Every annotation on a controller is a hook into one of those stages. `@RequestMapping` registers with the handler mapping. `@PathVariable` is read by an argument resolver. `@ResponseStatus` is read by a return-value handler. `HttpMessageConverter` does the JSON. When something feels "magical", it's almost always one specific stage you can name.

## `@RestController` and the mapping shortcuts

`@Controller` is the original handler stereotype — methods return view names by default (Thymeleaf, JSP). For an API service, you want JSON, which means `@ResponseBody` on every return value. `@RestController` is the shortcut:

```kotlin
@RestController                              // = @Controller + @ResponseBody on every method
@RequestMapping("/api/v1/orders")            // class-level prefix, supports versioning
class OrderController(
    private val orders: OrderService,        // constructor injection — no field @Autowired
)
```

Reach for plain `@Controller` only for templated HTML, error pages, or Spring MVC view tech (rare in modern API services).

The HTTP-method shortcuts are sugar over `@RequestMapping(method = ...)`:

| Shortcut | Equivalent to |
|---|---|
| `@GetMapping("/{id}")` | `@RequestMapping(value = "/{id}", method = [GET])` |
| `@PostMapping` | `… method = [POST]` |
| `@PutMapping` | `… method = [PUT]` |
| `@PatchMapping` | `… method = [PATCH]` |
| `@DeleteMapping` | `… method = [DELETE]` |

URI templates use `{var}` for path parameters; `**` is a path wildcard (avoid for API endpoints — too permissive). `consumes` / `produces` constrain content negotiation:

```kotlin
@PostMapping(
    consumes = [MediaType.APPLICATION_JSON_VALUE],
    produces = [MediaType.APPLICATION_JSON_VALUE],
)
fun create(@Valid @RequestBody req: CreateOrderRequest): ResponseEntity<OrderResponse> = ...
```

Versioning lives at the class-level `@RequestMapping("/api/v1/...")`. The full versioning strategy (URL prefix vs `Accept` header) belongs to `api-design-principles`.

## Parameter binding

| Annotation | Source | Notes |
|---|---|---|
| `@PathVariable` | URI template variable | `@PathVariable id: OrderId` — name inferred from parameter when the same |
| `@RequestParam` | Query string or form field | `required = true` by default; pair with `defaultValue` or use a Kotlin default arg |
| `@RequestBody` | Deserialised payload (Jackson) | One per method; combine with `@Valid` for validation |
| `@RequestHeader` | A single HTTP header | `@RequestHeader(HttpHeaders.IF_MATCH) etag: String?` |
| `@CookieValue` | A single cookie | Rare on JWT-stateless APIs |
| `@ModelAttribute` | Form fields / query bound onto a Kotlin object | For HTML forms; uncommon in JSON APIs |
| `@RequestPart` | A part of a `multipart/form-data` payload | Pair with `MultipartFile` for files |
| `MultipartFile` | A single uploaded file | Spring auto-resolves; cap via `spring.servlet.multipart.max-file-size` |
| `HttpServletRequest` / `HttpServletResponse` | The raw servlet API | Escape hatch — prefer typed alternatives |
| `Principal` / `Authentication` | The authenticated user (if any) | Spring Security populates this |
| `Locale` / `TimeZone` | Resolved from `Accept-Language` / session | For i18n |

For `@RequestParam`, Kotlin default arguments are cleaner than `defaultValue`:

```kotlin
@GetMapping
fun list(
    @RequestParam pageSize: Int = 20,     // Kotlin default — no defaultValue string needed
    @RequestParam cursor: String? = null, // nullable + default null = optional
): PageResponse<OrderResponse> = ...
```

`@RequestParam(required = false) String x` without `defaultValue` gives you a `null` and a footgun. Make the type `String?` explicitly and use `null` as the default — the Kotlin type system catches the missing check.

## Response shape

Three forms in increasing order of control:

```kotlin
// 1) Return the body directly — 200 OK by default
@GetMapping("/{id}")
fun get(@PathVariable id: OrderId): OrderResponse = orders.get(id).toResponse()

// 2) @ResponseStatus for a static status code that isn't 200
@PostMapping
@ResponseStatus(HttpStatus.CREATED)
fun create(@Valid @RequestBody req: CreateOrderRequest): OrderResponse = orders.create(req).toResponse()

// 3) ResponseEntity<T> for status + headers + body, dynamic per call
@PostMapping
fun create(@Valid @RequestBody req: CreateOrderRequest): ResponseEntity<OrderResponse> {
    val order = orders.create(req)
    val location = URI.create("/api/v1/orders/${order.id}")
    return ResponseEntity.created(location).body(order.toResponse())
}
```

Rules of thumb:
- Plain object return + (optional) `@ResponseStatus` — simplest, the right default for `GET` / `PUT` / `DELETE`.
- `ResponseEntity<T>` — when you need `Location`, `ETag`, conditional status, or a `204 No Content` with no body.
- `Unit` / `void` return → `200 OK` with empty body. Use `@ResponseStatus(HttpStatus.NO_CONTENT)` if you mean 204.

Don't mix `ResponseEntity` and direct returns inconsistently across one controller. Pick a default and stick with it; deviate when there's a reason.

## Minimal `@RestController` end-to-end

```kotlin
@RestController
@RequestMapping("/api/v1/orders")
class OrderController(
    private val orders: OrderService,
) {
    @PostMapping(
        consumes = [MediaType.APPLICATION_JSON_VALUE],
        produces = [MediaType.APPLICATION_JSON_VALUE],
    )
    fun create(@Valid @RequestBody req: CreateOrderRequest): ResponseEntity<OrderResponse> {
        val placed = orders.place(req.toCommand())
        val location = URI.create("/api/v1/orders/${placed.id}")
        return ResponseEntity.created(location).body(placed.toResponse())
    }

    @GetMapping("/{id}", produces = [MediaType.APPLICATION_JSON_VALUE])
    fun get(@PathVariable id: OrderId): OrderResponse = orders.get(id).toResponse()
}

data class CreateOrderRequest(
    @field:NotBlank val customer: String,
    @field:Positive val amountMinor: Long,
    @field:Size(min = 3, max = 3) val currency: String,
)

data class OrderResponse(
    val id: OrderId,
    val customer: String,
    val amountMinor: Long,
    val currency: String,
    val placedAt: Instant,
)
```

`@Valid` triggers Bean Validation; a violation raises `MethodArgumentNotValidException` before the controller body runs. The advice (next section) turns that into a `400` with field-level detail.

## `ProblemDetail` + `@RestControllerAdvice`

Spring 6 ships `org.springframework.http.ProblemDetail` (RFC 7807) — use it for every error response. One `@RestControllerAdvice` per service maps every domain exception:

```kotlin
@RestControllerAdvice                                          // = @ControllerAdvice + @ResponseBody
class ApiExceptionHandler {

    @ExceptionHandler(IllegalArgumentException::class)
    fun handleIllegalArgument(e: IllegalArgumentException): ProblemDetail =
        ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, e.message ?: "Invalid request").apply {
            title = "Invalid request"
            type = URI.create("https://errors.example.com/invalid-request")
        }

    @ExceptionHandler(NoSuchElementException::class)
    fun handleNotFound(e: NoSuchElementException): ProblemDetail =
        ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, e.message ?: "Resource not found").apply {
            title = "Not found"
            type = URI.create("https://errors.example.com/not-found")
        }

    @ExceptionHandler(MethodArgumentNotValidException::class)
    fun handleValidation(e: MethodArgumentNotValidException): ProblemDetail =
        ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, "Validation failed").apply {
            title = "Validation failed"
            type = URI.create("https://errors.example.com/validation")
            setProperty("violations", e.bindingResult.fieldErrors.map {
                mapOf("field" to it.field, "message" to it.defaultMessage)
            })
        }

    @ExceptionHandler(Exception::class)                        // last-resort fallback
    fun handleUnexpected(e: Exception): ProblemDetail =
        ProblemDetail.forStatusAndDetail(HttpStatus.INTERNAL_SERVER_ERROR, "Unexpected error").apply {
            title = "Internal server error"
            // do NOT echo e.message — that's information disclosure
        }
}
```

Things to know:
- **`@RestControllerAdvice` vs `@ControllerAdvice`.** The former adds `@ResponseBody` to every handler — what you want for JSON APIs. Use `@ControllerAdvice` only for view-returning apps.
- **One advice or several?** Most services live happily with one. Split by package or annotation only when you have a real reason (e.g. an admin module with different error shapes); order with `@Order` if it matters.
- **`ProblemDetail.forStatus(...)`** for a bare status without detail; **`ProblemDetail.forStatusAndDetail(...)`** to include a human-readable `detail`. Add `title`, `type`, and custom extensions via `setProperty(...)`.
- **`type` is a URI vocabulary**, not a free-text field. Pick a stable namespace and document each value — clients dispatch on `type`. Cross-ref `api-design-principles`.
- **Don't echo raw exception messages** for the catch-all `Exception` handler — that's an information-disclosure footgun. Log the exception with trace context; return a generic body with the trace ID.
- **Spring's built-in handlers.** `ResponseEntityExceptionHandler` (the abstract base) handles `MethodArgumentNotValidException`, `HttpMessageNotReadableException`, `HttpMediaTypeNotSupportedException`, `MissingServletRequestParameterException`, and friends out of the box — extend it if you want to keep the built-in mapping and only override specific cases.

## Filter vs Interceptor

Both run cross-cutting code around requests; they live at different layers.

| Aspect | Servlet `Filter` | `HandlerInterceptor` |
|---|---|---|
| Stage | Before `DispatcherServlet` | Inside `DispatcherServlet`, around the handler method |
| API | `jakarta.servlet.Filter` | `org.springframework.web.servlet.HandlerInterceptor` |
| Sees the request body | Yes (raw `HttpServletRequest`) | Yes (already parsed; body has been consumed by the time `preHandle` runs in most cases) |
| Sees the resolved handler | No | Yes — the `Object handler` is a `HandlerMethod` you can introspect (controller method, annotations on it) |
| Can short-circuit | Yes (don't call `chain.doFilter`) | Yes (`preHandle` returns `false`) |
| Ordering | `@Order` / `FilterRegistrationBean.order` | `WebMvcConfigurer.addInterceptors(...)` registration order or `@Order` |
| Use for | Transport-level: logging, MDC, trace context, CORS, tenant resolution from header, request-size limits | Handler-aware: per-annotation behaviour, rate limit by controller method, audit specific endpoints |

Rule of thumb: **filter** for things that apply to every request regardless of which handler it hits (logging, MDC, security). **Interceptor** when you need to know *which controller method* is about to run and decide based on its annotations.

Register filters as `@Component` (auto-picked up by Boot) or via a `FilterRegistrationBean<T>` when you need explicit URL patterns or order. `OncePerRequestFilter` is the helper base — guarantees the filter runs once per request even across forwards / async dispatches. Use `Ordered.HIGHEST_PRECEDENCE + N` (low values) for filters that should run early; security filters typically claim the highest priorities.

### Interceptor example — tenant resolution from `@RequestMapping` annotation

```kotlin
@Component
class TenantInterceptor(
    private val tenants: TenantResolver,
    private val context: RequestContext,                       // request-scoped bean
) : HandlerInterceptor {
    override fun preHandle(
        request: HttpServletRequest,
        response: HttpServletResponse,
        handler: Any,
    ): Boolean {
        // Only act on real controller methods (skip static resources)
        if (handler !is HandlerMethod) return true

        // Introspect the controller method's annotations
        val multiTenant = handler.getMethodAnnotation(MultiTenant::class.java)
        if (multiTenant != null) {
            val tenantId = request.getHeader("X-Tenant-Id")
                ?: throw IllegalArgumentException("X-Tenant-Id required")
            context.tenantId = tenants.resolve(tenantId)
        }
        return true
    }
}

@Configuration
class WebMvcConfig(
    private val tenantInterceptor: TenantInterceptor,
) : WebMvcConfigurer {
    override fun addInterceptors(registry: InterceptorRegistry) {
        registry.addInterceptor(tenantInterceptor)
            .addPathPatterns("/api/**")
    }
}
```

The interceptor reads a custom `@MultiTenant` annotation on the controller method — exactly the kind of thing a servlet filter can't easily do, because filters don't have the resolved `HandlerMethod`.

## CORS

Two scopes, pick by surface:

### Per-controller / per-method

```kotlin
@RestController
@RequestMapping("/api/v1/public")
@CrossOrigin(
    origins = ["https://app.example.com"],
    methods = [RequestMethod.GET, RequestMethod.POST],
    maxAge = 3600,
)
class PublicController(...)
```

### Global

```kotlin
@Configuration
class CorsConfig : WebMvcConfigurer {
    override fun addCorsMappings(registry: CorsRegistry) {
        registry.addMapping("/api/**")
            .allowedOrigins("https://app.example.com")
            .allowedMethods("GET", "POST", "PUT", "DELETE", "PATCH")
            .allowedHeaders("*")
            .allowCredentials(true)
            .maxAge(3600)
    }
}
```

Production rules:
- **No `*` for `allowedOrigins`** when `allowCredentials = true` — the browser rejects it. List explicit origins.
- **Coordinate with `spring-security`.** Security 6's `http.cors(Customizer.withDefaults())` reads the `CorsConfigurationSource` bean — without it, security filters block pre-flight `OPTIONS` requests.
- **CORS is browser-only.** Server-to-server callers ignore it. Don't rely on CORS as authorisation; that's `spring-security`'s job.

## `WebMvcConfigurer` — the customisation seam

`WebMvcConfigurer` is the override point for the MVC layer. Implement what you need; everything else inherits sensible defaults.

| Method | What you customise |
|---|---|
| `addInterceptors(InterceptorRegistry)` | Register `HandlerInterceptor`s with path patterns |
| `addCorsMappings(CorsRegistry)` | Global CORS rules |
| `addArgumentResolvers(MutableList<HandlerMethodArgumentResolver>)` | Inject custom domain types into controller parameters |
| `addReturnValueHandlers(MutableList<HandlerMethodReturnValueHandler>)` | Render custom return types (rare) |
| `configureMessageConverters(MutableList<HttpMessageConverter<*>>)` | Replace the converter list (also rare — usually you contribute to it) |
| `extendMessageConverters(MutableList<HttpMessageConverter<*>>)` | Add or reorder converters on top of defaults — the right hook in 99% of cases |
| `addFormatters(FormatterRegistry)` | Register `Converter<S, T>` / `Formatter<T>` for path / query binding (e.g. `String` → `TenantId`) |
| `configureContentNegotiation(ContentNegotiationConfigurer)` | Tune `Accept` header handling, default media type |
| `addResourceHandlers(ResourceHandlerRegistry)` | Static resources (rare in API services — typically the gateway / CDN does this) |

Do not extend `WebMvcConfigurationSupport` or annotate `@EnableWebMvc` in a Boot app — both disable Boot's `WebMvcAutoConfiguration` and you lose every sensible default (Jackson registration, message converters, validation, error handling). Implement `WebMvcConfigurer` instead.

## Custom argument resolver — typed domain context

Instead of reading `HttpServletRequest` headers from every controller method, surface a typed parameter that the framework populates:

```kotlin
// Marker annotation on the parameter
@Target(AnnotationTarget.VALUE_PARAMETER)
@Retention(AnnotationRetention.RUNTIME)
annotation class CurrentTenant

// Resolver
@Component
class CurrentTenantResolver(
    private val tenants: TenantResolver,
) : HandlerMethodArgumentResolver {

    override fun supportsParameter(parameter: MethodParameter): Boolean =
        parameter.hasParameterAnnotation(CurrentTenant::class.java) &&
            parameter.parameterType == TenantContext::class.java

    override fun resolveArgument(
        parameter: MethodParameter,
        mavContainer: ModelAndViewContainer?,
        webRequest: NativeWebRequest,
        binderFactory: WebDataBinderFactory?,
    ): TenantContext {
        val header = webRequest.getHeader("X-Tenant-Id")
            ?: throw IllegalArgumentException("X-Tenant-Id required")
        return tenants.resolve(header)
    }
}

// Registration
@Configuration
class WebMvcConfig(
    private val currentTenantResolver: CurrentTenantResolver,
) : WebMvcConfigurer {
    override fun addArgumentResolvers(resolvers: MutableList<HandlerMethodArgumentResolver>) {
        resolvers.add(currentTenantResolver)
    }
}

// Use
@GetMapping("/orders")
fun list(@CurrentTenant tenant: TenantContext): List<OrderResponse> =
    orders.listFor(tenant.id).map { it.toResponse() }
```

Same pattern works for a typed `CurrentUser` derived from a JWT, a `RequestMetadata` aggregate, anything domain-shaped. Replaces dozens of `request.getHeader(...)` calls with one declarative parameter.

## Async and streaming, briefly

A controller method can return an async type to free the servlet thread while work proceeds: `Callable<T>` (Spring submits to a managed executor), `DeferredResult<T>` (app resolves from elsewhere), `CompletableFuture<T>` (compose with downstream async). For streaming: `StreamingResponseBody` (write bytes over time), `SseEmitter` (server-sent events on a long-lived connection), `ResponseEntity<Resource>` (file download with `Content-Disposition`). Rare in CRUD; useful for long-running exports, file downloads, SSE notifications. With virtual threads enabled, the throughput motivation drops further — the servlet thread is cheap. See `spring-async` for the executor side.

## Anti-patterns

| Anti-pattern | Why it's wrong | Fix |
|---|---|---|
| Returning JPA entities directly | Persistence shape leaks into the contract; refactors break clients | Explicit `*Response` DTOs — see `clean-code-boundaries`, `hibernate` |
| `200 OK` with `{"error": "..."}` body | Generic HTTP clients can't tell success from failure | Use the right `4xx` / `5xx` + `ProblemDetail` |
| `@Transactional` on the controller | Wrong layer; couples HTTP to persistence | Move to the service; see `spring-transactions` |
| `try { ... } catch (e: BusinessException) { ... }` in every handler | Duplicates error logic across the surface | One `@RestControllerAdvice` mapping to `ProblemDetail` |
| Mixing `ResponseEntity` and direct returns randomly in one controller | Readers can't tell which case is which | Pick a default; deviate with intent |
| `@RequestParam(required = false) String x` without `defaultValue` | Gives `null`; null-check forgotten | `String? = null` with a Kotlin default + explicit handling |
| `"application/json"` literal strings | Typos compile but fail at runtime | `MediaType.APPLICATION_JSON_VALUE` |
| Swallowing exceptions in the controller body | Hides real errors; advice can't see them | Let them propagate |
| Echoing raw exception messages in the catch-all handler | Information disclosure (SQL fragments, file paths, stack traces) | Log with trace ID; return generic `ProblemDetail` |
| `@EnableWebMvc` in a Boot app | Disables `WebMvcAutoConfiguration` — Jackson, converters, validation lost | Use `WebMvcConfigurer` instead |
| Filter introspecting `HandlerMethod` annotations | Filters don't have the resolved handler — you'll fish around the URL string | Use a `HandlerInterceptor` |
| Interceptor reading the request body | Body is single-read; downstream resolvers see empty | Wrap with `ContentCachingRequestWrapper` |
| `*` in `allowedOrigins` with `allowCredentials = true` | Browser rejects pre-flight | Explicit origin list |
| Custom error format alongside `ProblemDetail` per endpoint | Two error shapes = double the client code | One shape — `ProblemDetail` |
| Trailing-slash inconsistency (`/orders` vs `/orders/`) | Spring Boot 3 removed implicit trailing-slash matching; one returns 404 | Pick one convention service-wide |

## Kotlin specifics

- **`data class` for request and response DTOs** is the standard. Immutable, structural equality, `copy(...)`, automatic Jackson deserialisation via the Kotlin module (auto-registered in Boot).
- **Default arguments over `defaultValue`.** Idiomatic Kotlin; one less Spring-specific incantation.
- **`Unit` return → empty body, 200 OK** unless you add `@ResponseStatus(HttpStatus.NO_CONTENT)`. Don't use `Void` / `Nothing?` — `Unit` is the native idiom.
- **`suspend fun` controllers** are supported in Spring 6. The method runs on the request thread by default (or a virtual thread if `spring.threads.virtual.enabled: true`). Useful when calling `suspend` services; don't `runBlocking` from a sync controller.
- **`@JvmInline value class`** for `OrderId` / `TenantId` path or query parameters works with a `Converter<String, OrderId>` registered via `WebMvcConfigurer.addFormatters(...)`.
- **Sealed response hierarchies** with polymorphic Jackson via `@JsonTypeInfo` + `@JsonSubTypes` work where the client needs a discriminator. Add an explicit `type: String` — exhaustive `when` in code, exhaustive dispatch on the client.
- **`Result<T>` / `runCatching` translation** at the controller boundary — turn a domain `Result.failure(e)` into a thrown exception the advice maps to `ProblemDetail`. Don't return `Result` from a controller. See `clean-code-boundaries`, `clean-code-error-handling`.
- **`kotlin-spring` (`all-open`) plugin** is mandatory — `@RestController` classes must be open for Spring AOP proxies. Boot's plugin opens them automatically.

## Observability and testing pointers

- **Metrics:** `/actuator/metrics/http.server.requests` — count, latency, status, URI template. Tag cardinality matters; see `spring-actuator`.
- **Tracing:** flows in automatically with Observation API + Micrometer Tracing on the classpath; `traceId` lands in MDC for log correlation.
- **`@WebMvcTest`** is the controller test slice — boots `DispatcherServlet`, the controller, `@RestControllerAdvice`, Jackson, validation. Use `MockMvc` (Kotlin DSL). See `test-integration`, `testing-strategy-kotlin-spring`.

## Related skills

- `spring` — router; cross-cutting Spring principles, the family map
- `spring-bean` — `@RestController` is a `@Component`; constructor injection
- `spring-boot` — Boot 3+ specifics; `application.yml` for `spring.servlet.multipart.*`, `spring.threads.virtual.enabled`, `spring.mvc.*`
- `spring-aop` — proxies behind `@RestControllerAdvice`; `kotlin-spring` `all-open` plugin
- `spring-events` — domain events published from a service the controller calls; never from the controller itself
- `spring-validation` — `@Valid` / `@Validated`, custom constraints, validation groups
- `spring-actuator` — `/actuator/metrics/http.server.requests`, observation, trace context
- `spring-modulith` — controllers live in the inbound adapter of one module
- `spring-rest-clients` — outbound HTTP (`RestClient`, `WebClient`, `RestTemplate`, OpenFeign)
- `spring-data-jpa`, `hibernate` — never return entities from a controller
- `spring-transactions` — `@Transactional` on the service, never on the controller
- `spring-async` — `@Async`, virtual threads, executor sizing for async return types
- `spring-scheduler` — `@Scheduled`; not a controller concern but the related cross-cutting executor
- `spring-amqp` — RabbitMQ inbound port; same controller-thin-translation principle
- `spring-cache` — HTTP caching headers (`ETag`, `Cache-Control`) on the controller side
- `spring-security` — `SecurityFilterChain`, `@PreAuthorize`, `Principal` injection, CORS coordination
- `api-design-principles` — the REST contract this skill wires up
- `testing-strategy-kotlin-spring`, `test-integration` — `@WebMvcTest`, `MockMvc` Kotlin DSL
- `methodology`, `methodology-verification`, `methodology-clarifying-questions` — process discipline
- `karpathy-guidelines` — the always-on coding discipline
- `clean-code-boundaries` — keep `HttpServletRequest` / `Pageable` / JPA types on the controller side of the seam
- `clean-code-error-handling` — exception-class design behind the `@RestControllerAdvice` mapping

## Limitations

- Targets Spring Boot **3+** on Kotlin 2.x / JVM 21+. Boot 2.x users will find most of this applicable but specific APIs (`ProblemDetail`, virtual threads, trailing-slash matching defaults, `RestClient`) differ.
- **WebFlux / reactive** is intentionally out of scope. For the WebMVC-vs-WebFlux decision, see `architecture`; the brief answer is "WebMVC + virtual threads on JVM 21 covers most needs."
- Doesn't cover the **full Spring Security filter chain** — `spring-security` owns it. The mention here is only the filter-vs-interceptor decision and CORS coordination.
- Doesn't cover **HATEOAS** (`spring-hateoas`), **GraphQL** (`spring-graphql`), **server-side templating** (Thymeleaf, JSP, FreeMarker) — out of scope for an API-service skill.
- Doesn't cover **OpenAPI generation** in depth (`springdoc-openapi`) — the contract side belongs to `api-design-principles`; the generator is one Boot starter away.
- WebSocket / STOMP support exists in Spring MVC but is not covered here — when it becomes a real use case it deserves its own skill.
