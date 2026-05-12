---
name: spring-events
description: "Spring's in-process event mechanism for Kotlin / Spring Boot 3+ services — `ApplicationEventPublisher` as the producer seam (already implemented by every `ApplicationContext`), plain POJOs / Kotlin `data class` as the event type (no need to extend `ApplicationEvent` since Spring 4.2), sealed event hierarchies for related facts with exhaustive `when` in listeners, `@EventListener` with parameter-type-inferred signatures and SpEL `condition = \"...\"` filtering, generic event listeners via `ResolvableType` for `DomainEvent<T>` shapes, async listeners via `@Async` + `@EnableAsync` (fire-and-forget, exceptions don't propagate, executor sizing matters — pair with `spring-async`), the killer feature `@TransactionalEventListener` with phases `BEFORE_COMMIT` / `AFTER_COMMIT` (default) / `AFTER_ROLLBACK` / `AFTER_COMPLETION` for side effects that must run only when the transaction is durable, listener ordering with `@Order(...)`, built-in Spring lifecycle events (`ApplicationStartingEvent`, `ApplicationEnvironmentPreparedEvent`, `ApplicationContextInitializedEvent`, `ApplicationPreparedEvent`, `ContextRefreshedEvent`, `ApplicationStartedEvent`, `ApplicationReadyEvent`, `ContextStoppedEvent`, `ContextClosedEvent`, `ApplicationFailedEvent`) and what each is for, Spring Modulith `@ApplicationModuleListener` as the cross-module convenience (`@TransactionalEventListener(AFTER_COMMIT) + @Async + @Transactional(REQUIRES_NEW)`) paired with the in-process event publication registry (transactional outbox in a DB table), idempotency requirements for listeners that the registry may retry, failure modes (sync listener exception aborts the publishing chain by default, async listener exceptions just log, AFTER_COMMIT listeners fire on already-committed state so a crashing listener leaves the side effect half-done), the line between in-process events and cross-service messaging (use `spring-amqp` / future `spring-kafka` for the latter), and Kotlin specifics (`data class` events, sealed interface families, `suspend fun` listener caveats). Use when publishing or consuming in-process events, picking sync vs async vs transactional, debugging 'why didn't this listener fire?' or 'why did the email send on a rolled-back order?', wiring projection handlers or audit / notification side effects after a write, or choosing between `@EventListener` / `@TransactionalEventListener` / `@ApplicationModuleListener`. Cross-service messaging is `spring-amqp`; the `@Async` executor and propagation deep is `spring-async`; `@Transactional` propagation deep is `spring-transactions`; Modulith module layout and the `event_publication` registry deep is `spring-modulith`; CQRS projection handlers detail is `cqrs-implementation`; aggregates emitting domain events is `ddd-tactical-patterns`."
risk: safe
source: "custom — Spring in-process events for Kotlin/Spring Boot 3+"
date_added: "2026-05-12"
---

# Spring Events (Kotlin / Spring Boot 3+)

> An in-process event is a way for one bean to tell the others "this fact is now true" without naming them. The seam is `ApplicationEventPublisher`. The discipline is knowing when the listener runs — same thread synchronously, another thread asynchronously, or after the database transaction is durable.

## Use this skill when

- Publishing a domain fact from a service method and not wanting the publisher to know who consumes it
- Deciding between calling a collaborator directly and going through an event
- Picking `@EventListener` vs `@TransactionalEventListener` vs `@ApplicationModuleListener` vs `@Async`
- Debugging "the listener didn't fire" / "the email went out on a rolled-back transaction" / "the projection saw stale state"
- Wiring projection handlers, audit logs, outbound notifications, webhooks — anything that must happen *after* the write commits
- Designing event types — `data class` shapes, sealed hierarchies, what payload to carry, what to omit
- Choosing whether a side effect needs durability beyond the JVM (outbox / event publication registry) or "best-effort after commit" is enough
- Reviewing code that listens to built-in Spring lifecycle events (`ApplicationReadyEvent`, `ContextRefreshedEvent`, …)
- Touching anything in a Spring Modulith codebase where modules talk to each other via events

## Do not use this skill when

