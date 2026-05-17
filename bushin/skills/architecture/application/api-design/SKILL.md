---
name: api-design
description: "REST/gRPC + event (RMQ/Kafka) contracts: status, errors, idempotency, schemas. NOT for auth."
---

# api-design

## When to use
- Designing a new REST or gRPC endpoint, service, or boundary.
- Designing an event contract — Kafka topic, RabbitMQ exchange / queue, payload schema, ordering, delivery semantics.
- Defining service-wide conventions for errors, pagination, versioning, idempotency, schema evolution.
- Choosing the right channel: sync REST/gRPC vs server-stream vs async event vs push-to-client.
- Reviewing an OpenAPI / `.proto` / AsyncAPI spec before implementation.
- Refactoring a contract where consumers report surprises.

## Principles
1. **Contract is a published commitment.** Lock URL + payload + status (or `.proto`, or event schema) before handlers. Migrations are the most expensive thing you'll ever ship.
2. **Status code is truth.** Never `200 OK` with `{"error": …}`. The status line is the API; the body is the detail.
3. **`401 ≠ 403`.** `401` = "I don't know who you are" (send `WWW-Authenticate`). `403` = "I know you; you can't." Confusing them leaks resource existence and breaks generic auth retries.
4. **Safe ≠ idempotent.** Safe = no side effects (`GET`/`HEAD`). Idempotent = same outcome on retry (`GET`/`PUT`/`DELETE`). `POST` is neither — add `Idempotency-Key` when retries must be safe.
5. **`400 ≠ 422`.** `400` = malformed (parser failed). `422` = parsed but business-invalid (validation). Routinely conflated.
6. **One error envelope per protocol.** RFC 7807 `ProblemDetail` for REST; `google.rpc.Status` for gRPC. Different shapes per endpoint multiply consumer complexity.
7. **Pagination has bounds.** Server-side `pageSize` cap; reject above. Offset for small/random-access; cursor (opaque base64 token) for large/append-mostly. Never both on one endpoint.
8. **Version on day one.** `/api/v1/…` (REST), `package x.y.v1;` (gRPC), `order.placed.v1` or schema-registry version (events). Adding versioning later costs an order of magnitude more.
9. **Schema evolution is append-only.** Add new optional fields; never repurpose. In gRPC, `reserved` removed numbers. In Avro/proto registry, BACKWARD-compatible only by default.
10. **Events are contracts too.** Event name (past-tense), payload, partition/routing key, delivery semantics (at-least-once is the default; exactly-once is expensive and scoped). Consumers couple to all of them.
11. **Async consumers must be idempotent.** Every broker delivers at-least-once on failure. Producers stamp an event ID; consumers dedupe by it.

## Procedure
1. **List the consumers and how they learn about changes.** Web, mobile (online vs backgrounded), partner, internal service, batch job. For each: do they pull (REST/gRPC), get pushed to (SSE/WebSocket/gRPC stream/FCM-APNs), or react to events (Kafka/RMQ)? If a consumer would silently miss state changes, the design is broken — name the channel.
2. **Sync or async per interaction.** Caller needs the answer in-call → sync. Caller doesn't (fan-out, decoupled, slow) → event. Hybrid (`202` + status resource + event/webhook on done) is common — finish both halves.
3. **Resources before handlers.** Nouns, identities, lifecycles. If the verb won't fit a method, the resource is probably wrong.
4. **Methods deliberately.** Safe vs idempotent matters more than the verb that "feels right".
5. **Error envelope first.** `ProblemDetail` (REST) / `google.rpc.Status` (gRPC). Wire one global handler before writing the second endpoint.
6. **Pagination per endpoint.** Cursor or offset — pick one. Cap `pageSize`.
7. **`v1` everywhere.** URL prefix / proto package / event name suffix or registry. No exceptions.
8. **Idempotency on retry-sensitive writes.** Sync: `Idempotency-Key` header (Stripe pattern). Async: event ID + consumer-side dedup.
9. **Review the five leaks.** Status/body mismatch; 401/403 confusion; 404/403 information leak; persistence entities in response or payload; consumer assumes exactly-once delivery.

