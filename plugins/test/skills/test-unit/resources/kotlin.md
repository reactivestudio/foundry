# Kotlin Unit-Test Tooling

The house stack and idioms for unit tests in a Kotlin codebase. Backtick names, `a/an` factories, `@Nested`, `assertSoftly`, parameterised tests, `assertThrows<T>`, `runTest`, MockK, Kotest-where-it-earns, `Clock` injection.

> *Kotlin's tests don't have to look like Java tests with `fun` instead of `void` — they can look like sentences.*

For the per-test discipline (F.I.R.S.T., BUILD-OPERATE-CHECK, DSL emergence) read `test-principles`. For the language-agnostic test-double / Khorikov classification, read `general.md` here. This file is **tooling**.

## 1. The stack — default

| Layer | Choice | Rationale |
|---|---|---|
| Runner | **JUnit 5 (Jupiter)** | `@Nested`, `@ParameterizedTest`, `@TestInstance`. |
| Assertions | **AssertJ** | Fluent, mature, custom-assertion-friendly. |
| Mocking | **MockK** | Kotlin-native; `suspend`, `final`, `object`, sealed types — no `open` boilerplate. |
| Property-based / spec-style | **Kotest** | Reach for it; not the default. |
| Time | **`java.time.Clock` injected** | Standard, deterministic. |
| Random | **`Random` injected with seed** | Same. |
| Coroutines | **`kotlinx-coroutines-test`** | `runTest`, virtual time. |

```kotlin
dependencies {
    testImplementation("org.junit.jupiter:junit-jupiter")
    testImplementation("org.assertj:assertj-core:3.26.3")
    testImplementation("io.mockk:mockk:1.13.13")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
    // optional:
    testImplementation("io.kotest:kotest-property:5.9.1")
    testImplementation("io.kotest:kotest-runner-junit5:5.9.1")
}

tasks.test { useJUnitPlatform() }
```

**Anti-patterns**: Hamcrest + AssertJ in the same project (pick one); JUnit 4 lingering after JUnit 5 adoption; Mockito + MockK in the same module.

## 2. Backtick test names

Use for every `@Test` in pure-JVM code.

```kotlin
// ✗ Java-style
@Test fun testSubmitWithEmptyLinesReturnsRejected() { … }

// ✓ Kotlin idiom — a sentence
@Test fun `submitting an Order with empty lines is rejected`() { … }
```

Three valid formulations (pick one team-wide):
1. **State-of-the-world** — `` `submitting an Order with no lines is rejected` ``. **House default.**
2. **Given-When-Then** — verbose; tolerable for complex setups.
3. **`should` phrasing** — common in BDD teams; the runner already implies "should".

```kotlin
class OrderTest {
    @Test fun `a draft Order has no submitted timestamp`() { … }
    @Test fun `submitting a draft Order sets the submitted timestamp`() { … }
    @Test fun `submitting an already-submitted Order is rejected`() { … }
}
```

Read the list aloud to a product owner. If the sentences make sense, the suite is documentation.

**Caveats**: Android instrumentation < API 30 doesn't allow backtick identifiers (use `@DisplayName`); CI dashboards may truncate at ~80 chars.

## 3. `a/an` fixture factories

Production aggregates (correctly) have constructors that enforce invariants. Test defaults live in `src/test`:

```kotlin
// src/test/kotlin/com/example/orders/domain/Fixtures.kt
fun anOrder(
    id: OrderId = OrderId(UUID.randomUUID()),
    customerId: CustomerId = CustomerId(UUID.randomUUID()),
    status: OrderStatus = OrderStatus.DRAFT,
    lines: List<OrderLine> = listOf(anOrderLine()),
    createdAt: Instant = Instant.parse("2024-01-15T10:00:00Z"),
): Order = Order(id, customerId, status, lines, createdAt)

fun anOrderLine(
    sku: Sku = Sku("SKU-001"),
    quantity: Int = 1,
    unitPrice: Money = Money(BigDecimal("99.00")),
): OrderLine = OrderLine(sku, quantity, unitPrice)
```

**Override only what matters** at the call site:

