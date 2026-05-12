---
name: spring-boot
description: "Spring Boot 3+/4 specifics for Kotlin services — what `@SpringBootApplication` actually unfolds into (`@SpringBootConfiguration` + `@EnableAutoConfiguration` + `@ComponentScan`), how auto-configuration works under the hood (`AutoConfiguration.imports`, `@AutoConfiguration` classes, `@ConditionalOnX` evaluation, `--debug` and `/actuator/conditions` for inspection), the starter ecosystem (curated dependency sets, what each starter brings, when to write a custom starter), the `@ConditionalOnProperty` / `@ConditionalOnClass` / `@ConditionalOnMissingBean` / `@ConditionalOnBean` / `@Profile` family for conditional wiring, typed `@ConfigurationProperties` with `@Validated` (records / Kotlin `data class`, nested types, `Duration` / `DataSize` / lists / maps, constructor binding by default in Boot 3, `@ConfigurationPropertiesScan`), property-source precedence (CLI > env > `application-{profile}.yml` > `application.yml` > defaults), profiles in the Boot sense (`spring.profiles.active`, `@Profile`, profile-specific YAML, profile groups), secrets handling at the configuration layer (env vars with `${VAR:?}` placeholders, `spring.config.import` with Vault / `configtree:` / `optional:file:`), `ApplicationRunner` / `CommandLineRunner` for ordered startup work, and Boot 3.0 → 3.5 → 4 highlights (Jakarta namespace, `ProblemDetail`, `@ServiceConnection` for Testcontainers, virtual threads via `spring.threads.virtual.enabled`, `RestClient` / `JdbcClient`, Observation API, GraalVM native). Use when bootstrapping a new Spring Boot service, debugging "why isn't this bean being created?", designing typed configuration, migrating from `@Value` to `@ConfigurationProperties`, picking properties / profile precedence, writing or reviewing a custom starter, or upgrading across Boot major versions. Bean lifecycle / scopes / DI mechanics live in `spring-bean`; AOP / proxies in `spring-aop`; `@Transactional` in `spring-transactions`; Actuator deep in `spring-actuator`."
risk: safe
source: "custom — Spring Boot 3+/4 specifics for Kotlin services"
date_added: "2026-05-12"
---

# Spring Boot (Kotlin / Spring Boot 3+)

> Spring Boot is conventions plus auto-configuration. Knowing what `@SpringBootApplication` actually does, what the active starters dragged in, and how `@ConditionalOnX` decides what gets wired — that's the difference between trusting Boot's magic and fighting it.

## Use this skill when

- Bootstrapping a new Spring Boot service — starter set, package layout, `@SpringBootApplication` placement
- Debugging "why isn't this bean / endpoint / property showing up?" — auto-config didn't trigger, `@ConditionalOnX` returned false, property wasn't picked up
- Designing typed configuration — `@ConfigurationProperties` shape, nesting, validation, defaults
- Migrating scattered `@Value("${...}")` to a typed `@ConfigurationProperties` data class
- Picking property values when the same key is set in multiple places (env var, CLI flag, profile YAML, default)
- Reading or writing a custom starter / auto-configuration module shared across services
- Writing `ApplicationRunner` / `CommandLineRunner` startup hooks with correct ordering
- Migrating across Boot versions (2.x → 3.x, 3.x → 4) and deciding which new features to adopt

## Do not use this skill when

- The question is about **bean lifecycle, scopes, `@Component` vs `@Bean`, `@PostConstruct`, `BeanPostProcessor`, `@Lazy` / `@DependsOn`, circular dependencies** — that's `spring-bean`. This skill assumes DI works; it owns Boot specifics on top.
- The question is about **`@Aspect`, pointcuts, advice ordering, proxy mechanics**, or self-invocation / `final` / `private` gotchas behind AOP-driven annotations — that's `spring-aop`.
- The question is about **`@Transactional` propagation / isolation / `rollbackFor` / `readOnly`** — that's `spring-transactions`.
- The question is about **`@Cacheable` / `@Scheduled` / `@Async` mechanics** — those are `spring-cache` / `spring-scheduler` / `spring-async`.
- The question is about **Actuator endpoints, health indicators, Micrometer tags** — that's `spring-actuator`. (This skill points at `/actuator/conditions` as an auto-config debug tool; the endpoint family lives there.)
- The question is about **Spring Modulith** module layout and event publication — that's `spring-modulith`.
- The question is about **`@RestController` / `ProblemDetail` mapping** — that's `spring-web-mvc`.
- The question is about **WebMVC vs WebFlux** — defer to `architecture` (briefly: WebMVC is the default; virtual threads close most of the gap).