- The task is **cross-service messaging** — RabbitMQ exchanges, Kafka topics, durable bus delivery — that's `spring-amqp` (or a future `spring-kafka`). In-process events stay inside one JVM; they are not a message broker.
- The task is **the `@Async` executor itself** — `ThreadPoolTaskExecutor` sizing, virtual threads, MDC / `SecurityContext` propagation, `CompletableFuture` patterns — that's `spring-async`. This skill mentions `@Async` only as the switch that makes a listener fire on another thread.
- The task is **`@Transactional` propagation / isolation / `rollbackFor`** — that's `spring-transactions`. This skill assumes you understand `@Transactional` and focuses on the listener side.
- The task is **Spring Modulith module layout, `ApplicationModuleTest`, the `event_publication` registry internals** — that's `spring-modulith`. This skill describes `@ApplicationModuleListener` and the registry briefly enough to choose the tool; the deep dive lives there.
- The task is **CQRS read-side projections, replay, polyglot read stores** — that's `cqrs-implementation`. The listener annotation is here; the projection design is there.
- The task is **aggregates emitting events, drainable event lists on the root, past-tense naming** at the DDD level — that's `ddd-tactical-patterns`. The Spring wiring from "aggregate returned events" → "consumers see them" is here.
- The task is **bean wiring** — `@Component` vs `@Bean`, scopes, lifecycle — that's `spring-bean`.

## Core principles

1. **In-process events decouple producers from consumers in the same JVM, nothing more.** No durability across crashes, no cross-service delivery, no fan-out across nodes. `ApplicationEventPublisher` is a method call wrapped in a registry, not a broker.
2. **The default is synchronous.** A plain `@EventListener` runs on the publisher's thread, inside the publisher's transaction, before `publishEvent(...)` returns. If you want anything else (async, after-commit, transactional boundary) you ask for it explicitly.
3. **Side effects that "must only happen if the transaction commits" use `@TransactionalEventListener` with `AFTER_COMMIT`.** This is the killer feature and the right default for emails, webhooks, projection updates, and outbound calls triggered by writes. Default `@EventListener` runs before commit and may fire on a rolled-back state.
4. **Events are facts, not commands.** Past tense (`OrderPlaced`, `PaymentFailed`), immutable `data class`, self-contained payload. A name like `UserShouldBeNotified` is a command in disguise — call the notifier directly.
5. **An exception in a synchronous listener aborts the rest of the publishing chain.** Spring iterates listeners in declared / `@Order` order; the first one to throw stops the others and the exception propagates back through `publishEvent(...)` to the caller. Asynchronous listeners run independently — exceptions only get logged.
6. **Listeners that the event publication registry may retry must be idempotent.** Modulith records every publication; failed listeners can be resubmitted. "Send email" run twice sends two emails; design the handler so replaying it is safe (idempotency key, conditional upsert, dedup).
7. **An in-process event in one JVM is not a substitute for cross-service messaging.** When you find yourself reaching for retry / persistence / fan-out across nodes, the answer is `spring-amqp` / Kafka + outbox — not a longer `@TransactionalEventListener`.

## Mental model — sync vs async vs transactional

`publishEvent(...)` hands the event to Spring's `ApplicationEventMulticaster`, which iterates matching listeners. Each listener annotation decides *how* it runs:

| Annotation | Thread | Inside publisher's TX? | On rollback? | On listener throw |
|---|---|---|---|---|
| `@EventListener` | Publisher's | Yes | Same path (chain abort can cause rollback) | Aborts chain, propagates to publisher |
| `@EventListener` + `@Async` | Executor's | No (worker thread is fresh) | Already submitted | Logged via `AsyncUncaughtExceptionHandler` |
| `@TransactionalEventListener(AFTER_COMMIT)` | Publisher's, after commit | No (outside TX) | Skipped | TX already committed; side effect partial |
| `@ApplicationModuleListener` (Modulith) | Executor's, after commit | New TX (`REQUIRES_NEW`) | Skipped | Recorded in `event_publication`, replayable |

Pick by the question "what must be true for this side effect to run?":

