# Kotlin idioms for API design (opt-in)

Load when the project is on Kotlin. Concentrates the few patterns that
materially shape API code in idiomatic Kotlin (the body uses plain Kotlin
intentionally; these are *additions*).

## Sealed hierarchies for domain errors

Domain failures map cleanly to a sealed interface; the controller / RPC
boundary translates to wire codes.

```kotlin
sealed interface UserError {
    data class NotFound(val id: String) : UserError
    data class DuplicateEmail(val email: String) : UserError
    data class ValidationFailed(val fields: Map<String, String>) : UserError
}

fun UserError.toProblemDetail(): ProblemDetail = when (this) {
    is UserError.NotFound          -> problem(404, "User not found", "user/${id}")
    is UserError.DuplicateEmail    -> problem(409, "Email already in use", email)
    is UserError.ValidationFailed  -> problem(422, "Validation failed", extras = mapOf("errors" to fields))
}
```

The compiler enforces exhaustiveness — adding a new error variant fails
the build until every translation site handles it.

## `Result<T>` vs exceptions at the boundary

Two coherent patterns; pick one per service:

**Exception-based** — let domain code throw, translate in the global
handler. Idiomatic with Spring `@RestControllerAdvice`. Cheap to write, but
the type signature lies (`fun create(): User` doesn't reveal it can fail).

**Result-based** — domain returns `Result<T, UserError>` (a custom union or
arrow-kt `Either`). The controller pattern-matches to a wire response.
Better static guarantees, more verbose.

Don't mix. Pick at the service-layer boundary and apply consistently.

## Coroutines + `Flow` for streaming

For server-streaming gRPC RPCs, return `Flow<T>` directly:

```kotlin
override fun watchUsers(request: WatchUsersRequest): Flow<UserEvent> =
    userService.eventStream(filter = request.filter)
        .map { it.toProtoEvent() }
```

`grpc-kotlin` collects the `Flow` and writes each emission to the wire.
Cancellation propagates: if the client disconnects, the collector cancels,
which cancels your upstream — make sure DB cursors and queue consumers
respect cancellation (`use { }` blocks, `Channel.consumeEach`).

## Cursor encoding with `kotlinx.serialization`

```kotlin
@Serializable
data class Cursor(val lastId: String, val lastSortKey: String)

fun Cursor.encode(): String =
    Base64.getUrlEncoder().withoutPadding()
        .encodeToString(Json.encodeToString(this).encodeToByteArray())

fun decodeCursor(token: String): Cursor =
    Json.decodeFromString(Base64.getUrlDecoder().decode(token).decodeToString())
```

Mark `Cursor` `@Serializable` so swapping JSON for CBOR (smaller token)
later is a one-line change.

## `require` for input invariants at the API edge

Idiomatic Kotlin uses `require` for caller-precondition checks. At the API
edge:

```kotlin
@GetMapping
fun list(@RequestParam(defaultValue = "20") limit: Int): ListResponse {
    require(limit in 1..100) { "limit must be in 1..100" }
    ...
}
```

`require` throws `IllegalArgumentException`; map that to `400` in the
global handler. (Validation that's about parsing — wrong type, missing
required field — is `MethodArgumentNotValidException` and goes to `422` per
the body's principles.)

## Proto-bound types — don't leak them

Generated proto classes (`User`, `UserStatus`) are framework types. Don't
let them creep into domain or service code:

```kotlin
// API layer
override suspend fun getUser(request: GetUserRequest): User {
    val user = userService.findById(UUID.fromString(request.id))   // domain User
        ?: throw StatusException(Status.NOT_FOUND...)
    return user.toProto()                                          // proto User
}

// Domain layer — knows nothing about proto
data class User(val id: UUID, val email: Email, val name: String, ...)
```

Otherwise a proto field rename ripples through every layer.

## `data class` for DTOs — but freeze the field order

`data class` `copy()` is positional by default. When the DTO is
`@Serializable`/Jackson-bound, mass `copy(...)` calls in tests are
positional too. Reordering fields silently breaks tests.

Use named arguments consistently:

```kotlin
// fragile
val req = CreateUserRequest("ada@example.com", "Ada")

// stable across field reorder
val req = CreateUserRequest(email = "ada@example.com", name = "Ada")
```

Lint rule worth enforcing at the boundary.
