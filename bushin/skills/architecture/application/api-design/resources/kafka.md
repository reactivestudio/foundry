# Kafka contract patterns

Load when designing topic layout, partitioning, schema, or consumer
semantics for Kafka. Pair with `events.md` for payload shape and `rmq.md`
when choosing brokers.

## Topic — the unit of contract

A topic is the **published contract**. Treat each topic like a REST
endpoint: name, schema, semantics, retention, partition strategy are all
part of the published surface.

Naming: `<domain>.<aggregate>.<event-type>` or
`<domain>.<aggregate>.<event-type>.<version>`.

```
billing.invoice.created.v1
billing.invoice.paid.v1
orders.order.placed.v1
audit.user.login
```

**One event type per topic** by default. Putting all events into a single
"event-bus" topic looks tidy but breaks:

- Every consumer re-reads everything to filter.
- Schemas diverge per event type silently.
- Compaction can't make sense of mixed key spaces.

Per-aggregate streams in event sourcing are an exception, and require
explicit per-event-type schema versioning within the topic.

## Partitions — capacity and ordering

Two roles in one knob:

- **Ordering boundary** — events with the same partition key arrive in
  order; across keys, no guarantee.
- **Parallelism cap** — within a consumer group, one partition is read
  by at most one consumer. 10 partitions ⇒ at most 10 parallel
  consumers in any group.

```
billing.invoice.created.v1, partitions=12, key=companyId
```

**Partition count is hard to change** after launch — adding partitions
rehashes existing keys to new partitions, breaking keyed ordering.
Size for peak parallelism + headroom from day one (12, 24, 48 are
typical starting points).

## Partition key — pick it for ordering, not load

| Goal | Key |
|---|---|
| Order per user / customer / company | `userId` / `companyId` |
| Order per business entity | aggregate ID (`orderId`, `invoiceId`) |
| No ordering, pure work distribution | random / round-robin / null key |
| Global order | single partition — kills parallelism; usually wrong |

Don't key on a low-cardinality value if order matters. A `status` field
with 3 values turns into 3 hot partitions and N − 3 idle ones.

If the partition key changes mid-life (a record reassigned to a new
customer), publish to the new key and let the old be ignored — there's
no "move" operation in Kafka.

## Compacted topics — latest-value semantics

```
config.user-settings, compaction = enabled, key = userId
```

The broker keeps only the **latest record per key**. A full topic scan
yields the current state for every key ever seen. Use for:

- Reference data (user settings, feature flags per tenant).
- Materialised state for KTable / GlobalKTable joins.
- "Latest known status" feeds.

**Don't compact** an event log you want to replay — compaction loses
intermediate history by design.

Tombstones (`null` value with the key) signal deletion under compaction.

## Schema registry — make schemas reviewable

Schema-less Kafka is a contract pretending it doesn't exist. Use a
registry (Confluent Schema Registry, Apicurio).

Compatibility modes — pick per topic:

| Mode | Producer rule | Consumer rule |
|---|---|---|
| **BACKWARD** (default) | new schema reads old data | old consumers tolerate new fields via defaults |
| FORWARD | old schema reads new data | new consumers read old data |
| FULL | both | both |
| NONE | anything goes | breaks at runtime |

**BACKWARD is the safe default** — producer rolls first, then consumers
catch up. New optional fields with defaults are the only safe additive
change.

Avro, Protobuf, or JSON Schema all work. Avro is the historical default
in Confluent stacks; protobuf is increasingly common when the same team
also ships gRPC contracts.

## Consumer groups — one logical reader

Each partition is consumed by exactly one consumer **in a group**.
Groups are independent — adding a new consumer group lets a new service
replay from any offset without affecting existing readers.

This is the fan-out primitive: each service that cares about a topic
gets its own consumer group with its own offset position.

## Offset commit — your at-least-once knob

```kotlin
// Auto-commit (default) — commits every auto.commit.interval.ms.
// Crash between commit and processing = duplicate.
// Crash after process but before commit = duplicate.
props["enable.auto.commit"] = "false"      // do this

// Manual commit AFTER processing
while (true) {
    val records = consumer.poll(Duration.ofMillis(500))
    records.forEach { process(it) }
    consumer.commitSync()                  // commit only after all processed
}
```

Manual commit after processing = at-least-once delivery. Combine with
consumer-side idempotency (event ID dedup) for end-to-end safety. See
`events.md` for the dedup patterns.

## Exactly-once (EOS) — scoped, not magical

Kafka EOS guarantees exactly-once **within Kafka**: read from input
topic, process, write to output topic — all in one transaction.

It does **not** extend to:
- External DB writes outside the Kafka transaction (use the outbox
  pattern; see `events.md`).
- HTTP calls to other services.
- Any side effect that isn't another Kafka topic.

For most systems: **at-least-once + consumer idempotency.** EOS is for
stream-processing pipelines (Kafka Streams, Flink) staying inside Kafka
end-to-end.

## Headers — out-of-band metadata

Use headers, not payload fields, for transport metadata:

- `event-id` — dedup key for the consumer (in addition to the payload's
  ID).
- `trace-id` / `span-id` — distributed tracing.
- `schema-version` — when not using a registry.
- `correlation-id` / `causation-id` — chain identification.

The payload stays domain-shaped; the headers carry plumbing.

## Retention — keep the history you actually need

| Policy | Use for |
|---|---|
| **Time-based** (e.g. 7d, 30d) | events you want replayable for new consumers / debugging |
| Size-based | bounded disk; combined with time-based |
| Compaction | latest-value lookup streams |
| Forever (compaction + long time) | event sourcing aggregates |

Default for a new event topic: **7d minimum** time-based. Shorter
retention forces consumers to keep up — useful as a discipline lever,
not a default.

## Common mistakes

- **All events in one topic** ("event bus"). Consumers filter at the
  application layer; schemas diverge per event type silently.
- **No partition key** when ordering matters → race conditions in
  consumers downstream.
- **Random key with `compaction=true`** → every key is unique, broker
  keeps everything, disk grows forever.
- **`enable.auto.commit = true`** with side effects → duplicates or
  losses depending on crash timing.
- **No schema registry.** Producer changes a field type silently →
  consumers crash at deserialization Tuesday morning.
- **One partition "to keep order"** → no parallelism, throughput hits
  the wall on the first 10× growth.
- **Repartitioning in production** to fix the previous mistake → keyed
  ordering breaks, downstream chaos.
- **Forgetting the outbox** for events emitted alongside DB writes →
  silent loss when the broker is briefly unreachable.
