---
name: spring
description: "Entry point and router for the spring-* family — Spring ecosystem navigation for Kotlin/Spring Boot 3+ services. Owns three things the per-topic siblings don't: the cross-cutting Spring principles that apply everywhere (constructor injection, `@Transactional` on service, typed config, default deny, AOP proxy rules, slices over full boot), the topic-routing logic (which `spring-*` sibling actually applies to the question on the table — `spring-bean` vs `spring-boot` vs `spring-data-jpa` vs `hibernate` vs `spring-aop` vs `spring-events` vs `spring-transactions` vs `spring-web-mvc` vs `spring-rest-clients` vs `spring-async` vs `spring-scheduler` vs `spring-validation` vs `spring-actuator` vs `spring-modulith` vs `spring-amqp` vs `spring-cache` vs `spring-security`), and the ecosystem-level anti-patterns (cargo-culting Spring annotations, fighting conventions, sprinkling `@Autowired` fields, treating Boot starters as black boxes). Use whenever the user mentions Spring, Spring Boot, a Spring annotation (`@Component`, `@Service`, `@Configuration`, `@Bean`, `@Transactional`, `@Async`, `@Scheduled`, `@EventListener`, `@RestController`, `@PreAuthorize`, `@Cacheable`, `@RabbitListener`, `@ConfigurationProperties`, …), or any Spring sub-project, AND the task isn't obviously inside one narrow sibling. Also use when the user asks 'which Spring skill applies here?', when the question spans multiple Spring concerns, or to ground the team on cross-cutting Spring principles. For the deep how-to on each topic, route to the matching `spring-*` sibling — this skill is the map, not the deep dive."
risk: safe
source: "custom — Spring ecosystem router for Kotlin/Spring Boot 3+"
date_added: "2026-05-12"
---

# Spring (router)

Spring is huge. This skill is the entrance — it owns the map and the cross-cutting principles, then routes to the narrow `spring-*` sibling that actually owns the deep how-to for your task.

> Spring is conventions. Knowing the conventions saves 80% of design effort. Fighting them = paying compound interest on accidental complexity.

## What this skill owns (and the siblings don't)

1. **The cross-cutting Spring principles** that apply across all Spring sub-projects (DI, transactions, AOP proxies, slices, config). Each sibling restates the principles relevant to its topic; this skill owns the canonical statement.
2. **The routing logic** — given a question, which `spring-*` sibling actually applies. Most questions touch one; some touch two or three.
3. **The ecosystem-level anti-patterns** — cargo-culting annotations, fighting Spring conventions, using `new SomeService()` to bypass DI, treating Boot starters as black boxes.

The siblings own the deep how-to on their topic. This skill never duplicates that depth — it points.

## Use this skill when

- The user mentions Spring, Spring Boot, or a Spring annotation, and it isn't obviously inside one narrow sibling.
- You need a quick decision: "which `spring-*` skill applies here?"
- The task spans multiple Spring concerns (e.g., "JPA + transactions + events" — touches `spring-data-jpa` + `spring-transactions` + `spring-events`).
- Onboarding someone new to the stack — start here, fan out to siblings as topics arise.
- Reviewing a PR that touches many Spring areas and you want the cross-cutting principles in one place.

## Do not use this skill when

- The task is obviously inside **one narrow sibling** — go straight there. `spring` is the router, not the worker.
- The task is **non-Spring** (pure Kotlin, pure JVM perf, infrastructure, build tooling) — see `karpathy-guidelines`, `clean-code`, `jvm-performance`, etc.

## The Spring map — which sibling for which task

### Spring Core (beyond Boot)

| Task | Skill |
|---|---|
| Register / inject a bean; `@Component` vs `@Bean`; bean lifecycle (`@PostConstruct`, `InitializingBean`, `SmartInitializingSingleton`); scopes (`singleton`, `prototype`, `request`); `@Primary` / `@Qualifier`; `@Profile` / `@Conditional*`; `BeanPostProcessor` / `FactoryBean`; `@Lazy` / `@DependsOn`; circular dependencies | **`spring-bean`** |
| Aspects, pointcut expressions, `@Around` / `@Before` / `@AfterReturning`; advice ordering; **proxy gotchas** (self-invocation, `final` methods, `private`, Kotlin `all-open` plugin); where cross-cutting belongs | **`spring-aop`** |
| `ApplicationEventPublisher`, `@EventListener`, `@TransactionalEventListener` (AFTER_COMMIT pattern), async events, ordering, Modulith `@ApplicationModuleListener` | **`spring-events`** |
| Bean Validation (`jakarta.validation`), `@Valid` / `@Validated`, groups, custom constraints, `MethodArgumentNotValidException` → `ProblemDetail` | **`spring-validation`** |

