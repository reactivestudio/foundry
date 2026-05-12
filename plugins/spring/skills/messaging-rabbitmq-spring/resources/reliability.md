# Reliability — Confirms, DLQ, Retry, Quorum, Outbox

How not to lose messages. How not to duplicate (much). How to recover from poison.

---

## 1. Publisher confirms — broker says "I got it"

```yaml
spring:
  rabbitmq:
    publisher-confirm-type: correlated
    publisher-returns: true
    template:
      mandatory: true
```

```kotlin
@Configuration
class RabbitConfig {
    @Bean
    fun rabbitTemplate(connectionFactory: ConnectionFactory,
                       converter: MessageConverter): RabbitTemplate =
        RabbitTemplate(connectionFactory).apply {
            messageConverter = converter
            setMandatory(true)
            setConfirmCallback { correlationData, ack, cause ->
                if (ack) {
                    log.debug("Publisher confirm ACK for {}", correlationData?.id)
                } else {
                    log.error("Publisher confirm NACK for {}: {}", correlationData?.id, cause)
                    // Retry, alert, or escalate
                }
            }
            setReturnsCallback { returned ->
                log.error("Returned message: {} routingKey={} reason={}",
                    returned.message, returned.routingKey, returned.replyText)
                // No queue matched — topology bug or wrong routing key
            }
        }
}
```

**Three guarantees combined:**
1. `publisher-confirm-type: correlated` — broker callback when message persisted (async)
2. `mandatory: true` + `publisher-returns: true` — return callback when no queue matched
3. `correlationData.id` — match callbacks to original publish for retry/log

### Sending with correlation

```kotlin
val correlationData = CorrelationData(UUID.randomUUID().toString())
rabbitTemplate.convertAndSend("domain.events", "code.order.created", event, correlationData)
```

### Async future-based handling

```kotlin
val future: CompletableFuture<CorrelationData.Confirm> = correlationData.future
future.whenComplete { confirm, ex ->
    if (confirm.isAck) { /* success */ }
    else { /* failed; retry or persist for later */ }
}
```

---

## 2. Transactional vs publisher-confirm — pick confirms

```kotlin
// Transactional — DON'T USE for performance
rabbitTemplate.invoke { template ->
    template.convertAndSend(...)
    template.convertAndSend(...)
    template.waitForConfirmsOrDie(5_000)
}
```

Transactional channels block. **Performance ~250× worse than confirms** (publisher confirm-type async).

**Always pick `publisher-confirm-type: correlated`** unless you need atomicity across multiple messages, which itself is a smell — better designed as a single message carrying a list, or as the outbox pattern.

---

## 3. Consumer ack modes

| Mode | When acked | Use |
|---|---|---|
| `auto` | On receive, before processing | Never in production |
| `manual` | When code calls `channel.basicAck(tag)` | Default for production |
| `none` (auto-ack at low level) | Treats as fire-and-forget | Almost never appropriate |

**Always `manual`.**

```kotlin
@RabbitListener(queues = ["events"], ackMode = "MANUAL")
fun handle(@Payload event: Event, channel: Channel, @Header(AmqpHeaders.DELIVERY_TAG) tag: Long) {
    try {
        process(event)
        channel.basicAck(tag, false)        // multiple = false: ack this one only
    } catch (e: Exception) {
        channel.basicNack(tag, false, false) // multiple=false, requeue=false → DLQ
    }
}
```

`basicNack(tag, multiple, requeue)`:
- `multiple = true` acks/nacks all unacked up to this tag — useful for batch processing
- `requeue = false` is **almost always right** in production. `requeue = true` causes immediate redelivery loops with no backoff → broker burnout.

---

## 4. Dead Letter Queue setup

Every primary queue needs a DLX + DLQ.

```kotlin
@Configuration
class QueuesConfig {

    // === Primary ===
    @Bean fun ordersExchange() = TopicExchange("domain.events")

    @Bean fun ordersQueue() = QueueBuilder.durable("orders.events")
        .quorum()
        .withArgument("x-dead-letter-exchange", "domain.events.dlx")
        .withArgument("x-dead-letter-routing-key", "order.failed")
        .build()

    @Bean fun ordersBinding(q: Queue, ex: TopicExchange) =
        BindingBuilder.bind(q).to(ex).with("code.order.*")

    // === Dead letter ===
    @Bean fun deadLetterExchange() = DirectExchange("domain.events.dlx")

    @Bean fun ordersDeadLetterQueue() = QueueBuilder.durable("orders.events.dlq")
        .quorum()
        .build()

    @Bean fun ordersDeadLetterBinding(@Qualifier("ordersDeadLetterQueue") q: Queue,
                                       @Qualifier("deadLetterExchange") ex: DirectExchange) =
        BindingBuilder.bind(q).to(ex).with("order.failed")
}
```

**What lands in the DLQ:**
- Messages `nack`'d with `requeue=false`
- Messages exceeding queue TTL (`x-message-ttl`)
- Messages dropped due to length limit (`x-max-length`)
- Rejected messages (`channel.basicReject(tag, false)`)

