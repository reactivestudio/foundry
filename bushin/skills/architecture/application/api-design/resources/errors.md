# Errors — one envelope, two protocols

Load when picking status codes, designing error responses, or mapping
domain failures to wire codes.

## REST — `ProblemDetail` (RFC 7807)

```json
{
  "type":     "https://errors.example.com/validation",
  "title":    "Validation failed",
  "status":   422,
  "detail":   "Request body failed validation",
  "instance": "/users",
  "errors": [
    { "field": "email", "message": "invalid format", "rejectedValue": "not-an-email" }
  ]
}
```

`Content-Type: application/problem+json`.

| Field | Required | Meaning |
|---|---|---|
| `type` | yes | URI naming the error class. Stable; consumers may switch on it. |
| `title` | yes | Short human-readable summary. Don't localise — that's `detail`'s job. |
| `status` | yes | Mirror of the HTTP status code. |
| `detail` | no | Human-readable explanation specific to this occurrence. |
| `instance` | no | URI of the specific occurrence (often the request path). |
| custom (`errors`, `traceId`, `retryAfter`, …) | no | Typed extensions. Document them. |

One envelope across the whole surface. Don't invent `{ "error": ... }` or
`{ "message": ... }` for one endpoint and `ProblemDetail` for another.

## REST — status code reference

| Code | Use | Body |
|---|---|---|
| `200 OK` | Successful `GET`/`PUT`/`PATCH`/`DELETE` (with returned body) | resource |
| `201 Created` | Successful `POST` creating a resource | created resource + `Location` |
| `202 Accepted` | Async work queued | status resource or pointer |
| `204 No Content` | Successful action, nothing to return | empty |
| `301`/`308` | Permanent redirect (308 preserves method) | `Location` header |
| `304 Not Modified` | Conditional `GET` matched `If-None-Match` | empty |
| `400 Bad Request` | Malformed request (bad JSON, missing required headers) | `ProblemDetail` |
| `401 Unauthorized` | Not authenticated | `ProblemDetail` + `WWW-Authenticate` |
| `403 Forbidden` | Authenticated, but not allowed | `ProblemDetail` |
| `404 Not Found` | Resource doesn't exist (or you're hiding it) | `ProblemDetail` |
| `405 Method Not Allowed` | Wrong method for this resource | `Allow` header |
| `409 Conflict` | State conflict (optimistic-lock fail, dependent rows, duplicate) | `ProblemDetail` |
| `410 Gone` | Permanently removed (signals "stop retrying") | `ProblemDetail` |
| `412 Precondition Failed` | `If-Match`/`If-Unmodified-Since` failed | `ProblemDetail` |
| `415 Unsupported Media Type` | Wrong `Content-Type` | `Accept` header listing supported |
| `422 Unprocessable Entity` | Validation errors on parsed-fine syntax | `ProblemDetail` with `errors[]` |
| `429 Too Many Requests` | Rate-limited | `ProblemDetail` + `Retry-After` + `X-RateLimit-*` |
| `500 Internal Server Error` | Server bug | `ProblemDetail` (don't leak stack) |
| `502 Bad Gateway` | Upstream returned garbage | `ProblemDetail` |
| `503 Service Unavailable` | Temporary (deploy, dependency down) | `ProblemDetail` + `Retry-After` |
| `504 Gateway Timeout` | Upstream didn't respond in time | `ProblemDetail` |

## gRPC — the 16 canonical codes

```
0  OK
1  CANCELLED          — caller cancelled (usually framework-generated)
2  UNKNOWN            — unexpected; treat like 500
3  INVALID_ARGUMENT   — request was malformed or violates contract (≈ 400/422)
4  DEADLINE_EXCEEDED  — caller's deadline elapsed (framework-generated)
5  NOT_FOUND          — resource doesn't exist (≈ 404)
6  ALREADY_EXISTS     — duplicate / unique constraint (≈ 409)
7  PERMISSION_DENIED  — authenticated, not allowed (≈ 403)
8  RESOURCE_EXHAUSTED — quota / rate limit (≈ 429)
9  FAILED_PRECONDITION— system state forbids this op (≈ 409, retry won't help)
10 ABORTED            — concurrency conflict (≈ 409, retry might help)
11 OUT_OF_RANGE       — pagination past end, value outside range
12 UNIMPLEMENTED      — method not implemented in this version
13 INTERNAL           — server bug (≈ 500)
14 UNAVAILABLE        — temporary; clients may retry (≈ 503)
15 DATA_LOSS          — unrecoverable corruption
16 UNAUTHENTICATED    — no/invalid credentials (≈ 401)
```

`FAILED_PRECONDITION` vs `ABORTED` is the one Claude routinely confuses:

- `FAILED_PRECONDITION` — retrying with the *same* request will fail the
  same way. Caller must change something (refresh state, re-auth, fix the
  resource).
- `ABORTED` — typically optimistic-lock failure. Retry *might* succeed
  after a refetch.

Always include `withDescription("...")` so the wire carries a human-readable
hint. For structured details (per Google AIP-193), attach typed
`com.google.rpc.Status` details (`BadRequest`, `ResourceInfo`,
`QuotaFailure`, `ErrorInfo`).

## Domain → wire mapping

| Domain situation | REST | gRPC |
|---|---|---|
| Resource doesn't exist | `404` | `NOT_FOUND` |
| Not authenticated | `401` (+`WWW-Authenticate`) | `UNAUTHENTICATED` |
| Authenticated but forbidden | `403` | `PERMISSION_DENIED` |
| Malformed request (parser failed) | `400` | `INVALID_ARGUMENT` |
| Validation error (parsed fine) | `422` | `INVALID_ARGUMENT` |
| Duplicate / unique constraint | `409` | `ALREADY_EXISTS` |
| Optimistic-lock failure | `409` (or `412` if `If-Match`) | `ABORTED` |
| State-machine refusal | `409` | `FAILED_PRECONDITION` |
| Rate-limited | `429` (+`Retry-After`) | `RESOURCE_EXHAUSTED` |
| Server bug | `500` | `INTERNAL` |
| Upstream / dep down | `502`/`503` | `UNAVAILABLE` |

## Don't leak

- Never include stack traces or internal class names in production error
  bodies. They help attackers map your stack.
- Be deliberate about `403` vs `404`: if existence is a secret, return
  `404` for unauthorised access; if existence is public, return `403`.

## `type` URIs — make them resolvable

`type` is a URI, not a code. Ideally:

```
https://errors.example.com/validation
https://errors.example.com/insufficient-funds
```

If a developer pastes the URI into a browser, they should see a page
explaining the error and how to fix it. Even a single doc page per `type`
beats a per-endpoint shape.