## Core principles

1. **Configuration is part of the contract.** Same binary in dev / staging / prod runs differently because of config, not code branches. Typed, validated, documented, IDE-navigable. Untyped `@Value("${...}")` scattered across fields is configuration debt.
2. **One way to register a bean per type.** `@Component` (+ scanning) for your own classes; `@Bean` methods in `@Configuration` for third-party classes; `@AutoConfiguration` only inside a starter. Never both for the same type.
3. **Read at least one auto-configuration class before trusting any starter.** Starters aren't magic — a curated dependency list plus an `@AutoConfiguration` that registers defaults. Reading the source once is the difference between a senior and a junior Spring dev.
4. **`@ConfigurationProperties` over `@Value`.** Always. Constructor-bound, `@Validated`, Kotlin `data class`.
5. **Defaults live in the `data class`, overrides live in `application.yml`.** YAML is the override layer. Less duplication, less drift.
6. **`@ConditionalOnX` for optional integrations and feature flags; `@Profile` only for `dev` / `staging` / `prod`.** Profile soup is a smell; `@ConditionalOnProperty` is the right tool for "this integration is enabled".
7. **Validate config at startup, not at first request.** `@Validated` + bean-validation annotations on `@ConfigurationProperties` turn bad config into a clear boot failure, not a 500 in production.
8. **Treat secrets as runtime input, never repo content.** Env vars with `${VAR:?required}`, secret manager (Vault / AWS Secrets Manager / K8s Secrets via `configtree:`), `spring.config.import` for layering.

## What `@SpringBootApplication` actually does

```kotlin
@SpringBootApplication
class App

fun main(args: Array<String>) {
    runApplication<App>(*args)
}
```

`@SpringBootApplication` is a meta-annotation that combines three:

| Meta-annotation | What it does |
|---|---|
| `@SpringBootConfiguration` | A `@Configuration` variant that marks this as the primary configuration class; tests use it to find the bootable app. |
| `@EnableAutoConfiguration` | Triggers the auto-configuration mechanism — scans `META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports` (Boot 2.7+) on the classpath and evaluates every `@AutoConfiguration` class via `@ConditionalOnX`. |
| `@ComponentScan` | Scans for `@Component` (and stereotypes) starting from this class's package and descending. |

That last one is why two anti-patterns hurt:
- **`@SpringBootApplication` in the default package** — `@ComponentScan` then has no package boundary, scans everything on the classpath, picks up unintended classes from libraries. Always put it in a top-level named package.
- **Overriding `@ComponentScan` on the application class** — the default scan covers the package and below, which is almost always what you want. Custom `basePackages` lists drift away from the real layout silently.

In Kotlin, the standard form is:

```kotlin
package com.example.orders

@SpringBootApplication
@ConfigurationPropertiesScan
class OrdersApplication

fun main(args: Array<String>) {
    runApplication<OrdersApplication>(*args)
}
```

`@ConfigurationPropertiesScan` is the modern alternative to `@EnableConfigurationProperties(X::class, Y::class, ...)` — Spring discovers `@ConfigurationProperties` classes via classpath scanning instead of an explicit list. Add it once on the application class.

## Auto-configuration — how it works, how to debug it

### The mechanism

1. `@EnableAutoConfiguration` reads every JAR's `META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports` (Boot 2.7+). Each line is a fully-qualified `@AutoConfiguration` class.
2. Spring evaluates each candidate's `@ConditionalOnX` annotations. If all pass, the class is loaded and its `@Bean` methods register beans.
3. Most starter beans use `@ConditionalOnMissingBean` — so if you declare your own `DataSource` / `ObjectMapper` / `RestClient`, the starter's default is silently skipped. That's the override hook.

