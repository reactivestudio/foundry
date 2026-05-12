---
name: spring-boot-mastery
description: "Spring Boot 3/4 mastery for Kotlin services — configuration with `@ConfigurationProperties` and profiles, bean lifecycle (`@PostConstruct`, `ApplicationRunner`, smart initialisation), AOP for cross-cutting concerns, Spring Modulith deep (events, application modules, encapsulation, observability), and the WebMVC vs WebFlux decision. Use when consolidating Spring Boot best practices, designing application bootstrap, or choosing imperative vs reactive."
risk: safe
source: "custom — Spring Boot mastery for Kotlin services"
date_added: "2026-05-12"
---

# Spring Boot Mastery (Kotlin)

Where the day-to-day Spring Boot expertise lives — beyond `@RestController` and `@Service`, into the parts that distinguish a senior Spring developer from a junior one.

> Spring is conventions. Knowing the conventions = saving 80% of design effort. Fighting them = paying compound interest on accidental complexity.

## Use this skill when

- Bootstrapping a new Spring Boot service (or reviewing one)
- Designing configuration: where do values live, how do profiles work, what gets validated?
- Adding cross-cutting concerns (logging, retry, audit, metrics) without `if` lattices
- Deeply integrating Spring Modulith — events, observability, encapsulation
- Choosing between WebMVC (blocking) and WebFlux (reactive)
- Migrating from Spring Boot 2.x to 3+ or 3.x to 4
- Tuning startup time, memory footprint, native image readiness

## Do not use this skill when

- The task is **API design** (REST/gRPC contracts) — use `api-design-principles`
- The task is **JPA / persistence** — use `database-design`
- The task is **testing** — use `testing-strategy-kotlin-spring`
- The task is **security** — use `spring-security-and-auth`
- You're writing routine controllers — use `architecture-patterns/resources/implementation-playbook.md` §1 Layered

## Selective Reading Rule

| File | Description | When to read |
|---|---|---|
| `resources/configuration-and-profiles.md` | `@ConfigurationProperties` with `@Validated`, profiles, properties precedence, secret management, externalised config | Setting up configuration; understanding why a property isn't picked up |
| `resources/bean-lifecycle-and-aop.md` | Bean lifecycle, `@PostConstruct`, `ApplicationRunner`, smart initialisation, lazy beans, AOP for cross-cutting (logging, retry, metrics) | Bootstrap order issues; adding aspects |
| `resources/modulith-deep.md` | Spring Modulith — application modules, events, encapsulation rules, `ApplicationModuleTest`, observation API, Documenter | Designing bounded contexts in a Modulith app; debugging cross-module access |
| `resources/webmvc-vs-webflux.md` | Decision tree: imperative WebMVC vs reactive WebFlux, mixing the two, when coroutines fit, JDBC reality | Choosing between WebMVC and WebFlux for a new service |
| `resources/boot-3-and-4-changes.md` | Spring Boot 3.0 → 3.5 → 4 highlights, breaking changes, `ProblemDetail`, `@ServiceConnection`, observation API, GraalVM native, virtual threads | Migrating; understanding what's new and what to use |

## Core principles

1. **Configuration is part of the contract.** Same code in dev / staging / prod runs because of config, not code. Treat config as an API: validated, typed, documented.
2. **One way to do each thing.** Spring offers 3 ways to register a bean (`@Component`, `@Bean`, explicit XML). Pick `@Component` for app classes, `@Bean` for things that need config, never XML in 2025+.
3. **Constructor injection always.** No field injection (`@Autowired` on field). Breaks immutability, breaks testability, breaks `final`.
4. **`@Transactional` at the service layer.** Not on repositories, not on controllers. Service is the transaction boundary.
5. **`@Async` and `@Scheduled` are not magic.** They use thread pools you didn't configure; they fail silently. Configure or don't use.
6. **Spring Modulith is the cheaper default** for new Spring Boot systems where bounded contexts haven't yet diverged in scale, compliance, or ownership. The "modulith vs. microservices" call itself belongs to `architecture` / `microservices-patterns-deep` — this skill just configures Modulith well when it's chosen.
7. **WebMVC by default.** WebFlux when you have a real reactive workload — not because "reactive sounds modern."
8. **Spring Boot Actuator from day 1.** Health, metrics, info. The cost of adding it later is greater than the cost of having it.

## Top 10 Spring Boot anti-patterns

1. **Field `@Autowired`** — see principle 3
2. **`@Transactional` on the controller** — wrong layer
3. **`@SpringBootApplication` in `default` package** — breaks classpath scanning
4. **`@ComponentScan` overriding default** — usually wrong, hard to debug
5. **Multiple `@SpringBootApplication`** — only one per app
6. **`new SomeService()` instead of injection** — bypasses DI, no AOP, no lifecycle
7. **`@Value("${...}")` on every field** — use typed `@ConfigurationProperties`
8. **Catching `Exception` and logging** — swallowing real errors
9. **`@Transactional(propagation = REQUIRED)` everywhere** — default; remove the noise; specify only when non-default
10. **Spring Cloud Sleuth / Brave** in 2025 — replaced by Micrometer Tracing + OpenTelemetry

## Spring DI 80/20

Annotations you actually need:

| Annotation | Purpose | When |
|---|---|---|
| `@Component` | "Spring should manage me" | Generic Spring-managed class |
| `@Service` | Same as `@Component`, semantic for service-layer | Service / use-case classes |
| `@Repository` | Same + JPA exception translation | Persistence adapters |
| `@Controller` / `@RestController` | Same + MVC handler | Web layer |
| `@Configuration` | Class defines `@Bean` methods | Wiring third-party classes |
| `@Bean` | Method produces a Spring-managed bean | Inside `@Configuration` |
| `@Primary` | Among multiple beans of same type, prefer this | Resolving DI ambiguity |
| `@Qualifier("name")` | Pick a specific bean by name | Multi-bean scenarios |
| `@Profile("...")` | Activate only in named profile | Dev/test/prod variation |
| `@ConditionalOn...` | Conditional bean registration | Library auto-config |
| `@ConfigurationProperties` | Typed config binding | All non-trivial config |

That's 11 annotations. 95% of Spring DI usage. Anything else (`@DependsOn`, `@Lazy`, `@Order`) — read the source before adding.

## Related skills

- `karpathy-guidelines` — discipline applies always
- `clean-code-systems` — constructor injection over field/setter; composition root discipline
- `clean-code-objects-and-data` — `@ConfigurationProperties` as a data class; DTO discipline
- `architecture-patterns` — layered (MVC) / Onion / Clean as the structural overlay
- `api-design-principles` — REST/gRPC contract details
- `database-design` — JPA, HikariCP, migrations
- `testing-strategy-kotlin-spring` — Spring test slices
- `spring-security-and-auth` — Spring Security
- `cqrs-implementation` — Modulith events at scale
- `system-design-fundamentals` — sizing decisions for Boot apps

## Limitations

- Patterns assume Spring Boot 3+ (we mention 4-specific features). Boot 2.x users should treat this as the migration target.
- Doesn't cover Spring's full ecosystem (Batch, Integration, Cloud) — those are separate ecosystems.
- For deep WebFlux / Project Reactor patterns, this skill points the way but doesn't replace dedicated reactive docs.
