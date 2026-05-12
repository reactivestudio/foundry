# REST API Best Practices

Deep-dive REST checklist. Stack: **Kotlin + Spring Boot + Spring MVC**.

## URL Structure

### Resource naming

```
# Good — plural nouns, kebab-case for multi-word resources
GET /api/users
GET /api/orders
GET /api/order-items

# Bad — verbs, inconsistent number
GET /api/getUser
GET /api/user                 # inconsistent singular
POST /api/createOrder
```

### Nested resources

```
# Shallow nesting — preferred
GET /api/users/{id}/orders
GET /api/orders/{id}

# Deep nesting — avoid
GET /api/users/{id}/orders/{orderId}/items/{itemId}/reviews
# Better — flatten:
GET /api/order-items/{id}/reviews
```

Rule of thumb: at most one level of nesting in the URL. If you need more, the deeper resource has its own identity and should live at the root.

---

## HTTP Methods and Status Codes

### GET — retrieve

```
GET /api/users              → 200 OK (list)
GET /api/users/{id}         → 200 OK or 404 Not Found
GET /api/users?page=2       → 200 OK (paginated)
```

### POST — create / non-idempotent action

```
POST /api/users
  Body: {"name":"John","email":"john@example.com"}
  → 201 Created
  Location: /api/users/123
  Body: {"id":"123","name":"John",…}

POST /api/users (validation failure)
  → 422 Unprocessable Entity
  Body: ProblemDetail with errors[]
```

### PUT — replace

```
PUT /api/users/{id}
  Body: {complete user object}
  → 200 OK (updated)
  → 404 Not Found
```

Must include the **entire** resource — semantics are "replace".

### PATCH — partial update

```
PATCH /api/users/{id}
  Content-Type: application/merge-patch+json
  Body: {"name":"Jane"}
  → 200 OK
  → 404 Not Found
```

Prefer JSON Merge Patch (RFC 7396) for simple cases, JSON Patch (RFC 6902) for complex array manipulation.

### DELETE — remove

```
DELETE /api/users/{id}
  → 204 No Content
  → 404 Not Found
  → 409 Conflict   (e.g. has dependent orders, soft-delete blocked)
```

---

## Filtering, Sorting, Searching

### Query parameters

```
# Filtering
GET /api/users?status=active
GET /api/users?role=admin&status=active

# Sorting (Spring Data idiom: ?sort=field,direction)
GET /api/users?sort=createdAt,desc
GET /api/users?sort=name,asc&sort=createdAt,desc

# Searching
GET /api/users?search=john
GET /api/users?q=john

# Sparse fieldsets (rarely needed if responses are tight)
GET /api/users?fields=id,name,email
```

Spring Data's `Pageable` resolver picks up `page`, `size`, and `sort` parameters automatically.

---

## Pagination Patterns

### Offset-based (default, small datasets)

```
GET /api/users?page=0&size=20

200 OK
{
  "items": [...],
  "page": 0,
  "pageSize": 20,
  "total": 150,
  "pages": 8
}
```

### Cursor-based (large/append-mostly datasets)

```
GET /api/users?limit=20&cursor=eyJpZCI6MTIzfQ

200 OK
{
  "items": [...],
  "nextCursor": "eyJpZCI6MTQzfQ",
  "hasMore": true
}
```

Cursors should be opaque base64-encoded (typically `{ "lastId": ..., "lastSortKey": ... }` JSON). Never let clients craft cursors themselves.

### Link Header pagination (truly RESTful)

```
GET /api/users?page=2

Response headers:
Link: <https://api.example.com/users?page=3>; rel="next",
      <https://api.example.com/users?page=1>; rel="prev",
      <https://api.example.com/users?page=1>; rel="first",
      <https://api.example.com/users?page=8>; rel="last"
```

Body stays clean, navigation is in headers. Used by GitHub's API.

---

## Versioning Strategies

### URL versioning (recommended for public REST)

```
/api/v1/users
/api/v2/users
```

Pros: visible, easy to route, easy to debug. Cons: multiple URLs per resource.

### Header versioning

```
GET /api/users
Accept: application/vnd.api+json; version=2
```

Pros: clean URLs. Cons: invisible, harder to test in a browser/curl.

### Query parameter

```
GET /api/users?version=2
```

