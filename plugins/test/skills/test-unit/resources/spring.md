# Spring at the Unit Layer

The short story: **almost no Spring-annotated test belongs in this skill.** Spring slice tests (`@WebMvcTest`, `@DataJpaTest`, `@JsonTest` for more than a tiny single serializer, `@RestClientTest`, `@SpringBootTest`) live in `test-integration`. This file exists mostly to **catch the edge cases** where a test that *looks* Spring-flavoured is actually a pure unit, and to draw the line firmly for everything else.

> *The Spring annotation is the smoke. The bean wiring is the fire. If your test needs the fire, it's an integration test. If it doesn't, drop the annotation and the smoke goes away — and so does the cost.*

## 1. The rule

If the test needs **ANY** Spring bean wiring — `@Autowired`, `@SpringBootTest`, `@MockkBean`, `@WebMvcTest`, `@DataJpaTest`, `@TestConfiguration`, `@Import`, `@ContextConfiguration` — **it is not a unit test**. Stop. Go to `test-integration`.

The unit-layer guarantee is *pure-JVM, no Spring container, no application context cache, no autowiring*. That guarantee is what makes the layer fast (milliseconds), independent (no shared context state), and diagnostic (a failure is in the unit, not in some wiring six classes away). Erode it and the layer's value collapses.

## 2. Three narrow exceptions

These are still "unit tests" by every meaningful definition — pure JVM, no container, no autowiring — even though they touch a class that *also* participates in Spring at runtime.

### 2a. `@ConfigurationProperties` validation tested as a `data class`

A Spring `@ConfigurationProperties` class with `init { require(...) }` invariants is just a Kotlin `data class`. Test the constructor directly; Spring is **not** loaded.

```kotlin
// Production
@ConfigurationProperties(prefix = "app.retry")
data class RetryProperties(
    val maxAttempts: Int,
    val initialBackoff: Duration,
    val backoffMultiplier: Double,
) {
    init {
        require(maxAttempts in 1..10) { "maxAttempts must be in 1..10, was $maxAttempts" }
        require(initialBackoff > Duration.ZERO) { "initialBackoff must be positive, was $initialBackoff" }
        require(backoffMultiplier > 1.0) { "backoffMultiplier must be > 1.0, was $backoffMultiplier" }
    }
}

// Unit test — no Spring, just constructor invocation
class RetryPropertiesTest {
    @Test
    fun `valid configuration succeeds`() {
        val props = RetryProperties(maxAttempts = 3, initialBackoff = Duration.ofMillis(100), backoffMultiplier = 2.0)
        assertThat(props.maxAttempts).isEqualTo(3)
    }

    @ParameterizedTest
    @ValueSource(ints = [0, -1, 11, 100])
    fun `maxAttempts outside 1..10 is rejected`(invalid: Int) {
        assertThatThrownBy { RetryProperties(maxAttempts = invalid, initialBackoff = Duration.ofMillis(100), backoffMultiplier = 2.0) }
            .isInstanceOf(IllegalArgumentException::class.java)
            .hasMessageContaining("maxAttempts")
    }

    @Test
    fun `non-positive initialBackoff is rejected`() {
        assertThatThrownBy { RetryProperties(maxAttempts = 3, initialBackoff = Duration.ZERO, backoffMultiplier = 2.0) }
            .hasMessageContaining("initialBackoff")
    }
}
```

This is a **value-object invariant test** that happens to be Spring-annotated in production. The annotation is irrelevant to the test; the test exercises the `init` block.

**What the test does NOT cover** — that's `test-integration`:
- Spring actually binds `app.retry.max-attempts: 3` from `application.yml` into the field.
- The `@Validated` annotation triggers JSR-380 validation on bind.
- A misnamed property fails on context startup.

Those need `@ConfigurationPropertiesScan` + a context to verify. Different layer.

### 2b. `@JsonTest`-style serializer rules — borderline, prefer pure

A pure custom Jackson serializer (`JsonSerializer<Money>`) is logic that converts a domain value to JSON. It can be tested *without* Spring by constructing a plain `ObjectMapper` and calling it:

```kotlin
class MoneyJsonSerializerTest {
    private val mapper = jacksonObjectMapper().apply {
        registerModule(SimpleModule().addSerializer(Money::class.java, MoneyJsonSerializer()))
    }

    @Test
    fun `Money serialises as a string with two decimal places`() {
        val json = mapper.writeValueAsString(Money(BigDecimal("99.50")))
        assertThat(json).isEqualTo(""""99.50"""")
    }

    @Test
    fun `Money preserves precision for fractional amounts`() {
        val json = mapper.writeValueAsString(Money(BigDecimal("0.01")))
        assertThat(json).isEqualTo(""""0.01"""")
    }
}
```