### Reading an auto-config class

When debugging "why is this bean here?", open the auto-config class (e.g. `JdbcTemplateAutoConfiguration`, `JacksonAutoConfiguration`, `WebMvcAutoConfiguration`). Three things to skim:
- `@ConditionalOnClass(...)` at the top → does the trigger class exist on the classpath?
- `@ConditionalOnProperty(...)` → is the right property enabled?
- `@ConditionalOnMissingBean` on each `@Bean` → if you already wired this, the starter steps aside.

### Debugging what got applied

- **Run with `--debug`** (or `debug: true` in YAML). Boot emits an `AUTO-CONFIGURATION REPORT`: "Positive matches" (auto-configs that fired) and "Negative matches" (skipped, with reason per `@ConditionalOnX` — "required class X not found", "property Y not set", "bean of type Z already defined"). The negative-matches section is usually the most informative.
- **`/actuator/conditions`** — same report served live from the running app as JSON. Lives in `spring-actuator`.

When an annotation-driven feature silently doesn't fire, `--debug` is the first thing to look at after confirming the `kotlin-spring` plugin is enabled and the class is a Spring-managed bean.

### Writing a custom auto-configuration (briefly)

For shared modules / starters:

```kotlin
@AutoConfiguration
@ConditionalOnClass(SomeRequiredClass::class)
@ConditionalOnProperty(name = ["my.starter.enabled"], havingValue = "true", matchIfMissing = true)
@EnableConfigurationProperties(MyStarterProperties::class)
class MyStarterAutoConfiguration {

    @Bean
    @ConditionalOnMissingBean
    fun defaultThing(props: MyStarterProperties): Thing = Thing(props)
}
```

Register in `src/main/resources/META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports` (one fully-qualified class per line). `@ConditionalOnMissingBean` is the discipline — consumers override by providing their own bean. Pre-Boot-2.7 (`META-INF/spring.factories`) still works but is legacy.

## Starters — what they are, what's curated

A Boot starter is a tiny artifact with two parts: a curated transitive-dependency list (the Boot BOM ensures version compatibility) and optionally an `@AutoConfiguration` class that wires sensible defaults. The win: no manual version juggling. The risk: treating starters as black boxes; see "Reading an auto-config class" above.

Common starters in a typical Kotlin service:

| Starter | What it brings |
|---|---|
| `spring-boot-starter-web` | Tomcat, Spring MVC, Jackson, validation, `RestClient` (Boot 3.2+) |
| `spring-boot-starter-data-jpa` | Spring Data JPA, Hibernate, JDBC, transaction management |
| `spring-boot-starter-validation` | `jakarta.validation` (Hibernate Validator) — required separately in Boot 3+ |
| `spring-boot-starter-actuator` | Health, metrics, info, conditions, env endpoints |
| `spring-boot-starter-security` | Spring Security 6, filter chain, password encoder |
| `spring-boot-starter-test` | JUnit 5, Mockito, AssertJ, JSONassert, Spring Test, `@SpringBootTest` |
| `spring-boot-starter-amqp` | Spring AMQP, RabbitMQ client, `@RabbitListener` |
| `spring-boot-starter-cache` | Spring Cache abstraction (Caffeine wires automatically if on classpath) |
| `spring-boot-starter-oauth2-resource-server` | OAuth2 Resource Server, JWT validation |
| `spring-boot-docker-compose` | (Boot 3.1+) Auto-start `docker-compose.yml` deps in dev |

Add only what you need. Each starter adds beans, startup time, and classpath surface. The starter dependency tree is the contract — when something behaves unexpectedly, `./gradlew dependencies` is a good first look.

## `@ConditionalOnX` family

These annotations decide whether a `@Configuration` / `@Bean` is registered. They're the workhorses of starters and the right tool for "is this integration enabled?" in app code.

