---
name: messaging-rabbitmq-spring
description: "RabbitMQ patterns for Kotlin/Spring Boot — exchanges (direct/topic/fanout/headers), queues, bindings, routing keys; Spring AMQP (`RabbitTemplate`, `@RabbitListener`); reliability (publisher confirms, mandatory flag, return callbacks, transactional vs publisher-confirms); idempotent consumers; dead-letter queues; retry with backoff; quorum queues; outbox pattern. Use when designing async messaging, integrating RabbitMQ in a Spring service, or debugging message loss / duplication / poison-message issues."
risk: safe
source: "custom — RabbitMQ + Spring AMQP patterns for Kotlin"
date_added: "2026-05-12"
---

# Messaging with RabbitMQ (Kotlin / Spring AMQP)

RabbitMQ is the right messaging tool when you need **routing flexibility, low operational footprint, and per-message acknowledgement semantics**. Kafka wins for high-throughput append-only logs; RabbitMQ wins for traditional work queues, RPC-style request/response, and fan-out with selective routing.

> A message system without dead-letter queues, idempotent consumers, and publisher confirms is a system that loses messages and you don't know it.

## Use this skill when

- Designing an async messaging architecture in a Spring service
- Integrating RabbitMQ as an event bus across bounded contexts
- Picking between direct, topic, fanout, and headers exchanges
- Wiring publisher confirms / returns / DLQ / retry policies
- Debugging message loss, duplication, or poison messages
- Implementing the transactional outbox pattern with RabbitMQ
- Choosing between classic mirrored queues and quorum queues

## Do not use this skill when

- You need a **durable replayable log** (event sourcing source-of-truth) — that's Kafka territory
- The task is **in-process events** within a single Spring app — use Spring Modulith events / `ApplicationEventPublisher`, see `cqrs-implementation`
- You need **strict ordering across all consumers** for millions of messages/sec — Kafka with partitioning
- The task is **request/response over HTTP/gRPC** — that's not messaging, see `api-design-principles`

## Selective Reading Rule

| File | Description | When to read |
|---|---|---|
| `resources/exchange-and-routing.md` | 4 exchange types (direct, topic, fanout, headers), bindings, routing keys, how to choose | Designing topology; deciding routing strategy |
| `resources/spring-amqp-patterns.md` | `RabbitTemplate`, `@RabbitListener`, message converters (Jackson2JsonMessageConverter), serialization, concurrency tuning | Implementing producer/consumer in Kotlin/Spring |
| `resources/reliability.md` | Publisher confirms, mandatory + return callbacks, transactional channels, consumer ack modes, idempotent consumers, DLQ, retry with exponential backoff, quorum vs classic queues, outbox | Hardening for production — at-least-once delivery, no-loss guarantees |

## Core principles

1. **At-least-once delivery is the default.** Messages can be redelivered, even with publisher confirms. **Consumers must be idempotent.** Plan for it from day one.
2. **Acknowledge after side effects, not before.** `manual` ack mode. Process message → commit DB / external effect → ack. If consumer crashes mid-process, message is redelivered.
3. **Dead-letter queue is non-negotiable.** Every queue needs a DLQ. A message that fails 3+ times goes to DLQ for human inspection. No DLQ → poison messages spin forever.
4. **Publisher confirms for any message that matters.** Without confirms, the broker can drop a message and the publisher doesn't know. Spring AMQP `publisher-confirm-type: correlated`.
5. **Quorum queues for new deployments.** Classic mirrored queues are deprecated. Quorum queues are Raft-based, more reliable, slightly slower. Default for new queues since RabbitMQ 3.8+.
6. **One queue per consumer group.** Different consumers want different processing? Different queues bound to the same exchange. Don't share a queue across logically different consumers.
7. **Routing keys are not a free-form string.** Define a convention (e.g., `<bounded-context>.<aggregate>.<event>` like `code.pullrequest.merged`) and stick to it.
8. **Don't use RabbitMQ as a database.** Messages are not a query store. If you find yourself "browsing" queues for state, you need a database.

## Anti-patterns (avoid)