### Spring Boot specifics

| Task | Skill |
|---|---|
| `@SpringBootApplication`, auto-configuration, starters, `@ConditionalOnX`, properties precedence, profiles in Boot, `@ConfigurationProperties` with `@Validated`, externalised config, secrets, `ApplicationRunner` / `CommandLineRunner` | **`spring-boot`** |
| Actuator endpoints, security on Actuator, health indicators, `info` contributors, Micrometer + tags, OpenTelemetry tracing, custom metrics | **`spring-actuator`** |
| Spring Modulith — application modules, `@ApplicationModuleListener`, event publication registry (in-process outbox), encapsulation rules, `ApplicationModuleTest`, observability via Observation API, `Documenter` | **`spring-modulith`** |

### Spring Web (sync; WebFlux out of scope)

| Task | Skill |
|---|---|
| `@RestController`, `@RequestMapping` family, `@RequestBody` / `@PathVariable` / `@RequestParam`, `@ControllerAdvice` + `ProblemDetail`, `HandlerInterceptor`, filters, content negotiation, multipart, CORS, `ResponseEntity` | **`spring-web-mvc`** |
| Outbound HTTP: `RestClient` (Boot 3.2+, default), `RestTemplate` (legacy), `WebClient` (sync mode), `HttpExchange` declarative clients, OpenFeign; error handling, retry, timeouts | **`spring-rest-clients`** |
| REST / gRPC contract design (resource modelling, status codes, idempotency, versioning, pagination) | `api-design-principles` |

### Spring Data / Persistence

| Task | Skill |
|---|---|
| `JpaRepository` hierarchy, derived queries, `@Query`, `@EntityGraph`, `Pageable`, Specifications, projections, keyset pagination, Spring Data JDBC | **`spring-data-jpa`** |
| Hibernate-specific: persistence context, entity lifecycle (transient / managed / detached / removed), `@Entity` / `@Embeddable` / `@MappedSuperclass`, fetch types, **N+1**, `JOIN FETCH`, `equals` / `hashCode` for entity, `data class` ловушки, optimistic locking, second-level cache | **`hibernate`** |
| `@Transactional` propagation / isolation / `rollbackFor` / `readOnly` / timeout, transaction boundary on the service, programmatic vs declarative, **AOP-proxy gotchas** (self-invocation, `private`, `final`), `TransactionTemplate`, distributed-transaction warning | **`spring-transactions`** |
| Schema design, indexes, Flyway migrations, polyglot store choice (Postgres / Mongo / ES / Clickhouse) | `database-design` |

### Async / Background

| Task | Skill |
|---|---|
| `@Async`, `AsyncConfigurer`, `ThreadPoolTaskExecutor`, **virtual threads** (Loom), proxy ограничения, context propagation (MDC / `SecurityContext` / tenant), `CompletableFuture` | **`spring-async`** |
| `@Scheduled` (cron / `fixedRate` / `fixedDelay` / `initialDelay`), `ThreadPoolTaskScheduler`, **ShedLock** for clustered scheduling, idempotency, observability of scheduled tasks | **`spring-scheduler`** |

### Messaging

| Task | Skill |
|---|---|
| RabbitMQ — exchanges, `RabbitTemplate`, `@RabbitListener`, publisher confirms, DLQ, retry, outbox | **`spring-amqp`** (formerly `messaging-rabbitmq-spring`) |
| Kafka | (future `spring-kafka` — not built yet) |

### Caching

| Task | Skill |
|---|---|
| `@Cacheable` / `@CacheEvict` / `@CachePut`, Caffeine, Redis, two-tier, invalidation strategy, stampede mitigation | **`spring-cache`** (formerly `caching-strategies-spring`) |

### Security

| Task | Skill |
|---|---|
| `SecurityFilterChain`, OAuth2 Resource Server with JWT, `@PreAuthorize` / method security, mTLS / service-to-service auth, multi-tenant security | **`spring-security`** (formerly `spring-security-and-auth`) |

### Testing

| Task | Skill |
|---|---|
| JUnit 5 + AssertJ + MockK, Spring test slices (`@WebMvcTest` / `@DataJpaTest` / `@JsonTest` / `@SpringBootTest`), Testcontainers, ArchUnit, Modulith tests | `testing-strategy-kotlin-spring` |

