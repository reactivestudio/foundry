# Integration Testing — General (Language-Agnostic) Discipline

What "integration" means at this layer, the deployment-seam principle, real-infrastructure-over-substitutes, isolation strategies, async, stubbing, fixtures. Applies equally to Kotlin, Python, Go, Node, Rust integration tests; Spring-specific patterns live in `spring.md`, Kotlin tooling in `kotlin.md`.

---

## 1. What "integration test" actually means at this layer

The word "integration" is overloaded. In this skill it has a specific meaning:

> **An integration test exercises production code wired to *real* infrastructure at the seam under test.**

It is **not**:

- An end-to-end test (whole user journey across multiple services).
- A unit test that happens to touch two classes.
- A `@SpringBootTest` that loads the whole context to check one repository method.
- A test that swaps in a fake / embedded / in-memory substitute for the production dependency.

It **is**:

- A repository test against the real database engine (Postgres, Mongo, etc., via Testcontainers).
- A controller test through the real HTTP stack (MockMvc / WebTestClient over the Spring MVC pipeline).
- A Kafka producer test that publishes to a real Kafka broker and reads back as a real consumer.
- An adapter test (in hexagonal terms): the production adapter class wired to the real external system.

The unit of "integration" is **one seam, with real infrastructure on the far side of that seam**. Not "everything", not "two classes".

---

## 2. The deployment-seam principle

Why does the integration tier exist? Because there is a class of bugs that **cannot be caught by unit tests no matter how thorough**:

- The JPA mapping is wrong — the column name on the entity doesn't match the column in the database.
- The JSONB query uses a Postgres operator (`@>`) that the in-memory substitute doesn't implement.
- The Flyway migration applies cleanly on H2 but fails on Postgres because of a Postgres-only constraint.
- The Kafka consumer is registered with the wrong `groupId` so messages skip it.
- The `@TransactionalEventListener(AFTER_COMMIT)` listener never fires in tests because the test's tx rolls back.
- The Spring Security filter chain rejects all requests in `@WebMvcTest` because security defaults engaged.
- The HTTP client doesn't follow redirects and the third-party API uses one.
- The serialiser writes `Instant` as a Unix timestamp; the consumer expects ISO-8601.

**Each of these bugs lives at a deployment seam — the boundary between your code and an external system / framework.** Unit tests stop at that boundary by definition (the boundary is mocked / faked). Integration tests cross that boundary on purpose.

The principle:

> **For every deployment seam where production could break in a way unit tests miss, there must be at least one integration test that crosses that seam with real infrastructure.**

Common seams that earn integration tests:

| Seam | Why unit tests can't catch it | What integration tests catch |
|---|---|---|
| ORM ↔ Database | Mocks don't run the SQL | Wrong column name, wrong cascade, JSONB operator behaviour |
| Controller ↔ HTTP stack | Mocks don't go through filters / validation / serialisation | 415 vs 422, missing `@Valid`, security default deny |
| Service ↔ Message broker | Mocks don't replicate partition assignment / delivery semantics | Wrong serializer, missing groupId, ack mode |
| App ↔ Outbound HTTP API | Mocks don't follow redirects / TLS / retries | Header missing, body format wrong, timeout too low |
| Tx-spanning code ↔ Event listener | Mocks don't replicate `AFTER_COMMIT` semantics | Listener never fires under rollback |
| Migration tool ↔ DB | Mocks don't actually run DDL | Migration syntax incompatible with Postgres / Mongo version |

Every one of these is a real production bug that has shipped because the team had "unit coverage" but no integration test crossing the seam.

---

## 3. The real-infrastructure mantra

> **Never substitute infrastructure with a fake unless the fake is the production substitute.**

Anti-patterns and why they fail:

- **H2 for Postgres.** H2 silently accepts most SQL but disagrees about JSONB, MERGE, RETURNING, ranges, partial / expression indexes, MVCC behaviour. The H2 test passes; the prod query fails. The bug is found by a customer.
- **Embedded Kafka for Apache Kafka.** The embedded broker is missing rebalance logic, consumer-group semantics, retention. The unit-test consumer "works", the prod consumer never picks up the message because the listener wiring is subtly different.
- **fakeredis for Redis.** Missing Lua scripting, missing `WAIT`, simplified expiry behaviour. The eviction test passes; the prod cache leaks.
- **In-memory MongoDB for MongoDB.** No replica set → no transactions; aggregation pipeline operators are partial. The aggregation test passes; the prod query returns wrong results.
- **WireMock for itself.** Wait, this is fine. WireMock is *for* stubbing — the production code talks to whatever URL it's configured with; WireMock just answers as the production HTTP API would. Stubbing the external system is fine; substituting the database with a different database is not.

