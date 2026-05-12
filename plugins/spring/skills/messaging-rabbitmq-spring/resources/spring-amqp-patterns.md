# Spring AMQP Patterns — Kotlin

`RabbitTemplate`, `@RabbitListener`, message converters, concurrency, request/reply.

---

## 1. Producer — `RabbitTemplate`

```kotlin
@Service
class OrderEventPublisher(private val rabbit: RabbitTemplate) {

    fun publish(event: OrderEvent) {
        val routingKey = "code.${event.aggregate}.${event.type}"
        rabbit.convertAndSend(
            "domain.events",      // exchange
            routingKey,
            event,
            { msg ->
                msg.messageProperties.apply {
                    deliveryMode = MessageDeliveryMode.PERSISTENT
                    contentType = MessageProperties.CONTENT_TYPE_JSON
                    setHeader("x-event-id", UUID.randomUUID().toString())
                    setHeader("x-tenant-id", event.tenantId)
                    correlationId = MDC.get("traceId")
                }
                msg
            }
        )
    }
}
```

**Key elements:**
- `convertAndSend(exchange, routingKey, payload, postProcessor)` — the post-processor lets you mutate message headers.
- `PERSISTENT` delivery mode — message survives broker restart (paired with durable queue).
- `x-event-id` for idempotency on the consumer side.
- `correlationId` from MDC — propagates tracing context.

---

## 2. Consumer — `@RabbitListener`

```kotlin
@Component
class OrderEventHandler(private val service: OrderProcessingService) {

    private val log = LoggerFactory.getLogger(javaClass)

    @RabbitListener(queues = ["orders.events"])
    fun handle(
        @Payload event: OrderEvent,
        @Header("x-event-id") eventId: String,
        @Header(AmqpHeaders.RECEIVED_ROUTING_KEY) routingKey: String,
        channel: Channel,
        @Header(AmqpHeaders.DELIVERY_TAG) tag: Long,
    ) {
        try {
            log.info("Processing event {} with key {}", eventId, routingKey)
            service.process(event, eventId)         // idempotent by eventId
            channel.basicAck(tag, false)            // manual ack on success
        } catch (e: TransientException) {
            log.warn("Transient failure for {}, requeue", eventId, e)
            channel.basicNack(tag, false, true)     // requeue=true; retry
        } catch (e: Exception) {
            log.error("Permanent failure for {}, DLQ", eventId, e)
            channel.basicNack(tag, false, false)    // requeue=false → DLQ
        }
    }
}
```

**Manual ack mode** is the production default. Auto ack drops messages on crash.

For declarative annotation-based retry, see `reliability.md`.

---

## 3. Message converter — JSON with Jackson

```kotlin
@Configuration
class RabbitConfig {
    @Bean
    fun jacksonConverter(objectMapper: ObjectMapper): MessageConverter =
        Jackson2JsonMessageConverter(objectMapper).apply {
            classMapper = DefaultClassMapper().apply {
                setTrustedPackages(
                    "com.example.assista.contract",
                    "com.example.assista.code",
                )
                setIdClassMapping(mapOf(
                    "OrderEvent" to OrderEvent::class.java,
                    "PullRequestMerged" to PullRequestMerged::class.java,
                ))
            }
        }

    @Bean
    fun rabbitTemplate(connectionFactory: ConnectionFactory,
                       converter: MessageConverter): RabbitTemplate =
        RabbitTemplate(connectionFactory).apply {
            messageConverter = converter
        }
}
```

**Class mapping** is important for security:
- Without `setTrustedPackages`, Jackson is told to instantiate any class from `__TypeId__` header — gadget chains, RCE risks.
- Use `setIdClassMapping` for explicit type names that don't leak class FQNs to the wire.

### Kotlin Serialization alternative

For projects already using kotlinx-serialization:

```kotlin
@Bean
fun kotlinxConverter(): MessageConverter = object : AbstractMessageConverter() {
    private val json = Json { ignoreUnknownKeys = true }
    override fun createMessage(obj: Any, props: MessageProperties): Message {
        @Suppress("UNCHECKED_CAST")
        val bytes = json.encodeToString(serializer(obj::class.java), obj as Any).toByteArray()
        return Message(bytes, props.apply {
            contentType = MessageProperties.CONTENT_TYPE_JSON
            setHeader("__TypeId__", obj::class.qualifiedName)
        })
    }
    override fun fromMessage(message: Message): Any {
        val typeId = message.messageProperties.headers["__TypeId__"] as? String
            ?: error("missing __TypeId__")
        val klass = Class.forName(typeId).kotlin
        return json.decodeFromString(serializer(klass.java), String(message.body))
    }
}
```

Same security note: validate `typeId` against an allow-list before `Class.forName`.

---

## 4. Concurrency tuning

