# Acceptance Tests — Kotlin Patterns

Kotlin-side tooling for the acceptance tier. Spring-side patterns live in `spring.md`; language-agnostic discipline lives in `general.md`. Read `general.md` first.

> "An acceptance test in Kotlin reads as plain English Kotlin. No reflection tricks, no DSL theatrics, no Cucumber indirection by default — just a fixture builder, a use-case call, and AssertJ on the recorded events." — house ethos

---

## 1. In-memory repository — the canonical pattern

A test-only class that implements the domain `Repository` port. Lives in `src/test/kotlin/<context>/`, NOT in `src/main` (production should never bypass invariants).

```kotlin
// src/test/kotlin/com/example/orders/InMemoryOrderRepository.kt
class InMemoryOrderRepository : OrderRepository {
    private val store = mutableMapOf<OrderId, Order>()

    override fun save(order: Order) {
        store[order.id] = order
    }

    override fun findById(id: OrderId): Order? = store[id]

    override fun findByCustomerId(customerId: CustomerId): List<Order> =
        store.values.filter { it.customerId == customerId }

    override fun delete(id: OrderId) {
        store.remove(id)
    }

    // Test-only conveniences (NOT part of the production port)
    fun clear() = store.clear()
    fun all(): List<Order> = store.values.toList()
}
```

**Discipline**:
- **Implement every method on the port.** If you `TODO()` one, the next test that hits it crashes with a useless message.
- **Respect the port's semantic contract.** If `findById` returns `Order?` in production, return `null` here; don't throw.
- **Add test-only conveniences (`clear`, `all`) below the override methods** — clearly separated. Don't expose them through the port type; access them through the concrete class.
- **No state in `src/main`** — the class is `src/test` only.

**Anti-pattern**: making `InMemoryOrderRepository` thread-safe / concurrency-aware. The acceptance test runs in one thread; concurrency belongs in `test-integration` against the real repository.

---

## 2. Recording event publisher

For services that publish domain events (Spring `ApplicationEventPublisher`, a custom `DomainEventPublisher`, Modulith events). The test-only publisher collects events into a list.

```kotlin
// src/test/kotlin/com/example/orders/RecordingEventPublisher.kt
class RecordingEventPublisher : DomainEventPublisher {
    private val _events = mutableListOf<DomainEvent>()
    val events: List<DomainEvent> get() = _events.toList()

    override fun publish(event: DomainEvent) {
        _events += event
    }

    fun clear() {
        _events.clear()
    }

    inline fun <reified E : DomainEvent> eventsOfType(): List<E> =
        events.filterIsInstance<E>()
}
```

**Pattern**:
- **Expose `events` as `List<DomainEvent>`** (immutable view), backed by a private `MutableList`. Tests cannot mutate the recorded log.
- **`clear()` for between-test reset**, called from `@BeforeEach` (or use a new instance per test).
- **`eventsOfType<E>()` helper** for asserting on a single event type when the use case publishes a mix.

**Spring-side adapter** (for Seam B): see `spring.md` for `@MockkBean` over `ApplicationEventPublisher` or Modulith's `PublishedEvents`.

---

## 3. Stub outbound adapter

For an outbound HTTP / messaging port. The stub is a Kotlin class implementing the port, with a small Given API.

```kotlin
// src/test/kotlin/com/example/orders/StubInventoryClient.kt
class StubInventoryClient : InventoryClient {
    private val responses = mutableMapOf<Sku, AvailabilityResponse>()
    private var defaultResponse: AvailabilityResponse? = null

    fun givenAvailability(sku: Sku, available: Int) {
        responses[sku] = AvailabilityResponse(sku, available)
    }

    fun givenDefaultUnavailable() {
        defaultResponse = AvailabilityResponse(Sku("any"), 0)
    }

    override fun checkAvailability(sku: Sku): AvailabilityResponse =
        responses[sku] ?: defaultResponse ?: error("StubInventoryClient: no response stubbed for $sku")
}
```

**Pattern**:
- **`given...` prefix** on the seeding methods — reads as the Given section of the test.
- **Explicit failure when no stub matches** (`error("...")`) — better than silently returning a default that might mask a missing-setup bug.
- The stub implements the **port**, NOT the underlying HTTP client (`RestTemplate`, `RestClient`). That's at the wrong level — would belong in a `@RestClientTest` (slice).

---

## 4. Fixture factories — richer than at the unit level

Unit-level fixtures build a single aggregate (`aDraftOrder()`, `aSubmittedOrder()` — see `clean-code-unit-tests/ddd-tests.md §4`). Acceptance-level fixtures **also populate the in-memory store** so the use case can find the aggregate.

