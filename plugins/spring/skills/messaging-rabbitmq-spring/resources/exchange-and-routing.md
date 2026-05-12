# Exchange types and Routing

How RabbitMQ routes: exchanges, queues, bindings, routing keys. Picking the right exchange.

---

## 1. The model — exchanges, queues, bindings

```
Producer → publish(exchange, routingKey, message)
              │
              ▼
         ┌─────────┐
         │EXCHANGE │      decides which queues get the message
         └────┬────┘      based on type + bindings
              │
        bindings (queue ← binding rule ← exchange)
              │
         ┌────┴────┐
         ▼         ▼
      ┌─────┐   ┌─────┐
      │QUEUE│   │QUEUE│   Consumers read from queues
      └─────┘   └─────┘
```

**Key insight:** producers publish to **exchanges**, not queues. Consumers read from **queues**. Bindings glue them together.

This separation is RabbitMQ's strength: producers don't know about consumers, routing is declarative, you can change topology without touching producers.

---

## 2. Direct exchange — exact match

```
Routing key:  "user.created"
Bindings:
  queue_audit       ← bound with "user.created"
  queue_billing     ← bound with "user.created"
  queue_notifications ← bound with "user.created"
```

All three queues receive the message. Each consumer competes within its own queue.

**Use for:**
- Point-to-point with a known recipient (the routing key IS the recipient).
- Multiple distinct consumer groups, each gets their own queue.

```kotlin
@Configuration
class DirectExchangeConfig {
    @Bean fun jobsExchange() = DirectExchange("jobs")
    @Bean fun emailJobsQueue() = Queue("jobs.email", true)
    @Bean fun smsJobsQueue() = Queue("jobs.sms", true)
    @Bean fun emailBinding(q: Queue, ex: DirectExchange) =
        BindingBuilder.bind(q).to(ex).with("email")
    @Bean fun smsBinding(q: Queue, ex: DirectExchange) =
        BindingBuilder.bind(q).to(ex).with("sms")
}

// Publish
rabbitTemplate.convertAndSend("jobs", "email", EmailJob(...))
rabbitTemplate.convertAndSend("jobs", "sms", SmsJob(...))
```

---

## 3. Topic exchange — pattern match

```
Routing key:  "code.pullrequest.merged"  (multi-segment, dot-separated)
Bindings:
  queue_code_audit     ← "code.*.*"             (all code events)
  queue_pr_specific    ← "*.pullrequest.*"      (all PR events)
  queue_pr_merged      ← "code.pullrequest.merged"  (exact)
  queue_critical       ← "code.#"               (everything under "code")
```

Pattern syntax:
- `*` matches exactly one segment
- `#` matches zero or more segments

**Use for:**
- Domain event distribution where consumers select by pattern
- Multi-tenant routing (`tenant.<id>.events.*`)
- Hierarchical subjects

```kotlin
@Configuration
class DomainEventsConfig {
    @Bean fun domainEventsExchange() = TopicExchange("domain.events")

    @Bean fun codeAuditQueue() = Queue("code.audit", true)
    @Bean fun codeAuditBinding(q: Queue, ex: TopicExchange) =
        BindingBuilder.bind(q).to(ex).with("code.*.*")

    @Bean fun prMergedQueue() = Queue("pr.merged.notifier", true)
    @Bean fun prMergedBinding(q: Queue, ex: TopicExchange) =
        BindingBuilder.bind(q).to(ex).with("code.pullrequest.merged")
}

// Publish
rabbitTemplate.convertAndSend(
    "domain.events",
    "code.pullrequest.merged",
    PullRequestMerged(...)
)
```

### Routing key convention (recommended)

Use `<bounded-context>.<aggregate>.<event>` with consistent casing (snake or kebab, pick one):

