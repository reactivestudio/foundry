---
name: spring-transactions
description: "Spring's transaction abstraction for Kotlin / Spring Boot 3+ services — `@Transactional` as a design decision that lives on the service layer (not the repository, not the controller, not the domain), propagation modes (`REQUIRED` / `REQUIRES_NEW` / `MANDATORY` / `NESTED` / `SUPPORTS` / `NOT_SUPPORTED` / `NEVER`) and the concrete scenario each one is right for, isolation levels (`READ_UNCOMMITTED` / `READ_COMMITTED` / `REPEATABLE_READ` / `SERIALIZABLE`) and what each prevents at what cost, `rollbackFor` / `noRollbackFor` (Spring rolls back on `RuntimeException` / `Error` by default but NOT on checked `Exception` — Kotlin has no checked exceptions so the default usually does the right thing), `readOnly = true` for Hibernate dirty-checking off / no flush / replica routing, `timeout`, the AOP-proxy gotchas that make `@Transactional` silently no-op (self-invocation, `private`, `final`, `kotlin-spring` plugin, `new SomeService()`), `TransactionTemplate` / `PlatformTransactionManager` for programmatic boundaries, `@TransactionalEventListener(phase = AFTER_COMMIT)` for after-commit side effects, multi-datasource (`@Transactional(\"txManagerName\")`) and the distributed-transaction / 2PC / XA warning (use the outbox pattern instead), Kotlin specifics (no checked exceptions, `kotlin-spring` open-by-default, coroutines + `@Transactional`, `runCatching` rollback gotcha), observability (`logging.level.org.springframework.transaction=TRACE`, Micrometer transaction metrics, detecting silent rollback). Use whenever the user writes or reviews `@Transactional`, debugs 'why didn't this roll back?', hits 'no transaction in progress' or `LazyInitializationException`, splits a method on a `REQUIRES_NEW` boundary, designs the transaction shape of a use case, or suspects an AOP proxy is being bypassed. AOP general mechanics and aspect authoring live in `spring-aop`; `JpaRepository` / queries / `Pageable` live in `spring-data-jpa`; Hibernate entity lifecycle / N+1 / fetch types in `hibernate`; the outbox pattern detail in `cqrs-implementation` / `spring-amqp`."
risk: safe
source: "custom — Spring transaction abstraction for Kotlin/Spring Boot 3+"
date_added: "2026-05-12"
---

# Spring Transactions (Kotlin / Spring Boot 3+)

> The transaction is a design boundary, not a technicality. `@Transactional` answers one question — "what set of writes must succeed or fail together?" — and the answer almost always lives on the service / use-case method. Get that boundary right and 80% of the rest of this skill is defaults.

## Use this skill when

- Writing or reviewing a `@Transactional` annotation — picking the layer, the propagation, the isolation, the rollback rules
- Debugging "why didn't this roll back?" / "why did it roll back?" / `LazyInitializationException` / `no transaction in progress`
- Splitting a method on a `REQUIRES_NEW` boundary (audit logs, idempotency stores, retry-with-side-effect)
- Designing the transaction shape of a use case that spans multiple aggregates, multiple repositories, or a write plus an external call
- Adding `@TransactionalEventListener(phase = AFTER_COMMIT)` for "fire only if the transaction actually commits" side effects
- Suspecting an AOP proxy is being bypassed — self-invocation, `private`, `final`, `new`-ed instance, Kotlin class without `open`
- Touching more than one datasource and wiring multiple `PlatformTransactionManager` beans
- Anyone says "two-phase commit", "XA", or "distributed transaction" out loud
- Reviewing Kotlin code with `runCatching` / `try { … } catch (e: Exception)` inside a `@Transactional` method — the rollback might be silently swallowed

## Do not use this skill when

- The question is **`JpaRepository`, derived queries, `Pageable`, projections, Specifications** — that's `spring-data-jpa`. (Spring Data repository methods are already each `@Transactional`; you don't need to add it on a repo.)
- The question is **Hibernate persistence context, entity lifecycle (transient / managed / detached / removed), fetch types, N+1, `equals` / `hashCode`** — that's `hibernate`. (Cross-ref here for `LazyInitializationException` outside the TX boundary.)
- The question is **`@Aspect`, pointcut expressions, advice ordering, custom aspects** in general — that's `spring-aop`. (The proxy-gotcha diagnosis for `@Transactional` lives **here**, not in `spring-aop`, because this is where readers come looking.)
- The question is **outbox pattern detail / Modulith `event_publication` / Kafka relay** — that's `cqrs-implementation` and `spring-amqp`. (This skill covers the `AFTER_COMMIT` listener pattern at the in-process level and points out when you need the outbox.)
- You're picking the **architectural layout** (Layered / Onion / Clean) or the **bounded-context split** — that's `architecture-patterns` / `ddd-strategic-design`.
- The task is **bean wiring, scopes, `@Component` vs `@Bean`** — that's `spring-bean`.

