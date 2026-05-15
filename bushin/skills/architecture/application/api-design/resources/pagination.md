# Pagination

Load when picking offset vs cursor, or when adding a list endpoint.

## The three patterns

| Pattern | Best for | Worst for |
|---|---|---|
| **Offset** (`?page=2&pageSize=20`) | Small / bounded datasets, random-access UI (jump to page 47) | Large or append-mostly tables — `OFFSET 100000` is O(n) |
| **Cursor** (`?cursor=eyJpZCI6...&limit=20`) | Large / append-mostly tables, infinite scroll, sync APIs | UIs that need "jump to page X" |
| **`Link` header** (RFC 8288) | Truly RESTful, GitHub-style | Clients that ignore headers |

Never both on the same endpoint. Pick one per resource.

## Offset — when small data lets you

```
GET /users?page=2&pageSize=20

200 OK
{
  "items": [...],
  "page": 2,
  "pageSize": 20,
  "total": 150,
  "pages": 8
}
```

Cap `pageSize` server-side (typically ≤ 100). Reject above with `400`.

Drawbacks:
- `OFFSET 100000 LIMIT 20` skips 100k rows — slow.
- Concurrent inserts shift pages: a row can appear twice or disappear
  between calls.

## Cursor — for anything you'll grow into

```
GET /users?limit=20&cursor=eyJpZCI6Im_xMjMifQ

200 OK
{
  "items": [...],
  "nextCursor": "eyJpZCI6InVfMTQzIn0",
  "hasMore": true
}
```

### Cursor format

Opaque base64 of an internal JSON. Typical shape:

```json
{ "lastId": "u_143", "lastSortKey": "2026-05-15T10:00:00Z" }
```

Rules:
- **Opaque to clients.** Clients pass it back verbatim. They don't parse it,
  they don't construct it.
- **Server-signed when stakes are high.** Sign with HMAC if the cursor
  contains anything sensitive or you don't want tampering.
- **No `total_count` by default.** Computing `COUNT(*)` over a huge
  partitioned table on every page is what cursor pagination escapes.
  Provide it only when callers genuinely need it and the dataset is small.
- **Versioned implicitly.** When you change the cursor shape, old cursors
  in flight may be invalid — return `400` with a "cursor expired" type.

### Plain-Kotlin sketch

```kotlin
data class Cursor(val lastId: String, val lastSortKey: Instant)

fun Cursor.encode(): String =
    Base64.getUrlEncoder().withoutPadding()
        .encodeToString(Json.encodeToString(this).encodeToByteArray())

fun String.decodeCursor(): Cursor =
    Json.decodeFromString(Base64.getUrlDecoder().decode(this).decodeToString())
```

## `Link` header pagination (RFC 8288)

```
GET /users?page=2
→
200 OK
Link: <https://api.example.com/users?page=3>; rel="next",
      <https://api.example.com/users?page=1>; rel="prev",
      <https://api.example.com/users?page=1>; rel="first",
      <https://api.example.com/users?page=8>; rel="last"

{ "items": [...] }
```

Body stays clean, navigation lives in headers. GitHub does this. Trade-off:
many client libraries don't parse `Link` headers out of the box.

## Server-side caps

Every list endpoint has:

| Knob | Typical value |
|---|---|
| Default `pageSize` when unspecified | 20 |
| Hard max `pageSize` | 100 (sometimes 1000 for trusted internal consumers) |
| Response on `pageSize` over the cap | `400` with `ProblemDetail` naming the cap |

Document the cap in OpenAPI / `.proto` comments so generated clients can
validate before sending.

## gRPC

Idiomatic gRPC pagination is cursor-based (`page_token` / `next_page_token`)
per Google AIP-158. See `grpc.md` for the proto shape.

## Common mistakes

- Returning `total_count` on a cursor-paginated huge table — defeats the
  purpose.
- Letting clients construct their own cursors (you lose opacity; they'll
  hardcode internal IDs).
- Using offset on an append-mostly stream (inserts shift pages mid-walk).
- No server cap on `pageSize` — one bad request OOMs the server.
- Mixing styles on one endpoint (`?page=` *and* `?cursor=`) — confusing,
  buggy.