| Event | Routing key |
|---|---|
| `PullRequestMerged` in `code` context | `code.pull-request.merged` |
| `DeploymentCompleted` in `cicd` | `cicd.deployment.completed` |
| `IncidentDeclared` in `sre` | `sre.incident.declared` |
| `UserRegistered` in `people` | `people.user.registered` |

Then consumers can subscribe with intent: `code.*.*` (all code events), `*.*.merged` (all merge events), etc.

---

## 4. Fanout exchange — broadcast

```
Routing key:  ignored
Bindings:     queue_a, queue_b, queue_c (no routing keys)
```

Every bound queue receives every message. Routing key is ignored.

**Use for:**
- Global broadcast (cache invalidation pub/sub)
- Replicating events to many consumers without selectivity
- Event sourcing-style fan-out

```kotlin
@Configuration
class CacheInvalidationConfig {
    @Bean fun cacheInvalidateExchange() = FanoutExchange("cache.invalidate")

    @Bean fun cacheInvalidateQueue() = AnonymousQueue()     // unique per instance
    @Bean fun cacheInvalidateBinding(q: Queue, ex: FanoutExchange) =
        BindingBuilder.bind(q).to(ex)
}
```

`AnonymousQueue()` creates a server-named auto-delete queue — perfect for instance-local fanout. Each instance gets its own queue bound to the same fanout exchange; on instance shutdown the queue disappears.

---

## 5. Headers exchange — header-based routing

```
Routing key:  ignored
Headers:      {tenant: "acme", priority: "high", type: "audit"}
Bindings:
  queue_acme_audit ← match all: {tenant: "acme", type: "audit"}
  queue_high_prio  ← match any: {priority: "high"}
```

Bindings match on header value(s) instead of routing key. Two match modes:
- `x-match: all` — all specified header pairs must match
- `x-match: any` — at least one must match

**Use case:** when routing depends on multiple orthogonal attributes (tenant, region, priority, type) that don't naturally hierarchy into a topic.

```kotlin
val q = Queue("high-priority-acme-events", true)
val ex = HeadersExchange("events.by.headers")
val binding = BindingBuilder.bind(q).to(ex)
    .whereAll(mapOf("tenant" to "acme", "priority" to "high")).match()
```

**In practice:** rare. Topic exchanges with well-designed routing keys cover 90% of cases. Reach for headers only when routing genuinely doesn't fit a hierarchy.

---

## 6. Dead Letter Exchange (DLX)

Every primary queue should have a DLX configured. When a message:
- Is rejected with `requeue=false`
- Is `nack`'d with `requeue=false`
- Expires (TTL)
- Exceeds queue length limit (`x-max-length`)

…it's routed to the DLX with the same routing key.

```kotlin
@Bean fun jobsExchange() = DirectExchange("jobs")

@Bean fun jobsDeadLetterExchange() = DirectExchange("jobs.dlx")

@Bean fun emailJobsQueue() = QueueBuilder.durable("jobs.email")
    .withArgument("x-dead-letter-exchange", "jobs.dlx")
    .withArgument("x-dead-letter-routing-key", "email")
    .build()

@Bean fun emailDeadLetterQueue() = Queue("jobs.email.dlq", true)

@Bean fun emailDlqBinding(@Qualifier("emailDeadLetterQueue") q: Queue,
                         @Qualifier("jobsDeadLetterExchange") ex: DirectExchange) =
    BindingBuilder.bind(q).to(ex).with("email")
```

A poison message that fails 3 retries → ends up in `jobs.email.dlq`. Inspect with `rabbitmqctl` or RabbitMQ Management UI. Decide: manual fix, drop, replay.

---

## 7. Topology declaration patterns

### Pattern A: declarative via Spring `@Bean` (preferred)

```kotlin
@Configuration
class RabbitTopology {
    @Bean fun exchange() = TopicExchange("domain.events", true, false)
    @Bean fun queue() = QueueBuilder.durable("orders.events")
        .withArgument("x-dead-letter-exchange", "domain.events.dlx")
        .withArgument("x-message-ttl", 600_000L)             // 10 min
        .build()
    @Bean fun binding(q: Queue, ex: TopicExchange) =
        BindingBuilder.bind(q).to(ex).with("order.*.*")
}
```