```kotlin
// src/test/kotlin/com/example/orders/AcceptanceFixtures.kt
fun TestContext.givenDraftOrder(
    customerId: CustomerId = CustomerId(UUID.randomUUID()),
    lines: List<OrderLine> = listOf(anOrderLine()),
): Order {
    val draft = Order.draft(OrderId(UUID.randomUUID()), customerId).withLines(lines)
    orders.save(draft)
    return draft
}

fun TestContext.givenSubmittedOrder(
    customerId: CustomerId = CustomerId(UUID.randomUUID()),
    lines: List<OrderLine> = listOf(anOrderLine()),
    submittedAt: Instant = fixedClock.instant(),
): Order {
    val submitted = Order.draft(OrderId(UUID.randomUUID()), customerId)
        .withLines(lines)
        .submit(submittedAt)
    orders.save(submitted)
    return submitted
}

fun anOrderLine(
    sku: Sku = Sku("SKU-001"),
    quantity: Int = 1,
    unitPrice: Money = Money(BigDecimal("99.00")),
): OrderLine = OrderLine(sku, quantity, unitPrice)
```

Where `TestContext` is the test base class that holds `orders: InMemoryOrderRepository`, `events: RecordingEventPublisher`, `fixedClock: Clock` (see §6 below).

**Patterns**:
- **`givenDraftOrder` returns the Order** — the test captures the id for later assertions: `val draft = givenDraftOrder(...)`.
- **`given...` populates the in-memory store** as a side effect. The test body is the use case's Given, in one line.
- **Compose from the unit-level fixtures** — `givenSubmittedOrder` reuses the domain's `submit(...)` transition, so the in-memory state is *valid by construction*.
- **State-named factories** — `givenDraftOrder`, `givenSubmittedOrder`, `givenCancelledOrder`. The factory name signals the *starting state*; tests pick the one matching their Given.

---

## 5. The acceptance test base class (or test context)

Group the in-memory adapters + clock + use cases under test in one place. Each test extends or includes the context.

```kotlin
// src/test/kotlin/com/example/orders/OrderAcceptanceContext.kt
abstract class OrderAcceptanceContext {
    protected val orders = InMemoryOrderRepository()
    protected val events = RecordingEventPublisher()
    protected val inventory = StubInventoryClient()
    protected val fixedClock: Clock = Clock.fixed(
        Instant.parse("2026-01-15T10:00:00Z"),
        ZoneOffset.UTC,
    )

    protected val submitOrderUseCase = SubmitOrderUseCase(orders, events, inventory, fixedClock)
    protected val cancelOrderUseCase = CancelOrderUseCase(orders, events, inventory, fixedClock)

    @BeforeEach
    fun resetState() {
        orders.clear()
        events.clear()
    }
}
```

**Pattern**:
- **One context per bounded context** — reuse across all the bounded context's acceptance tests.
- **`@BeforeEach` resets state** between tests (or use a new instance per test if your runner supports per-method instance).
- **Use cases are wired here** — every acceptance test in the context sees the same wiring.
- **`fixedClock`** — determinism. `Clock.fixed(...)`; passes to every use case that needs time.

**Alternative — composition over inheritance**: a `TestContext` data class composed into each test. Pick whichever the team prefers; the structure is what matters.

---

## 6. Acceptance test — full Kotlin example (Seam A, in-memory)

```kotlin
// src/test/kotlin/com/example/orders/SubmitOrderAcceptanceTest.kt
class SubmitOrderAcceptanceTest : OrderAcceptanceContext() {

    @Test
    fun `given a draft Order with one line, submitting moves it to SUBMITTED and publishes OrderSubmitted`() {
        // Given
        val draft = givenDraftOrder(lines = listOf(anOrderLine()))

        // When
        val outcome = submitOrderUseCase.submit(SubmitOrderCommand(draft.id))

        // Then
        assertThat(outcome).isInstanceOf(Outcome.Submitted::class.java)
        assertThat(orders.findById(draft.id)?.status).isEqualTo(SUBMITTED)
        assertThat(events.events).containsExactly(
            OrderSubmitted(draft.id, at = fixedClock.instant()),
        )
    }

    @Test
    fun `given a draft Order with no lines, submitting is rejected and no event is published`() {
        val draft = givenDraftOrder(lines = emptyList())

        val outcome = submitOrderUseCase.submit(SubmitOrderCommand(draft.id))

        assertThat(outcome).isInstanceOf(Outcome.Rejected::class.java)
        assertThat(orders.findById(draft.id)?.status).isEqualTo(DRAFT)
        assertThat(events.events).isEmpty()
    }

    @Test
    fun `submitting the same Order twice with the same idempotency key returns the same response and publishes once`() {
        val draft = givenDraftOrder()
        val key = IdempotencyKey("k-123")

        val first = submitOrderUseCase.submit(SubmitOrderCommand(draft.id, idempotencyKey = key))
        val second = submitOrderUseCase.submit(SubmitOrderCommand(draft.id, idempotencyKey = key))

        assertThat(second).isEqualTo(first)
        assertThat(events.eventsOfType<OrderSubmitted>()).hasSize(1)
    }
}
```