```kotlin
val order = anOrder(
    lines = listOf(
        anOrderLine(quantity = 2, unitPrice = Money("10.00")),
        anOrderLine(quantity = 1, unitPrice = Money("30.00")),
    ),
)
```

For **derived** fixtures, `.copy()`:

```kotlin
val submitted = anOrder().copy(status = OrderStatus.SUBMITTED)
```

**State-named factories** compose via real domain transitions — a stale fixture surfaces the moment the domain changes:

```kotlin
fun aDraftOrder(...): Order = …
fun aSubmittedOrder(...): Order = aDraftOrder(...).submit(submittedAt)
fun aCancelledOrder(...): Order = aSubmittedOrder(...).cancel(reason, at)
```

**House rule**: indefinite article — `anOrder`, `aCustomer`, `aReservation`. Reads naturally.

**Anti-patterns**:
- Fixture factory in `src/main` — test code belongs in `src/test`. Production should never bypass invariants.
- Constructing via reflection / `set private field`. Reach the target state via a domain transition; if no transition exists, add one (often the right move).
- Cryptic positional fixture: `Order(UUID.randomUUID(), "Ada", null, null, false)`. Use the named-defaults factory.

## 4. Extension functions and `infix` — DSL primitives

```kotlin
// Custom AssertJ assertion as extension
fun ObjectAssert<Order>.isSubmitted(): ObjectAssert<Order> {
    extracting(Order::status).isEqualTo(OrderStatus.SUBMITTED)
    return this
}

fun ObjectAssert<Order>.hasTotalOf(expected: Money): ObjectAssert<Order> {
    extracting(Order::total).usingComparator(Money.COMPARATOR).isEqualTo(expected)
    return this
}

// Chains naturally
assertThat(order).isSubmitted().hasTotalOf(Money("99.00"))
```

Kotest `infix`:

```kotlin
infix fun Order.shouldBeIn(status: OrderStatus) { this.status shouldBe status }
order shouldBeIn OrderStatus.SUBMITTED
```

**Where**:
- Custom assertions → `src/test/kotlin/<module>/assertions/<Type>Assertions.kt` — one file per asserted type.
- Common DSL primitives → `src/test/kotlin/<module>/Fixtures.kt`.

**Anti-patterns**: extending standard library types (pollutes IDE autocomplete in production); designing a `TestKit` class on day one (the DSL **emerges** — copy-paste → extract → name).

## 5. `@Nested inner class` — single concept, shared Given

```kotlin
class OrderTest {
    @Nested
    inner class `given a draft order` {
        private val order = aDraftOrder()

        @Test
        fun `submit moves it to SUBMITTED`() {
            val updated = order.submit(submittedAt = now)
            assertThat(updated.status).isEqualTo(SUBMITTED)
        }

        @Test
        fun `cancel moves it to CANCELLED`() {
            val updated = order.cancel(reason = "customer request", at = now)
            assertThat(updated.status).isEqualTo(CANCELLED)
        }
    }

    @Nested
    inner class `given a submitted order` {
        private val order = aSubmittedOrder()

        @Test
        fun `submit is rejected`() {
            assertThatThrownBy { order.submit(submittedAt = now) }
                .isInstanceOf(IllegalOrderTransition::class.java)
        }
    }
}
```

Renders as a tree in the IDE / Gradle report — a literal spec tree.

**Caveats**:
- `@Nested` defaults to fresh-instance-per-test (independence). `@TestInstance(Lifecycle.PER_CLASS)` for shared fixtures — but methods must not mutate them.
- `private val order = aDraftOrder()` allocates per test. **Don't** move to `companion object` to "save allocation" — independence violation.

## 6. `assertSoftly` / `assertAll` — multi-assert without short-circuit

```kotlin
// AssertJ
assertSoftly { softly ->
    softly.assertThat(response.id).isNotNull()
    softly.assertThat(response.status).isEqualTo("SUBMITTED")
    softly.assertThat(response.total).isEqualByComparingTo(BigDecimal("99.00"))
    softly.assertThat(response.createdAt).isCloseTo(now, within(1, SECONDS))
}

// JUnit 5
assertAll(
    { assertThat(response.id).isNotNull() },
    { assertThat(response.status).isEqualTo("SUBMITTED") },
)

// Kotest
assertSoftly(response) {
    id shouldNotBe null
    status shouldBe "SUBMITTED"
}
```