- **No publisher confirms.** Silent message loss when broker fails to enqueue.
- **`auto` ack mode.** Consumer acks on receive, before processing. Crash mid-process → message lost.
- **Catching exceptions in listener and acking anyway.** Hides poison messages. Let them fail; the retry / DLQ machinery exists for this.
- **One giant queue for everything.** Different consumer concerns share a queue, head-of-line blocking, slow consumer starves others.
- **Routing keys as a free-for-all.** No convention → topic exchange becomes useless wildcard soup.
- **No DLQ.** Poison messages spin forever; consumer never makes progress on real traffic.
- **Synchronous request/reply over messaging.** "Send message, wait for response with timeout" → use HTTP or gRPC. Messaging is async by nature; synchronous RPC over it adds latency and complexity for no gain.
- **Putting megabyte payloads in messages.** RabbitMQ is in-memory + disk-backed; big payloads hurt throughput. Put big things in object storage, reference by URL in the message.
- **No durable / persistent flag.** Non-persistent messages disappear on broker restart. Always `delivery_mode = persistent` for messages that matter.
- **Using `RabbitTemplate.convertAndSend(...)` synchronously without confirm handling.** Returns immediately; success != broker accepted. Use `correlatedConfirm` callbacks or transactional channels.

## When to pick RabbitMQ over Kafka

| Concern | RabbitMQ | Kafka |
|---|---|---|
| Throughput target | 50K msg/sec/node | 1M+ msg/sec |
| Latency | sub-ms | ~5ms |
| Routing flexibility | High — exchanges, topics, headers | Low — fixed topic / partition |
| Message-level ack | Yes | No (offset-based) |
| Replay history | No (consumed = gone unless DLQ) | Yes (configurable retention) |
| Ordering guarantee | Per-queue | Per-partition |
| Consumer groups | One queue, multiple consumers competing | First-class consumer groups |
| Operations | Simpler, single-node viable | Cluster + Zookeeper/KRaft |
| Best for | Work queues, RPC, fan-out, work distribution | Event log, stream processing, analytics |

You chose RabbitMQ — that's a fine fit for cross-context event distribution, work queues, fan-out to vendor adapters, and request/response style RPC. Kafka would be overkill.

## Stack mapping for assista-style polyglot

| Use case | Topology | Routing |
|---|---|---|
| Cross-bounded-context domain events | `topic` exchange `domain.events`, routing key `<ctx>.<aggregate>.<event>` (e.g., `code.pullrequest.merged`) | Each consumer binds with pattern (`code.*.*`, `*.pullrequest.*`) |
| Vendor adapter outbound webhooks | `direct` exchange `vendor.outbound`, routing key = vendor name | Per-vendor consumer queue |
| Fan-out notifications | `fanout` exchange `notifications.global` | Each subscriber has own queue |
| RPC-style work distribution | `direct` exchange + reply queue (avoid, prefer gRPC) | — |
| Slow downstream integration jobs (vendor API calls) | `direct` exchange `jobs`, dedicated queue per job class, prefetch=10 | — |

## Spring Boot integration headlines

```kotlin
// build.gradle.kts
implementation("org.springframework.boot:spring-boot-starter-amqp")
testImplementation("org.springframework.amqp:spring-rabbit-test")
testImplementation("org.testcontainers:rabbitmq")
```

```yaml
spring:
  rabbitmq:
    host: rabbit.internal
    port: 5672
    username: app
    password: ${RABBIT_PASSWORD}
    virtual-host: assista
    publisher-confirm-type: correlated     # critical
    publisher-returns: true
    template:
      mandatory: true                       # bounce undeliverable
    listener:
      simple:
        acknowledge-mode: manual            # explicit ack
        prefetch: 10
        retry:
          enabled: true
          max-attempts: 3
          initial-interval: 1s
          multiplier: 2
          max-interval: 30s
```

## Related skills

- `cqrs-implementation/resources/write-side-patterns.md` — Spring Modulith outbox pattern; the same idea, often the right starting point
- `architecture` Example 3 — when message bus is appropriate at the architectural level
- `ddd-context-mapping` — Published Language across the bus
- `api-design-principles` — REST/gRPC vs messaging decision
- `testing-strategy-kotlin-spring` — Testcontainers RabbitMQ for integration tests
- `database-design/resources/migrations.md` — outbox table for transactional outbox pattern
- `debugging-systematic` — when a message is "lost" (almost never; usually a consumer ack bug)

## Limitations

- Patterns assume Spring AMQP (`spring-boot-starter-amqp`). Reactive RabbitMQ (Spring AMQP Reactor) has slightly different API.
- No coverage of RabbitMQ Streams (added in 3.9) — different abstraction, more Kafka-like.
- Stop and ask if the **delivery guarantee target** is unclear (at-least-once vs exactly-once-ish vs best-effort) — it drives every reliability decision.
