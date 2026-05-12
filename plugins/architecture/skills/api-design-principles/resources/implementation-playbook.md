# API Design Principles Implementation Playbook

Detailed patterns, Kotlin/Spring code samples, and pitfalls referenced by the `api-design-principles` skill.

Stack assumption: **Kotlin + Spring Boot + Spring MVC + (optionally) grpc-kotlin / grpc-spring-boot-starter**. GraphQL is intentionally not covered.

---

## Core Concepts

### 1. RESTful Design Principles

**Resource-oriented architecture**

- Resources are nouns (`users`, `orders`, `products`), not verbs.
- HTTP methods carry the action semantics.
- URLs represent resource hierarchies.
- Consistent naming conventions across the surface.

**HTTP method semantics:**

| Method | Use | Idempotent | Safe |
|---|---|---|---|
| `GET` | Retrieve | ✅ | ✅ |
| `POST` | Create / non-idempotent action | ❌ | ❌ |
| `PUT` | Replace entire resource | ✅ | ❌ |
| `PATCH` | Partial update | ❌ (usually) | ❌ |
| `DELETE` | Remove | ✅ | ❌ |

### 2. gRPC + Protobuf Design Principles

**Contract-first**

- The `.proto` file is the single source of truth — schema, request/response shapes, service surface.
- Schema is versioned via the package name (`com.example.user.v1` → `v2`).
- Field numbers are immutable once published.
- Backward-compatible changes: add new optional fields, never reuse field numbers.

**When to pick gRPC over REST**

- Internal service-to-service traffic with high call volume.
- Need for bidirectional or server-side streaming.
- Polyglot consumers that benefit from generated clients.
- Strict typed contract with binary efficiency.

**When NOT to pick gRPC**

- Public API consumed by browsers (use REST + JSON or gRPC-Web with caveats).
- Ad-hoc CLI/curl-style debugging is a primary workflow.

### 3. API Versioning Strategies

| Strategy | Example | Pros | Cons |
|---|---|---|---|
| **URL versioning** (recommended for REST) | `/api/v1/users` | Visible, easy to route, easy to debug | Multiple URLs per resource |
| **Header versioning** | `Accept: application/vnd.api+json; version=2` | Clean URLs | Invisible, harder to test |
| **Query param** | `/api/users?version=2` | Easy to test | Easy to forget |
| **Package version** (gRPC) | `package com.example.user.v1;` | Idiomatic for protobuf | Requires careful proto file management |

---

## REST API Design Patterns

### Pattern 1: Resource Collection Design

```kotlin
// Good — resource-oriented endpoints
GET    /api/users              // List users (paginated)
POST   /api/users              // Create user
GET    /api/users/{id}         // Get specific user
PUT    /api/users/{id}         // Replace user
PATCH  /api/users/{id}         // Partial update
DELETE /api/users/{id}         // Delete user

// Nested resources (shallow)
GET    /api/users/{id}/orders  // User's orders
POST   /api/users/{id}/orders  // Create order for user

// Bad — action-oriented endpoints (avoid)
POST   /api/createUser
POST   /api/getUserById
POST   /api/deleteUser
```

### Pattern 2: Pagination and Filtering

```kotlin
// Request DTO with validation
data class ListUsersRequest(
    @field:Min(1) val page: Int = 1,
    @field:Min(1) @field:Max(100) val pageSize: Int = 20,
    val status: String? = null,
    val search: String? = null,
)

// Response DTO
data class PageResponse<T>(
    val items: List<T>,
    val page: Int,
    val pageSize: Int,
    val total: Long,
    val pages: Int,
) {
    val hasNext: Boolean get() = page < pages
    val hasPrev: Boolean get() = page > 1
}

@RestController
@RequestMapping("/api/users")
class UserController(private val service: UserService) {

    @GetMapping
    fun list(@Valid request: ListUsersRequest): PageResponse<UserResponse> {
        val pageable = PageRequest.of(request.page - 1, request.pageSize)
        val page = service.search(
            status = request.status,
            search = request.search,
            pageable = pageable,
        )
        return PageResponse(
            items = page.content.map { it.toResponse() },
            page = request.page,
            pageSize = request.pageSize,
            total = page.totalElements,
            pages = page.totalPages,
        )
    }
}
```

For large datasets prefer **cursor-based pagination** (see `references/rest-best-practices.md`).