For deep object equality, **AssertJ's `usingRecursiveComparison()`** — don't hand-write 20 field-by-field assertions:

```kotlin
assertThat(actualOrder)
    .usingRecursiveComparison()
    .ignoringFields("id", "createdAt")
    .isEqualTo(expectedOrder)
```

## 7. `@ParameterizedTest` — one concept, many examples

```kotlin
@ParameterizedTest(name = "{0} + {1} = {2}")
@CsvSource(
    "'1.00', '2.00', '3.00'",
    "'0.10', '0.20', '0.30'",       // famously fails with Double
    "'99.99', '0.01', '100.00'",
)
fun `addition of well-formed amounts is exact`(a: String, b: String, expected: String) {
    assertThat(Money(a) + Money(b)).isEqualByComparingTo(Money(expected))
}
```

`@MethodSource` for non-trivial inputs:

```kotlin
@ParameterizedTest
@MethodSource("rejectionCases")
fun `submit is rejected for these draft Orders`(scenario: String, draftOrder: Order, expected: String) {
    assertThatThrownBy { draftOrder.submit(submittedAt = now) }.hasMessageContaining(expected)
}

companion object {
    @JvmStatic
    fun rejectionCases(): List<Arguments> = listOf(
        Arguments.of("empty lines", aDraftOrder(lines = emptyList()), "at least one line"),
        Arguments.of("zero total", aDraftOrder(lines = listOf(orderLine(unitPrice = Money.ZERO))), "non-zero total"),
    )
}
```

For **sealed-class** parameter spaces, Kotest's data-driven tests read better than `@MethodSource`:

```kotlin
class OrderTransitionsSpec : FunSpec({
    withData(
        nameFn = { (from, action) -> "$from + $action" },
        Triple(DRAFT, Submit, SUBMITTED),
        Triple(DRAFT, Cancel("reason"), CANCELLED),
        Triple(SUBMITTED, Cancel("reason"), CANCELLED),
    ) { (from, action, expected) ->
        anOrder(status = from).apply(action).status shouldBe expected
    }
})
```

**House rule**: reach for parameterisation when you'd otherwise write 3+ structurally identical `@Test` methods.

## 8. `assertThrows<T>` / `assertThatThrownBy` — error paths

```kotlin
// ✓ JUnit 5
val ex = assertThrows<IllegalOrderTransition> { order.submit(submittedAt = now) }
assertThat(ex).hasMessage("Already submitted")

// ✓ AssertJ (preferred when chaining)
assertThatThrownBy { order.submit(submittedAt = now) }
    .isInstanceOf(IllegalOrderTransition::class.java)
    .hasMessage("Already submitted")

// ✓ Kotest
val ex = shouldThrow<IllegalOrderTransition> { order.submit(submittedAt = now) }
ex.message shouldBe "Already submitted"
```

**Anti-pattern**: try/catch/fail dance; catching base `Exception`. Always catch the specific type the production code commits to.

## 9. `Result<T>` and sealed `Outcome<T>` patterns

When a method returns `Result<T>` / sealed `Outcome<T>` instead of throwing, the test asserts on the **value**:

```kotlin
sealed interface SubmitOutcome {
    data class Submitted(val order: Order) : SubmitOutcome
    data class Rejected(val reason: String) : SubmitOutcome
}

@Test
fun `submit returns Rejected when lines are empty`() {
    val outcome = OrderService().submit(SubmitOrder(customerId, lines = emptyList()))

    assertThat(outcome)
        .isInstanceOf(SubmitOutcome.Rejected::class.java)
        .extracting("reason").isEqualTo("Order requires at least one line")
}
```

**House rule**: happy-path and exception-path tests read with the **same shape** — only the type and assertion differ.

## 10. `runTest` — virtual time for coroutines

Never `Thread.sleep`, never `runBlocking { delay(...) }` with real time.

