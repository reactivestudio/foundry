# Resilience Patterns

Circuit breaker, retry, bulkhead, time limiter, rate limiter — Resilience4j on Kotlin/Spring. Composition. Idempotency. Sagas (overview).

---

## 1. The five Resilience4j patterns

| Pattern | What | When |
|---|---|---|
| **Circuit Breaker** | Trip "open" after N failures, fail fast for cool-down period | Downstream is down/struggling; protect callers |
| **Retry** | Retry N times with backoff | Transient failures (network blip, brief 503) |
| **Bulkhead** | Limit concurrent calls to a resource | Prevent one slow downstream from exhausting your threads |
| **Time Limiter** | Cap individual call duration | Prevent unbounded waits |
| **Rate Limiter** | Cap calls/second | Honour vendor quotas; protect downstream |

These compose: Retry-inside-CircuitBreaker-inside-TimeLimiter. Order matters.

---

## 2. Setup

```kotlin
// build.gradle.kts
implementation("io.github.resilience4j:resilience4j-spring-boot3:2.2.0")
implementation("org.springframework.boot:spring-boot-starter-aop")
implementation("io.github.resilience4j:resilience4j-reactor:2.2.0")     // for Mono/Flux
```

```yaml
resilience4j:
  circuitbreaker:
    instances:
      githubApi:
        failure-rate-threshold: 50            # % of calls failed before opening
        slow-call-rate-threshold: 80           # % of slow calls before opening
        slow-call-duration-threshold: 2s       # threshold for "slow"
        minimum-number-of-calls: 10            # before threshold checked
        wait-duration-in-open-state: 30s       # cool-down before half-open
        permitted-number-of-calls-in-half-open-state: 3
        sliding-window-type: count_based       # or time_based
        sliding-window-size: 100
  retry:
    instances:
      githubApi:
        max-attempts: 3
        wait-duration: 500ms
        exponential-backoff-multiplier: 2
        retry-exceptions:
          - java.io.IOException
          - java.util.concurrent.TimeoutException
  bulkhead:
    instances:
      githubApi:
        max-concurrent-calls: 10
        max-wait-duration: 100ms
  timelimiter:
    instances:
      githubApi:
        timeout-duration: 5s
        cancel-running-future: true
  ratelimiter:
    instances:
      githubApi:
        limit-for-period: 30
        limit-refresh-period: 1s
        timeout-duration: 0
```

---

## 3. Circuit Breaker — the most important pattern

When a downstream service is overwhelmed, retrying makes it worse. A circuit breaker fails fast after detecting a problem, gives downstream time to recover.

### States

```
        ┌─────────┐  failure rate exceeded
        │ CLOSED  │ ─────────────────────────→ ┌──────┐
        │ (normal)│                              │ OPEN │
        └─────────┘ ← ───────────────────────── │(fail │
                          fail fast              │ fast)│
                                                  └──┬───┘
                                                      │ after cool-down
                                                      ▼
                                                ┌────────────┐
                                                │ HALF-OPEN  │
                                                │ (probe N   │
                                                │ calls)     │
                                                └────────────┘
                                                  ↓        ↓
                                            recovered    still failing
                                                  ↓        ↓
                                              CLOSED     OPEN
```

### Usage — annotation

```kotlin
@Service
class GitHubClient(private val httpClient: HttpClient) {

    @CircuitBreaker(name = "githubApi", fallbackMethod = "fallback")
    fun fetchUser(login: String): GitHubUser =
        httpClient.get("/users/$login").body<GitHubUser>()

    fun fallback(login: String, ex: Throwable): GitHubUser {
        log.warn("CircuitBreaker fallback for {}: {}", login, ex.message)
        return GitHubUser.unavailable(login)
    }
}
```

### Usage — programmatic

```kotlin
val cb = CircuitBreaker.ofDefaults("githubApi")
val supplier = CircuitBreaker.decorateSupplier(cb) { httpClient.get("/users/$login") }
val result: Try<GitHubUser> = Try.of(supplier).recover { fallback(login, it) }
```

### Picking thresholds

| Workload | Failure rate | Wait duration | Window |
|---|---|---|---|
| Critical (DB) | 50% | 30s | Count-based 50 |
| Vendor API (GitHub, Slack) | 50% | 60s | Count-based 100 |
| Best-effort feature | 30% | 10s | Count-based 20 |
| Slow-but-stable backend | Higher (use slow-call threshold) | 30s | Time-based 60s |

**Don't:** set thresholds aggressively (5% failure → open) → flapping under normal noise.

---

## 4. Retry — only with care