- "Right now, in the same atomic boundary" → `@EventListener` (sync).
- "Don't block the publisher; I don't care exactly when" → `@EventListener` + `@Async`.
- "Only if the transaction actually committed" → `@TransactionalEventListener(AFTER_COMMIT)`.
- "Across modules, durable, replayable" → `@ApplicationModuleListener` (which is the AFTER_COMMIT + async + REQUIRES_NEW combo with the outbox).

## `ApplicationEventPublisher` — the producer seam

`ApplicationEventPublisher` is a one-method interface. The `ApplicationContext` implements it, so you can inject either:

```kotlin
@Service
class PlaceOrderService(
    private val orders: OrderRepository,
    private val events: ApplicationEventPublisher,  // inject the narrower interface
) {
    @Transactional
    fun place(req: PlaceOrderRequest): Order {
        val order = Order.new(req)
        orders.save(order)
        events.publishEvent(OrderPlaced(order.id, order.customerId, order.total, Instant.now()))
        return order
    }
}
```

Prefer the narrow `ApplicationEventPublisher` over the full `ApplicationContext`. Smaller surface area, no temptation to fetch beans by name, intent is obvious to the reader.

`publishEvent(...)` returns `void`. The producer never sees who consumed (or whether anyone did). That's the whole point of the seam.

## Event type discipline — POJO, `data class`, sealed hierarchy

Since Spring 4.2 events don't need to extend `ApplicationEvent`. A plain Kotlin `data class` is the right shape:

```kotlin
data class OrderPlaced(
    val orderId: OrderId,
    val customerId: CustomerId,
    val total: Money,
    val placedAt: Instant,
)
```

Properties:

