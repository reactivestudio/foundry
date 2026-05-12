# Spring Boot 3.x and 4 — what's new

Notable changes from Boot 2 → 3 → 3.x → 4. Reference for migrations and "should I use this new feature?"

---

## 1. Spring Boot 3.0 (major release, Q4 2022)

### Breaking

- **Java 17 minimum** (no more Java 11/8). JVM 21 LTS recommended now.
- **`javax.*` → `jakarta.*`** — Jakarta EE 10 namespace migration. `javax.persistence.Entity` → `jakarta.persistence.Entity`. Same for `javax.servlet`, `javax.validation`, etc.
- **Hibernate 6** — major rewrite. Subtle behaviour changes around lazy loading, sequence generators, etc.
- **AOT (Ahead-of-Time)** compilation support, prerequisite for GraalVM native.
- **Observability via Micrometer**, replacing Sleuth.

### Migration impact

- Search/replace `javax.` → `jakarta.` (with exceptions: `javax.annotation.PostConstruct` is now `jakarta.annotation.PostConstruct`)
- Update validation imports
- Test Hibernate 6 behaviour changes — `@SequenceGenerator` reset to defaults; `@OneToMany` queries can differ; pull lazy loading test coverage

### New goodies

- **`ProblemDetail`** — RFC 7807 error response support built in. Use this for all REST errors (see `api-design-principles/resources/implementation-playbook.md` §Pattern 3).
- **Observability API** — Micrometer Observability replaces manual instrumentation.

---

## 2. Spring Boot 3.1 (2023)

### Key adds

- **`@ServiceConnection`** — auto-wire Testcontainers into Spring properties. Replaces `@DynamicPropertySource` boilerplate. See `testing-strategy-kotlin-spring/resources/testcontainers-integration.md` §3.

```kotlin
@Container
@ServiceConnection
val postgres = PostgreSQLContainer("postgres:16-alpine")
// spring.datasource.* properties auto-wired
```

- **Docker Compose support** — `spring-boot-docker-compose` starter: if `docker-compose.yml` in repo, Spring spins up dependencies at startup. Convenient for local dev.

```yaml
spring:
  docker:
    compose:
      enabled: true
      file: docker-compose.yml
```

- **Spring Authorization Server** — first-party OAuth2 authorization server.

---

## 3. Spring Boot 3.2 (2023)

### Highlight: virtual threads

```yaml
spring:
  threads:
    virtual:
      enabled: true
```

Servlet thread pool uses virtual threads (JVM 21+). Cheaper concurrency for blocking IO. Game-changer for WebMVC apps (see `webmvc-vs-webflux.md`).

### Other

- **`RestClient`** — modern synchronous HTTP client, replaces `RestTemplate` (deprecated for new code):

```kotlin
val client = RestClient.create()
val user: User = client.get()
    .uri("https://api.example.com/users/{id}", id)
    .retrieve()
    .body(User::class.java)
```

Better API than `RestTemplate`, fluent. Use this in WebMVC (use `WebClient` in WebFlux).

- **JdbcClient** — modern alternative to `JdbcTemplate` / `NamedParameterJdbcTemplate`:

```kotlin
val users = jdbcClient
    .sql("SELECT id, name FROM users WHERE status = :status")
    .param("status", "ACTIVE")
    .query(User::class.java)
    .list()
```

---

## 4. Spring Boot 3.3 (2024)

- **`@Conditional...` improvements** for better auto-config
- **Class data sharing** for faster startup
- **SBOM** generation by Spring Boot build plugin
- Refinements to virtual threads support
- Native image story matures

---

## 5. Spring Boot 3.4 (late 2024)

- More auto-config conditional improvements
- Improved Actuator endpoints
- Boot 3.x is stable; 4.x is the next major

---

## 6. Spring Boot 4 (planned / 2025-2026)

Major version. Anticipated themes (project-public as of writing):

- **Spring Framework 7** baseline
- **Jakarta EE 11**
- **Refined Loom integration** — virtual threads more pervasive
- **Modulith integration** deeper
- **GraalVM-first** ergonomics for native
- Continued AOT / startup improvements

`assista-platform` is on Boot 4.0.0-M2 (per CLAUDE.md). Pinned because some 4.x APIs aren't fully stable yet — common pattern for early adopters.

---

## 7. GraalVM Native Image

Spring 3+ supports compiling to native binary via GraalVM. Benefits:
- **~100ms startup** (vs 5-15s JVM)
- **~50-150MB memory** (vs ~500MB JVM)
- Trade-off: longer build (~minutes), reflection / dynamic class loading needs explicit hints

When to consider:
- **Serverless** functions / Lambda — startup-sensitive
- **CLI tools** in Java
- **Memory-constrained** environments (small VMs, edge)

When to skip:
- **Standard backend services** — JVM is fine; cold start happens once.
- **Apps heavy in reflection** (frameworks beyond Spring) — fighting native is painful.

Build:

```bash
./gradlew nativeCompile
./build/native/nativeCompile/app
```

Most teams won't need native. Spring Boot's regular startup is fine for long-running services.

---

## 8. Observation API (Micrometer)

Replaces Sleuth + ad-hoc metrics.

```kotlin
@Service
class OrderService(private val observationRegistry: ObservationRegistry) {

    fun place(req: PlaceOrderRequest): Order {
        return Observation.createNotStarted("order.place", observationRegistry)
            .lowCardinalityKeyValue("customerType", req.customerType)
            .observe { doPlace(req) }
    }
}
```

