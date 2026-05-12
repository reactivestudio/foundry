---
name: api-design-principles
description: "REST and gRPC/Protobuf API contract design for Kotlin/Spring Boot services — resource modeling, HTTP semantics (idempotency, status codes), error format (`ProblemDetail` / RFC 7807), versioning (URL vs header vs proto package), pagination (offset / cursor / Link header), filtering, rate limiting, auth-aware semantics (401 vs 403, retry-safe operations). Use when designing a new REST or gRPC endpoint, choosing between REST and gRPC for a use case, defining error / pagination / idempotency conventions for a service or team, reviewing an OpenAPI / proto spec before implementation, refactoring a poorly-shaped API, or auditing a contract for consistency. GraphQL is intentionally out of scope."
risk: safe
source: custom
---

# API Design Principles

> "An API is a contract. Once published, every shape you got wrong becomes someone else's bug."

The cost of fixing a bad API is paid by *every consumer* you have, every time, forever. Spending a day on the contract before code is the cheapest engineering work you will ever do.

## Use this skill when
- Designing a new REST or gRPC endpoint / service.
- Defining team / service-level conventions for errors, pagination, versioning, idempotency.
- Picking between REST and gRPC for a given use case (or combining them).
- Refactoring an existing API where consumers are reporting surprises.
- Reviewing an OpenAPI / proto specification before implementation begins.
- Establishing a consistency baseline across a multi-service API surface.
- Shaping endpoints for a specific consumer (mobile client, partner integration, internal service).