Pros: trivial to test. Cons: easy to forget and fall back to default.

**Recommendation:** URL versioning by default. Header versioning only when you control all clients and care deeply about clean URLs.

---

## Rate Limiting

### Response headers (de-facto standard)

```
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 742
X-RateLimit-Reset: 1640000000

# When throttled
429 Too Many Requests
Retry-After: 60
```

### Spring implementation with Bucket4j

```kotlin
// build.gradle.kts:
// implementation("com.bucket4j:bucket4j-core:8.10.1")

@Component
class RateLimitFilter(
    private val buckets: ConcurrentHashMap<String, Bucket> = ConcurrentHashMap(),
) : OncePerRequestFilter() {

    private fun bucketFor(key: String): Bucket = buckets.computeIfAbsent(key) {
        Bucket.builder()
            .addLimit { limit ->
                limit.capacity(100).refillGreedy(100, Duration.ofMinutes(1))
            }
            .build()
    }

    override fun doFilterInternal(
        req: HttpServletRequest,
        res: HttpServletResponse,
        chain: FilterChain,
    ) {
        val key = req.remoteAddr // or principal, or API key
        val bucket = bucketFor(key)
        val probe = bucket.tryConsumeAndReturnRemaining(1)

        res.setHeader("X-RateLimit-Limit", "100")
        res.setHeader("X-RateLimit-Remaining", probe.remainingTokens.toString())

        if (probe.isConsumed) {
            chain.doFilter(req, res)
        } else {
            res.status = HttpStatus.TOO_MANY_REQUESTS.value()
            res.setHeader("Retry-After", (probe.nanosToWaitForRefill / 1_000_000_000).toString())
            res.writer.write("""{"type":"https://errors.example.com/rate-limit","title":"Too many requests"}""")
        }
    }
}
```

For distributed deployments, back the buckets with Redis (`bucket4j-redis`) instead of an in-memory `ConcurrentHashMap`.

---

## Authentication and Authorization

### Bearer token

```
Authorization: Bearer eyJhbGciOiJIUzI1NiIs...

401 Unauthorized  — missing/invalid token
403 Forbidden     — token valid, permissions insufficient
```

### API keys (server-to-server)

```
X-API-Key: your-api-key-here
```

Wire both through Spring Security. Never roll your own.

---

## Error Response Format — `ProblemDetail` (RFC 7807)

### Consistent structure

```json
{
  "type": "https://errors.example.com/validation",
  "title": "Validation failed",
  "status": 422,
  "detail": "Request validation failed",
  "instance": "/api/users",
  "errors": [
    { "field": "email", "message": "invalid format", "rejectedValue": "not-an-email" }
  ]
}
```

Use Spring's built-in `org.springframework.http.ProblemDetail` — don't invent a custom envelope.

### Status code guidelines

| Code | Use for |
|---|---|
| `200 OK` | Successful `GET`, `PATCH`, `PUT` |
| `201 Created` | Successful `POST` creating a resource |
| `202 Accepted` | Async work queued, not yet done |
| `204 No Content` | Successful `DELETE`, successful action with no body |
| `400 Bad Request` | Malformed request (bad JSON, missing headers) |
| `401 Unauthorized` | Authentication missing or invalid |
| `403 Forbidden` | Authenticated, but not authorized for this resource |
| `404 Not Found` | Resource doesn't exist |
| `409 Conflict` | State conflict (duplicate, optimistic-lock failure) |
| `410 Gone` | Resource permanently removed |
| `415 Unsupported Media Type` | Wrong `Content-Type` |
| `422 Unprocessable Entity` | Validation errors on otherwise-valid syntax |
| `429 Too Many Requests` | Rate-limited |
| `500 Internal Server Error` | Server bug |
| `503 Service Unavailable` | Temporary unavailability (deploy, dep down) |

---

## Caching

### Cache headers

```
# Public, cacheable for 1h
Cache-Control: public, max-age=3600

# Never cache
Cache-Control: no-cache, no-store, must-revalidate

# Conditional requests with ETag
ETag: "33a64df551425fcc55e4d42a148795d9f25f89d4"
If-None-Match: "33a64df551425fcc55e4d42a148795d9f25f89d4"
→ 304 Not Modified  (empty body)
```

### Spring example