| Annotation | Fires when |
|---|---|
| `@ConditionalOnClass(X::class)` | `X` is on the classpath. The starter pattern: "if Jackson is present, configure it." |
| `@ConditionalOnMissingClass("X")` | `X` is *not* on the classpath. Used to opt out of one mode in favour of another. |
| `@ConditionalOnBean(X::class)` | Another bean of type `X` is already registered. Order matters — auto-configs typically run late. |
| `@ConditionalOnMissingBean` | No bean of this type is registered yet. The override hook: consumers can replace the default by declaring their own. |
| `@ConditionalOnProperty(name = ["x"], havingValue = "true", matchIfMissing = false)` | The property is set to the matching value. Feature-flag pattern. |
| `@ConditionalOnExpression("...")` | SpEL expression returns true. Powerful but harder to read — prefer the specific conditions above. |
| `@ConditionalOnWebApplication` / `@ConditionalOnNotWebApplication` | Useful inside starters that should only configure things in a servlet (or non-servlet) app. |
| `@Profile("...")` | The named profile is active. Use for `dev` / `staging` / `prod` variation. |

App-code use: feature flags (`@ConditionalOnProperty`), optional integrations (`@ConditionalOnClass`), profile-based wiring (`@Profile`). The full mechanism is mostly used inside starters.

## `@ConfigurationProperties` — discipline

### The shape

```kotlin
@ConfigurationProperties(prefix = "stripe")
@Validated
data class StripeProperties(
    @field:NotBlank val apiKey: String,
    @field:Pattern(regexp = "^whsec_.*") val webhookSecret: String,
    val timeout: Duration = Duration.ofSeconds(30),
    @field:Min(0) @field:Max(10) val retries: Int = 3,
    @field:NotEmpty val supportedCurrencies: List<String> = listOf("EUR", "USD"),
)
```

- **Kotlin `data class`** = immutable (`val`), typed, constructor-bound (Boot 3 default — no `@ConstructorBinding` needed), and ideal for `@ConfigurationProperties`.
- **`@Validated`** on the class + `jakarta.validation` annotations on fields = startup-time validation. Bad config = clear failure on boot, not a 500 at runtime.
- **`@field:`** annotation site target is needed in Kotlin so the validation annotations land on the JVM field (where Hibernate Validator looks).
- **Defaults in the data class**, not in `application.yml`. YAML is the override layer.
- **`Duration`** parsed from `60s`, `5m`, `PT1H`. **`DataSize`** parsed from `10MB`, `1GB`. **Lists** as YAML sequences. **Maps** as YAML maps.

### Registration

Two ways:

```kotlin
@SpringBootApplication
@ConfigurationPropertiesScan      // discovers @ConfigurationProperties classes automatically
class App
```

Or explicitly:

```kotlin
@Configuration
@EnableConfigurationProperties(StripeProperties::class, KafkaProperties::class)
class ConfigurationPropertiesConfig
```

`@ConfigurationPropertiesScan` is the modern preference — one annotation, no explicit list to maintain.

### Nested + lists + maps

Nested `data class`es, `List<T>` properties, and `Map<K, V>` properties all bind from YAML naturally — sequences for lists, nested maps for maps. The IDE knows the schema via `spring-configuration-metadata.json` (auto-generated when you add `spring-boot-configuration-processor` as an annotation processor). YAML typos get highlighted.

### Migration: `@Value` → `@ConfigurationProperties`

Group related `@Value` fields by prefix → create one `XxxProperties` data class per group → move defaults from constructor params into the data class → add `@Validated` + bean-validation annotations → boot the app and fix any validation failures (that's the point — errors before runtime) → delete the `@Value` annotations and inject the properties class instead → document `XxxProperties` (it's now part of the contract).

## Property precedence (highest wins)

When the same property is set in multiple places, Spring resolves in this order:

| # | Source | Example |
|---|---|---|
| 1 | Command-line arguments | `--app.name=override` |
| 2 | `SPRING_APPLICATION_JSON` env var | `SPRING_APPLICATION_JSON='{"app":{"name":"x"}}'` |
| 3 | JVM system properties | `-Dapp.name=override` |
| 4 | OS environment variables | `APP_NAME=override` |
| 5 | `spring.config.import` sources | Vault, `configtree:`, external files |
| 6 | Profile-specific YAML | `application-prod.yml` |
| 7 | Default YAML | `application.yml` |
| 8 | `@ConfigurationProperties` defaults | `val retries: Int = 3` in the data class |

