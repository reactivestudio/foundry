# Write-Side Patterns

Commands, handlers, command bus, aggregate emits events, transaction boundary, idempotency, outbox. Kotlin/Spring Boot.

---

## 1. Command shape

A command is a **request to change state**, expressed as immutable data. Use `sealed interface` to group commands by bounded context.

```kotlin
sealed interface OrderCommand {
    val orderId: OrderId

    data class Place(
        override val orderId: OrderId,
        val customerId: CustomerId,
        val items: List<OrderLine>,
        val shippingAddress: Address,
        val idempotencyKey: IdempotencyKey,
    ) : OrderCommand

    data class AddItem(
        override val orderId: OrderId,
        val productId: ProductId,
        val quantity: Int,
        val unitPrice: Money,
    ) : OrderCommand

    data class Cancel(
        override val orderId: OrderId,
        val reason: CancellationReason,
    ) : OrderCommand
}
```

Rules:

- Commands are **imperative** (`Place`, `AddItem`, `Cancel`) — past-tense names are for events.
- Commands carry **all the data needed to execute** — no reaching back to the caller mid-handler.
- Commands are **validated at the type system level** where possible (use `@JvmInline value class` for IDs, `Money` for amounts).
- Each command has an **idempotency key** if it's a `POST` from an external caller — see §6.

---

## 2. Command handler

One `@Service` per command class is the cleanest default. Group commands when they share dependencies and the grouping reads naturally.

### Single-command handler

```kotlin
@Service
class PlaceOrderHandler(
    private val orders: OrderRepository,
    private val pricing: PricingService,
    private val inventory: InventoryService,
    private val events: ApplicationEventPublisher,
    private val idempotencyStore: IdempotencyStore,
) {
    @Transactional
    operator fun invoke(cmd: OrderCommand.Place): OrderId {
        // 1. Idempotency guard
        idempotencyStore.findResult(cmd.idempotencyKey)?.let { return it as OrderId }

        // 2. Validation that requires external data
        require(cmd.items.isNotEmpty()) { "order must have items" }
        inventory.reserveAll(cmd.items)

        // 3. Build aggregate (which enforces invariants in its constructor / factory)
        val order = Order.place(
            id = cmd.orderId,
            customerId = cmd.customerId,
            items = cmd.items,
            shippingAddress = cmd.shippingAddress,
            pricing = pricing,
        )

        // 4. Persist
        orders.save(order)

        // 5. Publish domain events (drained from the aggregate)
        order.pullEvents().forEach(events::publishEvent)

        // 6. Record idempotency result
        idempotencyStore.record(cmd.idempotencyKey, order.id)

        return order.id
    }
}
```

### Grouped handler (for tightly related commands)

```kotlin
@Service
class OrderLifecycleHandler(
    private val orders: OrderRepository,
    private val events: ApplicationEventPublisher,
) {
    @Transactional
    fun addItem(cmd: OrderCommand.AddItem) {
        val order = orders.findById(cmd.orderId) ?: throw NotFoundException("Order", cmd.orderId)
        order.addItem(cmd.productId, cmd.quantity, cmd.unitPrice)
        orders.save(order)
        order.pullEvents().forEach(events::publishEvent)
    }

    @Transactional
    fun cancel(cmd: OrderCommand.Cancel) {
        val order = orders.findById(cmd.orderId) ?: throw NotFoundException("Order", cmd.orderId)
        order.cancel(cmd.reason)
        orders.save(order)
        order.pullEvents().forEach(events::publishEvent)
    }
}
```

Choose grouping based on cohesion, not number-of-files anxiety.

---

## 3. Command bus — needed or not?

**You probably don't need a generic command bus.** Spring DI is your bus: inject the handler into the controller and call it directly.

```kotlin
@RestController
@RequestMapping("/api/v1/orders")
class OrderController(
    private val placeOrder: PlaceOrderHandler,
    private val lifecycle: OrderLifecycleHandler,
) {
    @PostMapping
    fun place(@Valid @RequestBody req: PlaceOrderRequest): ResponseEntity<PlaceOrderResponse> {
        val id = placeOrder(req.toCommand())
        return ResponseEntity
            .created(URI.create("/api/v1/orders/$id"))
            .body(PlaceOrderResponse(id))
    }

    @PostMapping("/{orderId}/items")
    fun addItem(@PathVariable orderId: UUID, @Valid @RequestBody req: AddItemRequest) {
        lifecycle.addItem(req.toCommand(OrderId(orderId)))
    }

    @PostMapping("/{orderId}/cancel")
    fun cancel(@PathVariable orderId: UUID, @Valid @RequestBody req: CancelRequest) {
        lifecycle.cancel(req.toCommand(OrderId(orderId)))
    }
}
```