```kotlin
@GetMapping("/{id}")
fun getOne(@PathVariable id: UUID, request: WebRequest): ResponseEntity<UserResponse> {
    val user = service.findById(id) ?: throw NotFoundException("User", id)
    val etag = "\"${user.version}\""
    if (request.checkNotModified(etag)) {
        return ResponseEntity.status(HttpStatus.NOT_MODIFIED).build()
    }
    return ResponseEntity.ok()
        .eTag(etag)
        .cacheControl(CacheControl.maxAge(Duration.ofMinutes(5)).cachePrivate())
        .body(user.toResponse())
}
```

---

## Bulk Operations

```
POST /api/users:batch
Content-Type: application/json
{
  "items": [
    {"name":"User1","email":"user1@example.com"},
    {"name":"User2","email":"user2@example.com"}
  ]
}

207 Multi-Status (or 200 with per-item status)
{
  "results": [
    {"index":0,"status":201,"id":"abc"},
    {"index":1,"status":409,"error":"duplicate email"}
  ]
}
```

Use the `:batch` suffix (Google AIP-231) to make batch endpoints obvious.

---

## Idempotency

### Idempotency keys (for `POST` creating money/orders/etc.)

```
POST /api/orders
Idempotency-Key: 9e6b1e8c-7c8a-4f4a-9c6a-1c0a2b3c4d5e
Body: {...}

# Duplicate request with the same key:
→ 200 OK  (returns cached response, no second write)
```

Server stores `(idempotency_key, request_hash, response)` for a TTL (e.g. 24h). Same key + different body → `422 Unprocessable Entity`.

Stripe's API is the canonical reference for this pattern.

---

## CORS

```kotlin
@Configuration
class CorsConfig : WebMvcConfigurer {
    override fun addCorsMappings(registry: CorsRegistry) {
        registry.addMapping("/api/**")
            .allowedOrigins("https://example.com")
            .allowedMethods("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS")
            .allowedHeaders("*")
            .allowCredentials(true)
            .maxAge(3600)
    }
}
```

For finer-grained control, use `@CrossOrigin` on individual controllers.

---

## Documentation with springdoc-openapi

```kotlin
// build.gradle.kts:
// implementation("org.springdoc:springdoc-openapi-starter-webmvc-ui:2.6.0")

@RestController
@RequestMapping("/api/users")
@Tag(name = "Users", description = "User management")
class UserController(private val service: UserService) {

    @Operation(summary = "Get user by ID", description = "Returns full user profile")
    @ApiResponses(
        ApiResponse(responseCode = "200", description = "User found"),
        ApiResponse(responseCode = "404", description = "User not found",
            content = [Content(schema = Schema(implementation = ProblemDetail::class))]),
    )
    @GetMapping("/{id}")
    fun getOne(
        @Parameter(description = "User ID") @PathVariable id: UUID,
    ): UserResponse = service.findById(id)?.toResponse()
        ?: throw NotFoundException("User", id)
}
```

The OpenAPI document is served at `/v3/api-docs`, Swagger UI at `/swagger-ui.html`.

---

## Health and Monitoring with Spring Boot Actuator

```kotlin
// build.gradle.kts:
// implementation("org.springframework.boot:spring-boot-starter-actuator")

// application.yml:
// management:
//   endpoints:
//     web:
//       exposure:
//         include: health,info,metrics,prometheus
//   endpoint:
//     health:
//       show-details: when-authorized
```

You get for free:

| Endpoint | What |
|---|---|
| `GET /actuator/health` | Liveness + readiness |
| `GET /actuator/health/liveness` | Liveness probe (K8s) |
| `GET /actuator/health/readiness` | Readiness probe (K8s) |
| `GET /actuator/info` | App version, build info |
| `GET /actuator/metrics` | Metric names |
| `GET /actuator/prometheus` | Prometheus scrape endpoint (requires `micrometer-registry-prometheus`) |

Custom health indicators:

```kotlin
@Component
class ExternalApiHealthIndicator(private val client: ExternalApiClient) : HealthIndicator {
    override fun health(): Health = try {
        client.ping()
        Health.up().withDetail("latencyMs", client.lastLatencyMs).build()
    } catch (e: Exception) {
        Health.down(e).build()
    }
}
```

Never roll your own `/health` endpoint when Actuator is one starter away.
