# Spring Boot specifics (opt-in)

Load when the project is on Spring Boot. Maps the principles in the body
to the canonical Spring 6 / Boot 3+ wiring.

Stack assumed: Spring Boot 3.x, Spring MVC (WebMVC), Jackson Kotlin module,
optionally `grpc-spring-boot-starter`.

## Concern → default

| Concern | Default |
|---|---|
| REST framework | Spring MVC + `spring-boot-starter-web` |
| gRPC | `net.devh:grpc-spring-boot-starter` + `grpc-kotlin-stub` |
| Error envelope | `org.springframework.http.ProblemDetail` (built into Spring 6) |
| Validation | `jakarta.validation` annotations + `@Valid`; Spring auto-rejects with `400` (`MethodArgumentNotValidException`) |
| Pagination | `org.springframework.data.domain.Pageable` (offset) for small; manual cursor for large |
| Rate limiting | `bucket4j-core` + `OncePerRequestFilter`; back with Redis for clustered deploys |
| OpenAPI | `springdoc-openapi-starter-webmvc-ui` (serves at `/v3/api-docs` + `/swagger-ui.html`) |
| Health | `spring-boot-starter-actuator` — `/actuator/health/liveness` + `/readiness` |
| Metrics | Actuator + `micrometer-registry-prometheus` for `/actuator/prometheus` |

## `ProblemDetail` + global handler

```kotlin
@RestControllerAdvice
class ApiExceptionHandler {

    @ExceptionHandler(NoSuchElementException::class)
    fun handleNotFound(ex: NoSuchElementException): ProblemDetail =
        ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, ex.message ?: "not found").apply {
            type = URI.create("https://errors.example.com/not-found")
            title = "Resource not found"
        }

    @ExceptionHandler(MethodArgumentNotValidException::class)
    fun handleValidation(ex: MethodArgumentNotValidException): ProblemDetail {
        val errors = ex.bindingResult.fieldErrors.map {
            mapOf("field" to it.field, "message" to (it.defaultMessage ?: "invalid"), "rejectedValue" to it.rejectedValue)
        }
        return ProblemDetail.forStatusAndDetail(HttpStatus.UNPROCESSABLE_ENTITY, "validation failed").apply {
            type = URI.create("https://errors.example.com/validation")
            title = "Validation failed"
            setProperty("errors", errors)
        }
    }
}
```

Spring serialises `ProblemDetail` as `application/problem+json` automatically
when the response type is `ProblemDetail`.

## Validation — `@Valid` + jakarta

```kotlin
data class CreateUserRequest(
    @field:Email
    val email: String,
    @field:Size(min = 1, max = 100)
    val name: String,
)

@PostMapping
fun create(@Valid @RequestBody req: CreateUserRequest): UserResponse = ...
```

Failed validation throws `MethodArgumentNotValidException` → handler above
→ `422` with `errors[]`.

Note: Spring's default for `@Valid` failures is `400`. Override to `422` in
the handler — that's the RFC-correct mapping for "parsed fine, business
rules failed".

## Pagination

### Offset (built-in)

```kotlin
@GetMapping
fun list(@PageableDefault(size = 20) pageable: Pageable): Page<UserResponse> =
    service.search(pageable).map { it.toResponse() }
```

Spring picks `page`, `size`, `sort` from query params and applies a default
when missing. Cap `size` at the gateway / filter level — Spring's default
is unbounded.

### Cursor (manual)

```kotlin
@GetMapping
fun list(
    @RequestParam(defaultValue = "20") limit: Int,
    @RequestParam(required = false) cursor: String?,
): CursorPage<UserResponse> {
    require(limit in 1..100)
    return service.listAfter(cursor?.decode(), limit).toResponse()
}
```

Spring Data doesn't ship cursor pagination; write the repository query
yourself (`WHERE id > :lastId ORDER BY id LIMIT :n+1`, then trim the last
to compute `nextCursor`).

## Rate limiting — Bucket4j

```kotlin
@Component
class RateLimitFilter : OncePerRequestFilter() {
    private val buckets = ConcurrentHashMap<String, Bucket>()

    private fun bucketFor(key: String): Bucket = buckets.computeIfAbsent(key) {
        Bucket.builder()
            .addLimit { it.capacity(100).refillGreedy(100, Duration.ofMinutes(1)) }
            .build()
    }

    override fun doFilterInternal(req: HttpServletRequest, res: HttpServletResponse, chain: FilterChain) {
        val probe = bucketFor(req.remoteAddr).tryConsumeAndReturnRemaining(1)
        res.setHeader("X-RateLimit-Limit", "100")
        res.setHeader("X-RateLimit-Remaining", probe.remainingTokens.toString())
        if (probe.isConsumed) chain.doFilter(req, res)
        else {
            res.status = 429
            res.setHeader("Retry-After", (probe.nanosToWaitForRefill / 1_000_000_000).toString())
            res.contentType = "application/problem+json"
            res.writer.write("""{"type":"...","title":"Too many requests","status":429}""")
        }
    }
}
```

For clustered deploys swap `ConcurrentHashMap` for `bucket4j-redis` —
otherwise each pod has its own bucket.

## gRPC — `grpc-spring-boot-starter`

```kotlin
@GrpcService
class UserGrpcService(
    private val userService: UserService,
) : UserServiceGrpcKt.UserServiceCoroutineImplBase() {

    override suspend fun getUser(request: GetUserRequest): User {
        val user = userService.findById(UUID.fromString(request.id))
            ?: throw StatusException(Status.NOT_FOUND.withDescription("user ${request.id} not found"))
        return user.toProto()
    }
}
```

Status mapping via a global `ServerInterceptor` keeps `try/catch` out of
every method.

## ETag + conditional GET

```kotlin
@GetMapping("/{id}")
fun getOne(@PathVariable id: UUID, request: WebRequest): ResponseEntity<UserResponse> {
    val user = service.findById(id) ?: throw NotFoundException(id)
    val etag = "\"${user.version}\""
    if (request.checkNotModified(etag)) return ResponseEntity.status(304).build()
    return ResponseEntity.ok().eTag(etag).body(user.toResponse())
}
```

`WebRequest.checkNotModified` handles `If-None-Match` for you and writes
the response if matched.

## OpenAPI generation

`springdoc-openapi-starter-webmvc-ui` reads your controllers and DTOs
(including `jakarta.validation` annotations) and serves an OpenAPI 3 spec
at `/v3/api-docs`. Augment with `@Operation` / `@ApiResponses` on
controllers for richer docs.

## Actuator — don't write your own `/health`

```yaml
management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics,prometheus
  endpoint:
    health:
      show-details: when-authorized
      probes:
        enabled: true
```

You get `/actuator/health/liveness`, `/actuator/health/readiness`,
`/actuator/info`, `/actuator/metrics`, `/actuator/prometheus`. Custom checks
via `HealthIndicator` beans.