This is type-safe, fast, no reflection. The "command bus" pattern adds value only when:

- Commands cross process boundaries (message queue dispatch).
- You need cross-cutting middleware (logging, metrics, retry) and AOP / aspects aren't enough.

If you need a bus, prefer composition over reflection:

```kotlin
interface CommandHandler<C, R> {
    fun handle(command: C): R
}

@Component
class CommandBus(private val handlers: Map<KClass<*>, CommandHandler<*, *>>) {
    @Suppress("UNCHECKED_CAST")
    fun <C : Any, R> dispatch(command: C): R {
        val handler = handlers[command::class] as? CommandHandler<C, R>
            ?: error("No handler registered for ${command::class}")
        return handler.handle(command)
    }
}
```

This is rarely worth it. Defer the bus until you actually need it.

---

## 4. Aggregate emits domain events

> For the general design of aggregates, value objects, and domain events (invariants, repository per root, past-tense naming), see the **`ddd-tactical-patterns`** skill. This section covers only the CQRS-specific concern: **how the aggregate's events flow into the Spring `ApplicationEventPublisher`** for projection consumers.

Domain events live **on the aggregate**. The aggregate collects them in a private list; the command handler drains them after save and publishes through `ApplicationEventPublisher`.

```kotlin
class Order private constructor(
    val id: OrderId,
    val customerId: CustomerId,
    private val items: MutableList<OrderLine>,
    var status: OrderStatus,
    var shippingAddress: Address,
) {
    private val pendingEvents = mutableListOf<DomainEvent>()

    companion object {
        fun place(
            id: OrderId,
            customerId: CustomerId,
            items: List<OrderLine>,
            shippingAddress: Address,
            pricing: PricingService,
        ): Order {
            require(items.isNotEmpty()) { "empty order" }
            val priced = items.map { pricing.priceLine(it) }
            return Order(
                id = id,
                customerId = customerId,
                items = priced.toMutableList(),
                status = OrderStatus.PLACED,
                shippingAddress = shippingAddress,
            ).also {
                it.pendingEvents += OrderPlaced(
                    orderId = id,
                    customerId = customerId,
                    total = priced.sumOf { l -> l.subtotal() },
                    placedAt = Instant.now(),
                )
            }
        }
    }

    fun addItem(productId: ProductId, qty: Int, unitPrice: Money) {
        check(status == OrderStatus.PLACED) { "cannot add items to $status order" }
        val line = OrderLine(productId, qty, unitPrice)
        items += line
        pendingEvents += OrderItemAdded(id, productId, qty, unitPrice)
    }

    fun cancel(reason: CancellationReason) {
        check(status != OrderStatus.CANCELLED) { "already cancelled" }
        check(status != OrderStatus.SHIPPED) { "cannot cancel shipped order" }
        status = OrderStatus.CANCELLED
        pendingEvents += OrderCancelled(id, reason, Instant.now())
    }

    fun pullEvents(): List<DomainEvent> = pendingEvents.toList().also { pendingEvents.clear() }
}
```

Rules:

- **Past tense** — `OrderPlaced`, not `PlaceOrder`. Events describe what already happened.
- **Immutable** — `data class` for events.
- **Self-contained** — every event must carry enough data for projection handlers to do their job *without* querying the write side.
- **In `contract/` if cross-module** — events consumed outside this bounded context belong in the shared contract package.

---

## 5. Transaction boundary

The command handler's `@Transactional` boundary covers:
1. Loading the aggregate.
2. Calling aggregate methods.
3. Saving the aggregate.
4. Publishing events to `ApplicationEventPublisher`.

`ApplicationEventPublisher` events are delivered **after commit** if listeners use `@TransactionalEventListener` or `@ApplicationModuleListener`. This is why projection lag exists — and why the projection sees committed state, not in-flight state.

**Don't fight this.** Synchronous projection inside the write transaction couples the two stores and defeats the purpose.

---

## 6. Idempotency

Every command coming from an external caller (HTTP `POST`, async message) MUST be idempotent.

### Idempotency key in the command

```kotlin
@JvmInline value class IdempotencyKey(val value: String) {
    init { require(value.length in 8..128) }
}
```

Caller passes it as a header (`Idempotency-Key: <uuid>`), controller threads it into the command.