The line: **substitute the things you don't control (third-party APIs, services owned by other teams) with stubs. Use real instances of the things your production runs on (your databases, your brokers, your caches).**

Testcontainers is the practical answer for the second category: it gives you a real instance of the production engine, ephemerally, in any test environment.

---

## 4. Test isolation patterns — three strategies

Integration tests by definition share infrastructure (the container is started once; many tests run against it). Isolation between tests is a discipline, not a free property.

### 4a. Per-test transaction rollback

Each test runs inside a transaction; the transaction is rolled back at the end. The database returns to its pre-test state.

```
@BeforeEach: BEGIN
@Test: writes happen inside the tx
@AfterEach: ROLLBACK
```

**Pros**: zero cleanup code; fast (no I/O for cleanup); guaranteed isolation.

**Cons**: **only works for code that runs inside the test's transaction**. Code that crosses transaction boundaries (events committed in a `REQUIRES_NEW` nested tx, async handlers in a separate tx) is committed to the DB *behind the rollback's back* — your test still sees the data is gone (it rolled back), but the *next* test sees a polluted DB.

Use it for: read-side / query-only tests, single-tx repository tests.

Don't use it for: write-side flows with events, multi-tx scenarios, outbox-pattern tests, async-handler tests.

### 4b. Truncate-and-seed between tests

Each test starts with the DB explicitly cleaned (`TRUNCATE TABLE ... RESTART IDENTITY CASCADE` or equivalent). The test seeds whatever it needs; cleanup runs again before the next test.

```
@BeforeEach: TRUNCATE all relevant tables
@Test: writes happen, commit happens
@AfterEach (or next @BeforeEach): TRUNCATE again
```

**Pros**: works for any code, including cross-tx flows; explicit, easy to debug.

**Cons**: slower than rollback (truncates do real I/O); sensitive to table list (forget one, get cross-test pollution); cascade can be tricky.

Use it for: write-side flows, event / outbox tests, async-handler tests, anything that crosses tx boundaries.

### 4c. Namespace-per-test (data partitioning)

Each test inserts data under a unique namespace (random `tenantId`, random `customerId` UUID, random prefix). Tests don't clean up; they query only their own namespace.

**Pros**: tests can run in parallel against the same container; no `TRUNCATE` overhead; great for read-heavy suites.

**Cons**: requires every query to include the partition predicate (a discipline failure pollutes other tests); DB grows over a long test run; not all production code can be coerced into namespace-keyed queries.

Use it for: parallelisable read-side suites, projection / view tests, multi-tenant systems where the namespacing already exists in production.

### 4d. Container-per-test (extreme isolation)

Each test class (or each test method) starts its own container. Strongest isolation; slowest by far.

**Pros**: perfect isolation; trivial mental model.

**Cons**: container start-up dominates the test time; CI runs much longer; many tests share nothing.

Use it for: tests that legitimately need a fresh state (testing the bootstrap, testing initial migrations from empty); never as a default.

### Decision

| Test type | Default strategy |
|---|---|
| Repository query (read) | Transaction rollback |
| Repository CRUD (single tx) | Transaction rollback |
| Write + event listener | Truncate-and-seed |
| Outbox / cross-tx | Truncate-and-seed |
| Parallel read suite | Namespace-per-test |
| Bootstrap / migration test | Container-per-test |

---

## 5. Async / eventual consistency — Awaitility over `Thread.sleep`

Integration tests that touch async code (event handlers, projection rebuilds, ES indexing latency, Kafka consumer lag) cannot assert immediately — there's a window between *publish* and *observable*. The temptation is `Thread.sleep(X)`. **Don't.**

- Too short → flaky on slow CI.
- Too long → slow on dev.
- No middle ground.

The correct pattern is **poll until-asserted, with a timeout**:

```
poll every 100ms, up to 5 seconds:
    fetch projection
    if projection.status == "PLACED": assert and return
fail with "projection never reached PLACED within 5s"
```

Awaitility (Java) and its Kotlin DSL extension is the standard:

```kotlin
await()
    .atMost(Duration.ofSeconds(5))
    .pollInterval(Duration.ofMillis(100))
    .untilAsserted {
        val projection = projections.findByOrderId(orderId)
        assertThat(projection).isNotNull
        assertThat(projection!!.status).isEqualTo("PLACED")
    }
```