**Operating the DLQ:**
- Monitor depth — `rabbitmq_queue_messages{queue="orders.events.dlq"}` in Prometheus
- Alert on non-zero depth
- Have a runbook: inspect, fix root cause, decide drop/replay/manual fix

---

## 5. Retry with exponential backoff

Don't `requeue=true` and burn broker CPU. Use retry advice with backoff.

```kotlin
@Bean
fun retryInterceptor(): RetryOperationsInterceptor =
    RetryInterceptorBuilder.stateless()
        .maxAttempts(4)                                  // 1 + 3 retries
        .backOffOptions(1_000, 2.0, 30_000)              // initial 1s, multiplier 2x, max 30s
        .recoverer(RejectAndDontRequeueRecoverer())      // after exhausted → DLQ
        .build()

@Bean
fun listenerContainerFactory(...): SimpleRabbitListenerContainerFactory =
    SimpleRabbitListenerContainerFactory().apply {
        setAdviceChain(retryInterceptor())
        // ...
    }
```

After 4 attempts (1s, 2s, 4s, 8s gaps), message goes to DLQ via the `RejectAndDontRequeueRecoverer`.

**Caveats:**
- Stateless retry **blocks the consumer thread** during backoff. Slow consumers + retry = low throughput.
- For high-volume queues, prefer "delayed retry queue" pattern (see section 6).

---

## 6. Delayed retry queue pattern

For non-blocking retry with backoff, route failures through a delay queue:

```
events → consumer (fail) → retry.delay.queue (TTL=N seconds, DLX=events)
                                  ↓
                              after TTL
                                  ↓
                              events (redelivered)
```

After N retries, route to permanent DLQ.

```kotlin
@Bean fun eventsQueue() = QueueBuilder.durable("events")
    .withArgument("x-dead-letter-exchange", "events.retry.dlx")
    .build()

@Bean fun retryQueue() = QueueBuilder.durable("events.retry")
    .withArgument("x-dead-letter-exchange", "events.exchange")     // back to primary
    .withArgument("x-message-ttl", 10_000)                          // 10s delay
    .build()
```

Track retry count via a header (`x-attempt-count`); on Nth attempt, route to permanent DLQ instead of retry.

This is operationally heavier but doesn't block consumer threads.

### Plugin alternative

`rabbitmq_delayed_message_exchange` plugin allows scheduled delivery without queue tricks. Operations team must install; check before relying on it.

---

## 7. Idempotent consumer (essential)

Already covered in `spring-amqp-patterns.md` §6. The key idea:

```kotlin
fun handle(event: Event, eventId: String, tag: Long, channel: Channel) {
    if (processed.contains(eventId)) { channel.basicAck(tag, false); return }
    transaction {
        doWork(event)
        processed.record(eventId)
    }
    channel.basicAck(tag, false)
}
```

`event_id` is generated by the producer, stable across redeliveries. Consumer tracks it.

**At-least-once delivery is the default in RabbitMQ.** Even with publisher confirms, redelivery happens on consumer crash, network glitch, broker failover. Idempotency is non-negotiable.

---

## 8. Quorum vs classic queues

| Property | Classic mirrored | Quorum |
|---|---|---|
| Replication | Single master + mirrors (eventual) | Raft consensus across N nodes (strong) |
| Status | Deprecated in 3.8+; removed in 4.0 | Default for new queues |
| Failover speed | Slow on master crash | Fast, automatic |
| Throughput | Higher single-node | Lower under Raft overhead |
| Memory model | All in memory | Disk-based by default |
| Best for | Legacy | Production durability |

**Default for all new queues:** quorum.

```kotlin
@Bean fun q() = QueueBuilder.durable("name").quorum().build()
```

Caveat: quorum queues require 3+ nodes for actual benefit. Single-node RabbitMQ + quorum = same durability as classic + Raft overhead.

---

## 9. Cluster patterns

For HA + scale:

| Topology | Notes |
|---|---|
| Single node | Fine for low traffic / dev |
| 3-node cluster + quorum queues | Production default. Tolerates 1 node loss. |
| 5-node cluster | Tolerates 2 node losses; rare except for critical workloads |

**Critical:** don't use classic mirroring across a cluster with quorum queues; pick one. Mix = operational confusion.

Network partition handling:

```yaml
# rabbitmq.conf
cluster_partition_handling = autoheal       # or pause_minority
```

`pause_minority` is safer for split-brain prevention. `autoheal` favours availability.

---

## 10. Transactional outbox pattern

The problem: DB write + RabbitMQ publish must be atomic. They're separate systems; you cannot 2PC them reliably.

**Solution: outbox table in the DB**, populated in the same transaction as the domain write. A relay process polls the table and publishes to RabbitMQ.

### Spring Modulith provides this out of the box

```kotlin
@Service @Transactional
class CreateOrder(private val events: ApplicationEventPublisher) {
    fun execute(...): OrderId {
        val order = Order.create(...)
        orderRepo.save(order)
        events.publishEvent(OrderCreated(order.id, ...))   // persisted in event_publication
        return order.id
    }
}

@Component
class OrderEventToRabbitRelay(private val rabbit: RabbitTemplate) {
    @ApplicationModuleListener
    fun on(event: OrderCreated) {
        rabbit.convertAndSend("domain.events", "code.order.created", event)
    }
}
```