Or with annotation (auto-wired via AOP):

```kotlin
@Service
class OrderService {
    @Observed(name = "order.place")
    fun place(req: PlaceOrderRequest): Order { ... }
}
```

Emits:
- Metrics (Micrometer → Prometheus / etc.)
- Traces (Micrometer Tracing → OpenTelemetry / Zipkin)
- Logs with trace ID injected via MDC

One API, three observability pillars. Adopt for new code.

---

## 9. ProblemDetail (RFC 7807)

Already in `api-design-principles/resources/implementation-playbook.md` §Pattern 3. Worth highlighting: Spring 6 ships this built-in. Use it.

```kotlin
@ExceptionHandler(NotFoundException::class)
fun handleNotFound(ex: NotFoundException): ProblemDetail =
    ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, ex.message ?: "not found").apply {
        type = URI.create("https://errors.example.com/not-found")
        title = "Resource not found"
        setProperty("resourceId", ex.id)
    }
```

Output:
```json
{
  "type": "https://errors.example.com/not-found",
  "title": "Resource not found",
  "status": 404,
  "detail": "Order 123 not found",
  "instance": "/api/v1/orders/123",
  "resourceId": "123"
}
```

Standard. Use for all REST errors.

---

## 10. Boot 3.x configuration imports

`spring.config.import` for layered config sources:

```yaml
spring:
  config:
    import:
      - optional:file:.env.local
      - configtree:/etc/secrets/
      - vault:///secret/data/app/
```

Modern way to compose config from multiple sources without custom code.

---

## 11. Auto-configuration debug

```bash
./gradlew :app:bootRun --debug
```

Or set:
```yaml
debug: true
```

Output shows:
- Auto-configurations evaluated and accepted (Positive matches)
- Auto-configurations evaluated and skipped (Negative matches with reasons)

Use to understand why a bean isn't being created.

---

## 12. Spring Boot starter dependencies — current curated set

For new Boot 3+ services, typical `build.gradle.kts`:

```kotlin
dependencies {
    // Web
    implementation("org.springframework.boot:spring-boot-starter-web")
    implementation("com.fasterxml.jackson.module:jackson-module-kotlin")

    // Persistence
    implementation("org.springframework.boot:spring-boot-starter-data-jpa")
    implementation("org.flywaydb:flyway-core")
    implementation("org.flywaydb:flyway-database-postgresql")
    runtimeOnly("org.postgresql:postgresql")

    // Validation
    implementation("org.springframework.boot:spring-boot-starter-validation")

    // Observability
    implementation("org.springframework.boot:spring-boot-starter-actuator")
    implementation("io.micrometer:micrometer-registry-prometheus")
    implementation("io.micrometer:micrometer-tracing-bridge-otel")

    // Modulith
    implementation("org.springframework.modulith:spring-modulith-starter-core")
    implementation("org.springframework.modulith:spring-modulith-starter-jpa")
    implementation("org.springframework.modulith:spring-modulith-events-jpa")
    runtimeOnly("org.springframework.modulith:spring-modulith-actuator")

    // Kotlin
    implementation("org.jetbrains.kotlin:kotlin-reflect")

    // Test
    testImplementation("org.springframework.boot:spring-boot-starter-test")
    testImplementation("org.springframework.modulith:spring-modulith-starter-test")
    testImplementation("org.springframework.boot:spring-boot-testcontainers")
    testImplementation("org.testcontainers:postgresql")
    testImplementation("org.testcontainers:junit-jupiter")
    testImplementation("io.mockk:mockk")
    testImplementation("com.ninja-squad:springmockk:4.0.2")
}
```

If you're adding more, ask: is the starter really needed? Each adds startup time and surface.

---

## 13. Migration checklist (2.x → 3.x)

- [ ] Java 17+ required; consider JVM 21 LTS
- [ ] Search-replace `javax.` → `jakarta.` (use IDE's "Migrate to Spring Boot 3" inspection)
- [ ] Validate Hibernate 6 behaviour with existing tests
- [ ] Replace Sleuth with Micrometer Tracing
- [ ] Update Spring Security 6 config (filter chain syntax changed)
- [ ] Replace `WebSecurityConfigurerAdapter` (removed) with `SecurityFilterChain` bean
- [ ] Move to `ProblemDetail` from custom error envelopes
- [ ] Update test slice usage where Spring Test API changed
- [ ] Update Actuator endpoints (e.g., paths and security)

Spring's official migration guide is the canonical reference. Allow 1-3 days of dev time per service for a clean migration.

---

## 14. What I'd adopt from new releases

Quick "should we use this?" matrix:

| Feature | Adopt? |
|---|---|
| Virtual threads (`spring.threads.virtual.enabled`) | **Yes** if JVM 21+ and Boot 3.2+. Test under load. |
| `RestClient` for new HTTP client code | **Yes** — replace `RestTemplate` |
| `JdbcClient` for new JDBC code | **Yes** — replace `JdbcTemplate` for new code |
| `@ServiceConnection` for Testcontainers | **Yes** |
| Docker Compose at startup | Maybe — convenient for local dev, irrelevant for prod |
| GraalVM Native | **Probably not** for standard backend services |
| `@Observed` for new instrumentation | **Yes** — better than manual Micrometer |
| `ProblemDetail` for REST errors | **Yes** — standard |
| Spring Authorization Server | If you're building an OAuth server, **yes**; otherwise no |
| Spring Boot 4 early adoption | Cautiously — pin specific version, accept some friction |