Properties of a good poll-based assertion:

- **Polling interval much shorter than expected latency.** 100ms poll for ~500ms latency.
- **Timeout generous enough for CI but tight enough to fail fast.** 5s is a typical default for in-VM async; 30s only for genuinely slow flows (large index rebuilds).
- **Fail message names what was expected** so the failure log diagnoses itself.
- **Idempotent assertion inside the poll** — `untilAsserted` runs the lambda repeatedly; it must not mutate state.

Other-stack equivalents:
- Go: `assert.Eventually(t, fn, timeout, interval)` (testify).
- Python: `pytest-timeout` + custom retry, or `tenacity` retry-on-assertion.
- Node: `waitFor(fn, { timeout, interval })` (Testing Library).

---

## 6. Stubbing external systems

You don't own the third-party API; you cannot guarantee its uptime, its rate limit, its data; calling it in a test is a non-repeatability hazard. **Always stub.**

The three families:

### 6a. WireMock — record / replay HTTP stubs

```kotlin
wireMock.stubFor(get(urlPathEqualTo("/inventory/SKU-001/availability"))
    .willReturn(okJson("""{"available": 12}""")))
```

Best for: REST APIs you call out to, where you control the URL via a property.

### 6b. MockServer / Hoverfly — equivalent alternatives

MockServer (Java-first) and Hoverfly (Go-first, polyglot) play similar roles. WireMock dominates the JVM ecosystem.

### 6c. Pact stub server — contract-driven stubs

Pact (consumer-driven contracts) generates a stub server from the consumer-side contracts. The provider runs against the same contracts; both sides verify a single source of truth. See `test-contract` for the full pattern.

### 6d. In-process fakes — for protocols WireMock can't handle