```kotlin
@Retry(name = "githubApi")
@CircuitBreaker(name = "githubApi")
fun fetchUser(login: String): GitHubUser = ...
```

Annotation order: closest-to-method runs innermost. With both, the wrap order at runtime is:

```
CircuitBreaker → Retry → method
```

So retries happen first; if the retry budget exhausts, the circuit breaker counts the final failure.

### Retry hazards

- **Retry without backoff** — amplifies load on struggling service.
- **Retry without idempotency** — duplicate writes (charge customer twice).
- **Retry without max attempts** — eternal retry loop.
- **Retry on non-transient errors** — 400 Bad Request won't change; don't retry.

Whitelist retryable exceptions:

```yaml
retry:
  instances:
    githubApi:
      retry-exceptions:
        - java.io.IOException
        - java.net.SocketTimeoutException
      ignore-exceptions:
        - BadRequestException
```

Or programmatically:

```kotlin
val retry = Retry.of("githubApi", RetryConfig {
    maxAttempts(3)
    waitDuration(Duration.ofMillis(500))
    retryOnException { ex ->
        ex is IOException || (ex is HttpStatusException && ex.status >= 500)
    }
})
```

---

## 5. Bulkhead — thread isolation

```kotlin
@Bulkhead(name = "githubApi", type = Bulkhead.Type.SEMAPHORE)
fun fetchUser(login: String): GitHubUser = ...
```

If GitHub is slow, only 10 threads block on it; other endpoints stay responsive.

### Bulkhead types

- **Semaphore** (default in Resilience4j) — caller threads block waiting for permit. Lightweight.
- **Threadpool** — calls execute on a dedicated pool. Isolates blocking, but thread context switch overhead.

For most cases: **Semaphore**.

Use Threadpool when the underlying call is genuinely blocking (JDBC, long-running computation) and you want to isolate from caller threads.

---

## 6. Time Limiter

```kotlin
@TimeLimiter(name = "githubApi")
@CircuitBreaker(name = "githubApi")
fun fetchUser(login: String): CompletableFuture<GitHubUser> =
    CompletableFuture.supplyAsync { httpClient.get("/users/$login").body() }
```

TimeLimiter only works with `CompletableFuture` (or reactive `Mono`/`Flux`). For synchronous calls, use the underlying HTTP client's timeout config.

```kotlin
// WebClient: built-in timeout
val webClient = WebClient.builder()
    .baseUrl("https://api.github.com")
    .clientConnector(ReactorClientHttpConnector(
        HttpClient.create()
            .responseTimeout(Duration.ofSeconds(5))
            .option(ChannelOption.CONNECT_TIMEOUT_MILLIS, 3_000)
    ))
    .build()
```

Always set timeout. Default `WebClient` has no timeout — calls hang forever on unresponsive server.

---

## 7. Rate Limiter — quota enforcement

```kotlin
@RateLimiter(name = "githubApi")
fun fetchUser(login: String): GitHubUser = ...
```

```yaml
ratelimiter:
  instances:
    githubApi:
      limit-for-period: 30        # 30 calls
      limit-refresh-period: 1s    # per 1 second
      timeout-duration: 0         # caller fails immediately if no permit
```

Use to honour vendor quotas (GitHub: 5000/h authenticated; rate-limit yourself to stay safely below).

For per-tenant rate limiting (different limit per customer): see Bucket4j + Redis (covered in `caching-strategies-spring` / gateway).

---

## 8. Composition — `@Retry`, `@CircuitBreaker`, `@TimeLimiter`, `@Bulkhead` together

```kotlin
@Bulkhead(name = "githubApi")
@TimeLimiter(name = "githubApi")
@CircuitBreaker(name = "githubApi", fallbackMethod = "fallback")
@Retry(name = "githubApi")
fun fetchUser(login: String): CompletableFuture<GitHubUser> = ...
```

Resilience4j execution order (outermost to innermost):

```
Bulkhead → TimeLimiter → CircuitBreaker → Retry → method
```

Reasoning:
- **Bulkhead first**: limit concurrent attempts; if no permit, fail fast
- **TimeLimiter next**: bound the whole attempt (including retries)
- **CircuitBreaker**: if open, fail fast
- **Retry innermost**: retry once, the wrappers protect against runaway

Composition is powerful but care: TimeLimiter (5s) wrapping Retry (3 attempts × 500ms backoff) means each attempt has ~1.5s; one slow call can blow the budget.

---

## 9. Idempotency revisited (cross-service)

Without idempotency, retries are dangerous. Two strategies:

### Idempotency keys (HTTP/REST)