### Pattern 3: Error Handling with `ProblemDetail` (RFC 7807)

Spring 6 / Boot 3 ships `org.springframework.http.ProblemDetail` — use it instead of inventing a custom error envelope.

```kotlin
// Domain exceptions
class NotFoundException(resource: String, id: Any) :
    RuntimeException("$resource not found: id=$id")

class ConflictException(message: String) : RuntimeException(message)

class ValidationFailureException(val errors: List<FieldError>) :
    RuntimeException("validation failed")

data class FieldError(val field: String, val message: String, val rejectedValue: Any?)

// Global exception handler
@RestControllerAdvice
class ApiExceptionHandler {

    @ExceptionHandler(NotFoundException::class)
    fun handleNotFound(ex: NotFoundException): ProblemDetail =
        ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, ex.message ?: "not found").apply {
            type = URI.create("https://errors.example.com/not-found")
            title = "Resource not found"
        }

    @ExceptionHandler(ConflictException::class)
    fun handleConflict(ex: ConflictException): ProblemDetail =
        ProblemDetail.forStatusAndDetail(HttpStatus.CONFLICT, ex.message ?: "conflict").apply {
            type = URI.create("https://errors.example.com/conflict")
            title = "State conflict"
        }

    @ExceptionHandler(ValidationFailureException::class)
    fun handleValidation(ex: ValidationFailureException): ProblemDetail =
        ProblemDetail.forStatusAndDetail(HttpStatus.UNPROCESSABLE_ENTITY, "validation failed").apply {
            type = URI.create("https://errors.example.com/validation")
            title = "Validation failed"
            setProperty("errors", ex.errors)
        }

    @ExceptionHandler(MethodArgumentNotValidException::class)
    fun handleBindErrors(ex: MethodArgumentNotValidException): ProblemDetail {
        val errors = ex.bindingResult.fieldErrors.map {
            FieldError(it.field, it.defaultMessage ?: "invalid", it.rejectedValue)
        }
        return ProblemDetail.forStatusAndDetail(HttpStatus.UNPROCESSABLE_ENTITY, "validation failed").apply {
            type = URI.create("https://errors.example.com/validation")
            title = "Validation failed"
            setProperty("errors", errors)
        }
    }
}
```

Status code guidelines: see `references/rest-best-practices.md`.

### Pattern 4: HATEOAS (use sparingly)

HATEOAS adds `_links` to responses so a client can discover next actions. In practice most JSON APIs don't need it — adopt only when a real hypermedia-driven client benefits.

Spring HATEOAS Kotlin example:

```kotlin
// build.gradle.kts: implementation("org.springframework.boot:spring-boot-starter-hateoas")

import org.springframework.hateoas.EntityModel
import org.springframework.hateoas.server.mvc.WebMvcLinkBuilder.linkTo
import org.springframework.hateoas.server.mvc.WebMvcLinkBuilder.methodOn

@GetMapping("/{id}")
fun getOne(@PathVariable id: UUID): EntityModel<UserResponse> {
    val user = service.findById(id) ?: throw NotFoundException("User", id)
    return EntityModel.of(
        user.toResponse(),
        linkTo(methodOn(UserController::class.java).getOne(id)).withSelfRel(),
        linkTo(methodOn(UserController::class.java).list(ListUsersRequest())).withRel("collection"),
        linkTo(methodOn(OrderController::class.java).listByUser(id)).withRel("orders"),
    )
}
```

Resulting body:

```json
{
  "id": "…",
  "email": "…",
  "name": "…",
  "_links": {
    "self":       { "href": "/api/users/123" },
    "collection": { "href": "/api/users" },
    "orders":     { "href": "/api/users/123/orders" }
  }
}
```

**Decision rule:** if your client today is `curl` + your own SPA + a mobile app that all hardcode URLs, you don't need HATEOAS. Use only when a client genuinely walks links.

---

## gRPC + Protobuf Design Patterns

### Pattern 1: Service definition (proto3)