- **Immutable.** `val` everywhere; once published, the event cannot be mutated mid-iteration.
- **Past tense.** It's a fact that happened — `OrderPlaced`, `PaymentFailed`, `InventoryReserved`. Not `PlaceOrder` (that's a command) or `OrderShouldBeNotified` (that's an instruction).
- **Self-contained.** Carry everything a downstream listener needs. The aggregate may be in a different state by the time an async listener runs — looking it up later is a race condition.
- **Stable identity for dedup.** If listeners run via the publication registry and may retry, include a stable `eventId: UUID` or business-key combo so handlers can idempotently dedupe.

### Sealed hierarchies for event families

Related events on the same aggregate benefit from a sealed parent — listeners `when`-match exhaustively, the compiler enforces coverage when a new event is added (a real advantage over Java's open hierarchies). See the AFTER_COMMIT example below for the full pattern.

## `@EventListener` — synchronous, the default

```kotlin
@Component
class OrderMetrics(private val registry: MeterRegistry) {
    @EventListener
    fun on(event: OrderPlaced) {
        registry.counter("orders.placed", "currency", event.total.currency).increment()
    }
}
```

The method signature does the dispatching — Spring inspects the parameter type and only invokes this method for `OrderPlaced` events. No `instanceof`, no manual routing.

Notes on plain `@EventListener`:

- Runs **on the publisher's thread**, before `publishEvent(...)` returns.
- Runs **inside the publisher's transaction** if one is active. A throw rolls everything back.
- Iterated in `@Order(...)` declared order (lower = earlier). Without `@Order`, the order is undefined.
- An exception aborts the iteration. Subsequent listeners for the same event don't run.

### Conditional listeners with SpEL

```kotlin
@EventListener(condition = "#event.total.amountMinor > 100_000")
fun on(event: OrderPlaced) {
    fraudCheck.flag(event.orderId)
}
```

The SpEL `condition` is evaluated against the event before invocation. Useful for "only react to high-value orders", "only when the source matches this tenant", etc. Keep the SpEL short — anything non-trivial belongs in the listener body where it's readable and testable.

### Generic events — `ResolvableType`

Historically, generic types like `DomainEvent<Order>` were erased at runtime and listeners couldn't distinguish `DomainEvent<Order>` from `DomainEvent<Invoice>`. Spring's `ResolvableType` machinery preserves the generic parameter at the listener side (and on the publisher side if you implement `ResolvableTypeProvider` on your event class or pass an explicit `PayloadApplicationEvent`).

```kotlin
data class DomainEvent<T>(val payload: T, val occurredAt: Instant)

@Component
class OrderProjector {
    @EventListener
    fun on(event: DomainEvent<Order>) { /* … */ }   // matched by the generic parameter
}
```

Workable in practice; doesn't replace sealed hierarchies for related events but useful for generic envelope shapes.

## Async events — `@Async`

To make a listener run on another thread, add `@Async` (and `@EnableAsync` somewhere, typically on a `@Configuration` class):

```kotlin
@Component
class OrderPlacedEmailer(private val email: EmailGateway) {
    @Async
    @EventListener
    fun on(event: OrderPlaced) {
        email.sendOrderConfirmation(event.orderId, event.customerId)
    }
}
```

The publisher's thread returns immediately. Exceptions don't propagate — they go to an `AsyncUncaughtExceptionHandler` (default: log at WARN). No transaction unless the listener method itself is `@Transactional` (worker thread starts fresh).

Async events with side effects on a database write are usually wrong without `@TransactionalEventListener` — if the publisher rolls back, the async email may have already been sent. Combine the two (or use `@ApplicationModuleListener`, which already does).

Executor sizing, virtual threads, MDC / `SecurityContext` propagation, `CompletableFuture` patterns — all live in **`spring-async`**.

## `@TransactionalEventListener` — the after-commit pattern

The annotation queues the listener invocation and binds it to a phase of the publisher's transaction:

```kotlin
@Component
class OrderPlacedNotifier(private val email: EmailGateway) {
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    fun sendConfirmation(event: OrderPlaced) {
        email.sendOrderConfirmation(event.orderId, event.customerId)
    }
}
```

What this guarantees:

- Listener runs **after** the publisher's transaction has been COMMITted.
- If the transaction **rolls back**, the listener is **never invoked** — no email on a phantom order.
- Runs **on the same thread** as the publisher, **outside** the transaction. Hibernate session is closed (no lazy loading); no enclosing DB connection.

### Phases

| Phase | Fires | Use for |
|---|---|---|
| `BEFORE_COMMIT` | Just before commit, still inside the TX | Last-chance mutations that must be part of the atomic write (rare — usually "this is a step, not an event") |
| `AFTER_COMMIT` *(default)* | After successful COMMIT, outside the TX | 95% of cases: emails, webhooks, projection updates |
| `AFTER_ROLLBACK` | After ROLLBACK | Symmetric: log / metric / undo a pre-write side effect |
| `AFTER_COMPLETION` | After COMMIT or ROLLBACK | Cleanup that must happen regardless of outcome |

The default `AFTER_COMMIT` is what you almost always want. Other phases must be deliberate choices.

### Two gotchas

- **No transaction in scope at publish time** — the listener is **skipped silently** (TRACE log) unless `fallbackExecution = true` is set on the annotation. Use the flag cautiously; it papers over "why is this published from a non-transactional context?".
- **Listener crashes after COMMIT** — the TX is already durable, so the side effect is half-done. Three responses: accept best-effort and log; make the listener idempotent and retry via `@ApplicationModuleListener` + the publication registry; push durability into an outbox (see `cqrs-implementation`, `spring-amqp`).

### Example — AFTER_COMMIT on a sealed event hierarchy

```kotlin
sealed interface OrderEvent {
    val orderId: OrderId
    val occurredAt: Instant
}

data class OrderPlaced(
    override val orderId: OrderId,
    val customerId: CustomerId,
    val total: Money,
    override val occurredAt: Instant,
) : OrderEvent

data class OrderCancelled(
    override val orderId: OrderId,
    val reason: String,
    override val occurredAt: Instant,
) : OrderEvent

@Service
class PlaceOrderService(
    private val orders: OrderRepository,
    private val events: ApplicationEventPublisher,
    private val clock: Clock,
) {
    @Transactional
    fun place(req: PlaceOrderRequest): Order {
        val order = Order.new(req, clock.instant())
        orders.save(order)
        events.publishEvent(OrderPlaced(order.id, order.customerId, order.total, clock.instant()))
        return order
    }
}

@Component
class OrderNotifications(private val email: EmailGateway) {
    @TransactionalEventListener  // AFTER_COMMIT is the default
    fun on(event: OrderEvent) = when (event) {
        is OrderPlaced    -> email.sendOrderConfirmation(event.orderId, event.customerId)
        is OrderCancelled -> email.sendCancellationNotice(event.orderId, event.reason)
    }
}
```

The notifications method fires only after the order write commits. A rollback in `place(...)` means no email — no phantom confirmations. The sealed `OrderEvent` and exhaustive `when` mean a new subtype won't silently slip past the notifier.

## Async listener with `@Async`

For a side effect that should fire after commit *and* off the publisher's thread, the classical wiring is `@TransactionalEventListener` + `@Async`:

```kotlin
@Configuration
@EnableAsync
class AsyncConfig {
    // Executor configuration lives in spring-async — sizing, virtual threads, etc.
}

@Component
class WebhookFanout(private val webhooks: WebhookClient) {
    @Async
    @TransactionalEventListener
    fun on(event: OrderPlaced) {
        webhooks.deliver(event)   // slow IO — don't block the publisher thread
    }
}
```

Properties of the combo:

- Queued during the transaction, dispatched to the executor only after COMMIT.
- Publisher returns as soon as it finishes its own work; webhook delivery happens on a worker thread.
- No transaction unless the listener method itself is `@Transactional` (worker thread starts fresh).
- Exceptions do not propagate; configure an `AsyncUncaughtExceptionHandler` to capture them properly.

For most cross-module work in a Modulith app, this combo is more cleanly expressed as `@ApplicationModuleListener` — see below.

## Spring Modulith `@ApplicationModuleListener`

In a Spring Modulith codebase, the canonical listener annotation across modules is:

```kotlin
@Component
class InvoiceProjector(private val invoices: InvoiceProjections) {
    @ApplicationModuleListener
    fun on(event: OrderPlaced) {
        invoices.upsertFor(event.orderId, event.customerId, event.total)
    }
}
```

`@ApplicationModuleListener` is shorthand for `@TransactionalEventListener(phase = AFTER_COMMIT) + @Async + @Transactional(propagation = REQUIRES_NEW)`. Properties:

- Fires after the publisher's transaction commits.
- Runs asynchronously on the Modulith-configured executor.
- The listener body runs in **its own new transaction** — projection writes go through cleanly even though the publisher's transaction is already closed.
- The publication is **recorded in the `event_publication` table** before delivery and only marked complete after the listener returns. A crash mid-listener leaves the publication "incomplete" and replayable.

Deep treatment of `@ApplicationModuleListener`, the module boundary rules, `ApplicationModuleTest`, and replay APIs lives in **`spring-modulith`**. This skill points at the annotation; the sibling owns the depth.

## Event publication registry — the in-process outbox

Spring Modulith ships an outbox out of the box: every event published via `ApplicationEventPublisher` is recorded in the `event_publication` table **before** listeners are invoked. The row is removed only when every listener returns successfully. If a listener throws (or the JVM dies mid-delivery), the row stays — `IncompleteEventPublications.resubmitIncompletePublications(...)` replays it.

Implications: listeners may be invoked more than once (make them idempotent); the outbox is per-listener (only the failed one replays); the outbox is in-process to the DB, not cross-service (for Kafka / RabbitMQ delivery you still need a relay — see `spring-amqp` and `cqrs-implementation`).

Schema, replay, observability, and the relay-to-bus pattern live in `spring-modulith` and `cqrs-implementation`.

## Listener ordering — `@Order`

When multiple listeners match an event, sync and `@TransactionalEventListener` listeners run in `@Order(...)` declared order (lower = earlier). Without `@Order` the order is undefined; don't rely on it. Async listeners run concurrently — ordering is essentially undefined.

If listener A throws synchronously, listener B (later) does not run — chain-abort. That's a feature for "don't waste work after a precondition failed" and a bug if you expected independence. Use async listeners if you genuinely want independence.

## Built-in Spring lifecycle events

Spring publishes a fixed sequence of events during startup and shutdown. Listen to them with `@EventListener` like any other event.

| Event | When | Common use |
|---|---|---|
| `ApplicationStartingEvent` | Before `Environment` is prepared | Pre-bootstrap logging hooks (rare) |
| `ApplicationEnvironmentPreparedEvent` | Environment built, profiles active, properties loaded | Configure logging from properties |
| `ApplicationContextInitializedEvent` | Context exists, bean definitions not yet loaded | Library-level customisation (rare) |
| `ApplicationPreparedEvent` | Bean definitions loaded; beans not yet instantiated | Register additional bean definitions programmatically |
| `ContextRefreshedEvent` | All singletons created; `SmartInitializingSingleton` fired | "All beans exist" — not yet "ready" |
| `ApplicationStartedEvent` | After refresh, before runners | App started but not yet "ready" |
| `ApplicationReadyEvent` | After all `ApplicationRunner` / `CommandLineRunner` finished | "Ready to serve traffic" — preferred hook for runtime startup work |
| `ContextStoppedEvent` | `ApplicationContext.stop()` | Pause work without destroying beans |
| `ContextClosedEvent` | `ApplicationContext.close()` — shutdown start | Graceful shutdown work; runs before `@PreDestroy` |
| `ApplicationFailedEvent` | Startup threw before refresh completed | Crash reporting from a partially-bootstrapped app |

`@EventListener(ApplicationReadyEvent::class)` is the preferred hook for "do X when the app is fully up". Lifecycle ordering details live in `spring-bean`.

## Idempotency and failure modes — what to assume

| Listener kind | Runs how many times? | On throw |
|---|---|---|
| `@EventListener` (sync) | Exactly once if it doesn't throw; chain aborts on throw | Propagates to publisher; rolls back the enclosing TX |
| `@EventListener` + `@Async` | Exactly once per dispatch; no retry | Logged via `AsyncUncaughtExceptionHandler`; publisher already returned |
| `@TransactionalEventListener(AFTER_COMMIT)` | Exactly once if it doesn't throw | TX is already committed; side effect is half-done; logged |
| `@ApplicationModuleListener` | **At least once** — Modulith replays failed publications | Row stays in `event_publication`; replayable |

Design listeners for the strictest case you'll deploy under. If you'll ever use `@ApplicationModuleListener` or a Kafka relay, the listener must be **idempotent**: upsert by business key, dedup by event ID, check "did I already do this?" before doing it. Avoid blind `INSERT` or "fire email" — those are duplicate-unsafe.

## Anti-patterns

| Anti-pattern | Why it's wrong | Fix |
|---|---|---|
| Plain `@EventListener` for after-write side effects (email, webhook, projection) inside `@Transactional` | Runs *before* commit; if the publisher rolls back later, the side effect already happened on a transient state | Use `@TransactionalEventListener(AFTER_COMMIT)` |
| `@Async` listener without a configured executor | Default `SimpleAsyncTaskExecutor` creates a thread per task — unbounded, no naming, no propagation | Configure `ThreadPoolTaskExecutor` or virtual threads; see `spring-async` |
| Sealed event hierarchy listener with non-exhaustive `when` + `else -> Unit` | Defeats the point of sealed — new subtype slips past silently | Drop the `else`; let the compiler enforce coverage |
| Events as commands in disguise (`UserShouldBeNotified`, `OrderMustBeShipped`) | Events are facts; commands are imperatives | Past-tense fact (`UserRegistered`, `OrderPaid`) or call the collaborator directly |
| Event payloads as snapshots of full entities | Big, brittle, leaks internals across module boundaries | Carry IDs and the business facts the listener actually needs |
| Heavy logic in a synchronous `@TransactionalEventListener` | Holds the publisher's thread; on throw, TX is already committed but side effect is half-done | Promote to `@ApplicationModuleListener` (async + outbox) |
| Unbounded "any module listens to anything" growth | Same problem as global mutable state — invisible coupling | Use Modulith's module boundaries; events module produces declared in `contract/` |
| Catching the listener's own exception just to log it | Async listeners already log; for transactional ones it hides retry-worthy failures | Let it throw; tune `AsyncUncaughtExceptionHandler` or rely on Modulith retry |
| `publishEvent(...)` from a non-transactional context expecting `@TransactionalEventListener` to fire | Listener is skipped silently | Publish from a `@Transactional` method, or `fallbackExecution = true` (and document why) |
| Calling a downstream module's service directly when an event would do | Re-introduces the coupling events exist to remove | Publish an event; let the other module listen |

## Kotlin specifics

- **`data class` is the right event shape.** Immutable by `val`, structural equality, `copy(...)` for derived events.
- **Sealed interface families** are the right shape for related events on one aggregate or workflow. Listener `when` becomes exhaustive — adding a new subtype is a compile error at every site, not a silent miss.
- **`@JvmInline value class` IDs** in event payloads are fine; they erase to their underlying type at the JVM level for the event multicaster.
- **`object` events** are anti-idiomatic. Use a `data class` even if it has zero fields — equality semantics, future-proofing, less surprise.
- **`suspend fun` listeners.** Spring 6 supports `@EventListener` on a `suspend fun` (it's adapted via `kotlinx-coroutines-reactor`), but the listener runs on the calling thread by default — `suspend` doesn't automatically mean "off-thread". For "off-thread", combine with `@Async` (the dispatcher then becomes the executor's thread pool, not a coroutine scope) or pick the explicit `@ApplicationModuleListener`. Don't mix `runBlocking` inside a synchronous `@EventListener` — you'll deadlock yourself one day.
- **`kotlin-spring` (`all-open`) plugin** matters for `@TransactionalEventListener` and `@Async` listeners — they need a Spring AOP proxy on a non-`final` class. The plugin opens `@Component` / `@Service` classes automatically. Without it, you'll get cryptic CGLIB errors. See `spring-aop` and `spring-bean`.

## Related skills

- `spring` — router; cross-cutting Spring principles
- `spring-transactions` — `@Transactional` propagation, the proxy gotchas that decide whether `@TransactionalEventListener` ever fires, the rollback rules
- `spring-async` — `@Async` deep: `ThreadPoolTaskExecutor`, virtual threads, context propagation, `CompletableFuture`
- `spring-modulith` — `@ApplicationModuleListener`, the `event_publication` outbox, module boundary enforcement, `ApplicationModuleTest`
- `spring-aop` — proxy mechanics for `@Async` / `@TransactionalEventListener` (Kotlin `final`-by-default, self-invocation, `private` / `final` methods)
- `spring-bean` — bean lifecycle, `@PostConstruct` vs `ApplicationReadyEvent`, `SmartInitializingSingleton`
- `spring-amqp` — cross-service messaging when in-process events aren't enough; outbox + bus relay
- `cqrs-implementation` — projection handlers via `@ApplicationModuleListener`, read-side cursor tracking, replay
- `ddd-tactical-patterns` — aggregates emit domain events; this skill is the wiring from aggregate to consumer
- `testing-strategy-kotlin-spring` — `PublishedEvents` from Modulith for asserting events were emitted; `@RecordApplicationEvents` for slice-level testing
- `clean-code-error-handling` — listener exception design; what gets logged, what gets rethrown
- `debugging-systematic` — when "the listener didn't fire" and you need a method, not a guess
- `methodology` — always before code; `methodology-verification` for proving the listener actually ran in the test

## Limitations

- Targets Spring Boot **3+** on Kotlin 2.x / JVM 21+. Older Boot versions support most patterns but specific APIs (`fallbackExecution`, `@ApplicationModuleListener`) require Boot 3 / Modulith 1.x+.
- Doesn't cover **reactive events** — `Mono`-based publishing, `Flux` listeners, Reactor's `Sinks`. The imperative `ApplicationEventPublisher` machinery here does not directly apply to reactive chains.
- Doesn't cover the **`event_publication` schema** in depth (columns, retention, partitioning) — `spring-modulith` and `cqrs-implementation`.
- Doesn't cover **cross-service delivery** (durability across crashes, fan-out to nodes, broker semantics). For Kafka / RabbitMQ use the outbox + relay pattern from `spring-amqp` and `cqrs-implementation`.
- Doesn't cover **`@Async` executor sizing, virtual threads, MDC / `SecurityContext` propagation** — that's `spring-async`.
- Doesn't cover the **DDD aggregate-side event emission discipline** (collecting events on the aggregate, draining on save, naming) — that's `ddd-tactical-patterns`.
