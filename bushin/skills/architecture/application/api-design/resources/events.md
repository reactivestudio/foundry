# Event contracts

Load when designing an event payload, picking an event name, evolving an
existing event schema, or arguing for async-over-sync. Broker-specific
patterns live in `rmq.md` / `kafka.md`; channel decision in
`messaging-boundary.md`.

## Events vs commands — the first fork

| | Event | Command |
|---|---|---|
| Verb tense | past — `order.placed`, `user.registered` | imperative — `place-order`, `register-user` |
| Direction | broadcast (0..N consumers) | targeted (one handler) |
| Authority | "this happened, deal with it" | "do this, tell me if you can't" |
| Failure model | producer doesn't know if it landed | producer expects an ack |
| Coupling | consumers couple to the event shape | command targets one service |

If you find yourself naming an "event" with an imperative verb, you have a
command in disguise — and async commands are usually a mistake, because
you've lost the back-channel for failure.

## Event names

`<noun>.<past-tense-verb>` or `<noun>.<past-tense-verb>.<version>`.

```
order.placed
order.cancelled
payment.captured
user.email-changed
invoice.paid.v2
```

Hierarchy (`order.payment.captured`) pays off with RabbitMQ topic
exchanges — consumers subscribe to families with `order.*` or
`order.payment.*`. Keep keys lowercase, dot-separated, no spaces, no IDs
embedded (`order.42.cancelled` is wrong — `42` is payload data, not a
routing dimension).

## Payload shape — two schools

| Approach | When | Trade-off |
|---|---|---|
| **Event-carried state transfer** (snapshot of the entity) | High-fanout events; consumers shouldn't call back | Larger payloads; data ages between event and processing |
| **Event notification** (IDs + minimal context only) | Consumers can call back cheaply; small audience | Smaller payloads; tight coupling — consumer needs the producer's read API |

Default to **event-carried state** for high-fanout events. Otherwise N
consumers all stampede the producer for the same lookup.

## Required metadata — set on every event

- **Event ID** (UUID, monotonic v7 preferred) — consumer's dedup key.
- **Event type** + version — `order.placed.v1`.
- **Event timestamp** — when it *happened*, not when it was *published*.
- **Aggregate ID** (`orderId`, `userId`) — also the partition / routing key.
- **Causation ID** + **correlation ID** — invaluable for tracing chains.

## Don't include

- Full database row dumps (column names from the DB schema leak through
  to the consumer; renaming a column becomes a breaking event change).
- Internal state-machine breadcrumbs no consumer needs
  (`internal_step_index`).
- Mutable URLs that may have changed by consumption time. Embed the
  values, not pointers.

## Schema evolution — append-only

Same rule as REST DTOs and proto fields. Add new optional fields. Never
change the meaning of an existing field; never repurpose names.

Concretely per format:

| Format | Rule |
|---|---|
| **JSON Schema** | Optional fields only; consumers ignore unknown fields by default. |
| **Avro** (Kafka + Schema Registry) | `BACKWARD` compatibility by default — new producer's schema readable by old consumers. New fields need a default. |
| **Protobuf** | Same rules as gRPC. `reserved` removed field numbers. |

Breaking change → publish a new version (`order.placed.v2`). Run both in
parallel during migration. Consumers migrate at their pace. Deprecate
`v1` with a sunset date documented in the schema registry / catalog.

## Delivery semantics

| Semantic | What it means | Cost |
|---|---|---|
| At-most-once | Fire and forget; may be lost | Cheap; useless for anything important |
| **At-least-once** | Will be delivered, possibly multiple times | Default; consumers must dedupe |
| Exactly-once | Delivered exactly once end-to-end | Expensive; scoped to broker-internal flows (Kafka EOS), not external side effects |

**Practical rule:** assume at-least-once. Design consumers to dedupe by
event ID. "Exactly-once" claims from a broker apply only to broker-internal
operations — DB writes and external HTTP calls on the consumer side are
still your responsibility to make idempotent.

## Consumer idempotency — three patterns

1. **Dedup table.** Insert `(event_id, processed_at)`; primary key
   conflict ⇒ skip. Simplest, costs one extra write per message.
2. **Idempotent operation.** Handler's effect is naturally idempotent
   (`SET user.email = 'new@x.com'`). No dedup table needed.
3. **Optimistic version check.**
   `WHERE aggregate.version = event.expectedVersion`. Combines dedup
   with out-of-order protection.

Combine #1 or #3 with monotonic version checks — out-of-order delivery
is real even with single-partition keys (under rebalances, retries).

## Ordering

Order is only guaranteed **per partition** (Kafka) or **per queue**
(RabbitMQ). Cross-partition ordering doesn't exist.

Pick the partition / routing key for ordering, not load:

| Goal | Key |
|---|---|
| Order per user | `userId` |
| Order per business entity | aggregate ID (`orderId`, `invoiceId`) |
| No ordering needed | random / round-robin |
| Global order | single partition — kills parallelism; usually wrong |

Don't key on a value that distributes badly. A status field with 3 values
turns into 3 hot partitions and N − 3 idle ones.

## DLQ — dead letter queue

Every consumer needs a poison-message escape hatch:

- After N retries, move the message to a dead-letter queue / topic.
- Alarm on DLQ size > 0.
- Build a manual replay tool — DLQ messages eventually need to flow back
  through after the producer fix.

Without DLQ, one poison message blocks the partition or queue forever.

## Outbox pattern — reliable publication

To publish an event reliably alongside a DB write, use the **outbox**:

1. In the *same DB transaction* as the business write, insert a row into
   an `outbox` table.
2. A separate process polls the outbox and publishes to the broker, then
   marks rows as sent.
3. Crash anywhere ⇒ at worst, a duplicate event (consumer dedupes by
   event ID — see above).

**Never** call `producer.send()` from inside a DB transaction — the
broker isn't in your transaction boundary, and you'll get "wrote DB but
didn't publish" or vice versa.

## Choreography vs orchestration

| | Choreography | Orchestration |
|---|---|---|
| Coordination | services react to each other's events | central coordinator drives the flow |
| Coupling | loose | tighter (everyone knows the coordinator) |
| Best for | simple, observable flows | complex multi-step transactions (sagas) |

This is an architecture decision (not a contract one) — but it shapes
event vocabulary. Orchestrated flows tend to have `*.requested`,
`*.completed`, `*.failed` triplets per step.

## AsyncAPI

Just as OpenAPI describes REST and `.proto` describes gRPC, **AsyncAPI**
describes events — schema, channel binding, message metadata. Use it to
make event contracts reviewable in PRs alongside the rest of the API
surface.