That's a **pure unit test**. No Spring, no `@JsonTest`. **Prefer this**.

`@JsonTest` is occasionally useful when:
- You want Spring Boot's autoconfigured `ObjectMapper` (with all custom modules registered) so you don't manually wire each.
- You're testing a *combination* of serializers + deserializers + Jackson features (date format, naming strategy, polymorphic types) and the manual `ObjectMapper` setup would duplicate Spring's autoconfig.

In those cases `@JsonTest` is an **integration slice** — it loads the autoconfigured `ObjectMapper` from a small Spring context. Goes in `test-integration`, not here.

**The practical rule**: a single isolated serializer / deserializer → pure unit (this skill). A combination relying on Spring's `ObjectMapper` autoconfiguration → `@JsonTest` in `test-integration`.

### 2c. Pure controller logic extracted to a non-controller class

Controllers should be thin. When they aren't, the right move is **almost always** to extract the logic to a non-controller class (an application service or domain method) and test that as a pure unit. The remaining controller body is then thin enough to be covered by an integration slice (`@WebMvcTest`) — exactly where it belongs.

```kotlin
// ✗ Logic in the controller — hard to unit-test cleanly
@RestController
class OrderController(private val service: OrderService) {
    @PostMapping("/orders")
    fun submit(@RequestBody request: SubmitOrderRequest): ResponseEntity<*> {
        // 30 lines of validation and decision logic
        if (request.lines.isEmpty()) return ResponseEntity.badRequest().body("...")
        if (request.lines.size > 100) return ResponseEntity.badRequest().body("...")
        // ... more rules ...
        return ResponseEntity.ok(service.submit(...))
    }
}

// ✓ Extract the decisions to a pure class
class SubmitOrderValidator {
    fun validate(request: SubmitOrderRequest): ValidationResult { … }
}

// ✓ Unit-test the extracted class — pure, no Spring
class SubmitOrderValidatorTest {
    private val validator = SubmitOrderValidator()

    @Test
    fun `an empty line list is rejected with a clear message`() {
        val result = validator.validate(aRequest(lines = emptyList()))
        assertThat(result).isEqualTo(ValidationResult.Invalid("at least one line"))
    }

    @Test
    fun `more than 100 lines is rejected`() {
        val result = validator.validate(aRequest(lines = List(101) { aLine() }))
        assertThat(result).isEqualTo(ValidationResult.Invalid("at most 100 lines"))
    }
}

// The controller's remaining body is now ~3 lines — slice-test it with @WebMvcTest in test-integration.
```

The extraction is the **right thing to do** regardless of testing — controllers should be transport adapters, not decision sites. The fact that it makes the rules unit-testable is a happy side effect.

**Do not** attempt to unit-test a controller class directly (`OrderController(mockService).submit(request)`) — even though it compiles, the result is fragile:
- It bypasses Spring's request mapping, argument resolvers, validation, exception handling.
- A test that passes here can fail at runtime because the *real* request path goes through eight more Spring components.
- A `@WebMvcTest` slice in `test-integration` covers the same surface honestly, with realistic fidelity.

## 3. Tests that *look* like unit tests but aren't

If you see any of these in `test/unit/` (or whatever the unit-tier package is), they're misclassified. Move them to `test-integration`:

| Annotation / pattern | Why it's not unit |
|---|---|
| `@SpringBootTest` | Loads full application context. **The signature failure mode** of an inverted-pyramid suite. |
| `@WebMvcTest` | Loads MVC slice (controllers, filters, argument resolvers, validation, exception handlers). Slice test → integration. |
| `@DataJpaTest` | Loads JPA + a DataSource. Always integration. Use Testcontainers, not H2. |
| `@JsonTest` (multi-serializer / full autoconfig) | Loads Boot's Jackson autoconfiguration. Slice → integration. (Single isolated serializer with manual `ObjectMapper` → unit, see §2b.) |
| `@RestClientTest` | Loads `RestTemplate` / `WebClient` autoconfiguration + MockRestServiceServer. Slice → integration. |
| `@MockBean` / `@MockkBean` | Replaces a bean in a Spring context. The fact that you reach for it means a context exists; not a unit. |
| `@ContextConfiguration` | Explicit context loading. Not a unit. |
| `@TestConfiguration` | Beans for a Spring context. Not a unit. |
| `@Import(SomeConfig::class)` | Pulls Spring configuration. Not a unit. |
| `@DynamicPropertySource` | Dynamic Spring properties — implies a Spring environment. Not a unit. |
| `@TestPropertySource` | Same. |
| `@ActiveProfiles` | Same. |
| `@DirtiesContext` | The test is so context-dependent that it has to dirty it. Definitively integration. |
| `@Transactional` on a test class | Spring-managed transaction. Integration. |