Three tests, three concepts. Each reads as a user-story acceptance criterion. The DSL (`givenDraftOrder`, `submitOrderUseCase.submit`) hides the wiring noise. AssertJ + the recording publisher's `eventsOfType<E>()` give precise assertions on the published contract.

---

## 7. AssertJ on lists of events — custom assertions

For a use case that publishes multiple events, asserting on the list is the most important check. AssertJ's `containsExactly` (order-sensitive) and `containsExactlyInAnyOrder` (order-insensitive) cover the common cases.

```kotlin
assertThat(events.events).containsExactly(
    InventoryReserved(draft.id, fixedClock.instant()),
    OrderSubmitted(draft.id, fixedClock.instant()),
)
```

For a richer per-event assertion (subset matching, ignoring some fields), use AssertJ's `usingRecursiveComparison`:

```kotlin
assertThat(events.events).hasSize(2)
assertThat(events.eventsOfType<OrderSubmitted>().single())
    .usingRecursiveComparison()
    .ignoringFields("eventId", "timestamp")
    .isEqualTo(OrderSubmitted(orderId = draft.id, at = Instant.MAX))
```

For house-style readability, define a small custom assertion:

```kotlin
fun AbstractListAssert<*, *, DomainEvent, *>.containsEvent(event: DomainEvent): ObjectAssert<DomainEvent> {
    return extracting<Boolean> { it == event }
        .anySatisfy { assertThat(it).isTrue() }
        .let { this.first() as ObjectAssert<DomainEvent> }
}

// Usage
assertThat(events.events).containsEvent(OrderSubmitted(draft.id, fixedClock.instant()))
```

