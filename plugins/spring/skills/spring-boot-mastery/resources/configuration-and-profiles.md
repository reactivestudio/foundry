# Configuration and Profiles

Typed config, validation, profiles, secrets. The single most under-engineered area in Spring apps.

---

## 1. `@ConfigurationProperties` — always preferred over `@Value`

### Anti-pattern: `@Value` everywhere

```kotlin
@Service
class StripeClient(
    @Value("\${stripe.api-key}") private val apiKey: String,
    @Value("\${stripe.webhook-secret}") private val webhookSecret: String,
    @Value("\${stripe.timeout-seconds:30}") private val timeoutSeconds: Long,
    @Value("\${stripe.retries:3}") private val retries: Int,
)
```

Problems:
- Untyped — `timeout-seconds: not-a-number` fails at runtime
- No autocomplete in IDE — `application.yml` typos go undetected
- Defaults scattered across constructors
- Validation impossible

### Good: typed `@ConfigurationProperties`

```kotlin
@ConfigurationProperties(prefix = "stripe")
@Validated
data class StripeProperties(
    @field:NotBlank val apiKey: String,
    @field:NotBlank val webhookSecret: String,
    val timeout: Duration = Duration.ofSeconds(30),
    @field:Min(0) @field:Max(10) val retries: Int = 3,
)

@Configuration
@EnableConfigurationProperties(StripeProperties::class)
class StripeConfig

@Service
class StripeClient(private val props: StripeProperties) { … }
```

Or in Spring Boot 3+, `@ConfigurationPropertiesScan` on the application class auto-discovers:

```kotlin
@SpringBootApplication
@ConfigurationPropertiesScan
class App
```

### `application.yml`

```yaml
stripe:
  api-key: sk_test_xxx
  webhook-secret: whsec_yyy
  timeout: 60s
  retries: 5
```

IDE knows the schema (via `spring-configuration-metadata.json` auto-generated). Typos highlighted. `Duration` parsed from `60s`, `5m`, `PT1H`.

### Bonus: nested + lists

```kotlin
@ConfigurationProperties(prefix = "app")
data class AppProperties(
    val name: String,
    val features: Features,
    val externalApis: List<ExternalApi>,
) {
    data class Features(
        val newCheckoutEnabled: Boolean = false,
        val maxBatchSize: Int = 1000,
    )

    data class ExternalApi(
        @field:NotBlank val name: String,
        @field:URL val baseUrl: String,
        val timeout: Duration = Duration.ofSeconds(10),
    )
}
```

```yaml
app:
  name: assista-platform
  features:
    new-checkout-enabled: true
    max-batch-size: 500
  external-apis:
    - name: github
      base-url: https://api.github.com
      timeout: 30s
    - name: jira
      base-url: https://example.atlassian.net
      timeout: 15s
```

---

## 2. Property precedence (highest → lowest)

When the same property is set in multiple places, Spring resolves in this order (first wins):

1. Command-line arguments: `--app.name=override`
2. JVM system properties: `-Dapp.name=override`
3. `SPRING_APPLICATION_JSON` env var (JSON string)
4. OS environment variables: `APP_NAME=override`
5. External `application.yml` files (in classpath, then specific paths)
6. `application-{profile}.yml` (profile-specific)
7. `application.yml` (default)
8. Defaults in `@ConfigurationProperties` data class

This is why `kubectl set env DEPLOY=... APP_NAME=override` works — env var beats `application.yml`.

### Common gotchas

- **Kebab-case in YAML maps to camelCase in Kotlin**: `app.api-key` → `apiKey`
- **Env var convention**: dots → underscores, dash → underscore, uppercase: `APP_API_KEY`
- **`SPRING_PROFILES_ACTIVE=prod`** activates `application-prod.yml`

---

## 3. Profiles

Profile = named slice of configuration.

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

Activate via `SPRING_PROFILES_ACTIVE=prod` env var or `--spring.profiles.active=prod` CLI.

### Profile-specific files

