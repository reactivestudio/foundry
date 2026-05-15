# Code Examples — Bad vs Best

Six paired snippets illustrating the canonical mistakes Claude should catch. **Kotlin syntax for clarity only** — no coroutines, no `data class` semantics, no `runCatching` magic. Same shape applies to Java, Python, TS, Go.

---

## 1. Sync side-effect inside the happy path (T10)

**Bad** — order creation blocks on SMS:

```kotlin
fun placeOrder(req: OrderRequest): Order {
    val order = orderRepo.save(req.toOrder())
    smsClient.send(req.phone, "Order ${order.id} placed")  // 200 ms; can fail
    return order
}
```

If `smsClient` is slow → orders are slow. If `smsClient` is down → orders **fail** — but order placement is correct, only the notification isn't.

**Best** — emit an event; let a listener handle the side effect:

```kotlin
fun placeOrder(req: OrderRequest): Order {
    val order = orderRepo.save(req.toOrder())
    eventBus.publish(OrderPlaced(order.id, req.phone))     // fire-and-forget
    return order
}

// elsewhere:
fun onOrderPlaced(e: OrderPlaced) {
    smsClient.send(e.phone, "Order ${e.orderId} placed")   // retries independently
}
```

Order succeeds independently; SMS retries on its own. Compose with the outbox (§4) so event-publish is atomic with the order write.

---

## 2. Blind retry — thundering herd (PT8)

**Bad** — every client retries at the same moment:

```kotlin
repeat(5) {
    try { return externalApi.call(req) }
    catch (e: TransientException) { Thread.sleep(1000) }   // fixed 1 s
}
throw GiveUpException()
```

When the upstream recovers, **all** stuck clients hammer it at the same `+1 s` tick. The recovery instantly re-fails.

**Best** — exponential backoff + jitter:

```kotlin
var wait = 1_000L
repeat(5) { attempt ->
    try { return externalApi.call(req) }
    catch (e: TransientException) {
        if (attempt == 4) throw e
        Thread.sleep(wait + Random.nextLong(0, wait / 2))  // jitter
        wait = (wait * 2).coerceAtMost(30_000L)            // cap
    }
}
```

`wait = 1 s, 2 s, 4 s, 8 s, 16 s` (each with random padding) spreads clients across the recovery window. Don't retry on 4xx, on POST without an idempotency key (§5), or after the request deadline.

---

## 3. Rate-limit counter race (PT7)

**Bad** — `INCR` then check is non-atomic:

```kotlin
fun allow(userId: String, limit: Int): Boolean {
    val key = "rl:$userId:${currentMinute()}"
    val count = redis.incr(key)            // ← atomic
    if (count == 1L) redis.expire(key, 60) // ← NOT atomic with INCR
    return count <= limit
}
```

If the JVM dies between `INCR` and `EXPIRE`, the key has **no TTL** and the counter sticks at its current value forever — the user is silently blocked.

**Best** — atomic Lua script (executes server-side as one step):

```kotlin
private val SCRIPT = "local c=redis.call('INCR',KEYS[1]); if c==1 then redis.call('EXPIRE',KEYS[1],ARGV[1]) end; return c"

fun allow(userId: String, limit: Int): Boolean {
    val key = "rl:$userId:${currentMinute()}"
    return (redis.eval(SCRIPT, listOf(key), listOf("60")) as Long) <= limit
}
```

---

## 4. Two-write race — "state and event" (PT9)

**Bad** — write DB then publish to Kafka:

```kotlin
fun ship(orderId: OrderId) {
    orderRepo.markShipped(orderId)             // commits
    kafka.send(OrderShipped(orderId))          // may fail → event lost
}
```

If `kafka.send` fails after the DB commit, the state changed but no consumer ever hears about it — silent inconsistency forever. Reverse the order and the same hole exists in the other direction.

**Best** — outbox table; relay publishes asynchronously:

```kotlin
@Transactional
fun ship(orderId: OrderId) {
    orderRepo.markShipped(orderId)
    outboxRepo.save(OutboxRow(UUID.randomUUID(), "orders", serialize(OrderShipped(orderId))))
}

// separate relay process:
fun relay() = outboxRepo.fetchUnpublished(100).forEach { row ->
    kafka.send(row.topic, row.payload)
    outboxRepo.markPublished(row.id)
}
```

The TX is atomic; the event is guaranteed to land in `outbox`. Delivery is at-least-once — fine because the consumer is idempotent (§5).

---

## 5. At-least-once consumer with no idempotency (PT6, T9)

**Bad** — every event mutates state directly:

```kotlin
fun onPaymentReceived(e: PaymentReceived) {
    accountRepo.credit(e.accountId, e.amount)   // duplicates double-credit
}
```

Kafka redelivery (broker restart, consumer rebalance, retry) → account credited twice. There is no "exactly once" — that's the lie (T9).

**Best** — idempotency-key receiver:

```kotlin
fun onPaymentReceived(e: PaymentReceived) {
    val applied = receiptRepo.tryInsert(e.eventId)   // PK = eventId; conflict = duplicate
    if (!applied) return                              // already processed
    accountRepo.credit(e.accountId, e.amount)
}
```

`eventId` is the idempotency key; the receipt insert is the gate. First delivery commits, every duplicate bounces off the PK constraint. Same shape for external HTTP POSTs (header `Idempotency-Key: <uuid>`, TTL ≥ retry window; same-key + different body = `422`).

---

## 6. Cascading failure — no circuit breaker (PT8)

**Bad** — every request waits for a dead downstream:

```kotlin
fun getRecommendations(userId: String): List<Item> =
    recommenderApi.fetch(userId)               // 30 s timeout; one slow dep
```

When `recommenderApi` is dead, every incoming request occupies a thread for 30 s. Pool fills; the entire service stops responding — including endpoints that don't even touch recommendations.

**Best** — circuit breaker + fallback (shape; lib is Resilience4j or similar):

```kotlin
private val breaker = CircuitBreaker("recommender", failureRateThreshold = 50, waitDurationInOpen = 30_000)

fun getRecommendations(userId: String): List<Item> =
    breaker.executeSupplier { recommenderApi.fetch(userId) } ?: emptyList()
```

While `OPEN`, calls return the fallback in ~0 ms; threads aren't held. After timeout, a single probe tests recovery (`HALF-OPEN`). Pair with **bulkhead** (separate thread pool for `recommenderApi`) so other downstreams keep full capacity even when the breaker is open.

---

**In review, scan for:** sync side-effects in the happy path (§1), retry loops without jitter (§2), `INCR+EXPIRE` without Lua (§3), "write DB then publish" outside a TX (§4), event consumers without an idempotency check (§5), external calls without a circuit breaker (§6). Each is a small fix that prevents a 3 a.m. incident.
