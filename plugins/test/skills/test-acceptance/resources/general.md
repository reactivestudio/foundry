# Acceptance Tests — Language-Agnostic Discipline

The principles in this file apply equally to a Kotlin/Spring service, a Go HTTP service, a Python FastAPI service, a Node.js Express service. The acceptance-test layer is about **use cases through application service boundaries** — a concept independent of language and framework. The Kotlin / Spring specifics live in `kotlin.md` and `spring.md`.

> "Acceptance tests describe the *what*. Unit tests describe the *how*. Integration tests describe the *whether-it-wires*. Acceptance is the only layer where the test reads like the user story — because it IS the user story." — house ethos

---

## 1. The house definition (restated)

> An **acceptance test** is one test that exercises **one use case** end-to-end through the **application service boundary**, with infrastructure either replaced by **in-memory adapters** or booted **narrowly** (real DB via Testcontainers / equivalent; external HTTP stubbed). It asserts on the **observable outcome of the use case**: state changes, events published, HTTP responses. It does NOT assert on per-rule mechanics (that's unit) and does NOT include real external dependencies (that's e2e).

Three properties make a test "acceptance" rather than "unit" or "integration":

1. **The unit is the use case.** Not a class, not a layer, not a method — a *use case*. "Submit an order." "Cancel a reservation." "Settle an invoice." The acceptance test names the use case in its title; the body executes it.
2. **The entry is the application service.** Not the controller (that's a slice concern); not the aggregate directly (that's a unit concern). The application service is what *implements* a use case in a hexagonal / clean architecture. The test calls it directly (Seam A) or through HTTP that routes to it (Seam B).
3. **Externals are not real.** No real Postgres in production-cluster mode (Testcontainers is fine — that's still local). No real Stripe. No real Kafka cluster from another team. No real OAuth provider. If the test calls a real external system, it's an e2e test, not an acceptance test.

Anything else — naming, tooling, Gherkin or not, Seam A or Seam B — is a tactical choice.

---

## 2. Vocabulary disambiguation

The word "acceptance test" carries baggage from different communities. Be explicit about which is meant.

| Term | What it usually means | Relation to this skill |
|---|---|---|
| **Acceptance test** (this skill) | One use case end-to-end through the application service, in-memory or narrow. | This skill's exact subject. |
| **Use-case test** | Synonym for acceptance test in many DDD / hexagonal codebases. | Same thing; pick "acceptance" as the house word. |
| **Feature test** | Often interchangeable; sometimes scoped to "one feature" rather than "one use case". | Treat as a synonym. |
| **Story test** | A test written *from* a user story's acceptance criteria. Often Gherkin-flavoured. | Subset of acceptance tests; this skill includes them. |
| **BDD test** | Tests written in the BDD style (Given / When / Then). Can be Gherkin or plain. | Style, not a layer — see §6 below. |
| **Gherkin / Cucumber test** | Acceptance / story test written in the Gherkin language, executed via Cucumber. | Tool, not a layer — see §7 below. |
| **End-to-end test** (e2e) | Test against real external dependencies + the deployed environment. | OUTSIDE this skill — see `test-strategy → inverted-pyramid`. |
| **Smoke test** | Lightweight test that the system boots / basic happy path works. | Overlaps with acceptance — one Seam-B test often doubles as a smoke. |
| **Integration test** (in some shops) | Sometimes used to mean what this skill calls acceptance ("the use case integrated"). | Avoid the conflation; integration in this skill family means per-slice / per-adapter (`test-integration`). |

**House terminology**: this skill uses "acceptance test" as the canonical name. "Use-case test" is a synonym. Everything else is either a subset (story test), a style (BDD), a tool (Cucumber), or a different layer (e2e, smoke, slice).

---

## 3. Hexagonal / ports-and-adapters framing

Acceptance tests are clearest in a **hexagonal architecture** (ports and adapters; clean architecture). The application service is the hexagon's edge inward; its **ports** are interfaces declared in the domain / application layer:

```
                                ┌─────────────────────────────┐
   HTTP controller (adapter) ──►│                             │
                                │   Application service       │
   Kafka consumer (adapter)  ──►│   (uses domain aggregates)  │
                                │                             │◄── Domain
                                └──┬───────────────────┬──────┘
                                   │                   │
                          ┌────────▼────────┐ ┌────────▼────────┐
                          │  Repository     │ │  EventPublisher │   ← ports
                          │  (interface)    │ │  (interface)    │
                          └────────┬────────┘ └────────┬────────┘
                                   │                   │
                          ┌────────▼────────┐ ┌────────▼────────┐
                          │  JpaOrderRepo   │ │  SpringEventPub │   ← production adapters
                          │  (Postgres)     │ │  + Modulith     │
                          └─────────────────┘ └─────────────────┘
```

In **production**, ports are implemented by infrastructure adapters: `JpaOrderRepository`, `SpringApplicationEventPublisher`. In an **acceptance test (Seam A)**, the same ports are implemented by **test-only in-memory adapters**: `InMemoryOrderRepository`, `RecordingEventPublisher`. The application service doesn't know the difference — that's the point of the port. The acceptance test reverses the dependency arrow: production uses the production adapters; the test plugs in the test adapters.

**The acceptance test of "submit an order" wires this:**

```
   Test                    ┌─────────────────────────────┐
   ──── submit(cmd) ──────►│   Application service       │
                           └──┬───────────────────┬──────┘
                              │                   │
                     ┌────────▼────────┐ ┌────────▼────────┐
                     │ InMemoryOrderRepo│ │ RecordingEventPub│
                     └────────┬────────┘ └────────┬────────┘
                              │                   │
                              └──── asserted on by the test ───►
```

**Seam B (narrow `@SpringBootTest`)** uses the production adapters for the DB (Testcontainers gives real Postgres) and replaces only the outbound-HTTP adapter with a stub (`@MockkBean` or WireMock). The application service still doesn't know — the substitution is at the bean level.

---

## 4. The in-memory adapter patterns

### 4a. In-memory repository

A test-only class implementing the domain repository port. Stores aggregates in a `Map`; the Given populates it, the Then queries it. The implementation must respect the port's semantic contract (returning `null` / `Optional.empty()` for missing, throwing the right exception on save failure if the port specifies one), but otherwise it's the minimum code that satisfies the contract.

```kotlin
class InMemoryOrderRepository : OrderRepository {
    private val store = mutableMapOf<OrderId, Order>()
    override fun save(order: Order) { store[order.id] = order }
    override fun findById(id: OrderId): Order? = store[id]
    override fun findByCustomerId(id: CustomerId): List<Order> =
        store.values.filter { it.customerId == id }
}
```

**Why a class, not a Mockk mock**: a real implementation of the port lets the test populate state in the Given and inspect it in the Then *symmetrically*. A mock would require `every { repo.findById(any()) } returns ...` per test — that's mock setup, not Given-state. A real-but-in-memory implementation also catches bugs the production code would hit only at runtime (e.g. "the application service calls `findById` *before* `save` — the in-memory `null` makes this visible immediately").

**Where the class lives**: `src/test/` of the bounded context that owns the port. Reusable across all the acceptance tests of that context. NOT in `src/main/` — production code should never bypass its own invariants.

### 4b. Recording event publisher

A test-only `ApplicationEventPublisher` / `DomainEventPublisher` that collects published events into a list. The Then asserts on the list — order, count, payload.

```kotlin
class RecordingEventPublisher : DomainEventPublisher {
    val events: MutableList<DomainEvent> = mutableListOf()
    override fun publish(event: DomainEvent) { events += event }
    fun clear() { events.clear() }
}
```

**Use it for** every acceptance test that exercises a use case publishing domain events (which, in an event-driven service, is most of them). The recorded list IS the published contract for the rest of the system.

### 4c. Stub adapter for outbound HTTP

For an outbound HTTP port (e.g. `InventoryClient`, `PaymentGateway`), the test-only adapter returns canned responses. Two flavours:

- **In-memory stub** — a Kotlin class with `var nextResponse: Response` or a map of `request → response`. Use for Seam A where speed matters.
- **WireMock** — a HTTP server stubbed at the wire level. Use for Seam B where the HTTP layer is part of what's being tested.

```kotlin
class StubInventoryClient(private val responses: MutableMap<Sku, AvailabilityResponse> = mutableMapOf()) : InventoryClient {
    fun givenAvailability(sku: Sku, available: Int) {
        responses[sku] = AvailabilityResponse(sku, available)
    }
    override fun checkAvailability(sku: Sku): AvailabilityResponse =
        responses[sku] ?: AvailabilityResponse(sku, 0)
}
```

**Anti-pattern**: stubbing the outbound HTTP at the `RestTemplate` / `RestClient` level inside an acceptance test. That's adapter-level — belongs in a `@RestClientTest` (slice; see `test-integration`). The acceptance test stubs at the **port** level — one level higher.

---

## 5. Acceptance criteria → executable specs

User stories have acceptance criteria. The acceptance test is the **executable form** of those criteria. The translation is mechanical when both are written well.

**User story:**

```
As a customer
I want to submit my draft order
So that the warehouse can prepare it

Acceptance criteria:
- Given a draft Order with at least one line
  When the customer submits it
  Then the Order is moved to SUBMITTED
  And OrderSubmitted is published
  And the API returns 201 Created with a Location header pointing to the order

- Given a draft Order with no lines
  When the customer attempts to submit it
  Then the Order remains DRAFT
  And no event is published
  And the API returns 422 Unprocessable Entity with field=lines
```

**Two acceptance tests** (one per criterion). The first is the happy path; the second is one canonical error path. Per-rule variations ("what if the line quantity is negative?") are unit tests of `OrderLine` — NOT additional acceptance tests.

```kotlin
@Test
fun `submitting a draft Order with one line moves it to SUBMITTED and publishes OrderSubmitted`() {
    // Given
    val draft = givenDraftOrder(lines = listOf(anOrderLine()))

    // When
    val outcome = submitOrderUseCase.submit(SubmitOrderCommand(draft.id))

    // Then
    assertThat(outcome).isInstanceOf(Outcome.Submitted::class.java)
    assertThat(orders.findById(draft.id)?.status).isEqualTo(SUBMITTED)
    assertThat(events.events).containsExactly(
        OrderSubmitted(draft.id, at = fixedClock.instant())
    )
}

@Test
fun `submitting a draft Order with no lines is rejected and no event is published`() {
    val draft = givenDraftOrder(lines = emptyList())

    val outcome = submitOrderUseCase.submit(SubmitOrderCommand(draft.id))

    assertThat(outcome).isInstanceOf(Outcome.Rejected::class.java)
    assertThat(orders.findById(draft.id)?.status).isEqualTo(DRAFT)
    assertThat(events.events).isEmpty()
}
```

**Pattern**: one test name = one criterion, sentence-cased, ubiquitous-language. The body reads as the criterion.

---

## 6. The outside-in TDD flow — in detail

Outside-in TDD makes the acceptance test the **driver** of implementation. The flow is sometimes called *London-school TDD* or *double-loop TDD*; the outer loop is the acceptance test, the inner loop is the unit-test cycle.

**The double loop:**

```
   Outer loop:
   ┌──────────────────────────────────────────────────────────┐
   │  Write failing acceptance test (use case in plain English)│
   │                                                          │
   │  ┌──────────── Inner loop ──────────────────────────────┐│
   │  │  Acceptance fails at line X                          ││
   │  │     → Write failing unit test for what's missing     ││
   │  │     → Implement the production code (3 Laws of TDD)  ││
   │  │     → Unit test goes green                            ││
   │  │     → Refactor; unit + acceptance both green          ││
   │  │     → Re-run acceptance; fails at next missing piece  ││
   │  └──────────────────────────────────────────────────────┘│
   │  Acceptance test goes green from the inside out          │
   │  Refactor at the use-case level; both loops still green  │
   └──────────────────────────────────────────────────────────┘
```

**Concrete walk-through** for "submit an order":

1. Write the acceptance test. Uses `submitOrderUseCase.submit(SubmitOrderCommand(...))` — which doesn't exist yet. **Fails to compile.**
2. Create `SubmitOrderCommand` and `SubmitOrderUseCase` as empty shells. Test now compiles but **fails on the first assertion**: `orders.findById(draft.id)?.status` is `null` because the use case is a no-op.
3. Step inward. Write a unit test for the application service: *"submit calls `Order.submit(at)` on the loaded aggregate and saves it"*. Use `mockk` (or a real in-memory repo) and assert.
4. Implement `SubmitOrderUseCase.submit` to load the order, call `order.submit(clock.instant())`, save. Unit test passes.
5. Re-run acceptance. Now `findById` returns a SUBMITTED order. Next assertion: `events.events containsExactly OrderSubmitted(...)`. **Fails — the event isn't published.**
6. Step inward. Unit test: *"submit publishes the order's pending events via the publisher"*. Implement; passes.
7. Re-run acceptance. All assertions pass. **Refactor**: extract a `flushEvents` helper from the use case if the publishing pattern repeats.

**The acceptance test is the goal**. The unit tests are how you got there. After this cycle:

- The acceptance test proves *the use case works*.
- The unit tests carry *the per-rule coverage* (the test for `Order.submit` rejecting empty lines, the test for the publisher being called in order, the test for `clock.instant()` being used, etc.).
- The acceptance test does NOT replicate any of those per-rule assertions — it only checks the use-case outcome.

**This is the canonical TDD flow for use-case-driven development.** It pairs naturally with hexagonal architecture (Seam A is fast) and with the `methodology` skill's §4 verifiable-success-criteria discipline — the acceptance test IS the criterion.

For per-test TDD discipline (Three Laws, when to bend), see `test-principles → resources/tdd-discipline.md`.

---

## 7. BDD `Given / When / Then` at the use-case level

`Given / When / Then` is the natural rhythm of an acceptance test. It is the SAME structure as BUILD-OPERATE-CHECK at the per-test level (`test-principles`), applied at a different granularity:

- **Per-test BUILD-OPERATE-CHECK**: each individual test has three sections.
- **Use-case-level Given / When / Then**: the *whole acceptance test* is the Given / When / Then of *the use case*. The user-story acceptance criterion becomes the test name + body.

```kotlin
@Test
fun `given a draft Order with one line, when the customer submits it, OrderSubmitted is published and the API returns 201`() {
    // Given — the use-case precondition (matches the user story)
    val draft = givenDraftOrder(lines = listOf(anOrderLine()))

    // When — the use-case trigger
    val response = mockMvc.post("/api/v1/orders/${draft.id}/submit") { /* ... */ }

    // Then — the use-case outcome
    response.andExpect { status { isCreated() } }
    assertThat(events.events).containsExactly(OrderSubmitted(draft.id, fixedClock.instant()))
    assertThat(orders.findById(draft.id)?.status).isEqualTo(SUBMITTED)
}
```

The test name is the criterion. The body is the executable form. The structure is so transparent that a non-developer can read it.

**Without Gherkin**, you can still write BDD-style acceptance tests in plain JUnit / pytest / mocha — and on the JVM, that's typically the right choice. The structure is the discipline; the syntax is incidental.

---

## 8. Gherkin / Cucumber — when it pays, when it doesn't

Cucumber adds a separate `.feature` file in Gherkin syntax, with step definitions in Java / Kotlin / etc. that map `Given a draft Order with one line` to executable code.

```gherkin
# orders.feature
Feature: Submit Order

  Scenario: A draft order with at least one line is submitted successfully
    Given a draft Order with 1 line
    When the customer submits it
    Then the Order moves to SUBMITTED
    And OrderSubmitted is published
```

**Pros**:
- **Stakeholders can read AND edit `.feature` files** without touching code. If your product owner / domain expert genuinely participates in writing scenarios, this is high-leverage — the test IS the spec.
- The step definitions force a **shared vocabulary** between business and dev — bad domain terms get caught early.
- Tooling: Cucumber HTML reports, IDE plugins, scenario tagging.

**Cons**:
- **Indirection**: a one-line scenario in `.feature` requires a step definition in `.kt` that wires the actual call. Two files per concern instead of one. Refactoring a test requires touching both.
- **Step explosion**: with hundreds of scenarios, the step-definition library becomes its own subsystem. Reuse across scenarios is hard; over-general steps create coupling.
- **Worse IDE / refactoring support**: renaming a domain term means renaming both the Gherkin text and the step regex. Plain JUnit gets compile-time refactoring.
- **Slower**: Cucumber's runner adds overhead per scenario.
- **Stakeholders rarely actually read them** — that's the killer one. In most teams, the `.feature` files end up dev-maintained, dev-read, dev-edited. The premise of Cucumber's value evaporates.

**Decision rule** (house default):

> **Use Cucumber if and only if** business stakeholders genuinely read and edit `.feature` files. **In doubt: don't.** Plain JUnit / pytest / mocha with backtick names / sentence-cased descriptions reads better for dev-only teams and avoids the indirection.

**If you do use Cucumber**, scope it to the **highest-level use cases** only — not as a replacement for unit tests. One `.feature` per bounded context, one scenario per critical use case. Don't write 200 Gherkin scenarios; write 10 well-chosen ones.

The Kotlin / Spring specifics (cucumber-jvm, cucumber-kotlin) are touched on in `kotlin.md` — but the recommendation is the same: default to plain JUnit; reach for Cucumber only when the stakeholder-readability premise actually holds.

---

## 9. Use-case-level test DSL

The same DSL discipline from `test-principles` applies — but at the use-case level the DSL is richer. The Given populates an **in-memory store** (not just a value); the When invokes the **application service** (not a domain method); the Then asserts on **events + state + HTTP response**.

The DSL emerges through three rounds:

1. **Round 1 (copy-paste)**. Write the first acceptance test inline. Test reads ok; setup is verbose.
2. **Round 2 (extract)**. Three more acceptance tests share the same Given pattern. Extract `givenDraftOrder(lines = ...)` — populates the in-memory repository and returns the Order.
3. **Round 3 (name)**. The DSL has matured: `givenDraftOrder`, `givenSubmittedOrder`, `whenSubmitting(order)`, `thenEventsPublished(...)`. Test bodies are short and read as the user story.

**Bad** (verbose):
```kotlin
@Test
fun `submitting publishes`() {
    val order = Order.draft(OrderId(UUID.randomUUID()), CustomerId(UUID.randomUUID()))
        .withLine(OrderLine(Sku("SKU-001"), 1, Money("99.00")))
    orders.save(order)
    val cmd = SubmitOrderCommand(order.id, listOf(SubmitOrderLine(Sku("SKU-001"), 1)))
    val response = useCase.submit(cmd)
    assertThat(response).isInstanceOf(Outcome.Submitted::class.java)
    assertThat(events.events.first()).isInstanceOf(OrderSubmitted::class.java)
    // ... 8 more lines
}
```

**Good** (DSL):
```kotlin
@Test
fun `submitting a draft Order with one line publishes OrderSubmitted`() {
    val draft = givenDraftOrder(lines = listOf(anOrderLine()))

    val outcome = whenSubmitting(draft)

    thenOutcomeIs<Outcome.Submitted>(outcome)
    thenEventsPublished(OrderSubmitted(draft.id, fixedClock.instant()))
}
```

The DSL is **per-bounded-context** code in `src/test/`; do NOT generalise it across contexts (each context's ubiquitous language is its own).

---

## 10. Isolation between acceptance tests

Each acceptance test must run from a clean state. For Seam A, this is free: a new in-memory repository per test. For Seam B, it requires discipline:

- **Truncate the DB between tests** — `TRUNCATE TABLE … RESTART IDENTITY CASCADE` is faster than dropping/recreating the schema.
- **Reset stubs** — `WireMock.reset()`, `clearAllMocks()` for MockK, `reset(mockedBean)` for Mockito. Otherwise yesterday's stub fires for today's test.
- **Reset `RecordingEventPublisher.events`** between tests (or use a new instance per test).
- **Fixed clock** — every acceptance test injects a `Clock.fixed(...)`; never relies on `Instant.now()`. Tests are deterministic.

For per-test independence rules see `test-principles → F.I.R.S.T. → Independent`.

---

## 11. Acceptance tests vs the layers below — quick mapping

| Concern | Layer | Skill |
|---|---|---|
| `Order` aggregate's `submit()` invariant: empty lines rejected | Unit (domain) | `test-unit` |
| `Money.plus()` is commutative | Unit (value object) | `test-unit` |
| `OrderEntity` round-trips correctly through Postgres | Integration (`@DataJpaTest`) | `test-integration` |
| `POST /orders` with invalid body returns 422 | Integration (`@WebMvcTest`) | `test-integration` |
| `InventoryClient` builds the right URL and parses 200 / 404 | Integration (`@RestClientTest`) | `test-integration` |
| Submitting a draft Order publishes OrderSubmitted and the read model updates | **Acceptance** | **`test-acceptance`** (this skill) |
| Cancel-Order use case orchestrates Order + Inventory releases and publishes both events | **Acceptance** | **`test-acceptance`** (this skill) |
| Idempotent retry of submit returns the same response and publishes once | **Acceptance** | **`test-acceptance`** (this skill) |
| `OrderSubmittedEvent` matches the OrderProjector consumer's expected schema | Contract | `test-contract` |
| The deployed system in staging actually works against real Stripe | E2E (rarely chosen) | `test-strategy → inverted-pyramid` |

If you're writing a test and it doesn't fit one of these rows cleanly, the layer-allocation is probably wrong — re-read `test-strategy → what-test-where.md`.

---

## 12. Anti-patterns (language-agnostic)

- **Acceptance test asserts on a specific internal call** — `verify { repository.save(any()) }`. The acceptance test should assert on the **outcome** (state, events, response), not the mechanism. Move that assertion to the unit test of the application service if it matters.
- **Acceptance test mocks the aggregate** — see `SKILL.md → Anti-patterns`. Wrong unit.
- **Acceptance test has 25 assertions** — one mega-test. Split.
- **Acceptance test reuses the production app config unchanged** — externals enabled, retries on, async on. Use `@ActiveProfiles("test")` / equivalent and stub externals.
- **`Thread.sleep` in async use-case tests** — use Awaitility / polling on a real condition.
- **No fixed clock** — use-case test non-deterministic. Inject `Clock`.
- **In-memory adapter + `@SpringBootTest` in the same test** — pick one seam.
- **The acceptance test doesn't fail when the use case is broken** — the assertions are too weak. Tighten them; or the seam is too coarse and the bug is below the test's resolution.
- **Acceptance test is the only test for a use case** — no unit tests below it. The acceptance test passes, but a refactor breaks a per-rule invariant and the acceptance test misses it because it asserts only on the *use-case outcome*, not on each rule. Outside-in TDD prevents this by construction; bolting on acceptance tests after the fact does not.
- **The acceptance suite has 50 tests covering every variation of every use case** — wrong layer. Per-variation belongs at unit / slice. Acceptance covers the use case end-to-end, ONE happy path per use case, ONE representative error path. The total count for a moderate-complexity service is 5-15.

---

## 13. Summary — the acceptance-test shape

| Aspect | Acceptance test |
|---|---|
| Unit of the test | One use case (not a class, not a layer). |
| Entry point | Application service (directly via Seam A; via HTTP routing in Seam B). |
| Externals | In-memory adapters OR narrow boot with stubs / WireMock. NEVER real external systems. |
| What it asserts on | State (via in-memory repo or real DB query) + events (via recording publisher or `PublishedEvents`) + HTTP response (in Seam B). |
| Speed | Seam A: tens of ms. Seam B: 2-5 s per test. Both Fast *for the acceptance tier*. |
| Count | 5-15 for a Pyramid / Diamond service. Centre of gravity for Honeycomb. |
| Writes when? | Outside-in TDD: first. After implementation: less valuable but still possible (regression net). |
| Style | BDD `Given / When / Then` at the use-case level. Plain JUnit / pytest / etc. with sentence names; Cucumber ONLY when stakeholders read the `.feature` files. |
| Drives | Inner unit tests (outside-in) — and through them, the production code. |
| Does NOT cover | Per-rule invariants (unit), per-adapter mapping (integration), cross-service contracts (contract), real-environment e2e (rare). |