```protobuf
// proto/user/v1/user.proto
syntax = "proto3";

package com.example.user.v1;

import "google/protobuf/timestamp.proto";
import "google/protobuf/empty.proto";

option java_multiple_files = true;
option java_package = "com.example.user.v1";

service UserService {
  rpc GetUser   (GetUserRequest)    returns (User);
  rpc ListUsers (ListUsersRequest)  returns (ListUsersResponse);
  rpc CreateUser(CreateUserRequest) returns (User);
  rpc UpdateUser(UpdateUserRequest) returns (User);
  rpc DeleteUser(DeleteUserRequest) returns (google.protobuf.Empty);

  // Server-streaming: subscribe to user events
  rpc WatchUsers(WatchUsersRequest) returns (stream UserEvent);

  // Client-streaming: bulk create with backpressure
  rpc BulkCreateUsers(stream CreateUserRequest) returns (BulkCreateUsersResponse);
}

message User {
  string id = 1;
  string email = 2;
  string name = 3;
  google.protobuf.Timestamp created_at = 4;
  bool is_active = 5;
}

message GetUserRequest {
  string id = 1;
}

// Cursor-based pagination is idiomatic for gRPC
message ListUsersRequest {
  int32  page_size  = 1;
  string page_token = 2;
  string filter     = 3;  // Google AIP-160 style: "status=active AND name:*john*"
}

message ListUsersResponse {
  repeated User users          = 1;
  string       next_page_token = 2;
  int32        total_count     = 3;
}

message CreateUserRequest {
  string email = 1;
  string name  = 2;
}

message UpdateUserRequest {
  string id   = 1;
  User   user = 2;
  // Field mask for partial updates (Google AIP-134)
  google.protobuf.FieldMask update_mask = 3;
}

message DeleteUserRequest {
  string id = 1;
}

message WatchUsersRequest {
  string filter = 1;
}

message UserEvent {
  enum Type { TYPE_UNSPECIFIED = 0; CREATED = 1; UPDATED = 2; DELETED = 3; }
  Type   type = 1;
  User   user = 2;
}

message BulkCreateUsersResponse {
  int32 created_count = 1;
  int32 failed_count  = 2;
}
```

**Proto rules of thumb**

- Field numbers `1`–`15` are 1-byte encoded → reserve for hot fields.
- Never reuse a field number. To "remove" a field, mark it `reserved`.
- Use `google.protobuf.Timestamp`, `Duration`, `FieldMask`, `Empty` instead of inventing types.
- Enums: always have a `_UNSPECIFIED = 0` first value (Google style).
- Package version (`v1`, `v2`) is the API version. Bump it for breaking changes.

### Pattern 2: Kotlin server with grpc-kotlin + Spring

```kotlin
// build.gradle.kts (sketch)
// id("com.google.protobuf") version "..."
// implementation("io.grpc:grpc-kotlin-stub:...")
// implementation("net.devh:grpc-spring-boot-starter:...")

@GrpcService
class UserGrpcService(
    private val userService: UserService,
) : UserServiceGrpcKt.UserServiceCoroutineImplBase() {

    override suspend fun getUser(request: GetUserRequest): User {
        val user = userService.findById(UUID.fromString(request.id))
            ?: throw StatusException(
                Status.NOT_FOUND.withDescription("user ${request.id} not found")
            )
        return user.toProto()
    }

    override suspend fun listUsers(request: ListUsersRequest): ListUsersResponse {
        val page = userService.search(
            filter = request.filter,
            pageToken = request.pageToken.ifBlank { null },
            pageSize = request.pageSize.takeIf { it > 0 } ?: 20,
        )
        return ListUsersResponse.newBuilder()
            .addAllUsers(page.items.map { it.toProto() })
            .setNextPageToken(page.nextPageToken ?: "")
            .setTotalCount(page.total.toInt())
            .build()
    }

    override suspend fun createUser(request: CreateUserRequest): User {
        return try {
            userService.create(email = request.email, name = request.name).toProto()
        } catch (e: DuplicateEmailException) {
            throw StatusException(Status.ALREADY_EXISTS.withDescription(e.message))
        }
    }

    override fun watchUsers(request: WatchUsersRequest): Flow<UserEvent> =
        userService.eventStream(filter = request.filter).map { it.toProtoEvent() }

    override suspend fun bulkCreateUsers(
        requests: Flow<CreateUserRequest>,
    ): BulkCreateUsersResponse {
        var created = 0
        var failed = 0
        requests.collect { req ->
            try {
                userService.create(email = req.email, name = req.name)
                created++
            } catch (_: Exception) {
                failed++
            }
        }
        return BulkCreateUsersResponse.newBuilder()
            .setCreatedCount(created)
            .setFailedCount(failed)
            .build()
    }
}
```

