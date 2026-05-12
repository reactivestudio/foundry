---
name: test-integration
description: "Layer-specific discipline for integration / slice tests in a Kotlin / Spring codebase — the middle of the pyramid or the bulk of a diamond. Owns Spring Boot test slices (`@WebMvcTest`, `@DataJpaTest`, `@RestClientTest`, `@JsonTest`, `@JdbcTest`, `@DataRedisTest`, `@DataMongoTest`), Testcontainers for Postgres / Mongo / Elasticsearch / Kafka / Clickhouse / Redis, real-infrastructure-over-substitutes (no H2 standing in for Postgres, no embedded Kafka for Apache Kafka, no fakeredis for Redis), `@ServiceConnection` (Spring Boot 3.1+) over `@DynamicPropertySource`, container reuse for speed (`testcontainers.reuse.enable=true`), `@MockkBean` (mockk-spring) for boundary mocking, `@TestConfiguration` for fixed `Clock` / `IdGenerator`, transactional semantics traps (the `@Transactional` rollback lie when production code crosses tx boundaries with `REQUIRES_NEW`), `@TransactionalEventListener(AFTER_COMMIT)` testing, Awaitility for async polling (never `Thread.sleep`), WireMock for outbound HTTP, MockMvc Kotlin DSL, WebTestClient against `RANDOM_PORT`, adapter / port tests in hexagonal architecture, OAuth2 / JWT testing in slices, `@Sql` fixtures, `OutputCaptureExtension` for log-contract tests, ApplicationContext caching pitfalls. Use this skill whenever the user writes a slice test, sets up Testcontainers, debates `@WebMvcTest` vs `@SpringBootTest`, debugs a transactional test that 'sometimes passes', wires `@ServiceConnection`, audits an H2-substituting-for-Postgres setup, picks `@MockkBean` vs `@MockBean`, writes a `@DataJpaTest` and discovers it rolled back the listener call, or makes a WireMock-as-Testcontainer setup for an outbound integration. For shape selection (pyramid vs diamond, what layer should host this concern) see test-strategy. For per-test discipline (F.I.R.S.T. proportionally for this tier, BUILD-OPERATE-CHECK, DSL, naming) see test-principles. For pure unit content see test-unit. For application-service / use-case-level acceptance with narrow `@SpringBootTest` see test-acceptance. For cross-service contracts see test-contract."
risk: safe
source: "Adapted from existing testing-strategy-kotlin-spring + clean-code-unit-tests spring sections, plus house practice"
date_added: "2026-05-12"
---

# Test Integration — Slice & Testcontainers Discipline (Kotlin / Spring)

This skill owns the **middle of the test pyramid** — the integration tier where the seam under test is "production code wired to *real* infrastructure". Real Postgres via Testcontainers, real Kafka, real ES, real Redis. Spring Boot slices to load only the beans that matter. `@MockkBean` for the collaborators that must be stubbed. Awaitility for async. WireMock for outbound HTTP. The discipline that prevents `@SpringBootTest` proliferation and H2-pretending-to-be-Postgres.

> "An integration test is real-infrastructure for the seam under test — not the whole app. If your only integration shape is `@SpringBootTest`, you're not doing integration testing; you're doing slow end-to-end." — house ethos