Why this matters:
- **`kubectl set env APP_NAME=override`** beats `application.yml` — env vars are higher precedence. 12-factor apps depend on this.
- **Kebab-case in YAML maps to camelCase in Kotlin** (`app.api-key` → `apiKey`). Boot's relaxed binding handles both.
- **Env var convention:** dots and dashes become underscores, uppercase. `app.api-key` → `APP_API_KEY`. `spring.profiles.active` → `SPRING_PROFILES_ACTIVE`.
- **`${VAR:default}`** provides a default. **`${VAR:?error message}`** requires the var — startup fails if missing. Use the second form for secrets.

## Profiles in Boot

A profile is a named slice of configuration.

```yaml
# application.yml — common
app:
  name: assista
  base-url: http://localhost:8080

---
spring:
  config:
    activate:
      on-profile: dev

app:
  base-url: http://localhost:8080
spring:
  datasource:
    url: jdbc:postgresql://localhost:5432/assista_dev

---
spring:
  config:
    activate:
      on-profile: prod

app:
  base-url: https://api.assista.example.com
spring:
  datasource:
    url: jdbc:postgresql://db.internal:5432/assista
```

Activate with `SPRING_PROFILES_ACTIVE=prod` or `--spring.profiles.active=prod`.

### Profile-specific files

```
src/main/resources/
├── application.yml                 # default
├── application-dev.yml             # dev profile
├── application-test.yml            # test profile (auto-activated by @ActiveProfiles("test"))
├── application-prod.yml            # prod profile
└── application-local.yml           # local dev, gitignored
```

### Profile-scoped beans

```kotlin
@Configuration
class PaymentConfig {

    @Bean
    @Profile("!test")
    fun stripeGateway(props: StripeProperties): PaymentGateway = StripeGateway(props)

    @Bean
    @Profile("test")
    fun fakeGateway(): PaymentGateway = FakePaymentGateway()
}
```

In tests, `@ActiveProfiles("test")` activates `FakePaymentGateway`. The `!profile` syntax negates.

### Profile groups (Boot 2.4+)

```yaml
spring:
  profiles:
    group:
      production: ["prod", "metrics", "secure"]
```

Activating `production` activates all three. Use sparingly — flat profile lists are easier to reason about.

### Profile anti-patterns

- **Profile per environment** (`dev`, `staging`, `prod`) — fine, canonical.
- **Profile per feature** (`new-checkout`, `dark-mode`) — wrong; use `@ConditionalOnProperty` or a feature-flag platform.
- **Long combinations** (`dev,k8s,debug,local,metrics`) — confusing; keep flat or use profile groups.
- **`acceptsProfiles` checks scattered through code** — service code shouldn't ask "what profile am I in?". Inject different beans per profile.

## Secrets at the configuration layer

The rules:
- **Never** hardcode secrets in `application.yml`, never commit them to git, never bake them into a Docker image.
- **Always** read them from env vars, secret managers, or mounted files at runtime.

### Env-var placeholders

```yaml
stripe:
  api-key: ${STRIPE_API_KEY:?STRIPE_API_KEY is required}
  webhook-secret: ${STRIPE_WEBHOOK_SECRET:?STRIPE_WEBHOOK_SECRET is required}
```

The `:?` form requires the env var; startup fails immediately if it's not set. Far better than discovering it via a 500 the first time the secret is used.

### Layered external config

```yaml
spring:
  config:
    import:
      - optional:file:.env.local        # local override, optional
      - configtree:/etc/secrets/        # K8s mounted secrets (one file per key)
      - vault://secret/data/app/        # Spring Cloud Vault
```

`configtree:` is the standard K8s pattern: each file in the directory becomes a property (`/etc/secrets/db-password` → `db.password`). The pod mounts the secret, Boot picks it up.

### Local dev secrets

`application-local.yml` (gitignored) for personal API keys during dev. Activate with `SPRING_PROFILES_ACTIVE=local`. Or use a `.env` file + a dotenv plugin — both common, pick one per team.

## `ApplicationRunner` / `CommandLineRunner`

Hooks that run after context refresh, before `ApplicationReadyEvent`. Use for top-level coordinated startup work — verifying migrations applied, pinging dependencies, warming caches.