Spring Modulith persists the event in `event_publication` in the same DB tx as the order save. The async listener fires after commit. If the listener fails (RabbitMQ down), Modulith retries from the table on next startup.

See `cqrs-implementation/resources/write-side-patterns.md` §7 for the full pattern.

### Manual outbox (if not using Modulith)

```sql
CREATE TABLE outbox (
    id UUID PRIMARY KEY,
    routing_key VARCHAR(255) NOT NULL,
    payload JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sent_at TIMESTAMPTZ
);
```

```kotlin
@Component
class OutboxRelay(
    private val outbox: OutboxRepository,
    private val rabbit: RabbitTemplate,
) {
    @Scheduled(fixedDelay = 1_000)
    @Transactional
    fun flush() {
        outbox.findUnsent(limit = 100).forEach { row ->
            try {
                rabbit.convertAndSend("domain.events", row.routingKey, row.payload)
                outbox.markSent(row.id)
            } catch (e: Exception) {
                log.error("Outbox publish failed for {}: {}", row.id, e)
                // leave unsent; will retry next tick
            }
        }
    }
}
```

Pair with publisher confirms — mark `sent_at` only after broker confirms.

---

## 11. Monitoring — what to alarm on

| Metric | Alert when | Why |
|---|---|---|
| Queue depth on primary queue | > N for > M minutes | Consumer can't keep up |
| Queue depth on DLQ | > 0 | Poison messages need attention |
| Publisher NACK count | > 0 | Broker rejecting publishes |
| Returned messages (unroutable) | > 0 | Topology mismatch |
| Unacked messages | high steady state | Consumer hung |
| Connection / channel count growth | unbounded | Channel leak |
| Disk alarm threshold | broker triggers it | Broker stops accepting publishes |
| Memory alarm threshold | broker triggers it | Broker stops accepting publishes |
| `rabbitmq_resident_memory_limit` vs `_used` | > 80% | Approaching memory cap |

Spring Boot Actuator + Micrometer auto-binds RabbitMQ metrics with `management.metrics.binders.rabbitmq.enabled=true` (Boot's default if `spring-boot-starter-amqp` present).

---

## 12. Connection management — `ConnectionFactory`

```kotlin
@Bean
fun connectionFactory(): ConnectionFactory =
    CachingConnectionFactory("rabbit.internal").apply {
        username = "app"
        setPassword(System.getenv("RABBIT_PASSWORD"))
        virtualHost = "assista"
        channelCacheSize = 25
        // For high-throughput publishers
        setPublisherConfirmType(CachingConnectionFactory.ConfirmType.CORRELATED)
        setPublisherReturns(true)
    }
```

**`CachingConnectionFactory`**:
- One physical TCP connection
- Caches channels (logical multiplexing) up to `channelCacheSize`
- Channel cache size = max concurrent operations; size for peak

For very high throughput, use **`PooledChannelConnectionFactory`** which adds channel pooling on top.

---

## 13. Reliability checklist

Before deploying RabbitMQ in production:

- [ ] `publisher-confirm-type: correlated` enabled
- [ ] `mandatory: true` + return callback configured
- [ ] Consumer `acknowledge-mode: manual` everywhere
- [ ] Every queue has a DLX + DLQ
- [ ] Retry advice with exponential backoff configured
- [ ] Idempotent consumer pattern (event-id deduplication)
- [ ] Quorum queues for new queues (or documented reason for classic)
- [ ] Cluster of 3+ nodes (for production)
- [ ] Network partition handling configured (`pause_minority` preferred)
- [ ] Monitoring + alerts on queue depth, DLQ depth, broker memory/disk
- [ ] Outbox pattern (Modulith or manual) for atomic DB+publish
- [ ] Connection recovery configured (`spring.rabbitmq.connection-timeout`, `requested-heartbeat`)
- [ ] Tested under broker restart, network partition, slow consumer
- [ ] Runbook for poison message inspection and replay from DLQ

---

## 14. Common reliability pitfalls

- **`publisher-confirm-type: simple`** (synchronous). Blocks publisher. Use `correlated`.
- **`auto-delete: true` on persistent consumer queue.** Disconnects deletes queue → loss.
- **`autoStartup: false` on listener** during deploy. Service starts but no consumers; queues pile up.
- **Single-node cluster + quorum queue.** Slower than classic with no extra guarantee.
- **DLQ without a consumer or monitor.** Messages pile up invisibly.
- **`requeue = true` on every failure.** Tight loop, broker melts.
- **Retry forever.** No max attempts → poison messages eat the consumer pool.
- **Sharing channel across threads.** RabbitMQ channels are NOT thread-safe; share connection, pool channels.
- **No `correlationId` propagation.** Tracing across services breaks; on-call cries.
- **Outbox poll interval too long.** Latency between commit and publish becomes user-visible.
- **No idempotency, hoping "exactly-once" works.** It doesn't. Plan for redeliveries.