### CQRS / Architecture

| Task | Skill |
|---|---|
| CQRS write / read split, projections via Modulith events, outbox via `event_publication`, polyglot read stores | `cqrs-implementation` |
| Microservices patterns — gateway, discovery, mesh, Resilience4j, deployment strategies | `microservices-patterns-deep` |

## Cross-cutting Spring principles

The principles below apply across **every** `spring-*` sibling. Each sibling will restate the ones relevant to its topic with depth; this skill owns the canonical, ecosystem-wide statement.

1. **Constructor injection only.** No field `@Autowired`. Constructor injection is testable, immutable-friendly, fails fast at startup, supports `final`. Setter / field injection breaks all four.
2. **`@Transactional` on the service layer.** Not on repositories, not on controllers. The service is the transaction boundary. See `spring-transactions` for propagation rules and proxy gotchas.
3. **Typed `@ConfigurationProperties` over `@Value`.** Config is part of the contract: validated, typed, IDE-navigable, documentable. `@Value("${...}")` scattered across fields = configuration debt.
4. **Default deny in security.** All endpoints require auth except an explicit allow-list. See `spring-security`.
5. **Default idempotent in messaging and HTTP.** At-least-once delivery, retries, replays — consumers must be idempotent. See `spring-amqp` and `api-design-principles`.
6. **Default paginated and bounded in data.** No unbounded `findAll()`. Every list endpoint caps `pageSize`. See `spring-data-jpa` and `api-design-principles`.
7. **AOP proxies have rules.** `@Transactional`, `@Async`, `@Cacheable`, `@Scheduled`, `@PreAuthorize` all use Spring AOP proxies. They don't work on `private` methods, `final` methods, or self-invocation (`this.method(...)` skips the proxy). Kotlin classes are `final` by default — add the `kotlin-spring` (`all-open`) compiler plugin. See `spring-aop`.
8. **Test slices over full boot.** `@WebMvcTest` boots ~30 beans; `@SpringBootTest` boots ~300. Pick the smallest slice. See `testing-strategy-kotlin-spring`.
9. **Spring Modulith before microservices.** A single Spring Boot app with N application modules covers 80% of the architectural benefits of microservices at 5% of the operational cost. Split when organisational scaling — not technical curiosity — demands it. See `spring-modulith` and `microservices-patterns-deep`.
10. **Spring Boot Actuator from day one.** Health, metrics, info. The cost of adding it later is greater than the cost of having it. See `spring-actuator`.
11. **WebMVC is the default.** WebFlux only when a real reactive workload justifies it (high-fan-out IO, true streaming). For most CRUD-style services, virtual threads (Loom) give you WebFlux-class scalability with WebMVC ergonomics. See `spring-async`.

## Ecosystem-level anti-patterns

These cut across all `spring-*` siblings. Per-topic anti-patterns live in the matching sibling.

- **Cargo-culting annotations.** Adding `@Transactional` "just in case", `@Async` without configuring the executor, `@Cacheable` without TTL. Annotations are not free — each carries a contract; if you don't know the contract, don't use the annotation.
- **Field `@Autowired`.** Breaks testability, immutability, `final`. Constructor injection always.
- **`new SomeService()` instead of injection.** Bypasses DI, no AOP, no lifecycle, no proxies — `@Transactional` silently doesn't work.
- **`@SpringBootApplication` in `default` package.** Breaks classpath scanning silently. Always put it in a top-level package.
- **Multiple `@SpringBootApplication`** in one runtime.
- **`@ComponentScan` overriding the default.** Usually wrong, hard to debug later.
- **Fighting Spring conventions.** Custom property loaders, custom DI, custom transaction managers — almost always wrong. Find the Spring-blessed way before rolling your own.
- **Treating Boot starters as black boxes.** Read the auto-config class once. Knowing what's enabled by default is the difference between a senior and a junior Spring dev.
- **Mixing imperative and reactive haphazardly.** WebMVC controllers calling `Mono.block()` is a code smell. Pick one paradigm per service; see `spring-async` for the virtual-threads alternative.
- **`@Transactional` on the controller.** Wrong layer. Service is the transaction boundary.
- **Catching `Exception` and logging.** Swallows real errors. See `clean-code-error-handling` and per-topic siblings for layered error handling.
- **Self-invocation bypassing AOP.** Calling `this.transactionalMethod()` from inside the same class skips the proxy → `@Transactional` doesn't apply. See `spring-aop`, `spring-transactions`.