```yaml
spring:
  rabbitmq:
    listener:
      simple:
        concurrency: 5         # min concurrent consumers per listener
        max-concurrency: 20    # max under load
        prefetch: 10           # messages fetched per consumer
        acknowledge-mode: manual
```

**`prefetch`** controls how many unacked messages a consumer can hold at once. Tuning:
- **Low (1-2)**: fair distribution across consumers, but high RTT overhead.
- **High (50-100)**: high throughput, but slow consumers hoard work that fast consumers could process.
- **Sweet spot for most workloads: 10-20.**

**`concurrency` / `max-concurrency`**: Spring will scale consumers between min and max based on queue depth. Set min to handle steady-state, max to handle bursts.

For per-listener tuning:

```kotlin
@RabbitListener(
    queues = ["orders.events"],
    concurrency = "5-15",
    containerFactory = "rabbitListenerContainerFactory"
)
```

---

## 5. Listener container factory

For custom error handling, retry, ack mode per listener:

```kotlin
@Bean
fun rabbitListenerContainerFactory(
    connectionFactory: ConnectionFactory,
    converter: MessageConverter,
): SimpleRabbitListenerContainerFactory =
    SimpleRabbitListenerContainerFactory().apply {
        setConnectionFactory(connectionFactory)
        setMessageConverter(converter)
        setAcknowledgeMode(AcknowledgeMode.MANUAL)
        setPrefetchCount(10)
        setConcurrentConsumers(5)
        setMaxConcurrentConsumers(20)
        setDefaultRequeueRejected(false)        // failed messages → DLQ, not requeue
        setAdviceChain(retryInterceptor())       // see reliability.md
        setMissingQueuesFatal(false)             // boot succeeds if queue missing
    }
```

---

## 6. Idempotent consumer pattern (critical)

Messages can be delivered more than once. Consumers **must** be idempotent.

```kotlin
@Component
class IdempotentEventHandler(
    private val processedEvents: ProcessedEventStore,
    private val service: OrderService,
) {
    @RabbitListener(queues = ["orders.events"])
    fun handle(@Payload event: OrderEvent,
               @Header("x-event-id") eventId: String,
               channel: Channel,
               @Header(AmqpHeaders.DELIVERY_TAG) tag: Long) {

        if (processedEvents.contains(eventId)) {
            // Already processed; ack and skip
            channel.basicAck(tag, false)
            return
        }

        try {
            transactionTemplate.executeWithoutResult {
                service.process(event)              // domain logic + DB write
                processedEvents.record(eventId)      // in same tx
            }
            channel.basicAck(tag, false)
        } catch (e: Exception) {
            channel.basicNack(tag, false, false)    // → DLQ
        }
    }
}
```

`processed_events` table:

```sql
CREATE TABLE processed_events (
    event_id UUID PRIMARY KEY,
    processed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX ON processed_events (processed_at);
```

Periodically (Flyway repeatable / cron) prune old entries. The window must be larger than the maximum redelivery delay (usually hours).

### Alternative: idempotent domain operations

Sometimes the domain operation is naturally idempotent — `SET status = 'CANCELLED' WHERE id = X` is idempotent. If your domain has this property, the explicit `processed_events` table is unnecessary.

Most real workloads need the table.

---

## 7. Request/reply pattern (use sparingly)

Spring AMQP supports synchronous request/reply over messaging:

```kotlin
val reply: ReplyType = rabbit.convertSendAndReceiveAsType(
    "rpc.exchange",
    "service.method",
    Request(...),
    ParameterizedTypeReference.forType<ReplyType>(...)
)
```

How it works:
- RabbitMQ creates a temporary reply queue
- Producer sends with `reply-to` header set to the temp queue
- Consumer processes and sends reply to that queue
- Producer correlates reply via `correlationId`

**Why use sparingly:**
- Adds messaging round-trip latency (typically 5-50ms) — usually worse than direct HTTP/gRPC
- Couples producer to consumer (sync semantics over async transport)
- Failure modes: timeout, lost reply, broker hiccup → request seems to hang
- Hard to reason about

**Recommended:** prefer HTTP / gRPC for true request/response. Reserve messaging for fire-and-forget event distribution.

If you must do RPC, consider:
- Set a strict timeout (`setReplyTimeout(5_000)`)
- Use a dedicated reply queue per service instance, not anonymous

---

## 8. Routing key resolution in the listener

```kotlin
@RabbitListener(queues = ["events.audit"])
fun audit(
    @Payload payload: Map<String, Any>,
    @Header(AmqpHeaders.RECEIVED_ROUTING_KEY) routingKey: String,
    @Header(AmqpHeaders.RECEIVED_EXCHANGE) exchange: String,
    @Header(AmqpHeaders.MESSAGE_ID) messageId: String,
) {
    // Audit handler reads everything from "events.audit" queue
    // Multiple routing keys bind to this queue (e.g., "*.created", "*.deleted")
    // Use routingKey to dispatch internally
    when {
        routingKey.endsWith(".created") -> auditCreated(payload, routingKey)
        routingKey.endsWith(".deleted") -> auditDeleted(payload, routingKey)
        else -> log.warn("Unknown routing key {}", routingKey)
    }
}
```