```kotlin
@Test
fun `retry waits 100ms before retrying`() = runTest {
    val sut = Retrier()
    val deferred = async { sut.callWithRetry { error("always fails") } }
    advanceTimeBy(99)
    assertThat(deferred.isCompleted).isFalse()
    advanceTimeBy(2)
    assertThat(deferred.isCompleted).isTrue()
}
```

**Key tools**:
- `runTest { … }` — `TestScope` with `StandardTestDispatcher`. Virtual time.
- `advanceTimeBy(ms)` — moves virtual time forward.
- `advanceUntilIdle()` — drains all pending continuations.
- `runCurrent()` — runs currently queued continuations only.

**Caveat**: if production injects a `CoroutineDispatcher`, the test passes a `TestDispatcher`. Don't hard-code `Dispatchers.IO` — inject (`Repository(io: CoroutineDispatcher = Dispatchers.IO)`).

## 11. MockK — test doubles

```kotlin
class OrderServiceTest {
    private val orders = mockk<OrderRepository>()
    private val publisher = mockk<EventPublisher>(relaxed = true)
    private val service = OrderService(orders, publisher)

    @Test
    fun `submit persists the order and publishes OrderSubmitted`() {
        every { orders.findById(any()) } returns null
        every { orders.save(any()) } answers { firstArg() }

        service.submit(SubmitOrder(customerId, listOf(orderLine())))

        verify { orders.save(match { it.status == DRAFT }) }
        verify { publisher.publish(ofType<OrderSubmitted>()) }
    }
}
```

**Key features**:
- `mockk<T>()` — strict; un-stubbed calls throw.
- `mockk<T>(relaxed = true)` — returns defaults for un-stubbed calls. For `Unit`-returning collaborators only.
- `every { } returns / answers / throws` — stub.
- `verify { }` / `verify(exactly = 0) { }` — assert calls.
- `slot<T>()` + `capture(slot)` — capture args.
- **Suspend**: `coEvery` / `coVerify`. Using plain `every` on `suspend` throws.

```kotlin
@Test
fun `fetchOrder hits the right URL`() = runTest {
    coEvery { http.get("/orders/123") } returns orderResponse()
    val order = client.fetchOrder(OrderId("123"))
    coVerify { http.get("/orders/123") }
    assertThat(order.id).isEqualTo(OrderId("123"))
}
```

**Argument capture**:

```kotlin
val captured = slot<Order>()
every { orders.save(capture(captured)) } answers { captured.captured }
service.submit(SubmitOrder(customerId, listOf(orderLine(quantity = 3))))
assertThat(captured.captured.lines[0].quantity).isEqualTo(3)
```

**Anti-patterns**:
- **Mock-the-world** — six `every { }` lines. Seam is wrong; see `general.md` §5.
- **`verify(exactly = 1) { }` on everything** — over-specifies. Use `verify { }` by default.
- **`every { } answers { … real work … }`** — half-baked fake. Write a real `InMemoryOrderRepository`.
- **`relaxed = true` by default** — masks "forgot to stub". Relaxed only for fire-and-forget collaborators.

## 12. Kotest — when to reach for it

Both can run side-by-side. Pick Kotest for:
1. **Property-based** — `forAll(Arb.int(), Arb.string()) { … }`.
2. **Data-driven** — `withData(...)` for sealed-class parameter spaces.
3. **Spec styles** — `BehaviorSpec`, `StringSpec`, `FunSpec`.
4. **Rich matcher DSL** — `result shouldBe expected`, `instant should beAfter other`.

For 90% of unit tests, JUnit 5 + AssertJ + MockK is the simpler, less-surprising stack.

```kotlin
class MoneyPropertySpec : StringSpec({
    "addition is commutative" {
        forAll(Arb.bigDecimal(min = 0, max = 1_000_000), Arb.bigDecimal(min = 0, max = 1_000_000)) { a, b ->
            (Money(a) + Money(b)) == (Money(b) + Money(a))
        }
    }
})
```

## 13. `Clock` and `MutableClock` — time-sensitive tests

Inject `Clock`; never call `Instant.now()` / `LocalDate.now()` directly in production.