## Core principles

1. **The transaction boundary is the service / use-case method.** Not the controller (HTTP shouldn't dictate atomicity), not the repository (a repo doesn't know which other writes are in the same unit of work), not the domain (the domain shouldn't depend on Spring). The service answers "what writes succeed or fail together?" — that's exactly what a transaction is.
2. **`@Transactional` on a public method on a Spring-managed bean — or it's nothing.** The annotation drives an AOP proxy; bypass the proxy (self-invocation, `private`, `final`, `new`-ed instance, non-bean) and the annotation is dead text. Most "the transaction didn't fire" bugs are this.
3. **Read-only by default for read paths.** `@Transactional(readOnly = true)` turns off Hibernate dirty-checking, skips the flush, and lets the connection pool route to a read replica if configured. Cheaper, safer, more honest about intent.
4. **Default propagation is `REQUIRED`. Don't write it.** Every other propagation mode is a deliberate decision worth documenting; writing `propagation = REQUIRED` everywhere is noise that hides the deliberate ones.
5. **Default rollback is `RuntimeException` / `Error`, not checked `Exception`.** Kotlin has no checked exceptions, so for idiomatic Kotlin code the default is almost always right. If you have Java-checked-exception code in the call stack (legacy JDBC, third-party libs), use `rollbackFor = Exception::class` explicitly.
6. **Catching the rollback-triggering exception inside the `@Transactional` method silently breaks rollback.** `try { … } catch (e: Exception) { log.warn(...) }` — Spring's interceptor never sees the exception, so it never marks for rollback. `runCatching { … }` has the same problem. Either re-throw, or call `TransactionAspectSupport.currentTransactionStatus().setRollbackOnly()` explicitly.
7. **Transactions are scarce and connections are scarcer.** A long `@Transactional` method holding the connection while it calls an external HTTP API is the classic "thread pool exhausted, connection pool exhausted, app deadlocks" outage. Push slow IO outside the boundary, or split with `REQUIRES_NEW`.
8. **Distributed transactions are almost always wrong.** Two-phase commit over JDBC + JMS / RabbitMQ / Kafka tightly couples everyone's availability and locks rows for the duration of network round-trips. Use the outbox pattern instead — see `cqrs-implementation` and `spring-amqp`.

## The `@Transactional` mental model

```
Controller          Service                        Repository / Hibernate
─────────────       ────────────────────────       ────────────────────────
HTTP request  ──►   @Transactional method  ──►    SQL statements
                    │                              │
                    ├── proxy intercepts call      │
                    │   begin TX, get connection   │
                    │                              │
                    │   ┌─── business logic ───┐   │
                    │   │   load aggregate     ├──►│  SELECT ... FOR UPDATE? 
                    │   │   mutate aggregate    │  │
                    │   │   save aggregate     ├──►│  INSERT / UPDATE
                    │   │   publish events     │  │
                    │   └──────────────────────┘   │
                    │                              │
                    └── proxy after method:        │
                        if no exception: COMMIT ──►│  COMMIT
                        else            : ROLLBACK ►  ROLLBACK
                        then publish AFTER_COMMIT listeners
HTTP response ◄──   return                         release connection
```

Five things this picture says, all of which the rest of the skill expands:

1. The proxy is the actor. Skip the proxy and nothing here happens.
2. The TX wraps the entire method. Slow IO inside = connection held for the duration.
3. Commit and rollback are decided by what comes out of the method (return vs throw), not by anything you write inside (except `setRollbackOnly()`).
4. `AFTER_COMMIT` listeners run after the COMMIT line, **on the same thread**, **outside** the TX.
5. If the proxy didn't fire (gotchas below), every step in the middle still happens — there's just no TX wrapping them. That's the silent no-op that costs you a weekend.

## Propagation — pick by the answer to "what if there's already a TX?"

Set with `@Transactional(propagation = Propagation.X)`.

| Propagation | If outer TX exists | If no outer TX | Use when |
|---|---|---|---|
| **`REQUIRED`** (default) | Join it | Start a new one | 99% of cases. Default; don't write it explicitly. |
| **`REQUIRES_NEW`** | Suspend outer, start a new inner TX, resume outer after inner ends | Start a new one | Audit log / idempotency record / outbox marker that must commit independently of the outer outcome. Retry-with-side-effect: the side effect's TX commits even if the outer rolls back. |
| **`NESTED`** | Inner SAVEPOINT inside outer TX — inner can roll back without rolling outer back | Start a new one | Rare. Multi-step business logic where a sub-step may fail and you want to discard just that sub-step. Postgres + JDBC supports savepoints; Hibernate caches make this less clean than it sounds. |
| **`SUPPORTS`** | Join it | Run with no TX | Read methods that work either way and don't care. In practice `readOnly = true` on a normal `REQUIRED` is clearer. |
| **`NOT_SUPPORTED`** | Suspend outer, run with no TX, resume outer after | Run with no TX | Calling a long-running external API or a non-transactional resource that must NOT hold a DB connection. Niche. |
| **`MANDATORY`** | Join it | Throw `IllegalTransactionStateException` | Internal helper method that is meaningless outside a TX — enforces "caller must already be transactional". Useful as a tripwire on shared library code. |
| **`NEVER`** | Throw `IllegalTransactionStateException` | Run with no TX | Method that must NEVER run inside a TX (e.g. it sleeps, calls a slow API, or runs DDL). Tripwire. |

Two patterns you'll actually use:

- **`REQUIRES_NEW` for the side-effect that must commit independently.** Audit log, idempotency key write, outbox row. Even if the business TX rolls back, the side-effect TX has already committed.
- **`MANDATORY` as a contract tripwire.** A shared helper that assumes a TX is active — annotate `propagation = MANDATORY` so misuse fails loudly at the call site instead of silently running without a TX.

### `REQUIRES_NEW` — Kotlin example

```kotlin
@Service
class PlaceOrderService(
    private val orders: OrderRepository,
    private val audit: AuditService,
    private val payments: PaymentGateway,
) {
    @Transactional
    fun place(req: PlaceOrderRequest): Order {
        val order = Order.new(req)
        orders.save(order)
        audit.record(AuditEvent.OrderPlaced(order.id))     // commits independently — see below
        payments.charge(order)                              // throws → outer TX rolls back, audit row stays
        return order
    }
}

@Service
class AuditService(private val repo: AuditRepository) {
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    fun record(event: AuditEvent) {
        repo.save(AuditRecord.from(event))
    }
}
```

Result: payment failure rolls back the `orders` write, leaves the audit row in place — the auditor can reconstruct "this user tried to place this order and we rejected it." If both wrote in one TX, the rollback would erase the attempt too.

(In CQRS-style code with Spring Modulith, the same idea is done via `@TransactionalEventListener(AFTER_COMMIT)` for the happy path and an outbox for durability — see the `cqrs-implementation` skill. `REQUIRES_NEW` is the manual building block underneath those patterns.)

## Isolation — pick by the anomaly you can't tolerate

Set with `@Transactional(isolation = Isolation.X)`. Defaults to the database default (Postgres: `READ_COMMITTED`).

| Isolation | Prevents | Allows | Cost |
|---|---|---|---|
| `READ_UNCOMMITTED` | (nothing) | Dirty reads, non-repeatable reads, phantoms | Lowest. Postgres treats this the same as `READ_COMMITTED` (no dirty reads possible). |
| `READ_COMMITTED` (Postgres default) | Dirty reads | Non-repeatable reads, phantoms | Low. Each statement sees a fresh snapshot of committed data. |
| `REPEATABLE_READ` | Dirty + non-repeatable reads | Phantoms (limited in Postgres — uses snapshot isolation that prevents most) | Medium. One snapshot for the whole TX. May fail with serialization errors on concurrent updates — retry on `40001`. |
| `SERIALIZABLE` | Dirty + non-repeatable reads + phantoms | (nothing) | Highest. Postgres uses Serializable Snapshot Isolation (SSI) — concurrent TXs may abort with `40001` and need retry logic. |

Defaults are right for almost everything. Reach for higher isolation when:

- **`REPEATABLE_READ`** — a single TX reads the same row twice and the values must match (financial reports, multi-step decisions on a snapshot).
- **`SERIALIZABLE`** — concurrent writers each read-then-decide-then-write to the same row and the result must be as if they ran one at a time. Most commonly worked around with `SELECT ... FOR UPDATE` or an optimistic version column instead.

Concurrent anomalies and how to think about them are deeper than this skill — pair with `database-design` and your DB's docs.

## Rollback rules — defaults and Kotlin

Spring's `TransactionInterceptor` rolls back on:

- `RuntimeException` and its subclasses ✅
- `Error` and its subclasses ✅
- Checked `Exception` and its subclasses ❌ (commits!)

Override with:

```kotlin
@Transactional(
    rollbackFor = [Exception::class],            // roll back on checked exceptions too
    noRollbackFor = [BusinessExpectedFailure::class],  // don't roll back on this specific RuntimeException
)
fun doSomething() { … }
```

### Kotlin specifics

Kotlin has no checked exceptions. Every exception you throw is a `RuntimeException`. So the default — "roll back on `RuntimeException`" — does the right thing in pure-Kotlin code without any `rollbackFor`. You only need `rollbackFor = Exception::class` when calling into Java code that throws checked exceptions you want to treat as failure.

### The silent-rollback-breaker

```kotlin
@Transactional
fun place(req: PlaceOrderRequest) {
    val order = Order.new(req)
    orders.save(order)
    try {
        payments.charge(order)
    } catch (e: PaymentFailedException) {       // ← caught here
        log.warn("payment failed", e)
        order.markFailed()                       // ← still gets persisted!
    }
    // method returns normally → COMMIT
}
```

`payments.charge(order)` threw, you handled it, the method returns normally — Spring sees no exception leaving the proxy, so it **commits**. The user gets a "failed" order persisted instead of nothing.

Same trap with `runCatching`:

```kotlin
@Transactional
fun place(req: PlaceOrderRequest) {
    val order = Order.new(req)
    orders.save(order)
    runCatching { payments.charge(order) }       // ← swallows everything
        .onFailure { log.warn("payment failed", it) }
    // method returns normally → COMMIT
}
```

Three fixes, in order of preference:

1. **Don't catch it.** Let the exception out. The proxy rolls back. Translate to an HTTP error in `@ControllerAdvice`.
2. **Catch, then re-throw a domain exception.** `throw OrderPlacementFailed(e)` — preserves rollback, gives the caller a typed error.
3. **Explicit rollback flag.** `TransactionAspectSupport.currentTransactionStatus().setRollbackOnly()` then handle the case locally. Use sparingly; it's a back-door.

## `readOnly = true` — small annotation, real effect

```kotlin
@Service
class OrderReadService(private val orders: OrderRepository) {
    @Transactional(readOnly = true)
    fun get(id: OrderId): Order = orders.findById(id.value).orElseThrow { … }
}
```

What it does:

- **Hibernate dirty-checking off.** No snapshot of loaded entities, no diff at flush. Faster, less memory.
- **No automatic flush.** Even if you mutate an entity by accident, it won't be written.
- **Connection-level hint.** `Connection.setReadOnly(true)` — some pools (HikariCP + a routing datasource) can route to a read replica.
- **Documentation.** Tells the next reader "this method does not write."

Use on every read-only service method. The cost is one annotation; the upside is real.

## `timeout`

```kotlin
@Transactional(timeout = 5)   // seconds
fun expensiveQuery() { … }
```

JDBC drivers honor this at the statement level. Useful for runaway queries and admin endpoints. Default is no timeout — a hung query holds the connection until something else (DB, network, k8s) kills it. Combine with a global `spring.datasource.hikari.connection-timeout` and pool-level statement timeouts for defense in depth.

## AOP proxy gotchas — where `@Transactional` silently dies

`@Transactional` is implemented as Spring AOP advice on a proxy. The proxy is what calls the interceptor that begins / commits / rolls back the TX. If you bypass the proxy, none of that happens — your method runs with no TX, **silently**.

The four ways to bypass the proxy:

### 1. Self-invocation — `this.method()` from inside the same class

This is the most common bug.

```kotlin
@Service
class OrderService(private val orders: OrderRepository) {

    fun place(req: PlaceOrderRequest): Order {
        val order = Order.new(req)
        return persist(order)              // ← direct call: `this.persist(...)` — skips the proxy
    }

    @Transactional
    fun persist(order: Order): Order {     // proxy advice attached, but the call above never goes through the proxy
        return orders.save(order)
    }
}
```

`place(...)` is called via the proxy (no `@Transactional`, no-op interceptor). Inside, `persist(order)` is `this.persist(order)` — a direct JVM method call, not a proxy call. The interceptor never fires. `persist` runs **without a TX**. `orders.save(order)` opens its own short auto-commit TX from Spring Data, and the apparent atomic boundary you wanted around `persist` doesn't exist.

#### Clean fix — split the methods across two beans

```kotlin
@Service
class OrderService(
    private val persistence: OrderPersistence,
) {
    fun place(req: PlaceOrderRequest): Order {
        val order = Order.new(req)
        return persistence.persist(order)   // ← goes through OrderPersistence's proxy
    }
}

@Service
class OrderPersistence(private val orders: OrderRepository) {
    @Transactional
    fun persist(order: Order): Order = orders.save(order)
}
```

Now the call is `persistence.persist(...)` on a different bean — the call goes through `OrderPersistence`'s proxy and the interceptor fires.

If the two methods really belong together (single use case), the cleanest answer is "put `@Transactional` on the outer method, not the inner one." Most of the time the outer method is what should own the TX boundary anyway.

#### Smells, not fixes

- **`AopContext.currentProxy()`** to fetch the proxy from inside the class. Works, but couples your code to `EnableAspectJAutoProxy(exposeProxy = true)` and reads like a tax on someone's compromise. Almost always means "I haven't extracted the second class yet."
- **`@Lazy` self-injection** — inject `lateinit var self: OrderService`, call `self.persist(...)`. Same outcome, same coupling. Same diagnosis: extract the bean.

### 2. `private` methods

```kotlin
@Service
class OrderService {
    @Transactional
    private fun persist() { … }   // proxy can't intercept private methods
}
```

Spring AOP proxies wrap **public** methods. `private` (and Kotlin internal `internal` on the JVM compiles to `public` with mangled names, but the visibility check is on the source-level `public`) won't be intercepted. The `@Transactional` annotation is ignored.

Fix: make it `public` and consider whether it should be on a different bean (so it can be called from outside).

### 3. `final` methods / classes — and the Kotlin angle

Spring AOP creates proxies in one of two ways:

- **JDK dynamic proxy** if the class implements an interface — works fine, proxies the interface, no inheritance needed.
- **CGLIB subclass proxy** if there's no interface — Spring generates a runtime subclass that overrides each method and adds the interceptor.

CGLIB can't subclass a `final` class or override a `final` method. In Java this is rare. In Kotlin **every class is `final` by default and every method is `final` by default**.

This is what the `kotlin-spring` (`all-open`) compiler plugin solves. Enable it once in your build:

```kotlin
// build.gradle.kts
plugins {
    kotlin("plugin.spring") version "..."
}
```

The plugin marks classes annotated with `@Component` / `@Service` / `@Repository` / `@Controller` / `@RestController` / `@Configuration` / `@Async` / `@Transactional` / `@Cacheable` as `open` automatically. Without the plugin, you'd see a cryptic CGLIB error at startup. With it, the default Spring stereotypes Just Work.

For plain classes that aren't stereotyped but you still want proxied (e.g. a `@Bean`-registered class), mark them `open` explicitly. Or, often cleaner, extract an interface — JDK dynamic proxy works on any class because it doesn't need to subclass.

### 4. `new SomeService()` — not a bean

```kotlin
class OrderController {
    private val service = OrderService(...)   // ← `new`-ed, not injected
    
    @PostMapping("/orders")
    fun place(...) = service.place(...)
}
```

`service` is a plain JVM object. No Spring proxy was ever wrapped around it. The `@Transactional` annotation on `OrderService.place` is dead text. Same for `@Async`, `@Cacheable`, `@PreAuthorize`, `@Scheduled`.

Fix: constructor-inject. This is the cardinal rule from `spring-bean`.

### How to recognise the bug

Symptoms:

- Methods that should be atomic aren't — partial writes survive what looks like a failure
- `LazyInitializationException` thrown outside the `@Transactional` method (no TX = no Hibernate session)
- No `BEGIN` / `COMMIT` in the SQL log around the method
- `TransactionSynchronizationManager.isActualTransactionActive()` returns `false` inside the supposedly transactional method
- A `@TransactionalEventListener` listener never fires (no TX commit = no AFTER_COMMIT event)

Quickest diagnosis: turn on `logging.level.org.springframework.transaction=TRACE` and look for "Creating new transaction" around your method call. If it's missing, the proxy was bypassed.

## Programmatic alternative — `TransactionTemplate`

When declarative `@Transactional` doesn't fit (fine-grained per-block boundaries inside one method, multi-resource coordination, conditional commit), use `TransactionTemplate`:

```kotlin
@Service
class BulkImporter(
    private val tx: TransactionTemplate,
    private val rows: RowRepository,
) {
    fun import(batches: List<Batch>) {
        batches.forEach { batch ->
            tx.execute { status ->
                try {
                    rows.saveAll(batch.rows)
                } catch (e: ValidationException) {
                    status.setRollbackOnly()        // rolls back this batch, the loop continues
                }
            }
        }
    }
}
```

Justifications:

- Per-iteration TX in a loop without splitting into another bean
- Coordinating multiple transaction managers (rare — see below)
- Conditional rollback that doesn't map cleanly to exception flow

For 95% of cases, `@Transactional` on the service method is clearer. Programmatic is the escape hatch.

## Multi-datasource transactions

When you have more than one DataSource, you have more than one `PlatformTransactionManager`. Bean names disambiguate:

```kotlin
@Configuration
class TxManagers {
    @Bean("primaryTxManager")
    fun primary(@Qualifier("primaryDs") ds: DataSource): PlatformTransactionManager =
        DataSourceTransactionManager(ds)

    @Bean("reportingTxManager")
    fun reporting(@Qualifier("reportingDs") ds: DataSource): PlatformTransactionManager =
        DataSourceTransactionManager(ds)
}

@Service
class ReportingService(...) {
    @Transactional("reportingTxManager")
    fun load(): Report = …
}
```

What does **not** work: a single `@Transactional` that atomically covers writes to both datasources. That's a distributed transaction (2PC / XA).

`ChainedTransactionManager` was a "best effort 2PC" middle ground. **It is deprecated** as of Spring Framework 5.3 and not the answer. If your design wants atomicity across two stores, the answer is almost always:

- One of the stores is the **system of record**; the other holds a **derived view** updated asynchronously (read-your-writes / eventual consistency)
- An **outbox** in the system-of-record store; a separate process relays to the second store with at-least-once delivery and idempotent consumers

Both of these collapse "two writes that must succeed together" into "one write plus a reliable hand-off." See `cqrs-implementation`, `spring-amqp`.

## Distributed transactions — the warning

XA / 2PC across JDBC + JMS / RabbitMQ / Kafka in 2026 is almost always wrong:

- Locks rows on the DB side for the duration of network round-trips with the broker — throughput collapses
- Single point of failure: the transaction coordinator's outage takes everyone down
- Recovery semantics on broker outages are messy and broker-specific
- Doesn't compose across HTTP services (no shared XA coordinator) — so you get a half-solution for one tier

The pattern that actually works: **outbox**. Write the domain change and an outbox row in **one local DB transaction**. A relay process reads the outbox and publishes to the bus with retries; consumers are idempotent. See `cqrs-implementation` and `spring-amqp`.

When XA is genuinely the right answer (rare, financial-settlement-level): build a separate skill for it. Default position is "no XA."

## After-commit pattern

Side effects that must happen **only** if the TX actually commits — sending an email, emitting an external event, calling a webhook — should fire from a `@TransactionalEventListener`:

```kotlin
@Service
class PlaceOrderService(
    private val orders: OrderRepository,
    private val events: ApplicationEventPublisher,
) {
    @Transactional
    fun place(req: PlaceOrderRequest): Order {
        val order = Order.new(req)
        orders.save(order)
        events.publishEvent(OrderPlaced(order.id))   // queued; delivered after commit
        return order
    }
}

@Component
class OrderPlacedNotifier(private val email: EmailGateway) {
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    fun sendConfirmation(event: OrderPlaced) {
        email.sendOrderConfirmation(event.orderId)
    }
}
```

Properties:

- The listener runs **on the same thread**, **after** COMMIT, **outside** the TX. No new TX unless the listener itself is `@Transactional`.
- If the TX rolls back, the listener is **not** invoked — the email is never sent on a phantom order.
- If the listener throws, the TX is already committed — the failure does not undo the COMMIT. It does, however, take out the current request unless you catch it inside the listener.

Phases (`TransactionPhase`):

- `BEFORE_COMMIT` — last chance to mutate inside the TX
- `AFTER_COMMIT` (default and what you want 95% of the time)
- `AFTER_ROLLBACK` — symmetric: log / metric / cleanup the failed case
- `AFTER_COMPLETION` — fires for both commit and rollback

For durability — "email must be sent even if the JVM crashes between COMMIT and the listener" — `@TransactionalEventListener` alone is not enough. You need the **outbox pattern** (Modulith's `event_publication` table or a hand-rolled one). The listener fires from the outbox process, with retries and idempotency. See `cqrs-implementation`, `spring-events`, `spring-modulith`, `spring-amqp`.

## Observability

When something doesn't roll back when you expected, look in this order:

1. **`logging.level.org.springframework.transaction=TRACE`** — logs every `Creating new transaction`, `Participating in existing transaction`, `Initiating transaction commit`, `Initiating transaction rollback`. If the message isn't there, the proxy was bypassed.
2. **JDBC / Hibernate SQL log** (`logging.level.org.hibernate.SQL=DEBUG`, `org.hibernate.orm.jdbc.bind=TRACE` for params) — look for `BEGIN` / `COMMIT` / `ROLLBACK` around your method.
3. **`TransactionSynchronizationManager.isActualTransactionActive()`** — sprinkle inside the method temporarily if you suspect a proxy bypass. Returns `false` = no TX.
4. **Micrometer `transaction` metrics** — `JdbcTransactionManager` and Hibernate publish timers for begin / commit / rollback duration. Spikes in rollback rate are a red flag.
5. **Connection-pool metrics** — HikariCP exposes `hikaricp.connections.active` and `hikaricp.connections.pending`. Spikes during what should be fast endpoints mean a TX is holding a connection for too long.

## Anti-patterns

| Anti-pattern | Why it's wrong | Fix |
|---|---|---|
| `@Transactional` on a controller method | HTTP doesn't dictate atomicity; couples the boundary to the wrong layer; opens connection earlier than needed | Move to the service / use-case method |
| `@Transactional` on a `JpaRepository` | Spring Data already wraps each repo method in its own TX; redundant | Remove; put the boundary on the service |
| `@Transactional(propagation = REQUIRED)` everywhere | Default; pure noise; hides the few methods where propagation is a deliberate choice | Remove from defaults; keep only on `REQUIRES_NEW` / `MANDATORY` / `NESTED` |
| `try { … } catch (Exception) { log }` inside a `@Transactional` method | The proxy never sees the exception → no rollback → partial writes commit | Re-throw, or `setRollbackOnly()` |
| `runCatching { … }` inside `@Transactional` without re-throwing | Same trap as the catch above | Re-throw on failure, or use `.getOrThrow()` |
| Nested `@Transactional` confusion | Two `@Transactional` methods in a chain run in the **same** TX (`REQUIRED` default). Many people expect a new TX | Read the propagation rules; use `REQUIRES_NEW` if you want a new one |
| Self-invocation of a `@Transactional` method | `this.method()` skips the proxy → no TX | Extract to a second bean, or move `@Transactional` to the outer method |
| `@Transactional` on a `private` / `final` / `new`-ed method | Proxy can't intercept it | Make public + bean + `open` (or via `kotlin-spring` plugin) |
| `@Transactional` for a pure read | Starts a write-capable TX; misses `readOnly` optimizations and replica routing | Add `readOnly = true` |
| `@Transactional` wrapping a slow external HTTP call | DB connection held for the duration; pool exhaustion under load | Split: do the DB work in one TX, the HTTP call outside, use AFTER_COMMIT for fire-and-forget |
| `@Transactional` on every method "just in case" | Cargo cult; obscures real boundaries; introduces propagation surprises | One `@Transactional` per use case, on the use-case method |
| Mixing `@Transactional` with manual `entityManager.flush()` / `clear()` to "fix" weird behaviour | Symptom; usually means the boundary is wrong | Find the right boundary; flushing manually is a code smell |
| Distributed transaction across DB + broker via XA / 2PC | Tightly couples availability; recovery is messy; doesn't compose with HTTP | Use the outbox pattern instead |
| `ChainedTransactionManager` for multi-resource atomicity | Deprecated; was best-effort, never true 2PC | Outbox; or accept eventual consistency |

## Kotlin specifics

- **No checked exceptions → default rollback is right.** Don't sprinkle `rollbackFor = Exception::class` everywhere. Use it only when interacting with Java code that throws checked exceptions you want to treat as failure.
- **`kotlin-spring` (`all-open`) plugin is mandatory.** Without it, `@Transactional` on a class compiled `final` fails at startup with a cryptic CGLIB error. With it, every Spring stereotype is auto-`open`. Set it in `build.gradle.kts` once.
- **`object` can't be `@Transactional`.** A Kotlin `object` is a JVM singleton, not a Spring bean — no proxy, no advice. Use `@Component` / `@Service` on a regular class.
- **`runCatching` rollback gotcha.** Same trap as `try/catch`. Either re-throw via `.getOrThrow()` or call `setRollbackOnly()` explicitly. Treat `runCatching` inside `@Transactional` as a red flag in code review.
- **Coroutines + `@Transactional`** — Spring 6 supports reactive transaction managers (`R2dbcTransactionManager`, `ReactiveTransactionManager`) that work with `suspend fun`. For traditional JDBC + JPA, the safer pattern is to keep `@Transactional` on a regular `fun` and call it from a `suspend fun` that does its own dispatching (`withContext(Dispatchers.IO) { service.transactionalCall() }`). Mixing imperative TX with coroutine cancellation is subtle — the TX is bound to a thread, not a coroutine, so coroutine cancellation does not auto-rollback the TX.
- **`@JvmInline value class` ids** in `@Transactional` method signatures — fine; they erase to their underlying type at the JVM level.
- **`internal` visibility** compiles to `public` at the JVM level with a mangled name. AOP proxies work, but if you call across module boundaries you may hit unexpected access errors. Prefer `public` for cross-bean transactional methods.

## Related skills

- `spring` — router; cross-cutting Spring principles (constructor injection, `@Transactional` on service)
- `spring-bean` — bean wiring, `@Component` vs `@Bean`, constructor injection, `@Lazy` / `@DependsOn`, circular deps
- `spring-boot` — `@ConfigurationProperties`, profile / property precedence, auto-config debugging
- `spring-aop` — `@Aspect`, pointcut expressions, advice ordering, the proxy mechanics (this skill covers the `@Transactional`-specific proxy gotchas; `spring-aop` covers the general aspect machinery)
- `spring-events` — `ApplicationEventPublisher`, `@EventListener`, `@TransactionalEventListener`, Modulith `@ApplicationModuleListener` (after-commit at scale)
- `spring-data-jpa` — `JpaRepository`, derived queries, Specifications, `Pageable` (each repo method is already transactional)
- `hibernate` — persistence context, entity lifecycle, fetch types, N+1, `LazyInitializationException` (the canonical "no TX in scope" symptom)
- `spring-amqp` — outbox for RabbitMQ; idempotent consumers
- `spring-async`, `spring-scheduler`, `spring-cache` — sibling AOP-driven annotations with the same proxy rules
- `spring-modulith` — `event_publication` outbox; `@ApplicationModuleListener` (async after-commit)
- `cqrs-implementation` — write-side TX boundary, outbox detail, projection lag
- `database-design` — isolation, locking, `SELECT ... FOR UPDATE`, optimistic version columns
- `testing-strategy-kotlin-spring` — `@DataJpaTest` slices and TX rollback in tests
- `clean-code-error-handling` — exception design that interacts cleanly with rollback rules
- `debugging-systematic` — when the TX silently doesn't fire and you need a method, not a guess
- `methodology` — always invoke before code; verify before claiming the boundary works

## Limitations

- Targets Spring Boot **3+** on Kotlin 2.x / JVM 21+ with PostgreSQL as the default RDBMS. Other DBs (MySQL, Oracle, SQL Server) differ in default isolation, locking, and 2PC support — pair with their docs.
- Doesn't cover **reactive transactions** (`R2dbcTransactionManager`, `ReactiveTransactionManager`, `TransactionalOperator`) in depth. The imperative `@Transactional` machinery this skill covers does not directly apply to `Mono` / `Flux` chains — a dedicated reactive-transactions skill would.
- Doesn't cover **JTA / XA / two-phase commit** beyond the warning. If your design genuinely needs them (financial settlement, regulatory mandate), engage a specialist and build a separate skill.
- Doesn't cover **database-side concurrency primitives** in depth — advisory locks, `SELECT ... FOR UPDATE`, optimistic locking via `@Version`, retry on serialization failure. Pair with `database-design` and your DB's docs.
- Doesn't cover **schema migrations under load** (Flyway / Liquibase, zero-downtime DDL) — that's `database-design`.
- The proxy-gotcha diagnosis lives **here** in this skill (it's the canonical place readers come to debug "why didn't this roll back"). The general aspect-authoring machinery — `@Aspect`, `@Around`, pointcut grammar — is `spring-aop`'s territory.