Spring's `RabbitAdmin` auto-declares these beans on startup (idempotent).

### Pattern B: imperative via `RabbitAdmin`

```kotlin
rabbitAdmin.declareExchange(TopicExchange("dynamic.events"))
rabbitAdmin.declareQueue(Queue("subscription.${tenantId}", true))
rabbitAdmin.declareBinding(
    BindingBuilder.bind(Queue("subscription.$tenantId", true))
        .to(TopicExchange("dynamic.events"))
        .with("tenant.$tenantId.*")
)
```

For dynamic topology (e.g., per-tenant queues created on subscription).

### Pattern C: external — RabbitMQ definitions JSON (operations-managed)

For production, sometimes ops team manages topology via `definitions.json` imported on broker startup. App code asserts (does not declare) the topology. Use `setDeclarationFailureMode(FAIL_FAST)` to assert at boot.

---

## 8. Queue properties

| Property | Setting | Effect |
|---|---|---|
| `durable: true` | Survives broker restart | Always for persistent workloads |
| `auto-delete: true` | Deleted when last consumer disconnects | For per-instance/ephemeral queues only |
| `exclusive: true` | Only one connection can use; deleted on disconnect | Reply-to queues |
| `x-message-ttl` | Per-message TTL in ms | Stale messages → DLQ |
| `x-max-length` | Max queue size | Prevent unbounded growth → DLQ overflow |
| `x-max-length-bytes` | Max queue size in bytes | Memory bound |
| `x-dead-letter-exchange` | Where to send rejected/expired | Always set |
| `x-dead-letter-routing-key` | Routing key in DLX | Often the same as original |
| `x-queue-type: quorum` | Quorum queue (Raft) | Default for new queues, more reliable |
| `x-queue-type: classic` | Classic mirrored queue | Legacy; deprecated in newer versions |

### Quorum queue example

```kotlin
@Bean fun ordersQueue() = QueueBuilder.durable("orders.events")
    .quorum()                                                 // x-queue-type: quorum
    .withArgument("x-dead-letter-exchange", "orders.dlx")
    .withArgument("x-message-ttl", 600_000L)
    .build()
```

Quorum queues:
- Raft-replicated (typically 3 nodes)
- Stronger durability guarantees
- Slightly higher latency than classic
- Lower throughput than classic in single-node setups
- **Default for new production queues since RabbitMQ 3.8+**

---

## 9. Pitfalls

- **Mixing message persistence and queue durability.** Durable queue + non-persistent message = message lost on broker restart. Always pair durable queues with `delivery_mode = persistent` for important messages.
- **Routing key conventions changing mid-flight.** Old consumers bind to `user.created`, new producers publish `user.registered`. Topology drift = silently dropped messages. Document and version the convention.
- **Topic exchange with no consumers bound.** Messages "delivered to exchange" but no queue gets them. Without `mandatory: true` + return callback, you don't know. Always test with `mandatory: true` in dev.
- **Anonymous queues for persistent consumers.** Auto-delete on disconnect → broker restart → consumer reconnects but queue's gone, missed messages while disconnected. Use named, durable queues for persistent consumers.
- **`exclusive: true` queues consumed by multiple instances.** Only one connection can attach. Second instance starts → fails. Use only for true RPC reply-to.
- **No DLX.** Every reject → message disappears with no trace. **Every queue needs a DLX.**
- **Single huge queue with many consumers.** Head-of-line blocking: a slow consumer blocks the head, fast consumers starve. Use prefetch + multiple queues for parallelism.
- **Fanout to consumers that need filtering.** Wastes bandwidth — every consumer receives everything, drops most. Use topic exchange with patterns.