(Custom assertions live in the same context's `src/test/`; one custom assertion per recurring shape, not per test.)

---

## 8. Use-case-level test DSL — `givenX / whenY / thenZ`

The DSL emerges through three rounds of refactoring (see `general.md §9`). The end state for an order context:

```kotlin
// Given
fun givenDraftOrder(lines: List<OrderLine> = listOf(anOrderLine())): Order
fun givenSubmittedOrder(lines: List<OrderLine> = listOf(anOrderLine())): Order
fun givenAvailability(sku: Sku, available: Int)

// When
fun whenSubmitting(order: Order, idempotencyKey: IdempotencyKey? = null): Outcome
fun whenCancelling(order: Order, reason: String): Outcome

// Then
inline fun <reified E : DomainEvent> thenEventsPublished(vararg expected: E)
fun thenOrderIs(orderId: OrderId, status: OrderStatus)
inline fun <reified O : Outcome> thenOutcomeIs(actual: Outcome)
```

**A test using the DSL**:

```kotlin
@Test
fun `cancelling a submitted Order releases inventory and publishes OrderCancelled + InventoryReleased`() {
    val submitted = givenSubmittedOrder(lines = listOf(anOrderLine(sku = Sku("SKU-1"))))
    givenAvailability(Sku("SKU-1"), available = 10)

    val outcome = whenCancelling(submitted, reason = "customer requested")

    thenOutcomeIs<Outcome.Cancelled>(outcome)
    thenOrderIs(submitted.id, CANCELLED)
    thenEventsPublished(
        OrderCancelled(submitted.id, reason = "customer requested", at = fixedClock.instant()),
        InventoryReleased(submitted.id, sku = Sku("SKU-1"), quantity = 1, at = fixedClock.instant()),
    )
}
```

**Three lines per section.** Test reads as the user story. The DSL is per-bounded-context; do NOT generalise across contexts.

---

## 9. Coroutines / suspend use cases — `runTest`

When the application service is `suspend` (coroutine-based), use kotlinx-coroutines-test's `runTest` to drive it deterministically.

```kotlin
class SubmitOrderAcceptanceTest : OrderAcceptanceContext() {

    @Test
    fun `submit completes within the test scheduler`() = runTest {
        val draft = givenDraftOrder()

        val outcome = submitOrderUseCase.submit(SubmitOrderCommand(draft.id))   // suspend

        assertThat(outcome).isInstanceOf(Outcome.Submitted::class.java)
        assertThat(events.events).hasSize(1)
    }
}
```

For a use case that delays (e.g. retry with backoff), `runTest`'s virtual scheduler advances time without real waiting:

```kotlin
@Test
fun `retry-with-backoff completes after the virtual delay`() = runTest {
    val draft = givenDraftOrder()
    inventory.failsTwiceBeforeSucceeding()

    val outcome = submitOrderUseCase.submit(SubmitOrderCommand(draft.id))

    assertThat(currentTime).isEqualTo(/* expected virtual ms */)
    assertThat(outcome).isInstanceOf(Outcome.Submitted::class.java)
}
```

**Pattern**: pass `kotlinx.coroutines.test.TestScope`'s `coroutineContext` as the use case's dispatcher; use `currentTime` (in ms since test start) to assert on virtual elapsed time.

---

## 10. Kotest `BehaviorSpec` — when the team uses Kotest with BDD

Most teams use JUnit + Kotlin's backtick names; that reads well already. Some teams use **Kotest** with `BehaviorSpec` for explicit BDD flavour:

```kotlin
class SubmitOrderAcceptanceSpec : BehaviorSpec({
    val ctx = OrderAcceptanceContext.create()

    Given("a draft Order with one line") {
        val draft = ctx.givenDraftOrder(lines = listOf(anOrderLine()))

        When("the customer submits it") {
            val outcome = ctx.submitOrderUseCase.submit(SubmitOrderCommand(draft.id))

            Then("the Order is SUBMITTED and OrderSubmitted is published") {
                outcome.shouldBeInstanceOf<Outcome.Submitted>()
                ctx.orders.findById(draft.id)?.status shouldBe SUBMITTED
                ctx.events.events.shouldContainExactly(
                    OrderSubmitted(draft.id, at = ctx.fixedClock.instant()),
                )
            }
        }
    }
})
```

**Pros**: explicit `Given / When / Then` blocks; nested `When` blocks for variations; reads as a structured spec.
**Cons**: lambda-heavy; refactoring across `Given / When / Then` chains is fiddlier than JUnit; closing over mutable state requires care.

**House recommendation**: if the project is already on Kotest, `BehaviorSpec` is a fine choice for acceptance tests. If the project is on JUnit, **don't introduce Kotest just for the BDD flavour** — plain JUnit with sentence names is equally readable and doesn't add a dependency.

---

## 11. Cucumber-JVM / cucumber-kotlin — only when stakeholders read `.feature`

Restating the general-file recommendation: **default to plain JUnit**. Use Cucumber only when business stakeholders genuinely read and edit `.feature` files. If you do use it:

**`build.gradle.kts`**:
```kotlin
testImplementation("io.cucumber:cucumber-java:7.x")
testImplementation("io.cucumber:cucumber-junit-platform-engine:7.x")
testImplementation("io.cucumber:cucumber-spring:7.x")    // for @SpringBootTest integration
```

**`src/test/resources/features/submit-order.feature`**:
```gherkin
Feature: Submit Order
  Scenario: A draft order with at least one line is submitted successfully
    Given a draft Order with 1 line
    When the customer submits it
    Then the Order moves to SUBMITTED
    And OrderSubmitted is published
```

**`src/test/kotlin/com/example/orders/cucumber/SubmitOrderSteps.kt`**:
```kotlin
class SubmitOrderSteps(private val ctx: OrderAcceptanceContext) {

    private lateinit var draft: Order
    private lateinit var outcome: Outcome

    @Given("a draft Order with {int} line(s)")
    fun aDraftOrderWith(lineCount: Int) {
        draft = ctx.givenDraftOrder(lines = (1..lineCount).map { anOrderLine() })
    }

    @When("the customer submits it")
    fun submit() {
        outcome = ctx.submitOrderUseCase.submit(SubmitOrderCommand(draft.id))
    }

    @Then("the Order moves to {word}")
    fun orderStatusIs(status: String) {
        assertThat(ctx.orders.findById(draft.id)?.status?.name).isEqualTo(status)
    }

    @Then("OrderSubmitted is published")
    fun orderSubmittedIsPublished() {
        assertThat(ctx.events.eventsOfType<OrderSubmitted>()).hasSize(1)
    }
}
```

**Pattern**: step definitions delegate to the same DSL the JUnit tests use (`OrderAcceptanceContext`). The DSL is the shared layer; Cucumber adds the `.feature`-to-step-definition indirection on top.

**Caveats**:
- The Cucumber runner is slower than JUnit's; budget for it.
- Refactoring requires editing both `.feature` text and step regex.
- For Spring integration: `@CucumberContextConfiguration` + `@SpringBootTest` — but that means each scenario boots Spring; consider scope carefully.

**Net**: Cucumber on JVM is supported and works. It is not the recommendation unless the stakeholder-readability premise actually holds.

---

## 12. AssertJ vs Kotest matchers — pick one

The Kotlin ecosystem has two dominant assertion libraries:

- **AssertJ** — Java-origin, fluent, mature, excellent collection / event-list assertions. Used heavily in Spring projects.
- **Kotest assertions** — Kotlin-native, infix DSL (`shouldBe`, `shouldContain`), pairs with Kotest's runner.

Either works for acceptance tests. **Stick with whatever the project already uses.** Mixing both forces every reader to context-switch.

**AssertJ for an acceptance test:**
```kotlin
assertThat(events.events).containsExactly(OrderSubmitted(draft.id, fixedClock.instant()))
assertThat(orders.findById(draft.id)?.status).isEqualTo(SUBMITTED)
```

**Kotest for the same:**
```kotlin
events.events.shouldContainExactly(OrderSubmitted(draft.id, fixedClock.instant()))
orders.findById(draft.id)?.status shouldBe SUBMITTED
```

For *AssertJ on event lists*, the `containsExactly` / `containsExactlyInAnyOrder` / `extracting` / `usingRecursiveComparison` family is hard to beat for precision.

---

## 13. Smell → fix for Kotlin acceptance tests

| Smell | Fix |
|---|---|
| Test imports `MockKMatcherScope.every` and stubs `every { repository.save(any()) }` | Replace mock with `InMemoryOrderRepository`. Mock at the port; use a real implementation. |
| Test imports `MockKMatcherScope.every` and stubs the **aggregate** | Wrong unit. Mock the **ports**, not the aggregate. The aggregate IS the engine the test exercises. |
| Test sleeps for `Thread.sleep(2000)` | Use Awaitility (`await().atMost(2.seconds).until { ... }`) or refactor to a deterministic seam (callback, suspend function). |
| Test uses `Instant.now()` | Inject `Clock.fixed(...)`; pass through the use case. |
| Test fixture builders in `src/main` | Move to `src/test`. Production code should never bypass invariants. |
| 25 `@Test` methods covering every variation of one use case | Pull variations down to unit tests; keep one happy path + one canonical error per use case at the acceptance tier. |
| 25-line Given block | Extract `givenDraftOrder(...)` / `givenSubmittedOrder(...)` etc.; test body should be 3-6 lines. |
| Two acceptance tests share an `@BeforeEach` populating state | OK if all tests need it; otherwise prefer explicit `given...` in the test body for the variations. |
| Acceptance test asserts on `verify { eventPublisher.publish(...) }` | Use `RecordingEventPublisher.events` and AssertJ `containsExactly` — observable outcome, not method-call verification. |
| Two `RecordingEventPublisher`s in one test class (Spring's `ApplicationEventPublisher` + a custom one) | One source of truth — pick the production publisher type, record at that level. |
| `runTest { }` wrapped around a synchronous use case | Drop `runTest`; only suspend code needs the test scheduler. |
| Kotest `BehaviorSpec` in a JUnit codebase, or vice versa | Conform to the project default. Mixing harms readability more than the BDD flavour gains. |
| Cucumber `.feature` files written but never read by anyone outside dev | Migrate to plain JUnit; delete Cucumber dependency. The premise of Cucumber's value isn't met. |

---

## 14. Summary — Kotlin idioms for acceptance tests

| Concern | Kotlin idiom |
|---|---|
| In-memory adapter | Plain Kotlin class implementing the port, `mutableMapOf`-backed, in `src/test`. |
| Recording event publisher | Plain Kotlin class, immutable `events` view over a `MutableList`. |
| Stub outbound HTTP | Plain Kotlin class implementing the port; `given...` seeding methods. |
| Fixture factories | `given...` extension functions on the test context, returning the constructed aggregate, side-effecting the in-memory store. |
| Test context | Base class or composed `TestContext` data class holding adapters + clock + use cases; `@BeforeEach` resets state. |
| Deterministic time | `Clock.fixed(Instant.parse("..."), UTC)` injected via the test context. |
| Coroutines | `runTest { }` from kotlinx-coroutines-test; virtual scheduler for delays. |
| BDD style | Backtick test names with sentence Given / When / Then; Kotest `BehaviorSpec` only if Kotest is the project default. |
| Cucumber | Only when stakeholders genuinely read `.feature` files. Otherwise plain JUnit. |
| Assertions | AssertJ or Kotest matchers — pick one; AssertJ is the Spring-project default and shines for event-list assertions. |
