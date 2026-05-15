---
name: api-design
description: "REST/gRPC contracts: status, errors, idempotency, pagination, versioning. NOT for auth flow."
---

# api-design

## When to use
- Designing a new REST or gRPC endpoint, service, or boundary.
- Defining service-wide conventions for errors, pagination, versioning, idempotency.
- Choosing between REST and gRPC for a use case (or combining them).
- Reviewing an OpenAPI spec or `.proto` before implementation.
- Refactoring a contract where consumers report surprises.

## Principles
1. **Contract is a published commitment.** Lock URL + payload + status (or `.proto`) before handlers. Consumer migrations are the most expensive thing you'll ever ship.
2. **Status code is truth.** Never `200 OK` with `{"error": …}`. The status line is the API; the body is the detail.
3. **`401 ≠ 403`.** `401` = "I don't know who you are" (send `WWW-Authenticate`). `403` = "I know you; you can't." Confusing them leaks resource existence and breaks generic auth retries.
4. **Safe ≠ idempotent.** Safe = no side effects (`GET`/`HEAD`). Idempotent = same outcome on retry (`GET`/`PUT`/`DELETE`). `POST` is neither — add `Idempotency-Key` when retries must be safe.
5. **`400 ≠ 422`.** `400` = malformed (parser failed). `422` = parsed but business-invalid (validation). Routinely conflated.
6. **One error envelope.** RFC 7807 `ProblemDetail` (`type`/`title`/`status`/`detail`/`instance` + typed extensions) across the whole surface. Per-endpoint shapes multiply consumer complexity.
7. **Pagination has bounds.** Server-side `pageSize` cap; reject above. Offset for small/random-access; cursor (opaque base64 token) for large/append-mostly. Never both on one endpoint.
8. **Version on day one.** `/api/v1/…` (REST) or `package x.y.v1;` (gRPC). Carrying `v1` from launch costs an order of magnitude less than adding it later.
9. **Field evolution is append-only.** Add new optional fields; never repurpose. In gRPC, `reserved` removed numbers — never reuse.

## Procedure
1. **Resources before handlers.** List nouns, identities, lifecycles. If the verb won't fit a method, the resource is probably wrong.
2. **Methods deliberately.** Safe vs idempotent matters more than the verb that "feels right".
3. **Error envelope first.** `ProblemDetail` (REST) or `google.rpc.Status` (gRPC). Wire one global handler before writing the second endpoint.
4. **Pagination per endpoint.** Cursor or offset — pick one. Cap `pageSize`.
5. **`v1` everywhere.** URL prefix or proto package. No exceptions.
6. **`Idempotency-Key` on retry-sensitive `POST`s.** Payments, sends, ticket creation — anything you'd hate to repeat.
7. **Review the four leaks.** Status/body mismatch, 401/403 confusion, 404/403 information leak, persistence entities in the response.

## REST vs gRPC — quick frame
| Boundary | Pick | Why |
|---|---|---|
| Browser / public / partner | REST + JSON | curl-debuggable, browser-native, lowest onboarding cost |
| Internal high-volume service-to-service | gRPC | binary efficiency, generated clients, typed contracts |
| Streaming (server / bidi) | gRPC | first-class; SSE / WebSocket in REST are workarounds |
| Polyglot internal consumers | gRPC | one `.proto` → clients in every language |
| Ad-hoc CLI debugging is the workflow | REST | grpcurl exists but is heavier |

Combining is fine — gRPC inside, REST at the edge. Decide per-boundary.

## Red flags
- A `POST` URL contains a verb.
- An endpoint returns `200 OK` with an error body.
- Two endpoints with the same shape return different error envelopes.
- `pageSize` has no server-side cap.
- A protobuf change reused a field number.
- The spec is silent on what happens when the same `Idempotency-Key` arrives twice with different bodies.

## When NOT to use
- Auth mechanism (JWT / OAuth2 / filter chain). This skill covers auth-shaped *contract* (`401` vs `403`, `WWW-Authenticate`), not the flow.
- Async event contracts (queue topology, payload shape, ordering). Deciding question: "does the caller need an answer in this call?"
- CQRS split between read and write models — handle the split elsewhere, then return here for each side's surface.
- System-level "which boundary speaks what" — that's an architecture-level call. This skill is the tactical contract.
- Capacity / load sizing.

## Resources
| File | Load when |
|---|---|
| `resources/theory.md` | Justifying a contract decision (Fielding constraints, contract-first rationale) |
| `resources/rest.md` | Designing or refactoring a REST endpoint |
| `resources/grpc.md` | Writing or evolving a `.proto` |
| `resources/rest-vs-grpc.md` | Choosing between protocols for a new boundary |
| `resources/errors.md` | Picking status codes; mapping domain errors to wire codes |
| `resources/pagination.md` | Picking offset vs cursor; sizing caps |
| `resources/versioning.md` | Introducing v2 or weighing strategies |
| `resources/idempotency.md` | Adding retry-safety to a state-changing `POST` |
| `resources/anti-patterns.md` | Reviewing an existing surface for contract smells |
| `resources/messaging-boundary.md` | Asking "should this be sync at all?" |
| `resources/spring.md` | Project is on Spring Boot |
| `resources/kotlin-idioms.md` | Project is on Kotlin and you want idiomatic glue |
| `resources/ddd-binding.md` | API sits at a bounded-context edge |

## Source
Fielding (REST dissertation, 2000); Richardson Maturity Model; Google AIP 100/121/131/134/154/158/160/193/231; RFC 7807 (Problem Details); RFC 9110 (HTTP Semantics); Stripe API conventions.