If any of these appear on a class you're calling a "unit test", that's a category error. Promote to `test-integration` or refactor the production code so the rules become pure-JVM (see §2c).

## 4. The "but it's fast though" objection

Sometimes a `@SpringBootTest`-flavoured test runs in 800ms and feels "almost like a unit test". It is not. Three reasons it stays in `test-integration` (or higher):

1. **Context cache state.** Spring caches application contexts across tests. The 800ms is the *first* test; later tests in the same context are fast. But the cache is sensitive to the combination of annotations / property sources / mocked beans; a small change can fragment the cache and re-pay the context-load cost N times. This is invisible to the test author and a frequent CI surprise.
2. **Different failure mode.** When a Spring test fails, the failure is at *some* layer in the wiring; diagnosis means reading the stack and reasoning across many components. A pure unit test failure is local — the unit and its inputs are the entire surface.
3. **Different speed tier.** A unit test target is <50ms; a slice test target is <500ms. They get different signals (run-on-save vs run-on-build). Mixing them in the same tier hides slow tests behind fast ones.

Keep the tiers honest. A "fast Spring test" is a *fast integration test*; it goes in `test-integration` and that's a fine outcome.

## 5. The "but I want a fake bean wired in" objection

When the temptation is "I want to wire an in-memory fake repository into a Spring context and run the application service against it", you have a choice:

- **`test-acceptance`** — application-service-level tests with **manually-constructed** application services (no Spring) and in-memory adapters. The whole test is pure JVM. This is the right home for "use case with fake adapters".
- **`test-integration`** — actual Spring context with `@MockkBean` / `@TestConfiguration` providing fake beans. Heavier; reserve for cases where Spring's wiring is itself part of what you want to verify.

Pure unit (this skill) is *not* the right home. The moment you instantiate a Spring context, you've left this layer.

## 6. Smell → fix

| Smell | Fix |
|---|---|
| `@SpringBootTest` in a class called `…UnitTest` | Move to `test-integration`, or extract the logic to a pure class and unit-test that. |
| `@WebMvcTest(OrderController::class)` in the unit tier | Move to `test-integration`. |
| `OrderController(mockService).submit(...)` direct call in a "unit test" | Extract the decisions to a non-controller class; unit-test that. Slice-test the thin controller in `test-integration`. |
| `@ConfigurationProperties` validation tested only via Spring context | Add a pure `data class` constructor test for the `init { require(...) }` invariants. Keep the Spring-binding test in `test-integration`. |
| Custom Jackson serializer tested via `@JsonTest` | Switch to a plain `ObjectMapper`-based unit test; reserve `@JsonTest` for combinations relying on autoconfig (those stay in `test-integration`). |
| `@MockkBean OrderRepository` in a unit test | Either it's an integration test (use `@MockkBean` properly in `test-integration`) or it's an acceptance test (use a plain `mockk<OrderRepository>()` / in-memory fake without Spring). |
| `@TestPropertySource("classpath:test.yml")` | Spring environment. Integration. |
| `@Autowired` in a unit test | Same. |

## 7. The honest summary

The "unit layer in Spring" is mostly a **negative space**:
- The thing **happens to be Spring-flavoured in production** (`@ConfigurationProperties`, `@RestController`, `@Service`).
- The **test treats it as plain Kotlin** — no Spring annotation on the test, no autowiring, no context.
- If you can't write the test that way, the test belongs at a sibling layer.

Three categories of test still legitimately live here:
1. `@ConfigurationProperties` invariants — pure constructor invocation; no Spring.
2. Custom Jackson serializers — manual `ObjectMapper`; no `@JsonTest`.
3. Logic extracted out of controllers into pure classes — pure constructor invocation; no `@WebMvcTest`.

Everything else with a Spring annotation on it: **see `test-integration`**.