```kotlin
@Component
@Order(1)
class StartupChecks(
    private val migrations: MigrationVerifier,
    private val externalApis: ExternalApiHealth,
) : ApplicationRunner {
    override fun run(args: ApplicationArguments) {
        migrations.verifyAllMigrationsApplied()
        externalApis.pingAll()
    }
}
```

- **`ApplicationRunner`** receives parsed `ApplicationArguments`; **`CommandLineRunner`** receives raw `String[]`. Prefer `ApplicationRunner`.
- **`@Order(n)`** controls order across runners — lower runs first.
- **Throwing aborts startup.** Use deliberately: a failed migration check should refuse to boot.
- **Don't put per-bean init logic here** — that belongs in `@PostConstruct` (see `spring-bean`).
- For "do X once the app is fully ready" without blocking readiness, prefer `@EventListener(ApplicationReadyEvent::class)` — fires *after* all runners.

## Anti-patterns

- **`@Value("${...}")` on every field** — untyped, scattered defaults, no validation. Use `@ConfigurationProperties`.
- **`@SpringBootApplication` in the default package** — `@ComponentScan` then scans everything on the classpath.
- **Multiple `@SpringBootApplication` classes in one runtime** — Boot runs one; the others are footguns for tests and IDE run configs.
- **Overriding `@ComponentScan` on the application class** — the default is almost always right; custom `basePackages` drifts.
- **Treating starter dependencies as untouchable black boxes** — skim each starter's `@AutoConfiguration` class once.
- **Defaults duplicated in both data class and `application.yml`** — keep defaults in the data class; YAML is the override layer.
- **Hardcoded secrets in `application.yml`** — env vars with `${VAR:?}`, or secret managers via `spring.config.import`.
- **`Environment.getProperty("...")` injection** — bypasses typing and validation.
- **`@Configuration` classes with imperative logic in the constructor** — they should declare beans, not run logic. Push side effects to `@PostConstruct` on a `@Bean` or `ApplicationRunner`.
- **Skipping `@Validated`** on `@ConfigurationProperties` — bad config then shows up at first use, not at startup.
- **Spring Cloud Sleuth / Brave in 2026** — replaced by Micrometer Tracing + OpenTelemetry.

## Boot 3.0 → 3.5 → 4 highlights

| Version | Highlight | Adopt? |
|---|---|---|
| 3.0 | Java 17 minimum; `javax.*` → `jakarta.*`; Hibernate 6; AOT support; `ProblemDetail` (RFC 7807) built into Spring 6 | Yes — this is the baseline now |
| 3.0 | Observability API (Micrometer Observation) replaces Sleuth | Yes — emits metrics + traces + MDC log enrichment from one API |
| 3.1 | `@ServiceConnection` — auto-wire Testcontainers into Spring properties | Yes — replaces `@DynamicPropertySource` boilerplate; see `testing-strategy-kotlin-spring` |
| 3.1 | `spring-boot-docker-compose` starter — auto-start `docker-compose.yml` deps in dev | Optional — convenient locally, irrelevant in prod |
| 3.1 | Spring Authorization Server (first-party OAuth2 server) | Only if you're running an IdP |
| 3.2 | **Virtual threads** via `spring.threads.virtual.enabled: true` (requires JVM 21+) | Yes — game-changer for WebMVC throughput on blocking IO |
| 3.2 | `RestClient` (modern synchronous HTTP client) | Yes — replaces `RestTemplate` for new code; see `spring-rest-clients` |
| 3.2 | `JdbcClient` (modern JDBC alternative to `JdbcTemplate`) | Yes — for new JDBC code |
| 3.3+ | Class-data sharing (CDS) for faster startup; SBOM generation; conditional-annotation refinements | Mostly free; CDS helps if startup matters |
| 4.x | Spring Framework 7 baseline, Jakarta EE 11, deeper Loom integration, Modulith integration deeper, GraalVM-first ergonomics | Cautiously — pin specific milestones, accept some friction |

### Virtual threads (Boot 3.2+, JVM 21+)

```yaml
spring:
  threads:
    virtual:
      enabled: true
```