```
POST /api/orders
Idempotency-Key: 9e6b1e8c-7c8a-4f4a-9c6a-1c0a2b3c4d5e
```

Server stores `(key → result)`. Duplicate request with same key → return cached result, no double-write.

See `api-design-principles/references/rest-best-practices.md` §11.

### Idempotent operations

```kotlin
// Idempotent by design
SET status = 'CANCELLED' WHERE id = X            // OK to repeat
INSERT ... ON CONFLICT (id) DO NOTHING            // OK to repeat
UPDATE balance = balance + 100 WHERE id = X       // NOT idempotent — accumulates
```

Prefer idempotent operations where possible. Where impossible: idempotency keys.

---

## 10. Outbox pattern (cross-service write consistency)

Already covered in `cqrs-implementation/resources/write-side-patterns.md` §7 and `messaging-rabbitmq-spring/resources/reliability.md` §10.

**Reminder for cross-service:**
- Service A writes to its DB + emits event in same transaction (via outbox table or Modulith `event_publication`)
- Background relay publishes to RabbitMQ/Kafka
- Service B consumes, processes idempotently, updates its DB
- If B fails, message stays in queue; retry; DLQ if poisoned

This pattern replaces 2PC across services.

---

## 11. Saga (orchestration vs choreography) — overview

For a multi-step workflow spanning services (e.g., place order → reserve stock → charge card → ship), atomicity isn't free. Two patterns:

### Choreography (event-driven)

```
OrderService:    place → emit OrderPlaced event
StockService:    consume → reserve → emit StockReserved or StockReservationFailed
BillingService:  consume StockReserved → charge → emit Charged or ChargeFailed
ShippingService: consume Charged → ship
                       ↑
              if anything fails, emit compensation events
              (e.g. StockReservationFailed → release stock)
```

Pros: loose coupling. Cons: hard to follow flow in code; needs careful event design.

### Orchestration (central coordinator)

```
SagaOrchestrator:
   step1: call StockService.reserve()
   step2: call BillingService.charge()
   step3: call ShippingService.ship()

   on failure of step N: invoke compensation for steps 1..N-1
```

Pros: clear central state machine. Cons: orchestrator becomes a god-component.

Frameworks: **Axon Framework** (saga support), **Camunda** (BPMN), **Temporal**, **Spring Statemachine**.

Detailed coverage: future `saga-orchestration` skill if needed.

---

## 12. Chaos engineering basics

Production resilience isn't proved until it's tested under failure. Practices:

- **Game days**: scheduled incident simulation
- **Chaos Monkey** (Netflix): kill random instances
- **Latency injection**: add 1s delay to one downstream — does your system survive
- **Resource starvation**: throttle a DB → does your circuit breaker trip?

Don't run chaos in prod without ops capability and runbooks. Stage-first.

---

## 13. SLO awareness

Resilience strategies affect SLOs. Examples:

- Aggressive retries → more downstream load → cascading failure
- Circuit breaker open → fail-fast → fewer slow responses but more 503s
- Rate limiter → predictable load but rejects spikes

Define your SLOs first (see `system-design-fundamentals` and `architecture` Example 3 mention of SLI/SLO). Resilience config follows from SLO requirements:

- "99.9% availability" → graceful degradation matters
- "p99 < 500ms" → time limiter at 500ms
- "Vendor X limited to 100rps" → rate limiter at 90rps

---

## 14. Common pitfalls

- **Retry on writes without idempotency.** Duplicate side effects.
- **Retry forever on 4xx.** Client errors don't fix themselves.
- **Circuit breaker never recovers.** Half-open probe failing → still open. Check downstream health.
- **TimeLimiter on blocking JDBC.** `cancel-running-future` doesn't actually interrupt the JDBC call; only abandons the future. Use connection-level timeouts too.
- **No fallback method.** Circuit opens → all callers explode with `CallNotPermittedException`. Always have a fallback (cached value, default, partial response, well-formed error).
- **Synchronous retry inside async pipeline.** Blocks the reactor thread. Use `Mono.retry` / `retryWhen`.
- **Single global circuit breaker for many endpoints.** One endpoint's failure trips the whole breaker; other endpoints unaffected get cut off. Per-endpoint or per-vendor breakers.
- **No metrics on Resilience4j events.** Without `circuitbreaker.calls{state="open"}` etc., you can't see what's happening. Wire Micrometer.
- **Retry budget unlimited.** Across many concurrent callers, retries multiply. Use a retry budget at the gateway / mesh level.
- **Compensation as an afterthought** in sagas. Plan compensations first; they're as important as the happy path.