## Spring DI 80/20 — annotations you actually need

11 annotations cover 95% of Spring DI usage. Anything else (`@DependsOn`, `@Lazy`, `@Order`) — read the source before adding.

| Annotation | Purpose | When |
|---|---|---|
| `@Component` | "Spring should manage me" | Generic Spring-managed class |
| `@Service` | Same as `@Component`, semantic for service layer | Service / use-case classes |
| `@Repository` | Same + JPA exception translation | Persistence adapters |
| `@Controller` / `@RestController` | Same + MVC handler | Web layer |
| `@Configuration` | Class defines `@Bean` methods | Wiring third-party classes |
| `@Bean` | Method produces a Spring-managed bean | Inside `@Configuration` |
| `@Primary` | Among multiple beans of same type, prefer this | Resolving DI ambiguity |
| `@Qualifier("name")` | Pick a specific bean by name | Multi-bean scenarios |
| `@Profile("...")` | Activate only in named profile | Dev/test/prod variation |
| `@ConditionalOn...` | Conditional bean registration | Library auto-config |
| `@ConfigurationProperties` | Typed config binding | All non-trivial config |

## Kotlin specifics across all Spring skills

These idioms appear in nearly every `spring-*` sibling. This skill owns the canonical mention; each sibling adds depth for its topic.

- **Constructor injection is implicit** in Kotlin's primary constructor — no `@Autowired` needed.
- **Kotlin classes are `final` by default.** Spring AOP creates subclasses → AOP-driven annotations (`@Transactional`, `@Async`, `@Cacheable`, `@Scheduled`, `@PreAuthorize`) fail silently or throw at startup unless classes are `open`. Add the `kotlin-spring` compiler plugin to make `@Component` / `@Configuration` / `@Service` / `@RestController` classes `open` automatically. For JPA `@Entity`, add `kotlin-jpa` (`no-arg`).
- **`data class` for `@Entity` is a bug factory.** `equals` / `hashCode` over all fields, Hibernate proxies, lazy fields → see `hibernate`.
- **`data class` for `@ConfigurationProperties` is ideal.** Immutable, typed, validated.
- **Sealed hierarchies** for commands, events, errors — exhaustive `when`, no `else` branch.
- **`@JvmInline value class`** for typed IDs and constrained primitives at boundaries.
- **MockK** over Mockito — idiomatic `every {}` / `verify {}`, supports `coEvery` for `suspend`, no `open` requirement.
- **Coroutines + Spring** — `suspend` functions work in `@RestController` (Spring MVC 6+ supports them), in `@RabbitListener` indirectly, and with `kotlinx-coroutines-reactor` bridging. Don't `runBlocking` from a thread you don't own.

## Related skills (outside `spring-*` family)

- `karpathy-guidelines` — applies always
- `clean-code`, `clean-code-systems` — composition root, constructor injection, POJOs at core
- `clean-code-objects-and-data` — `data class` discipline, anaemic vs behaviour-rich, JPA entity hybrids
- `architecture-patterns` — where Spring components sit in Layered / Onion / Clean
- `architect-review` — review of an existing Spring structure
- `ddd-tactical-patterns` — aggregates, value objects, repositories (the substrate Spring Data binds to)
- `solid-principles`, `grasp-patterns`, `gof-patterns` — design discipline underneath
- `debugging-systematic` — when Spring "magic" doesn't fire (proxy missed, bean not picked up, transaction silently rolled back)
- `methodology-verification` — Spring's auto-magic means false positives are easy; verify before claiming done

## Limitations

- This skill covers Spring Boot **3+** on Kotlin 2.x / JVM 21+. Boot 2.x users will find most of it applicable but specific APIs differ.
- **WebFlux / reactive** is intentionally out of scope — virtual threads (Loom) cover most of the same need with the imperative model. Reactive deep work needs its own skill.
- Spring Batch / Spring Integration / Spring Cloud Stream / Spring Cloud Gateway / Spring GraphQL / Spring Session / Spring Mail are real Spring projects without dedicated skills here — when they come up, the closest sibling (`spring-amqp`, `microservices-patterns-deep`, `spring-web-mvc`) is the launching pad until a dedicated skill is built.
- The skill is **a map**, not a deep dive. If you find yourself needing depth, route to the sibling.