For gRPC, raw TCP, JDBC drivers, etc., WireMock doesn't apply. Either:
- Use a protocol-specific mock (e.g., `grpc-java`'s `InProcessServerBuilder`).
- Use Testcontainers with the real service (if it's open-source and dockerised).
- Accept the missing test and document why.

**House rule**: never call a real external service in a test. The cost is non-repeatability (flaky external services become your flakes) + cost (rate limits, money) + slowness. If the external service is owned by your org, prefer Pact (`test-contract`) over WireMock — it survives both sides drifting.

---

## 7. Database fixtures — three approaches

Real-infrastructure tests need real data. How to put it there:

### 7a. SQL fixture scripts

```sql
-- src/test/resources/fixtures/three-orders.sql
INSERT INTO customers (id, name) VALUES ('00000000-...-0001', 'Ada');
INSERT INTO orders (id, customer_id, status) VALUES
    ('00000000-...-0001', '00000000-...-0001', 'DRAFT'),
    ('00000000-...-0002', '00000000-...-0001', 'SUBMITTED');
```

Loaded via Spring's `@Sql(scripts = ["/fixtures/three-orders.sql"])` or equivalent.

**Pros**: explicit, fast (raw SQL), portable.

**Cons**: gets out of sync with schema changes; not type-safe; hard to vary one field across tests; large fixture files become unreadable.

Best for: a small number of canonical "scenarios" used by many tests.

### 7b. Factory-bot / object-mother helpers

```kotlin
fun anOrderEntity(
    customerId: UUID = UUID.randomUUID(),
    status: String = "DRAFT",
    createdAt: Instant = Instant.now(),
) = OrderEntity(id = UUID.randomUUID(), customerId = customerId, status = status, createdAt = createdAt)
```

Called from test code; persists via `TestEntityManager` or the repository.

**Pros**: type-safe; refactor-safe; varying one field is trivial; close to the test.

**Cons**: per-test code, can drift between tests; needs discipline to keep one canonical builder per entity.

Best for: most integration tests. Combine with `@Sql` for scenarios used by many tests.

### 7c. Fixture inheritance / shared base classes

```kotlin
abstract class CustomerAndOrderFixtures {
    protected val knownCustomer = Customer(id = UUID.fromString("..."), name = "Ada")
    protected val knownOrder = Order(id = UUID.fromString("..."), customerId = knownCustomer.id, ...)

    @BeforeEach
    fun seed() { customerRepo.save(knownCustomer); orderRepo.save(knownOrder) }
}
```

**Pros**: each test gets the canonical world for free.

**Cons**: shared mutable state in the suite; each test depends on a fixture decision made elsewhere; refactor to the base class breaks 50 tests at once.

Best for: read-only fixtures shared across a whole test class; bad for fixtures that the test itself wants to vary.

### Pragmatic recipe

- Define **one canonical builder per entity** (`anOrder()`, `aCustomer()`) in a shared test-only package.
- Most tests build their own world inside `@BeforeEach` or inline, using the builders.
- For multi-entity scenarios reused by ≥3 tests (e.g., "a customer with three past orders"), extract a `givenCustomerWithPastOrders(...)` helper, not a base class.
- Reach for SQL fixtures only when the data is large *and* unchanging *and* used by many tests.

---

## 8. Independence — the integration-tier hardest property

The first `@Test` runs against a freshly started container. The second runs against the same container with the first test's data still in it. The 50th runs against a container that's seen 49 prior writes.

The default failure mode is **test order dependence**: test A passes when run alone; test B passes when run alone; A then B fails because B reads what A wrote.

Independence at the integration tier is:

- **Each test's view of the DB is what its `@BeforeEach` set up, and nothing more.** Implemented via rollback (4a) or truncate (4b).
- **No test depends on the order it runs in.** Run the suite in random order to catch order-dependent tests.
- **No test depends on container state from a prior test run** when reuse is enabled. Either truncate at the start of every test run, or rely on rollback.
- **Mutable static state is forbidden** (e.g., `companion object var counter`). It survives across tests and pollutes silently.

Quick diagnostic for an order-dependent test: run the suite five times in randomised order. If it fails sometimes, you have an order dependency. Track down the test that's leaking state; fix the leak, not the order.

---

## 9. Repeatable — the train test

> **A test is Repeatable if it produces the same outcome on a developer laptop, on CI, and on a train without Wi-Fi.**

At the integration tier, the threats are:

- **System clock.** Tests using `Instant.now()` / `Date()` produce different output every run. Fix: inject a `Clock` (Java/Kotlin) / freeze time (Python `freezegun`, Go monkey-patch); use a fixed Clock in tests.
- **System time zone.** A test running in `Europe/Berlin` and `America/New_York` produces different `LocalDateTime`. Fix: in tests, set the JVM zone to UTC; or always use `Instant` / `OffsetDateTime`.
- **System locale.** String formatting differs (`,` vs `.` for decimal). Fix: pin `Locale.ROOT` in tests.
- **Random number generators.** A `Random()` without a seed produces non-deterministic output. Fix: inject a seeded `Random`.
- **External network calls.** Even a stubbed-out WireMock is a real network call to localhost. Usually fine, but flakes happen under load. Tighten WireMock to fail-fast on unexpected paths.
- **Container state with reuse.** Reused containers carry prior test data. Fix: truncate at `@BeforeEach`, or design tests to coexist.
- **JVM `-Duser.timezone` not set.** Fix in `build.gradle.kts`: `tasks.withType<Test> { systemProperty("user.timezone", "UTC") }`.

Quick check: write the test, run it 10 times in a row. Then change the system clock to 6 months in the future and run again. Then change the time zone. Then disconnect from the network. The test should still pass — every time — or it isn't Repeatable.

---

## 10. Self-validating — boolean output, not log inspection

The integration tier is most prone to **passing tests that didn't actually verify anything**. The two failure modes:

### 10a. Assert-nothing tests

```kotlin
@Test
fun `submits an order`() {
    service.submit(aSubmitOrderRequest())
    // no assertion — passes if no exception thrown
}
```

This is a smoke test, not an integration test. It catches uncaught exceptions and that's all. Add an assertion on the observable outcome (the persisted state, the published event, the response body).

### 10b. Log-content "verification"

```kotlin
@Test
fun `submits the order`() {
    service.submit(aSubmitOrderRequest())
    // ... manually check logs to confirm it worked
}
```

The test "passes" but verifies nothing programmatically. Either:
- Convert the log inspection into an actual assertion (database query, event publication, response).
- If the log line itself is part of the contract (audit log), use a log-capture extension (`OutputCaptureExtension` in Spring) to assert on the captured output.

### House discipline

Every integration test asserts on **at least one observable outcome** through real assertion machinery (AssertJ, Kotest matchers, Hamcrest). No `println`, no manual inspection. The CI machine cannot read logs.

---

## 11. Anti-patterns at the integration layer (cross-language)

- **The catch-all `@SpringBootTest` base class.** "It works; let's reuse it" → six months later every test is a full-context load → CI is 14 minutes. Audit; downgrade to slices.
- **Embedded substitutes.** H2, fakeredis, embedded Kafka, embedded Mongo. Each lies about behaviour. Testcontainers everywhere there's a real engine; in-process fakes only where Testcontainers can't help.
- **Single shared container across multiple test classes with no cleanup contract.** Tests pass alone, fail together. Either commit to rollback (read-only) or truncate (write).
- **Test order dependence.** Test A seeds data; test B asserts on the seeded data. Both pass if A runs first, both fail otherwise. Make each test self-contained.
- **`Thread.sleep` for "let the event settle".** Flaky. Use polling.
- **Real network calls in tests.** Outage on a third-party = your CI is red. Stub.
- **Mutable test fixtures shared across classes.** A change in one class breaks tests in another. Each test class owns its fixtures; share only **immutable** canonical builders.
- **Asserting on whatever the test wrote, with no transformation.** "Write order O; assert order O exists." Always true if persistence didn't throw; tests nothing meaningful. Assert on observable behaviour: status transition, computed field, returned ID.
- **Counting on `@BeforeAll` to set up a stateful world used by every test.** Fragile; the first failure cascades. Per-test setup with shared **read-only** scaffolding is more robust.
- **Catching expected exceptions silently.** `try { service.submit(...); fail() } catch (e: Exception) { }` — too broad. Use the library's `assertThrows<SpecificException> { ... }` and assert on the message / type.

---

## 12. The proportional F.I.R.S.T. — for this tier

The unit-tier targets do not apply. The integration tier earns its own:

| Letter | Unit-tier target | Integration-tier target |
|---|---|---|
| **Fast** | < 50 ms per test | < 1 s per slice test; < 5 s per `@SpringBootTest` |
| **Independent** | No shared static state | Each test owns its DB view (rollback or truncate) |
| **Repeatable** | No clock / locale / random / time zone | Same + container reuse handled + WireMock for outbound |
| **Self-validating** | Real assertion machinery | Same — plus observable outcomes (DB query, event captured, response body) |
| **Timely** | TDD cycle | At minimum, the integration test ships in the same PR as the seam it covers |

A test taking 800 ms is **Fast for the integration tier**. A test taking 30 s is not Fast for *any* tier. The targets are tier-relative but not flexible enough to excuse `@SpringBootTest` that loads everything to test one thing.

---

## 13. Smell → fix (cross-stack)

| Smell | Fix |
|---|---|
| Test takes 30 s to run | It's a `@SpringBootTest` doing slice work — narrow to the slice |
| Test fails only in random order | Order dependency; find the leaking test, isolate its writes |
| Test fails Mondays after a weekend gap | Container reuse stale state; truncate at `@BeforeEach` |
| Test passes locally, fails on CI | Container start latency; clock; time zone; network speed — check all four |
| Test stubs the database with H2 | Replace with Testcontainers; H2 lies |
| Test sleeps 200 ms then asserts | Replace with `await().atMost(...).untilAsserted { ... }` |
| Test calls real third-party API | Replace with WireMock / `MockRestServiceServer` |
| Test asserts "no exception" only | Add an assertion on the observable outcome |
| Test writes 10 entities, asserts on 10 | Builder helpers; one-line per entity; assertion focuses on the outcome, not the count |
| Same `@Transactional` rolls back the listener call you wanted to verify | Remove `@Transactional`; use explicit truncate |
| 30 test classes each create their own container | Singleton container in shared base / `@ImportTestcontainers` |
| Schema state survives across test runs unexpectedly | Verify `testcontainers.reuse.enable` and truncate strategy |
| Test exercises three controllers and two services | It's an acceptance test; relocate to `test-acceptance` |

---

## 14. Summary — what makes a good integration test

A good integration test:

- Crosses a **real deployment seam** with real infrastructure on the far side.
- Tests **one seam at a time** — not the whole app.
- Cleans up after itself — **rollback** for read-side, **truncate** for write-side.
- Uses **polling** for async, never `Thread.sleep`.
- Stubs **external** systems (third-party APIs, services owned by others), uses **real** instances of internal infrastructure (your DBs, brokers, caches).
- Asserts on **observable outcomes** through real assertion machinery.
- Reads in **BUILD-OPERATE-CHECK** like every other test (see `test-principles`).
- Is **Fast for its tier** — sub-second for slices, under five seconds for full-context tests.
- Is **Independent**, **Repeatable**, **Self-validating** — by design, not by accident.

The integration tier is the **floor** of any test pyramid. A suite without it is missing the bugs that live at the seams — the bugs that ship.