For queues bound to multiple routing keys, dispatch inside the listener.

---

## 9. Listener-level error handler

```kotlin
@Component
class RabbitErrorHandler : ConditionalRejectingErrorHandler.DefaultExceptionStrategy() {
    override fun isFatal(t: Throwable): Boolean = when {
        t is ListenerExecutionFailedException && t.cause is BusinessLogicException -> false
        t is MessageConversionException -> true     // poison: bad JSON, DLQ immediately
        else -> super.isFatal(t)
    }
}

@Configuration
class RabbitErrorConfig(private val errorHandler: RabbitErrorHandler) {
    @Bean
    fun listenerContainerFactory(connectionFactory: ConnectionFactory) =
        SimpleRabbitListenerContainerFactory().apply {
            setConnectionFactory(connectionFactory)
            setErrorHandler(ConditionalRejectingErrorHandler(errorHandler))
        }
}
```

**Pattern:** `isFatal = true` → no retry, straight to DLQ. `isFatal = false` → retry (with backoff if configured).

---

## 10. Spring Modulith outbox + RabbitMQ relay

For transactional outbox with cross-service publishing:

```kotlin
// 1. Aggregate emits in-process event
@Service @Transactional
class CreateOrder(...) {
    fun execute(cmd: PlaceOrderCommand): OrderId {
        val order = Order.create(...)
        orderRepo.save(order)
        events.publishEvent(OrderCreated(order.id, order.customerId, order.total))
        return order.id
    }
}

// 2. Listener (committed by Modulith outbox) relays to RabbitMQ
@Component
class OrderEventRelay(private val rabbit: RabbitTemplate) {
    @ApplicationModuleListener
    fun on(event: OrderCreated) {
        rabbit.convertAndSend(
            "domain.events",
            "code.order.created",
            event
        )
    }
}
```

The `@ApplicationModuleListener` runs async after the writing transaction commits. Spring Modulith persists the event in `event_publication` table; if the listener fails, Modulith retries from the table on restart. See `cqrs-implementation/resources/write-side-patterns.md` §7 for the full outbox pattern.

---

## 11. Testing

```kotlin
@Testcontainers
@SpringBootTest
class OrderEventHandlerTest {

    companion object {
        @Container
        @ServiceConnection
        val rabbit = RabbitMQContainer("rabbitmq:3.13-management-alpine")
    }

    @Autowired private lateinit var rabbit: RabbitTemplate
    @Autowired private lateinit var processed: ProcessedEventStore

    @Test
    fun `processes event idempotently on duplicate delivery`() {
        val event = OrderCreated(OrderId.random(), CustomerId.random(), Money(100, "EUR"))
        val eventId = UUID.randomUUID().toString()

        rabbitTemplate.convertAndSend("domain.events", "code.order.created", event) {
            it.messageProperties.setHeader("x-event-id", eventId); it
        }
        rabbitTemplate.convertAndSend("domain.events", "code.order.created", event) {
            it.messageProperties.setHeader("x-event-id", eventId); it
        }

        await().untilAsserted {
            assertThat(processed.contains(eventId)).isTrue()
            verify(exactly = 1) { service.process(any()) }    // idempotent
        }
    }
}
```

Use `org.testcontainers:rabbitmq` for real RabbitMQ in tests. Awaitility for async polling.

---

## 12. Common pitfalls

- **Forgetting `@EnableRabbit`** — listeners are ignored, no errors.
- **Mixing `@Transactional` and manual ack.** Tx commits but ack happens after; if process crashes between, tx is committed and message redelivered. Use idempotent operations or the outbox pattern.
- **`auto` ack mode + slow processing.** Ack happens on delivery, before processing. Crash mid-process = loss. Always use `manual`.
- **Catching all exceptions and acking.** Hides poison messages. Let the broker route to DLQ.
- **Sharing one `RabbitTemplate` across many threads with different connection requirements.** Each `RabbitTemplate` should be tied to one `ConnectionFactory`. For separate logical channels (publish vs subscribe), declare separate beans.
- **Reading large payloads.** RabbitMQ keeps unacked messages in memory. Big payloads + slow consumers = OOM. Keep messages small (< 100KB ideal, hard limit 1MB).
- **Producer not setting `mandatory: true`** with `publisher-returns: true`. Undeliverable messages silently disappear instead of returning to producer.
- **`@RabbitListener` method `private`.** Spring needs the method `public` (or `internal`, which is public in JVM bytecode) to proxy it.