```
src/main/resources/
├── application.yml             # default
├── application-dev.yml         # dev profile
├── application-test.yml        # test profile (auto-activated by @ActiveProfiles("test"))
├── application-prod.yml        # prod profile
└── application-local.yml       # local dev (gitignored)
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

In tests, `@ActiveProfiles("test")` activates `FakePaymentGateway`.

### Profile anti-patterns

- **Profile per environment** (`dev`, `staging`, `prod`) — fine.
- **Profile per feature** (`new-checkout`, `dark-mode`) — wrong. Use feature flags / `@ConditionalOnProperty`, not profiles.
- **Profile combinations** (`dev,k8s,debug`) — confusing. Try to keep flat.

---

## 4. Validation

`@Validated` on the `@ConfigurationProperties` class + `jakarta.validation` annotations validate at startup.

```kotlin
@ConfigurationProperties(prefix = "stripe")
@Validated
data class StripeProperties(
    @field:NotBlank val apiKey: String,
    @field:Pattern(regexp = "^whsec_.*", message = "must start with whsec_")
    val webhookSecret: String,
    @field:DurationMin(seconds = 1)
    @field:DurationMax(minutes = 5)
    val timeout: Duration = Duration.ofSeconds(30),
    @field:Min(0) @field:Max(10) val retries: Int = 3,
    @field:NotEmpty val supportedCurrencies: List<String> = listOf("EUR", "USD"),
)
```

If `application.yml` has `stripe.retries: -1`, the app **fails to start** with a clear error. Better than discovering it via 500 errors in prod.

Note the `@field:` prefix — Kotlin annotation site target needed for these annotations to land on the JVM field.

---

## 5. Secrets

Never:
- Hardcode in `application.yml`
- Commit to git
- Bake into Docker image

Always:
- Env vars at runtime
- Secret manager (Vault, AWS Secrets Manager, K8s Secrets)
- `spring.config.import: vault://...` for Spring Cloud Vault

```yaml
# application.yml — placeholder, real value from env at runtime
stripe:
  api-key: ${STRIPE_API_KEY:?STRIPE_API_KEY is required}
```

The `:?` syntax requires the env var to be set, otherwise fail at startup.

### Local dev secrets

`application-local.yml` (gitignored) for personal API keys during dev. Activated only locally via `SPRING_PROFILES_ACTIVE=local`.

`.env` files + `dotenv` plugins also common.

---

## 6. External config sources

```yaml
spring:
  config:
    import:
      - vault://path/to/secret    # Spring Cloud Vault
      - configtree:/etc/secrets/  # K8s mounted secrets as files
      - optional:file:.env.local  # local optional file
```

`configtree` reads each file in a directory as a property (`/etc/secrets/db-password` → `db.password`). Common K8s pattern.

---

## 7. Refreshing config at runtime (Spring Cloud)

Spring Cloud Config + `@RefreshScope` allow config changes without restart:

```kotlin
@RefreshScope
@Service
class FeatureToggleService(private val props: FeatureProperties)
```

POST `/actuator/refresh` re-reads config. Use sparingly:
- Beans become proxies (small perf cost)
- Not all properties can be refreshed (e.g., `spring.datasource.*` — connection pool already built)

For feature flags, prefer dedicated tooling (Unleash, LaunchDarkly, OpenFeature) over `@RefreshScope`.

---

## 8. Auto-configuration introspection

```bash
./gradlew :app:bootRun --debug
# or in app
java -jar app.jar --debug
```

Output includes:
- "Positive matches" — auto-configs activated
- "Negative matches" — auto-configs evaluated and skipped, with reasons

When you wonder "is Spring auto-configuring this for me?" — `--debug` answers.

---

## 9. Custom auto-configuration

For shared modules across services:

```kotlin
// In module assista-platform-starter
@AutoConfiguration
@ConditionalOnClass(SomeRequiredClass::class)
@ConditionalOnProperty(name = ["assista.starter.enabled"], havingValue = "true", matchIfMissing = true)
@EnableConfigurationProperties(StarterProperties::class)
class AssistaStarterAutoConfiguration {

    @Bean
    @ConditionalOnMissingBean
    fun somethingDefault(props: StarterProperties): Something = Something(props)
}
```

Register in `META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports`:

```
pro.vlprojects.assista.starter.AssistaStarterAutoConfiguration
```

Now any service depending on this module gets `Something` automatically.

`@ConditionalOnMissingBean` means consumers can override.

---

## 10. Configuration anti-patterns

- **`@Value("\${app.foo}")` on every field** — switch to `@ConfigurationProperties`.
- **Defaults in `application.yml`** — put defaults in the data class. `application.yml` should be **overrides**.
- **Long `application.yml` (>200 lines)** — split by concern, use profiles, or extract `@ConfigurationProperties` per concern.
- **No validation** — typos and missing vars discovered in prod. Always `@Validated`.
- **Profile names mean different things in different envs** — "dev" in your repo ≠ "dev" in someone else's. Be specific: "dev-local", "dev-staging".
- **`Environment` injection** — `@Autowired Environment env; env.getProperty("...")` bypasses typing. Don't.
- **`@Configuration` classes with logic** — they should declare beans, not run logic. Logic goes in `@PostConstruct` of a bean.

---

## 11. Migration: from `@Value` hell to `@ConfigurationProperties`

1. Group related `@Value` fields by prefix (`stripe.*`, `kafka.*`)
2. Create `XxxProperties` data class per group
3. Move defaults from constructor params to data class
4. Add `@Validated` + bean validation annotations
5. Run app — if startup fails, fix configs (this is good — finding errors before runtime)
6. Delete `@Value` annotations
7. Document `XxxProperties` in README — they're now part of the contract