## Channel decision — per interaction
| Interaction | Pick | Why |
|---|---|---|
| Browser / partner / curl-debuggable sync | REST + JSON | universal, browser-native, lowest onboarding cost |
| Internal high-volume service-to-service sync | gRPC | binary efficiency, generated clients, typed contracts |
| Streaming to a known consumer (server / bidi) | gRPC | first-class; SSE / WebSocket in REST are workarounds |
| Server pushes to an open browser tab | SSE (one-way) / WebSocket (two-way) | natively supported, no broker |
| Mobile app receives changes when backgrounded / killed | FCM / APNs | OS-level delivery; in-app channels don't reach a sleeping app |
| Fan-out to N internal consumers, caller doesn't wait | Event (Kafka / RMQ) | decouples producer and consumer lifecycles |
| Targeted work queue with retry / DLQ | RabbitMQ | queues, routing, dead-letter primitives |
| Replayable event log / activity stream / event sourcing | Kafka | partitioned, retained, compacted topics |

REST + gRPC + events coexist. Decide **per interaction**, not per system.

## Red flags
- A `POST` URL contains a verb.
- An endpoint returns `200 OK` with an error body.
- Two endpoints with the same shape return different error envelopes.
- `pageSize` has no server-side cap.
- A protobuf change reused a field number.
- The spec is silent on what happens when the same `Idempotency-Key` arrives twice with different bodies.
- A consumer is described as "needs to know when X happens" but no delivery channel is named.
- An event payload looks like a database row dump.
- The async design assumes exactly-once delivery; consumers don't dedupe.
- An "event" is named with an imperative verb (`process-order`) — it's a command in disguise.

## When NOT to use
- Auth mechanism (JWT / OAuth2 / filter chain). This skill covers auth-shaped *contract* (`401` vs `403`, `WWW-Authenticate`), not the flow.
- CQRS split between read and write models — handle the split elsewhere, then return here for each side's surface.
- System-level "which boundary speaks what" — that's an architecture-level call. This skill is the tactical contract.
- Capacity / load sizing.
- Broker operations (cluster sizing, replication, monitoring, on-call) — only the *contract* belongs here.

## Resources
| File | Load when |
|---|---|
| `resources/theory.md` | Justifying a contract decision (Fielding constraints, contract-first rationale) |
| `resources/rest.md` | Designing or refactoring a REST endpoint |
| `resources/grpc.md` | Writing or evolving a `.proto` |
| `resources/rest-vs-grpc.md` | Choosing between sync protocols for a boundary |
| `resources/events.md` | Designing an event contract — naming, payload, schema evolution, consumer idempotency, DLQ, outbox |
| `resources/rmq.md` | RabbitMQ topology — exchanges, queues, routing keys, DLX, ack semantics |
| `resources/kafka.md` | Kafka topics, partition keys, compaction, schema registry, EOS scope |
| `resources/messaging-boundary.md` | Sync vs async per interaction; server-to-client push patterns; webhooks |
| `resources/errors.md` | Picking status codes; mapping domain errors to wire codes |
| `resources/pagination.md` | Picking offset vs cursor; sizing caps |
| `resources/versioning.md` | Introducing v2 or weighing strategies |
| `resources/idempotency.md` | Retry-safety on `POST`; consumer dedup on events |
| `resources/anti-patterns.md` | Reviewing an existing surface for contract smells |
| `resources/spring.md` | Project is on Spring Boot |
| `resources/kotlin-idioms.md` | Project is on Kotlin and you want idiomatic glue |
| `resources/ddd-binding.md` | API sits at a bounded-context edge |

## Source
Fielding (REST dissertation, 2000); Richardson Maturity Model; Google AIP 100/121/131/134/154/158/160/193/231; RFC 7807 / 9457 (Problem Details); RFC 9110 (HTTP Semantics); Stripe API conventions; AsyncAPI 3.0; Confluent Kafka design guides; RabbitMQ official docs; Outbox / Saga patterns.
