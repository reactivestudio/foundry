# Anti-patterns catalog

Concrete smells with the canonical fix. Load when reviewing an existing
surface or auditing a draft spec.

| Smell | Why it's wrong | Fix |
|---|---|---|
| `POST /getUser`, `POST /createOrder` | Verb in URL; the HTTP method already carries it. | `GET /users/{id}`, `POST /orders`. |
| `GET` that mutates state | Breaks safe-retry, breaks caches, breaks audit logs. Browsers and proxies pre-fetch `GET`s. | Switch to `POST` (creates) or `PUT` (replaces). |
| `200 OK` with `{"error": "..."}` | Generic HTTP clients, proxies, and monitors all read the status line. Hiding errors in a `2xx` body breaks all of them. | Use the right `4xx`/`5xx` with `ProblemDetail`. |
| `404` for "you don't own this" when existence is known to the caller | Leaks existence to attackers when convenient, but consumers can't tell "wrong ID" from "no access". | `403` if existence is known to the caller (e.g. they listed it). `404` if existence is the secret. Be deliberate, and document the choice. |
| `400 Bad Request` for validation errors | `400` says "I couldn't parse this". Validation errors *parsed fine*, they just failed business rules. | `422 Unprocessable Entity` with `ProblemDetail.errors[]`. |
| Unbounded `pageSize` | Single bad client can OOM the server with `?pageSize=1000000`. | Server cap (e.g. ≤ 100). Reject above the cap with `400`. |
| Persistence entity as response body | Couples wire format to DB schema; renaming a column becomes a breaking API change. | Explicit response DTO owned by the API layer. Map in the controller. |
| Version inside request body or no version at all | Hidden from URL, undebuggable from logs, easy to forget. | URL prefix (`/api/v1/…`) for REST, package (`com.example.x.v1`) for gRPC. |
| `201 Created` with empty body | Caller has to do an extra `GET` to retrieve the new ID. | Return the created resource (or at least its ID) + `Location` header. |
| Mixed `snake_case` and `camelCase` in JSON | Generated clients break or get weird casings. | One convention per surface. `camelCase` is the JSON default. |
| `PATCH` that replaces the whole resource | Consumers expecting partial-update semantics will silently wipe fields. | JSON Merge Patch (RFC 7396) for simple, JSON Patch (RFC 6902) for complex. Signal via `Content-Type`. |
| `PUT` for partial updates | Violates "PUT replaces"; future clients sending the full resource will overwrite your "merge" assumptions. | If it's a partial update, it's a `PATCH`. |
| Per-endpoint error shape (`{ error: "..." }`, `{ message: "..." }`, `{ errors: [...] }` all in the same API) | Every consumer has to write per-endpoint error parsing. | One `ProblemDetail` envelope across the whole surface. |
| Returning `total_count` on cursor-paginated endpoints over huge tables | Forces a full `SELECT COUNT(*)` on every page — kills performance. | Omit `total_count` for cursor pagination. Provide it only for bounded datasets. |
| gRPC: reusing a removed field number | Old clients silently decode the new field's bytes as the old field. Data corruption. | Mark the old number `reserved`. Pick a fresh number. |
| gRPC: enum starting at `0 = ACTIVE` | Default-constructed messages have your "ACTIVE" status — silent semantic errors. | `0 = UNSPECIFIED` always (Google AIP-126). |
| gRPC: unbounded server stream with no heartbeat | Client can't tell "server is busy" from "server is dead". | Send a periodic keepalive or heartbeat message. |
| gRPC: no client-side deadline | RPCs hang forever when the network drops. | Always `withDeadlineAfter(...)` on the client. |
| Deep nesting in URLs (`/users/{u}/orders/{o}/items/{i}/reviews/{r}`) | URLs become brittle, reordering breaks every consumer, deep-linking gets ugly. | At most one level. Deeper resources have their own identity at the root. |
| Bulk endpoint named `/api/bulk-users` or `/api/users/bulk` | Invents a convention that varies per service. | `POST /api/users:batch` (Google AIP-231 colon syntax). |
| Synchronous endpoint for work that takes >5s | Times out, blocks the connection, retries duplicate the work. | `202 Accepted` + `Location` to a status resource, or move it behind a queue (see `messaging-boundary.md`). |
| Stringly-typed enums in JSON ("status": "act1ve") | Typos silently route to defaults; impossible to discover valid values. | Enumerate in OpenAPI; reject unknown values with `422`. |
| `DELETE` that returns the deleted resource | Wastes bandwidth; consumers rarely use it. | `204 No Content`. Caller already had the resource. |