### Pattern 3: gRPC status code mapping

Map domain errors to gRPC `Status` consistently:

| Domain situation | gRPC status |
|---|---|
| Validation failure | `INVALID_ARGUMENT` (3) |
| Resource not found | `NOT_FOUND` (5) |
| Duplicate / unique constraint | `ALREADY_EXISTS` (6) |
| Caller lacks permission (authn ok) | `PERMISSION_DENIED` (7) |
| Caller not authenticated | `UNAUTHENTICATED` (16) |
| Optimistic-lock / state conflict | `FAILED_PRECONDITION` (9) |
| Concurrent modification | `ABORTED` (10) |
| Rate-limited | `RESOURCE_EXHAUSTED` (8) |
| Caller cancelled | `CANCELLED` (1) — usually not thrown by you |
| Server bug | `INTERNAL` (13) |
| Downstream/dep down | `UNAVAILABLE` (14) — clients may retry |
| Deadline exceeded | `DEADLINE_EXCEEDED` (4) — usually framework-generated |

Always include `withDescription("…")` so clients see a human-readable hint.

For structured error details, attach `com.google.rpc.Status` with typed `details` (e.g. `BadRequest`, `ResourceInfo`) — see Google AIP-193.

### Pattern 4: Streaming patterns

| RPC kind | Use case |
|---|---|
| **Unary** | Default request/response |
| **Server streaming** | Subscriptions, long-running events, watch APIs |
| **Client streaming** | Bulk upload, sensor data, log streams with backpressure |
| **Bidirectional** | Interactive sessions (chat, collaborative editing) |

Streaming rules:

- Set deadlines on the client side, always.
- For server streams that may run "forever" (watch APIs), expose a keepalive or a periodic heartbeat message.
- Resource-clean on cancellation: when the client disconnects, your `Flow` collector should be cancelled — make sure DB cursors and Kafka consumers close.

### Pattern 5: Versioning gRPC contracts

- New endpoint behaviour → add a new RPC method, don't change existing.
- Breaking schema change → new package `com.example.user.v2`, new proto file, new service.
- Run `v1` and `v2` in parallel during migration. Deprecate `v1` methods with `option deprecated = true;` and a sunset window.
- Field-level evolution within `v1`: only add new fields, never repurpose existing field numbers.

---

## Best Practices

### REST APIs

1. **Plural nouns** for collections (`/users`, not `/user`).
2. **Stateless** — every request carries its own context.
3. **Correct status codes** — 2xx success, 4xx client error, 5xx server error.
4. **Version from day one** — `/api/v1/…` even if there's no `v2` yet.
5. **Always paginate** large collections.
6. **Rate-limit** public endpoints.
7. **OpenAPI** for docs — generated from code with springdoc-openapi.
8. **Idempotency keys** on `POST`s that create money/orders/etc.

### gRPC APIs

1. **Contract-first** — write the `.proto` before the implementation.
2. **Version through the package** — `com.example.user.v1`.
3. **Never reuse field numbers**; mark removed fields `reserved`.
4. **`_UNSPECIFIED = 0`** for every enum.
5. **Cursor pagination** — `page_token` / `next_page_token`, not offset.
6. **Map domain errors to canonical `Status` codes** consistently across services.
7. **Use `FieldMask`** for partial updates instead of inventing optionals.
8. **Set deadlines client-side**, always.

## Common Pitfalls

- **Ignoring HTTP semantics** — `POST` for a read, `GET` with side effects, etc.
- **Inconsistent error format** — every endpoint returns a different envelope. Use `ProblemDetail`.
- **Breaking changes without version bump** — clients explode silently.
- **Exposing JPA entities as response bodies** — couples the wire format to the DB schema.
- **No rate limits** — first abuse takes you down.
- **Offset pagination on huge tables** — `OFFSET 100000 LIMIT 20` is slow; use cursors.
- **Tight coupling to the database schema** — API shape should reflect the domain, not the table.
- **gRPC: reusing proto field numbers** — silently corrupts data on old clients. Never.
- **gRPC: unbounded server streams without heartbeat** — clients can't detect dead servers.
- **gRPC: no deadline** — RPCs hang forever on the network.

## Resources

- `references/rest-best-practices.md` — deep dive on REST: URL structure, methods, status codes, pagination, rate limiting, caching, idempotency, OpenAPI, Actuator
