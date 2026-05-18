# REST protocol specifics

Load when designing or refactoring a REST endpoint. Examples in plain Kotlin
syntax — no framework annotations (those live in `spring.md`).

## URL shape

- **Plural nouns** for collections: `/users`, not `/user`. One convention
  per surface.
- **kebab-case for multi-word resources**: `/order-items`, not
  `/orderItems` or `/order_items`.
- **At most one level of nesting**: `/users/{id}/orders` is fine; deeper
  means the inner resource has its own identity and should live at the
  root.

```
GET    /users              # list (paginated)
POST   /users              # create
GET    /users/{id}         # read
PUT    /users/{id}         # replace
PATCH  /users/{id}         # partial update
DELETE /users/{id}         # remove
GET    /users/{id}/orders  # nested read
```

## Method semantics — the four properties

| Method | Safe | Idempotent | Body | Typical success |
|---|---|---|---|---|
| `GET` | ✅ | ✅ | no | `200` |
| `HEAD` | ✅ | ✅ | no | `200` (headers only) |
| `POST` | ❌ | ❌ | yes | `201` (created) / `200` / `202` |
| `PUT` | ❌ | ✅ | yes (full resource) | `200` / `204` |
| `PATCH` | ❌ | varies | yes (delta) | `200` / `204` |
| `DELETE` | ❌ | ✅ | rarely | `204` |

**Safe** ⇒ no observable side effects. **Idempotent** ⇒ N identical calls
produce the same final state as 1 call.

## `201 Created` — the full pattern

Always include:
- `Location:` header pointing at the new resource.
- Body containing the created resource (saves the caller a follow-up `GET`).

```
POST /users
{ "name": "Ada", "email": "ada@example.com" }

201 Created
Location: /users/u_a1b2c3
{
  "id": "u_a1b2c3",
  "name": "Ada",
  "email": "ada@example.com",
  "createdAt": "2026-05-15T10:00:00Z"
}
```

## `PATCH` — pick a flavour and signal it

Two RFCs, two `Content-Type`s:

- **JSON Merge Patch (RFC 7396)** — `Content-Type: application/merge-patch+json`.
  Body looks like the resource; `null` means "delete this field". Good for
  flat updates.
- **JSON Patch (RFC 6902)** — `Content-Type: application/json-patch+json`.
  Body is an array of operations (`add` / `remove` / `replace` / `move`).
  Good when you need array manipulation.

Don't invent a third format. Don't accept both on the same endpoint without
documenting which the caller is sending.

## Conditional GETs with `ETag`

```
GET /users/{id}
→ 200 OK
  ETag: "v17"
  { "id": "...", "version": 17, ... }

# Caller's next request:
GET /users/{id}
If-None-Match: "v17"
→ 304 Not Modified         # empty body
```

For mutating operations (`PUT`/`PATCH`/`DELETE`), use `If-Match` for
optimistic concurrency:

```
PUT /users/{id}
If-Match: "v17"
{ ...new state... }

→ 200 OK   (success, ETag becomes "v18")
→ 412 Precondition Failed   (someone else updated; client must refetch)
```

## Rate-limit response — the triad

Three things together:

```
HTTP/1.1 429 Too Many Requests
Retry-After: 30
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1747320600
Content-Type: application/problem+json

{
  "type": "https://errors.example.com/rate-limit",
  "title": "Too many requests",
  "status": 429,
  "detail": "Try again in 30 seconds"
}
```

Set `X-RateLimit-*` on *every* response, not just `429`. Lets clients
self-throttle.

## Bulk endpoints — Google AIP-231

```
POST /users:batch
{
  "items": [
    { "name": "Ada",   "email": "ada@example.com" },
    { "name": "Babel", "email": "bad-email" }
  ]
}

200 OK
{
  "results": [
    { "index": 0, "status": 201, "id": "u_a1b2c3" },
    { "index": 1, "status": 422, "error": { "type": "...", "title": "..." } }
  ]
}
```

Colon-suffix (`:batch`) makes batch operations visually distinct from
regular CRUD. Per-item status lets callers handle partial failure.

## Filtering, sorting, searching — query-param conventions

```
# Filter
GET /users?status=active
GET /users?role=admin&status=active

# Sort
GET /users?sort=createdAt,desc
GET /users?sort=name,asc&sort=createdAt,desc

# Search
GET /users?q=ada
```

For complex query syntax, consider Google AIP-160 filter expressions
(`status=ACTIVE AND name:ada*`).

## HATEOAS — adopt only when warranted

`_links` in the response lets a client discover next actions:

```json
{
  "id": "o_42",
  "status": "PAID",
  "_links": {
    "self":    { "href": "/orders/o_42" },
    "cancel":  { "href": "/orders/o_42:cancel" },
    "refund":  { "href": "/orders/o_42:refund" }
  }
}
```

Adopt only when a client genuinely walks links (state-machine UIs,
hypermedia-aware clients). For curl + SPA + mobile that all hardcode URLs,
it's overhead.

## Plain-Kotlin DTO sketch

```kotlin
data class UserResponse(
    val id: String,
    val name: String,
    val email: String,
    val createdAt: Instant,
)

data class CreateUserRequest(
    val name: String,
    val email: String,
)

data class ListUsersResponse(
    val items: List<UserResponse>,
    val nextCursor: String?,   // null when no more pages
)
```

Notice: the DTO is owned by the API layer, not the domain or persistence.
Map at the controller edge.