### Idempotency store

```kotlin
interface IdempotencyStore {
    fun findResult(key: IdempotencyKey): Any?
    fun record(key: IdempotencyKey, result: Any)
}

@Repository
class JpaIdempotencyStore(private val em: EntityManager) : IdempotencyStore {
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    override fun findResult(key: IdempotencyKey): Any? = …

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    override fun record(key: IdempotencyKey, result: Any) = …
}
```

`REQUIRES_NEW` so the idempotency check commits independently — duplicate request short-circuits even if the original is mid-flight.

Schema:

```sql
CREATE TABLE idempotency_keys (
    key VARCHAR(128) PRIMARY KEY,
    result_type VARCHAR(64) NOT NULL,
    result_payload JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '24 hours'
);
CREATE INDEX ON idempotency_keys (expires_at);
```

TTL via scheduled cleanup. 24 hours covers most retry windows.

---

## 7. Outbox pattern with Spring Modulith

For events that must reach an external bus (Kafka), in-process publish-after-commit isn't enough: the bus could be down, the publish could fail, and you'd lose the event.

Solution: **outbox table** — persist the event in the same transaction as the aggregate save; a separate process relays from outbox to bus.

Spring Modulith ships an outbox out of the box: `event_publication` table. Every event published via `ApplicationEventPublisher` is recorded there before delivery. If a listener fails, the entry stays — you can replay via `IncompleteEventPublications.resubmitIncompletePublications(...)`.

For external bus (Kafka), the pattern is:

```kotlin
@Component
class OrderPlacedKafkaRelay(
    private val producer: KafkaTemplate<String, ByteArray>,
) {
    @ApplicationModuleListener
    fun on(event: OrderPlaced) {
        producer.send(
            "orders",
            event.orderId.value.toString(),
            event.toAvro().toByteBuffer().array(),
        ).get(5, TimeUnit.SECONDS)  // throw on failure → Modulith retries from event_publication
    }
}
```

Modulith handles the durability; you handle the serialization and the bus call.

---

## 8. Validation: where it lives

Three layers of validation, each with its own job:

| Where | What | Tools |
|---|---|---|
| **Controller / DTO** | Format validation (email shape, length, regex) | Bean Validation `@Valid`, `@NotBlank`, `@Pattern` |
| **Command handler** | Cross-aggregate or external-data validation (inventory check, pricing) | Plain Kotlin `require()` / service calls |
| **Aggregate** | Invariants — rules that must always hold for the entity itself | `init {}` block, method `check()` calls |

Don't pile everything in the handler. Aggregate invariants belong on the aggregate; if you can't get to it without parsing a `String` first, that's a DTO concern.

---

## 9. Returning the right HTTP code for commands

| Outcome | HTTP code | Notes |
|---|---|---|
| Command accepted, work synchronous | `201 Created` + `Location` header | For create-style commands |
| Command accepted, work synchronous, no new resource | `200 OK` | For update-style commands |
| Command accepted, projection lags | `202 Accepted` + `Location` to read endpoint | Honest about eventual consistency |
| Validation failure | `422 Unprocessable Entity` | Bean Validation or aggregate invariant |
| Aggregate state forbids op | `409 Conflict` | Idempotent retry doesn't help; state's wrong |
| Not found | `404 Not Found` | Aggregate doesn't exist |
| Duplicate idempotency-key | `200 OK` with original result | Same as original response |

`202 Accepted` is honest. If the user calls `GET /orders/{id}` immediately after `POST /orders` and the projection hasn't caught up, they'd get `404`. Better to communicate the lag.

---

## 10. Anti-patterns

- **Command handlers calling other command handlers.** Suggests an aggregate boundary problem. Inline or rethink.
- **Returning aggregate state from a command handler.** Commands change state; queries return state. If the caller needs state back, they query after. Exception: returning the new aggregate ID (for `Location` header) is fine.
- **Events as commands in disguise.** `UserShouldBeNotifiedEvent` is a command. Real event: `UserRegistered` (past tense, fact).
- **Publishing events that read like internal state changes.** `OrderTotalRecomputed` is internal. The event should describe a business-level fact (`OrderItemAdded`) and let projections derive the total.
- **Skipping idempotency "because the client is well-behaved".** They're not. Retries happen.
- **Heavy logic inside `@TransactionalEventListener`.** It runs synchronously after commit; if it crashes, your aggregate is saved but the event isn't projected. Use `@ApplicationModuleListener` (async, with outbox durability) for anything non-trivial.