## Do not use this skill when
- The task is **authentication / authorization mechanics** (JWT validation, `@PreAuthorize`, OAuth2 flows) — use `spring-security-and-auth`. (This skill covers *auth-shaped semantics* on the contract: 401 vs 403, idempotency for retries, error formats that don't leak.)
- The task is **async event contract design** (queue topology, event payload shape, ordering) — use `messaging-rabbitmq-spring`. If you find yourself asking "should this be a webhook or an event?", you're in messaging territory.
- The task is **command-vs-query endpoint shape under CQRS** (write-side accepting commands, read-side returning projections) — use `cqrs-implementation` for the split, then come here for the HTTP/gRPC surface of each side.
- The task is the **strategic REST-vs-gRPC decision at system level** (which boundary uses which protocol) — use `architecture` for the decision frame, then this skill for the contract details.
- The task is **API capacity / scaling** (how much load can this endpoint hold) — use `system-design-fundamentals` and `caching-strategies-spring`.
- The task is a **deep API review** with severity-graded findings — use `architect-review`.
- The task is **infrastructure-only** (proxies, gateways, mesh routing) with no contract change.

## Core principles

1. **The contract is the source of truth.** Lock the contract (URL shape + payload + status codes, or `.proto`) before writing handler code. Code changes are cheap; consumer migrations are not.
2. **Resources are nouns; HTTP methods carry the verb.** `POST /users` not `POST /createUser`. The verb is in the method, not in the URL.
3. **Idempotency is a property, not a method.** `PUT` and `DELETE` should be safe to retry; `POST` usually is not. If `POST` needs to be retry-safe (payments, message sends), make it idempotent via an `Idempotency-Key` header and document the dedup window.
4. **Status codes mean what they say.** `2xx` only when the operation succeeded. `4xx` only when the caller can fix the request. `5xx` only when the server failed. Never `200 OK` with `{"error": ...}` — that breaks every generic HTTP client.
5. **Errors are part of the API.** Use `ProblemDetail` (RFC 7807): consistent `type` / `title` / `status` / `detail` / `instance` plus extensions. One error format across the whole surface — different shapes per endpoint multiplies consumer complexity.
6. **Version on day one.** `/api/v1/users` (REST) or `package com.example.users.v1;` (proto). The cost of adding versioning later is much higher than carrying `v1` from the start.
7. **Pagination has bounds.** Every list endpoint has a server-enforced `pageSize` cap. Cursor pagination for large / append-mostly datasets; offset for small / random-access; never both on the same endpoint.
8. **401 ≠ 403.** `401 Unauthorized` = "I don't know who you are." `403 Forbidden` = "I know who you are, you can't do this." Confusing them leaks information and breaks generic auth retries.

## REST vs gRPC — the quick decision

| Use case | Pick | Why |
|---|---|---|
| Public / browser-facing surface | **REST + JSON** | Human-readable, curl-debuggable, browser-native. |
| Internal high-volume service-to-service | **gRPC** | Binary efficiency, generated clients, streaming. |
| Polyglot internal consumers | **gRPC** | One `.proto` → clients in every language. |
| Bidirectional or server streaming | **gRPC** | First-class streaming; SSE / websockets in REST are workarounds. |
| Ad-hoc CLI / curl debugging is a primary workflow | **REST** | grpcurl exists but is heavier; REST wins for casual exploration. |
| Need strict typed contract + binary efficiency | **gRPC** | Field numbers are immutable; protobuf catches drift. |
| Partner / third-party integration | **REST** | Lowest onboarding cost for external developers. |

Combining is fine: gRPC inside, REST at the edge. The decision is per-boundary, not per-system.

## Top anti-patterns

| Anti-pattern | What's wrong | Fix |
|---|---|---|
| `POST /getUser` | Action in URL; verb confused with method. | `GET /users/{id}`. |
| `GET` that mutates state | Breaks safe-retry, breaks caches, breaks audit. | `POST` or `PUT` if it mutates. |
| `200 OK` with `{"error": "..."}` | Generic HTTP clients can't tell success from failure. | Use the right `4xx` / `5xx` with `ProblemDetail`. |
| `404` for "you don't own this" | Leaks existence to attackers; consumers can't distinguish. | `403` if existence is known; `404` if truly absent. |
| Unbounded `pageSize` | One bad client OOMs the server. | Cap `pageSize` (e.g. ≤ 100), return `400` past the cap. |
| Returning entities directly | Persistence shape leaks; refactors break the contract. | Explicit response DTOs, owned by the API layer. |
| Version in request body | Hidden from URL, undebuggable, easy to forget. | URL (`/v1/...`) for REST, proto package for gRPC. |
| Empty body on `201 Created` | Caller has to fetch immediately to get the new ID. | Return the created resource (or at least the ID + `Location` header). |
| Mixing snake_case and camelCase | Looks unprofessional; bites generated clients. | One convention per surface (camelCase recommended for JSON in Kotlin/Spring; protobuf is snake_case in `.proto` and camelCase in generated Kotlin). |
| `PATCH` that replaces the whole resource | Violates PATCH semantics; consumers can't do partial updates safely. | Use JSON Merge Patch (RFC 7396) or JSON Patch (RFC 6902), or use `PUT` if it's really a replace. |

## Stack mapping (Kotlin/Spring)

| Concern | Default for new services |
|---|---|
| REST framework | Spring MVC (WebMVC), Jackson Kotlin module. |
| gRPC framework | `grpc-kotlin` + `grpc-spring-boot-starter` (or `net.devh:grpc-spring-boot-starter`). |
| Error format | Spring 6's `ProblemDetail` + a global `@RestControllerAdvice` handler. |
| Validation | `jakarta.validation` annotations on request DTOs; Spring auto-rejects with `400`. |
| Pagination | Offset (`Pageable`) for ≤ 10k row collections; cursor for larger / append-mostly. |
| Versioning (REST) | URL prefix (`/api/v1/...`). |
| Versioning (gRPC) | Package version (`com.example.users.v1`). |
| OpenAPI generation | `springdoc-openapi` (Spring 6/Boot 3+). |
| Rate limiting | Bucket4j with a Spring filter, exposed via `X-RateLimit-*` response headers. |

## Selective reading rule

| File | When to read |
|---|---|
| `resources/implementation-playbook.md` | Designing the actual contract — full REST patterns (collections, pagination, `ProblemDetail`, HATEOAS) and gRPC patterns (proto, server, status mapping, streaming, versioning) with Kotlin/Spring code. |
| `references/rest-best-practices.md` | Deep REST checklist: URL structure, status codes, filtering, pagination variants, rate limiting, caching headers, auth headers. |

## Related skills

| Skill | This not that |
|---|---|
| `spring-security-and-auth` | Auth *mechanism* (filter chain, JWT, OAuth2). This skill covers auth-shaped *contract* (401 vs 403, `WWW-Authenticate` header, idempotency for retries). |
| `messaging-rabbitmq-spring` | Async contracts (events, queues, ordering). This skill is sync request/response. The deciding question is "does the caller need an answer in this call?" |
| `cqrs-implementation` | Splitting the read and write models. This skill shapes the HTTP/gRPC surface of each side once you've decided to split. |
| `architecture` | Strategic decision (REST vs gRPC at system level, which boundaries get which protocol). This skill is the tactical contract. |
| `architecture-patterns` | Where the API layer sits in Onion / Clean / Layered. This skill is what flows across the layer's outer edge. |
| `architect-review` | Severity-graded review of an existing API surface. This skill designs and refactors; that one audits. |
| `system-design-fundamentals` | Capacity / sizing for the API. |
| `caching-strategies-spring` | HTTP caching headers (`ETag`, `Cache-Control`) and downstream caches — paired with this skill's contract guidance. |
| `database-design` | Persistence shape underneath. Always different from the API DTO shape; never expose entities directly. |

## Limitations
- A good contract cannot save a bad domain model. If the API feels awkward, the underlying domain probably needs work — pair with `ddd-tactical-patterns` or `clean-code-objects-and-data`.
- GraphQL is intentionally out of scope. If a use case genuinely pulls toward GraphQL (multi-shape reads from many heterogeneous clients), prefer a focused REST endpoint or a BFF instead, and surface the question to `architecture`.
- Stop and ask if consumer profile, latency requirements, or versioning policy are unclear — those are the inputs every other decision rests on.
