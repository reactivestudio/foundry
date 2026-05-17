# RabbitMQ contract patterns

Load when designing exchanges, queues, and routing for an RMQ-based async
boundary. Pair with `events.md` for payload shape and `messaging-boundary.md`
for the channel decision.

## Topology — exchange → queue → consumer

```
producer → [exchange] --routing key--> [queue A] → consumer group A
                                  └──> [queue B] → consumer group B
                                  └──> [DLQ via DLX] (poison messages)
```

Producers publish to **exchanges**, never directly to queues. Consumers
read from **queues**. A queue is bound to an exchange with a routing key
pattern. This indirection is the whole point of AMQP — re-route or
add a new consumer group without producer changes.

## Exchange types — pick one per purpose

| Exchange | Routing | Use for |
|---|---|---|
| **direct** | exact match on routing key | dispatch by event type when keys are flat |
| **topic** | wildcards on dotted keys (`*` one segment, `#` zero+) | hierarchical events (`order.payment.captured`) |
| **fanout** | broadcast to all bound queues | notifications, cache invalidation, fan-out reads |
| **headers** | match on message headers | rare; avoid unless routing logic genuinely needs it |

Defaults: **topic** for event-style traffic, **direct** for command-style
work queues.

## Queue properties — make survival explicit

```
queue.declare(
    name        = "orders.placed.warehouse-notifier",
    durable     = true,        # queue definition survives broker restart
    auto_delete = false,
    arguments   = {
        "x-queue-type":             "quorum",     # modern default; replicated
        "x-dead-letter-exchange":   "orders.dlx", # poison messages go here
        "x-message-ttl":            86_400_000,   # 24h before DLX
        "x-max-length":             1_000_000,    # bounded; alarm before
    }
)
```

Publish with `delivery_mode = 2` (persistent) for messages that must
survive broker restart. Without `durable queue + persistent message +
manual ack`, you have at-most-once delivery dressed up.

**Quorum queues** are the modern default — replicated across nodes,
crash-safe. Classic mirrored queues are legacy.

## Acknowledgments — manual, always

```kotlin
// Auto-ack (default in many libs) — message removed from the queue the
// moment it's delivered, before your handler runs. Crash mid-handler =
// silently lost.
channel.basicConsume(queueName, /* autoAck= */ true, deliverCallback, cancelCallback)

// Manual ack — message stays until you ack. Crash = redelivered.
channel.basicConsume(queueName, /* autoAck= */ false, { tag, delivery ->
    try {
        process(delivery.body)
        channel.basicAck(tag, false)
    } catch (e: RetryableException) {
        channel.basicNack(tag, false, /* requeue= */ true)
    } catch (e: PoisonException) {
        channel.basicNack(tag, false, /* requeue= */ false)  // → DLX
    }
})
```

**Always manual ack** for at-least-once delivery. Auto-ack is for
throwaway streams where loss is acceptable (debug dumps, telemetry).

## DLX — dead letter exchange

```
orders-exchange ──► orders-queue (x-dead-letter-exchange: orders-dlx)
                                                                  │
                                                                  ▼
                                                          orders-dlx ──► orders-dlq
```

A message is re-published to the DLX when:
- The consumer rejects it (`basic_nack(requeue=false)`).
- Its TTL expired.
- The queue reached its length limit.

You then either:
- Hold DLQ messages for manual inspection and replay.
- Implement automated retry with backoff via a TTL'd retry-queue chain:
  `orders.retry.30s` (TTL 30s, DLX = orders-exchange) → original queue.
  Three such queues at 10s / 1m / 10m give you exponential-ish backoff.

Without DLX, one poison message blocks the queue forever or quietly
vanishes.

## Prefetch — the backpressure dial

```kotlin
channel.basicQos(prefetchCount = 10)
```

How many unacked messages a consumer holds at a time. Too low → consumer
idle waiting for ack round-trips. Too high → uneven distribution across
consumer instances (one greedy consumer holds everything; others starve).
Start with 10–50, measure, tune to your handler latency.

## Routing key conventions

Dotted hierarchy, lowercase, no IDs:

```
order.placed
order.cancelled
order.payment.captured
order.payment.refunded
user.profile.updated
```

Consumers subscribe to families:

- `order.*` — one segment after `order` (placed, cancelled)
- `order.payment.*` — captured, refunded
- `order.#` — everything `order.…` (zero+ segments)

`#` after a prefix is the catch-all. `*` is exactly one segment.

## Message properties — metadata you always set

```kotlin
val props = AMQP.BasicProperties.Builder()
    .messageId("evt_${UUID.randomUUID()}")    // dedup key for the consumer
    .correlationId(parentMessageId)            // tracing chain
    .timestamp(Date())
    .contentType("application/json")
    .type("order.placed.v1")                   // event type + version
    .deliveryMode(2)                           // persistent
    .build()
```

`messageId` is the consumer's idempotency token. Set it; consumers dedupe
by it.

## Competing consumers vs fan-out

| Goal | Topology |
|---|---|
| Work queue — N consumers split the load | one queue, N consumers |
| Fan-out — every consumer group gets every message | one exchange, one queue **per consumer group**, each bound to the exchange |

Sharing one queue across unrelated consumer groups is a common mistake —
the broker load-balances between them, so each group sees only its
fraction. Each consumer group needs its own queue, bound to the shared
exchange with appropriate routing keys.

## Common mistakes

- **No DLX.** Poison message → consumer crashes in a redeliver loop, or
  the broker silently drops it after retries (depending on config).
- **Auto-ack with side effects.** Process crashes → message gone, side
  effect missing.
- **Publishing directly to a queue.** Works but you lose the indirection
  AMQP gave you. Always publish to an exchange.
- **Shared queue between consumer groups.** Two groups load-balance
  against each other instead of receiving independent copies.
- **No `delivery_mode = 2`** on a durable queue → broker restart loses
  in-flight messages.
- **No `prefetch_count`.** One consumer monopolises; others starve.
- **Routing key with IDs.** `order.42.cancelled` is wrong; `42` belongs
  in the payload.

## When RabbitMQ vs Kafka

| Need | RabbitMQ | Kafka |
|---|---|---|
| Retry / DLQ semantics out of the box | ✓ | manual |
| Per-message TTL | ✓ | per-topic only |
| Long retention / replay | uncommon | core feature |
| Order across a stream of messages by key | per queue | per partition |
| Schema registry on the broker | external | Confluent SR built-in |
| Work queue with N competing consumers | natural | possible (consumer group) |
| Millions of msgs/sec sustained | bounded | core strength |

Pair this with `kafka.md` and the decision frame in
`messaging-boundary.md` when choosing brokers.