```kotlin
// Production
class OrderService(private val clock: Clock) {
    fun submit(command: SubmitOrder): Order =
        Order.draft(command.customerId).submit(submittedAt = clock.instant())
}

// Test — fixed
private val clock = Clock.fixed(Instant.parse("2024-01-15T10:00:00Z"), UTC)
private val service = OrderService(clock)
```

When time must **advance**, a `MutableClock`:

```kotlin
class MutableClock(initial: Instant) : Clock() {
    private var current: Instant = initial
    override fun instant(): Instant = current
    override fun getZone(): ZoneId = UTC
    override fun withZone(zone: ZoneId): Clock = this
    fun advance(duration: Duration) { current = current.plus(duration) }
}

@Test
fun `order is auto-cancelled after 24h`() {
    val clock = MutableClock(Instant.parse("2024-01-15T10:00:00Z"))
    val service = OrderService(clock)
    val order = service.submit(...)

    clock.advance(Duration.ofHours(25))
    service.autoCancelStale()

    assertThat(service.findById(order.id).status).isEqualTo(CANCELLED)
}
```

**Even better for pure domain code**: pass `at: Instant` as a parameter; don't inject `Clock` into the domain. The application service holds the `Clock` and passes the value down.

```kotlin
// Domain — pure
fun Reservation.confirm(at: Instant): Reservation {
    require(at < holdExpiresAt) { "Hold has expired" }
    return copy(status = CONFIRMED)
}
```

**House rule**: forbid `Instant.now()` / `LocalDate.now()` in production via Detekt or ArchUnit (`noClasses().that().resideInAPackage("..domain..").should().callMethod(Instant::class.java, "now")`).

## 14. The Kotlin testing-stack — recap

| Aspect | Choice |
|---|---|
| Naming | Backtick sentence, state-of-the-world |
| Fixtures | `a/an` factory in `src/test`; `copy()` for derived |
| Assertions | AssertJ chains; `assertSoftly` for multi-part single concept |
| Custom assertions | Extension on `ObjectAssert<T>` |
| Mocking | MockK (strict by default; `relaxed = true` only for `Unit`-returning) |
| Stateful collaborators | In-memory fake, not chained `every` |
| Parameterised | `@ParameterizedTest` + `@CsvSource` / `@MethodSource`; Kotest `withData` for sealed |
| Property-based | Kotest `forAll` / `checkAll` |
| Time | Injected `Clock`; or `at: Instant` parameter in domain |
| Coroutines | `runTest`, `advanceTimeBy` |
| Grouping | `@Nested inner class \`given …\`` |

## 15. Kotlin anti-patterns

- `@Test fun testSubmit()` — Java-style. Use backticks.
- `@Test fun \`should work\`()` — vacuous. Describe the behaviour.
- Cryptic positional fixture — named factory.
- `Instant.now()` in domain code — parameter or injected `Clock`.
- `runBlocking { delay(...) }` in a unit test — use `runTest`.
- Plain `every` / `verify` on `suspend` — `coEvery` / `coVerify`.
- MockK + Mockito coexisting — pick one.
- 30-line `@BeforeEach` — extract a factory.
- Premature `TestKit` class — DSL emerges; round one copy-paste, round two extract, round three name.
- Asserting on `toString()` — couples to formatting; assert on fields.
- `private var sut = …` at class level — surprise leak between tests. `private val` is fine.

## 16. The minimal Kotlin unit-test template

When in doubt, this shape:

```kotlin
class <Subject>Test {

    // 1. Fixed deterministic constants
    private val now = Instant.parse("2024-01-15T10:00:00Z")

    // 2. Test doubles only for collaborators escaping the JVM
    private val publisher = RecordingEventPublisher()              // fake, not mock

    // 3. Subject under test
    private val subject = <Subject>(publisher)

    @Test
    fun `<sentence describing the behaviour>`() {
        val input = a<Subject>Input(...)                            // BUILD

        val outcome = subject.<operation>(input, at = now)          // OPERATE

        assertThat(outcome).<assertion>()                           // CHECK state
        assertThat(publisher.events).containsExactly(...)           // CHECK events / interactions if relevant
    }
}
```

If this shape doesn't fit, you're probably trying to write a test that belongs at a sibling layer — re-read `general.md` §8 (Khorikov quadrants) and `test-strategy` for shape selection.