This skill is the **content** of integration tests; for shape selection (does this concern even belong at the integration tier?) see `test-strategy`. For per-test discipline (F.I.R.S.T. proportionally — a slice test legitimately runs in hundreds of ms; that's still "Fast" *for this tier*) see `test-principles`.

## Use this skill when

- Writing a `@WebMvcTest` for a controller — request mapping, validation, exception mapping, security.
- Writing a `@DataJpaTest` (or `@JdbcTest`) for a repository / query / migration — and you need real Postgres semantics, not H2.
- Writing a `@RestClientTest` for an outbound HTTP client — `MockRestServiceServer` stubs the endpoint.
- Setting up Testcontainers for Postgres / Mongo / ES / Kafka / Clickhouse / Redis — singleton container, `@ServiceConnection`, reuse.
- Debugging a transactional test that "sometimes passes" — almost certainly a `@Transactional` rollback hiding a cross-tx side effect.
- Testing a `@TransactionalEventListener(AFTER_COMMIT)` listener — and discovering the test's rollback makes it never fire.
- Writing an adapter test in a hexagonal port-and-adapter codebase (the adapter is the seam between domain and infrastructure — that's exactly what integration tests are for).
- Adding WireMock as a Testcontainer for an end-to-end style outbound HTTP integration.
- Auditing a suite where 80% of tests are `@SpringBootTest` and the CI takes 14 minutes.
- Picking `@MockkBean` vs `@MockBean` — and standardising on one across the suite.
- Wiring `@AutoConfigureTestDatabase(replace = NONE)` and `@ImportTestcontainers` for `@DataJpaTest` against real Postgres.

## Do not use this skill when

- Picking the *shape* — should this concern be tested at unit, integration, or acceptance? That's `test-strategy`.
- Writing or reviewing the *content* of a single test (BUILD-OPERATE-CHECK, naming, DSL, F.I.R.S.T.) — that's `test-principles`. This skill assumes the principles are applied; it adds the integration-layer specifics on top.
- Writing a pure unit test (no Spring, no Testcontainers, < 50 ms) — that's `test-unit`.
- Writing a use-case-level acceptance test through a narrow `@SpringBootTest` with in-memory adapters — that's `test-acceptance`.
- Writing a consumer-driven contract test (Pact / Spring Cloud Contract) — that's `test-contract`.
- Writing ArchUnit / Modulith fitness tests — that's `test-architecture`.

## Selective Reading Rule

Read the file that matches the question you're answering.

| File | Description | When to read |
|---|---|---|
| `resources/general.md` | Language-agnostic integration-test discipline — what "integration" means at this layer, the deployment-seam principle, real-infrastructure-over-substitutes, isolation strategies, async polling, stubbing external systems, fixture patterns. | First read — frames everything below. Applies to Python, Go, Node integration tests too. |
| `resources/kotlin.md` | Kotlin-specific tooling for the integration tier — Awaitility Kotlin DSL, AssertJ idioms, WireMock Kotlin, MockK at the boundary, Testcontainers `companion object` patterns, fixture factories with real IDs / FKs, Kotest `Spec` mention. | When picking Kotlin-side tooling inside a slice or Testcontainers-based test. |
| `resources/spring.md` | Spring tooling for integration tests in depth — the slice catalogue, `@SpringBootTest` when (and only when), `@ServiceConnection` vs `@DynamicPropertySource`, Testcontainers + Spring for each store, container reuse, `@MockkBean` vs `@MockBean`, `@TestConfiguration`, transactional traps, MockMvc Kotlin DSL, WebTestClient, WireMock-as-Testcontainer, OAuth2 / JWT in slices, `@Sql`, `OutputCaptureExtension`, profiles, the Spring test pyramid. | The bulk of this skill. Read whenever you touch a Spring slice annotation or a Testcontainer in a Spring test. |

## The slice hierarchy

The cost-vs-coverage trade-off in one table. **Pick the smallest slice that exercises the unit under test.**

| Slice | Loads | Use for | Typical time |
|---|---|---|---|
| (no Spring) | nothing | Pure domain / utility code | < 50 ms |
| `@JsonTest` | Jackson + `ObjectMapper` | Custom serializers / deserializers, `@JsonView`, polymorphic types | ~ 100 ms |
| `@RestClientTest(Client::class)` | `RestClient` / `RestTemplate` + `MockRestServiceServer` | Outbound HTTP client tests | ~ 150 ms |
| `@JdbcTest` | `JdbcTemplate` + `DataSource` | Raw SQL / `JdbcTemplate`-based repositories | ~ 400 ms (shared container) |
| `@DataJpaTest` | JPA + `EntityManager` + repositories + auto-rolling-back tx; H2 by default → **override** | Repository methods, custom queries, JPA mapping | ~ 400 ms (shared container) |
| `@DataMongoTest` / `@DataRedisTest` | The specific data store | Store-specific repository tests | varies |
| `@WebMvcTest(Controller::class)` | `@Controller` + `@ControllerAdvice` + security; no services / repos | Controller behaviour, validation, error responses | ~ 800 ms |
| `@SpringBootTest(MOCK)` | Full context + `MockMvc` | Cross-slice flows; bootstrap smoke | ~ 2-5 s |
| `@SpringBootTest(RANDOM_PORT)` | Full context + real Tomcat / Jetty + `WebTestClient` | True end-to-end through the wire | ~ 5-10 s |

**Rule:** start at the most-restrictive level and step up only when the slice physically cannot host the test. Each step up is a 5-10× speed penalty.

## House rules

1. **Slices over `@SpringBootTest`.** `@SpringBootTest` is the last resort, not the default. A controller test that doesn't fit in `@WebMvcTest` is usually a controller doing too much.
2. **Testcontainers over H2 / embedded substitutes.** H2 silently accepts Postgres-isms it shouldn't; embedded Kafka is missing producer / consumer semantics that production has. The startup cost is paid for in truthfulness. Container reuse mitigates it.
3. **Real infrastructure where the deployment seam lives.** If production runs on Postgres 16, the test runs on Postgres 16 (Testcontainers). If it talks to Kafka, the test talks to Kafka. Substitutes lie about behaviour.
4. **`@ServiceConnection` over `@DynamicPropertySource`** (Spring Boot 3.1+). One line vs eight; the framework wires it. Drop to `@DynamicPropertySource` only for custom properties.
5. **`@MockkBean` (mockk-spring) over `@MockBean` (Spring's Mockito)** for Kotlin services. `every { … } returns …` matches the rest of the codebase. Pick one, stick with it; mixing the two forces every reader to context-switch.
6. **Container reuse on developer machines, fresh on CI.** `~/.testcontainers.properties: testcontainers.reuse.enable=true` locally; ephemeral CI runners shouldn't reuse (they don't persist the daemon anyway).
7. **Awaitility over `Thread.sleep` for any async assertion.** Fixed sleeps are flaky and slow; polling is deterministic and fast.

## What integration tests are FOR

The integration tier is the floor under whatever shape your suite has. These are the concerns that *only* show up at the integration layer — unit tests cannot catch them by construction:

- **Repository queries against real Postgres** — JSONB operators, partial indexes, `ON CONFLICT`, RETURNING, ranges, MVCC. H2 lies; Testcontainers don't.
- **Controller HTTP layer** — request mapping, content negotiation, `@Valid` validation, `@RestControllerAdvice` exception mapping, security filters, ProblemDetail formatting.
- **JSON serialisation contracts** — custom `JsonSerializer` / `JsonDeserializer`, `@JsonView`, polymorphic `@JsonTypeInfo`. Tests through `@JsonTest` with `JacksonTester`.
- **Outbound HTTP clients** — URL construction, headers, body serialisation, error handling, retries. `@RestClientTest` with `MockRestServiceServer`.
- **Kafka producers and consumers** — partition keys, serialisers, headers, consumer group rebalances. Testcontainers `KafkaContainer`.
- **Spring `@EventListener` and `@TransactionalEventListener`** — the listener wiring, the AFTER_COMMIT semantics, the phase ordering. Unit tests of the listener bean cover its logic; integration tests cover that it actually fires.
- **Transactional event semantics** — the listener fires *only on commit*; the test must commit to observe it. This is the most common slice-test trap.
- **Outbox pattern** — write inside the business tx → row appears in `outbox` table → poller picks it up → publishes to Kafka. Three transactions, three commit points, exactly the kind of multi-tx flow integration tests exist for.
- **Adapter / port tests in hexagonal codebases** — the adapter is the seam between domain and infrastructure. Test it with real infrastructure; that's its job.
- **Migrations** — Flyway / Liquibase apply cleanly on a fresh container; the schema matches the JPA mapping; expected DDL is present.

## What integration tests are NOT for

- **Per-rule domain logic.** A test that asserts `Order.submit()` rejects an empty line list should NOT load Spring; that's a `test-unit` concern. Loading `@SpringBootTest` to test a pure domain rule is a 50× speed penalty for zero added coverage.
- **Whole user journeys across multiple bounded contexts.** A test that starts at HTTP, goes through three services, two queues, and a projection rebuild is an acceptance / end-to-end test — see `test-acceptance` (or `test-contract` for the cross-service compatibility piece). Don't stuff it into `@SpringBootTest` and call it integration.
- **Cross-service contracts.** Pact / Spring Cloud Contract is its own discipline — see `test-contract`. Trying to verify cross-service compatibility through your own `@SpringBootTest` produces a brittle suite that breaks on every counterpart deploy.
- **Architecture / module-boundary rules.** ArchUnit, Spring Modulith — see `test-architecture`. These are fast unit-tier checks; running them inside `@SpringBootTest` is wasted startup time.

## Anti-patterns

- **`@SpringBootTest` everywhere.** Each one loads ~300 beans, adds 5-15s to CI, churns the application-context cache. Audit by test class; replace with the narrowest slice that hosts the test.
- **Application-context proliferation via `@MockkBean` / `@TestConfiguration` variants.** Every unique combination of mock declarations and test config creates a new context. 30 test classes with one-off mocks = 30 cached contexts (or worse, churn past the cache size). Group consistent combos in base classes; share `@TestConfiguration`.
- **H2-as-Postgres** — `@DataJpaTest` without `@AutoConfigureTestDatabase(replace = NONE)`. Spring silently substitutes H2. Your "Postgres test" runs on H2; the JSONB query passes in test, fails in prod. Painful debugging.
- **In-memory substitutes** — fakeredis, embedded Kafka, embedded Mongo — for the same reason. The substitute is "mostly" production. The "mostly" is where the bugs hide.
- **`@DirtiesContext` as a normal tool.** A giant flag that the test is leaking state. Slows CI dramatically (forces context rebuild on the next test). Find the leak, not the workaround.
- **`Thread.sleep(X)` instead of Awaitility.** Fixed delay = flaky on slow CI / fast on dev = unreliable. Use Awaitility; poll with backoff.
- **Real network calls in tests.** Calling a real third-party API: non-repeatable (their flakes are now your flakes), slow, sometimes costs money / rate-limited. WireMock / `MockRestServiceServer` / `@RestClientTest` is non-negotiable.
- **`@Transactional` on the test class for *write-side* flows.** Rollback hides events / outbox writes / `REQUIRES_NEW`-committed work. Use explicit cleanup (`TRUNCATE`) for write-side; `@Transactional`-rollback is for read-side query tests.
- **`@SpringBootTest(properties = ["..."])` overriding everything to make the test pass.** When the test depends on properties that don't match production, you're testing a system that doesn't ship. Use `@ActiveProfiles("test")` + `application-test.yml`; diverge from prod only where necessary.
- **Reusing one `@SpringBootTest` base class because "it was easier".** Three months later, every test extends it; the suite is `@SpringBootTest`-flavoured by accident. Audit; downgrade.

## Related skills

| Skill | Why |
|---|---|
| `test` | The router skill. Points here for integration-tier work. |
| `test-strategy` | Shape selection (pyramid / diamond / inverted). Tells you whether the concern even belongs at the integration tier. |
| `test-principles` | Per-test discipline — F.I.R.S.T. (proportionally for this tier), BUILD-OPERATE-CHECK, DSL, naming, Khorikov's four pillars. **Do not duplicate** that content here — point to it. |
| `test-unit` | Sibling, layer below. Pure unit tests with no Spring. |
| `test-acceptance` | Sibling, layer above. Application-service / use-case-level tests through narrow `@SpringBootTest` with in-memory adapters. |
| `test-contract` | Sibling. Consumer-driven contracts (Pact, Spring Cloud Contract) — the right tool for cross-service compatibility, beats brittle e2e. |
| `test-architecture` | Sibling. ArchUnit / Modulith / Pitest fitness functions — fast unit-tier quality gates. |
| `database-design` | What the schema *should* be; integration tests verify what it *is*. |
| `cqrs-implementation` | Write-side / read-side split. Integration tests of the projection-rebuild path live here. |
| `messaging-rabbitmq-spring` | RabbitMQ / Kafka producer / consumer patterns — the production code that the Kafka / Rabbit integration tests cover. |
| `spring-security-and-auth` | OAuth2 / JWT / `SecurityFilterChain` — `@WebMvcTest` security setup uses this. |
| `methodology-verification` | After every integration-test change, *re-run* the suite in the current session; "should pass" is not evidence. Containers don't lie. |
| `methodology-karpathy-guidelines` | §4 verifiable success criteria — the integration test *is* the verifiable criterion for the deployment-seam behaviour. |
| `debugging-systematic` | When a Testcontainers test fails "only on Tuesdays", root-cause the leak, don't add `@DirtiesContext`. |

## Limitations

- **Tier-relative F.I.R.S.T.** A slice test taking 800 ms is *Fast for the integration tier*; the < 50 ms unit-tier target does not apply. Apply F.I.R.S.T. proportionally — a `@SpringBootTest` taking 30 seconds is NOT Fast for any tier.
- **Container reuse is a developer-machine optimisation.** CI starts cold; pre-pull images in CI cache, accept the cold-start cost.
- **`@ServiceConnection` requires Spring Boot 3.1+.** On older versions, fall back to `@DynamicPropertySource` (one example per store in `resources/spring.md`).
- **The slice catalogue is not exhaustive.** New slices appear (`@DataNeo4jTest`, `@WebFluxTest`, etc.) — the pattern (smallest slice that hosts the test) holds; consult Spring Boot docs for the latest.
- **Some seams have no slice.** Spring Batch, Spring Integration, Quartz — these often require `@SpringBootTest` because the slice doesn't exist or is incomplete. Accept it for those cases; don't generalise from them.
- **WireMock-as-Testcontainer vs WireMock-embedded.** Both work; the Testcontainer flavour is cleaner for end-to-end-style outbound integration tests. The embedded `WireMockExtension` is fine for slice-level `@RestClientTest` scenarios.
- **Mutation testing is orthogonal.** Pitest applies to whatever layer hosts the tests; it doesn't move the centre of gravity. See `test-architecture`.
- **Property-based testing rarely fits the integration tier.** Properties belong at the unit layer where they're cheap; at the integration tier, the container overhead defeats the input-space sweep. Exception: serialiser round-trip properties.