Servlet container, `@Async`, `@Scheduled`, AMQP listeners use virtual threads. Cheap concurrency for blocking IO — the pragmatic alternative to WebFlux for most CRUD services. Verify under load; avoid `synchronized` blocks around IO (pin-heavy).

### `ProblemDetail`, Observation API, GraalVM Native

- **`ProblemDetail`** (RFC 7807) ships in Spring 6 — use for all REST errors; mapping discipline in `spring-web-mvc`.
- **`@Observed`** emits metrics + traces + trace-ID-enriched logs from one annotation; replaces Sleuth. Depth in `spring-actuator`.
- **GraalVM Native** (`./gradlew nativeCompile`) — ~100ms startup, ~50-150MB memory. Adopt for serverless / CLI / memory-constrained; skip for standard backend services.

## Kotlin specifics

- **`@ConfigurationProperties` + `data class`** is the canonical form. Immutable (`val`), typed, constructor-bound by default in Boot 3 (no `@ConstructorBinding`). `data class` is a value carrier, not an AOP target — no need to open it.
- **`@field:` annotation site target** is required for validation annotations (`@field:NotBlank`, `@field:Min`) so they land on the JVM field where Hibernate Validator reads them. Without `@field:`, the annotation lands on the Kotlin property and is ignored at validation time.
- **Sealed types don't round-trip cleanly** through `@ConfigurationProperties` (no discriminator support). For sum-typed config, model as a flat shape with a `type` discriminator and resolve in a factory `@Bean`.
- **`kotlin-spring` (`all-open`) plugin** is mandatory for every Boot Kotlin project — `@Configuration` and AOP-eligible classes must be open, and Kotlin makes classes `final` by default. The plugin auto-opens `@Configuration` / `@Component` / `@Service` / `@RestController` / `@Async` / `@Transactional` / `@Cacheable`. Detail lives in `spring-bean`.
- **`@JvmInline value class`** in `@ConfigurationProperties` works for typed wrappers (e.g. `ApiKey`, `TenantId`) if the inline class wraps a single `val` of a supported type.

## Related skills

- `spring` — router for the family; cross-cutting principles
- `spring-bean` — bean lifecycle, scopes, DI mechanics, `@PostConstruct` / `ApplicationRunner` ordering
- `spring-aop`, `spring-transactions`, `spring-async`, `spring-scheduler`, `spring-events`, `spring-cache` — AOP-driven concerns that sit on Spring beans
- `spring-actuator` — `/actuator/conditions` and the full Actuator endpoint family
- `spring-modulith`, `spring-web-mvc`, `spring-rest-clients`, `spring-data-jpa`, `hibernate`, `spring-validation`, `spring-amqp`, `spring-security` — topic-specific siblings
- `testing-strategy-kotlin-spring` — test slices, `@ServiceConnection`, Testcontainers
- `clean-code-systems` — composition root, constructor injection, typed config
- `architecture` — layout patterns (Layered / Onion / Clean), WebMVC vs WebFlux framing
- `methodology-karpathy-guidelines`, `methodology-verification`, `debugging-systematic`, `methodology-clarifying-questions` — process discipline wrapping everything

## Limitations

- Targets Spring Boot **3+** on Kotlin 2.x / JVM 21+. Boot 2.x users will find most of this applicable but specific APIs (`AutoConfiguration.imports` vs `spring.factories`, constructor-binding defaults, `@ServiceConnection`, virtual threads) differ.
- Covers the **configuration / bootstrap / auto-configuration / starter** layer. The rest of Spring Boot (Actuator endpoints, Modulith internals, MVC handlers, Security filters) lives in dedicated siblings.
- WebMVC vs WebFlux is intentionally out of scope — that's an `architecture`-level decision; virtual threads close most of the gap.
- Doesn't cover the full Spring ecosystem (Batch, Integration, Cloud Stream, Cloud Gateway, GraphQL, Session, Mail) — closest sibling (`spring-amqp`, `microservices-patterns-deep`, `spring-web-mvc`) is the launching pad.
- GraalVM Native bean-registration quirks (reflection hints, `@RegisterReflectionForBinding`, `RuntimeHintsRegistrar`) are mentioned but not deep — for production native use, see Spring's native-image documentation.
