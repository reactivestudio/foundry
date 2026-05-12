# WebMVC vs WebFlux — the imperative/reactive decision

The single biggest "which stack" decision in Spring. Often misunderstood.

---

## 1. The honest answer first

**Default: WebMVC.** Use WebFlux only when you have a real reactive workload.

This is the opposite of what hype suggests. Reactive is "modern" — but in 2025, with virtual threads (`Project Loom`) in JVM 21, the case for WebFlux is weaker than it was.

---

## 2. What each is

| | **WebMVC** | **WebFlux** |
|---|---|---|
| Programming model | Imperative; one thread per request | Reactive; few threads, many concurrent operations |
| Underlying server | Tomcat / Jetty (servlet) | Netty / Undertow (non-blocking) |
| API style | `@RestController`, `ResponseEntity<T>` | `@RestController`, `Mono<T>` / `Flux<T>` |
| DB layer | JDBC (blocking), Spring Data JPA | R2DBC (reactive), Spring Data R2DBC |
| Concurrency | Thread per request (200 default) | Event loop (4-8 threads) |
| Debuggable stack traces | Linear, easy | Distributed across threads, harder |
| Mental model | Synchronous, straightforward | Reactor / `Mono` / `Flux` semantics |

---

## 3. When WebFlux wins

- **High concurrent connections with low CPU work per request.** Chat servers, SSE/WebSocket fan-out, long-polling endpoints — these saturate thread pools in WebMVC.
- **Outbound calls dominate latency.** Service that mostly waits on 5 downstream services. Reactive composition (`Mono.zip`) is natural.
- **Backpressure matters.** Streaming data to clients faster than they can consume → reactive handles backpressure properly.
- **Already in reactive ecosystem.** R2DBC for DB, Reactor for Kafka, etc.

---

## 4. When WebMVC wins (most cases)

- **CRUD-heavy services.** Per-request work is mostly: 1 DB call, some logic, return JSON. Thread pool overhead is irrelevant.
- **JPA / blocking DB.** Spring Data JPA, Hibernate, JDBC are blocking — using them in WebFlux means wrapping in `Mono.fromCallable(...)` on a `Schedulers.boundedElastic()`, which loses most reactive benefits.
- **Team comfort.** Imperative code is easier to read, debug, hire for.
- **Spring Boot Actuator, Spring Security, ecosystem tooling** — better-developed for WebMVC.

For ~80% of Spring Boot services, WebMVC is correct. Heuristic: if your service is "REST → JPA → response", **WebMVC**. Don't second-guess.

---

## 5. Virtual threads change the calculus

**Spring Boot 3.2+** supports virtual threads (Project Loom, JVM 21):

```yaml
spring:
  threads:
    virtual:
      enabled: true
```

Effects:
- Servlet thread pool now uses virtual threads
- Each request gets a virtual thread (lightweight, ~KB instead of MB)
- Blocking IO (JDBC, file IO, HTTP client) doesn't pin OS threads
- Million-concurrent-request capability with familiar WebMVC code

In effect: **virtual threads give WebMVC most of what WebFlux offered, with simpler code**.

When to enable:
- High concurrency + blocking IO (DB, HTTP clients)
- Apps that would otherwise need WebFlux
- After load testing — verify behaviour under your specific workload

Caveats:
- `synchronized` blocks **pin** the carrier thread — be aware. Use `ReentrantLock` instead in hot paths.
- Third-party libraries with thread pools may behave oddly. Test.
- ThreadLocal usage works but per-virtual-thread cost adds up.

---

## 6. Decision tree

```
Does your service handle 10K+ concurrent connections?
├── No → WebMVC
└── Yes
    │
    Is most of the work blocking IO (DB, HTTP)?
    ├── Yes
    │   │
    │   Are you on JVM 21+ with Spring Boot 3.2+?
    │   ├── Yes → WebMVC + virtual threads ✓ (best of both)
    │   └── No → WebFlux (with reactive drivers!)
    │
    └── No, lots of CPU work or stream processing
        └── WebFlux (real reactive workload)
```

---

## 7. Mixing — possible but messy

You can have both:
- Most app uses WebMVC
- A single reactive endpoint via `@Controller` returning `Mono<T>`

But you need `spring-boot-starter-webflux` in classpath; the auto-config detects `WebFlux` and may switch the server to Netty. Mixed mode is supported via `@EnableWebFlux` etc. — but adds confusion. Pick one per service.

---

## 8. Kotlin coroutines + Spring

Coroutines are the Kotlin-idiomatic answer to reactive. Spring 5.3+ supports `suspend` functions in `@RestController`:

```kotlin
@RestController
class OrderController(private val service: OrderService) {

    @GetMapping("/orders/{id}")
    suspend fun get(@PathVariable id: UUID): OrderResponse =
        service.findById(id) ?: throw NotFoundException()
}

@Service
class OrderService(...) {
    suspend fun findById(id: UUID): OrderResponse? = withContext(Dispatchers.IO) {
        repo.findById(id)?.toResponse()
    }
}
```

This works with WebFlux. With **WebMVC + virtual threads**, even cleaner — call regular blocking code, no `withContext` needed.

For coroutines deeper (StateFlow, Channels, structured concurrency) — see separate skill (could write `kotlin-coroutines-spring` if you choose Tier 2).

---

## 9. Practical guidance for new services

**For `assista-platform` and similar Spring backends:**

1. **Start with WebMVC.** Default. Boring is good.
2. **Enable virtual threads** if on JVM 21 + Boot 3.2+. Test thoroughly under load.
3. **WebFlux is the answer only if** you genuinely need 10K+ concurrent connections, OR your workload is stream-processing-shaped (Kafka consumer with backpressure, etc.).
4. **Don't mix imperative + reactive in one app.** Adds confusion without clear win.

---

## 10. The performance reality check

In benchmarks (TechEmpower, Spring team data):
- WebMVC handles ~20K req/s per instance on modest hardware
- WebFlux handles ~50K req/s under perfect reactive conditions (R2DBC, etc.)
- WebMVC + virtual threads is in the same ballpark as WebFlux for many workloads

For a service doing 1K-10K req/s, **the difference doesn't matter**. The bottleneck is the DB. Pick the model that's easier to maintain.

---

## 11. Migration considerations

**Moving WebMVC → WebFlux:**
- Replace `ResponseEntity<T>` returns with `Mono<ResponseEntity<T>>`
- Replace JdbcTemplate / JPA with R2DBC repositories (different API; entities differ)
- Replace `RestTemplate` with `WebClient`
- Replace `MockMvc` test slices with `WebTestClient`
- Spring Security WebFlux config differs significantly from WebMVC

Not a drop-in. Most teams who switch back, switch back.

**Moving WebMVC → WebMVC + virtual threads:**
- Flip a config flag.
- Test under load.
- Done.

Choose accordingly.

---

## 12. Anti-patterns

- **Choosing WebFlux for hype.** "Reactive is modern" isn't a requirement.
- **Wrapping blocking JPA in `Mono.fromCallable(...)`.** You lose 90% of reactive benefits while keeping all the complexity. If you can't go full reactive, don't go reactive.
- **Mixing `block()` / `await()` calls in WebFlux pipelines.** Breaks reactive semantics; defeats the purpose.
- **Premature WebFlux + R2DBC for "scale we might need someday."** YAGNI. Stick with WebMVC + virtual threads until forced.
- **Using `RestTemplate` in WebFlux.** Switch to `WebClient`. (Spring 6 deprecated `RestTemplate` for new code — use `RestClient` in WebMVC, `WebClient` in WebFlux.)
