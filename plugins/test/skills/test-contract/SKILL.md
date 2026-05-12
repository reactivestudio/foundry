---
name: test-contract
description: "Consumer-driven contract tests for cross-service compatibility — verifying 'consumer X expects provider Y to return Z' without standing up a real end-to-end environment. Covers Pact JVM as the dominant tool for REST and Kafka / message contracts, Spring Cloud Contract (SCC) as the Spring-house alternative with consumer-side stub generation and provider-side test generation, OpenAPI-driven contract testing as a lighter schema-only option, and the full contract-test pipeline (consumer publishes pact → provider verifies in CI → can-i-deploy gate before deploy). Covers when contract tests pay (multiple services, multiple teams, independent deployability, async messaging across team boundaries), when they don't (single service / monolith / no team boundary / very stable internal API — slice tests on each side beat the contract-test machinery), the Pact Broker / Pactflow as central contract storage, the consumer-side test (mock provider, assert on what was expected), the provider-side verification (replay each pact against the real provider, return real data via provider states), contract evolution (deprecation flow, backward compat windows, the matrix of consumer/provider versions), Kafka and event-driven message contracts (both sides agree on schema and semantics), and webhook-driven CI (broker triggers consumer pipelines when provider deploys). Use this skill whenever the user designs a contract test, picks Pact vs SCC vs OpenAPI, sets up a Pact broker, writes a consumer-side test, runs provider verification, debugs a failing provider verification, plans contract-driven evolution of a service, decides whether contract tests beat e2e for cross-service compatibility, or asks 'do we need this?'. For unit / integration / acceptance see test-unit / test-integration / test-acceptance; for shape see test-strategy; for the API the contract verifies see api-design-principles; for the messaging substrate see messaging-rabbitmq-spring."
risk: safe
source: "House synthesis on consumer-driven contracts using Pact JVM and Spring Cloud Contract"
date_added: "2026-05-12"
---

# Test Contract — Consumer-Driven Contracts for Cross-Service Compatibility

A contract test is the cheapest answer to a question that costs teams enormous amounts of pain: **"is consumer A still compatible with provider B?"** Without contract tests, the only honest answer is a shared end-to-end environment, a staging deploy of both sides, and a flaky cross-service test that breaks the moment someone re-deploys an unrelated downstream. With contract tests, each service runs the check **in its own CI**, against an artefact in a broker, with no shared environment.

> "A contract is the consumer's expectation of the provider, captured as an executable artefact, stored centrally, and verified independently on both sides. The consumer proves it doesn't expect impossible things; the provider proves it can deliver what every consumer expects." — house ethos

This skill is **layer-specific** — it covers the contract-test tier of the strategy chosen in `test-strategy`. It does not replace unit / integration / acceptance tests; it sits **next to** them and answers a question those tiers cannot: cross-service compatibility *without* a real cross-service environment.

## Use this skill when

- Designing a contract test between two services that have **independent release cycles** and may be owned by **different teams**.
- Picking between **Pact** (richer ecosystem, language-agnostic, broker-centric), **Spring Cloud Contract** (Spring-house, stub generation on consumer side, test generation on provider side), and **OpenAPI / AsyncAPI contract testing** (schema-only, lightest).
- Setting up the **Pact Broker** / Pactflow / SCC stub-runner artifact repository as the central source of truth.
- Writing a **consumer-side** test that records expectations against a generated mock provider.
- Running **provider verification** — replaying each consumer pact against the real provider, asserting it produces the expected response (with real data set up via provider states).
- Debugging a **failing provider verification** — the consumer expects a field, the provider no longer produces it; or the consumer expects a 200, the provider now returns 422.
- Planning **contract evolution** — deprecating fields, widening tolerance on the consumer side, the deprecation flow ("the provider can stop returning X once all consumers have stopped asking for it").
- Designing **Kafka / event contracts** — both sides agree on the message schema *and* the semantics; Pact's `MessagePact` and SCC's `message` contracts both cover this.
- Wiring **can-i-deploy** into the deploy pipeline: "given this version, is it compatible with every currently-deployed counterpart?".
- Deciding whether contract tests **beat e2e** for a given cross-service compatibility concern (they almost always do, but not always).
- The team asks **"do we need contract testing at all?"** — for a monolith with one team, the honest answer is no. This skill is honest about its scope.

## Do not use this skill when

- Writing **unit tests** of in-process logic — that's `test-unit` / `test-principles`.
- Writing **slice / integration tests** that exercise a real DB or Kafka but not cross-service compatibility — that's `test-integration`.
- Writing **use-case / acceptance tests** that drive the service through application services — `test-acceptance`.
- The two parties are **inside one repository, one team, one release cycle** — a contract artefact between them is bureaucratic overhead. A slice test of each side, plus a shared type module, is enough.
- The question is **API design** itself ("how should I shape this endpoint?") — `api-design-principles`. Contract tests verify a *given* contract; they don't design it.

## Selective Reading Rule

Read the file that matches the decision you're making.

| File | Description | When to read |
|---|---|---|
| `resources/general.md` | Language- and tool-agnostic CDC discipline — the consumer-driven mindset, the Pact-style flow, HTTP vs message contracts, schema-only (OpenAPI / AsyncAPI / Protobuf) vs behaviour-driven (Pact), versioning / compatibility windows / deprecation, the broker as central storage, can-i-deploy, contract-test failure modes, when CDC is overkill, anti-patterns. | Read first — vocabulary and the model. |
| `resources/kotlin.md` | Pact JVM idioms in Kotlin — Gradle setup, consumer-side JUnit 5 + Pact DSL test (`@PactTestFor`, `@ExtendWith(PactConsumerTestExt.class)`, `RequestResponsePact`, `MessagePact`), publishing pacts via Gradle, provider verification with `@Provider`, `@PactBroker`, `@TestTemplate`, provider state setup, Kotlin-specific syntax notes and gotchas, realistic OrderService / InventoryService examples. | When using Pact JVM in a Kotlin project — most cross-team JVM contract testing. |
| `resources/spring.md` | Spring Cloud Contract patterns — Groovy / YAML / Kotlin DSL contracts, consumer-side `@AutoConfigureStubRunner`, provider-side auto-generated tests via the SCC Gradle plugin, Kotlin DSL contract examples, SCC vs Pact tradeoffs, SCC + Kafka message contracts, OpenAPI-driven contract testing as a third option. | When the team is already on Spring and prefers in-house tooling, or when comparing SCC against Pact for a given fit. |

## What is a contract test

A contract test is an executable artefact that captures **the consumer's expectation of the provider**, stored centrally, and verified independently on both sides.

- The **consumer** writes a test that uses a generated mock of the provider. The test records the request the consumer makes and the response it expects. The output is a **pact file** (or SCC stub) — a serialised contract.
- The contract is **published** to a central store: a Pact Broker (Pactflow), or an artifact repository (Nexus / Artifactory) for SCC stubs.
- The **provider** pulls the contract and runs a **verification**: for each consumer expectation, stand up the real provider, set up the data the contract requires (via *provider states*), replay the request, and assert the actual response matches.
- The **can-i-deploy** check, run at deploy time, asks the broker: "given consumer-X version V_c and provider-Y version V_p, is the matrix of pacts compatible?"

The two sides are decoupled. The consumer suite does not need the provider; the provider suite does not need the consumer. The contract is the only shared artefact. **This is what makes contract testing scale to dozens of services across multiple teams** — no shared environment, no cross-team CI dependency, no flaky e2e cycle.

What a contract test **is not**:

- It is not a substitute for **unit tests**. The consumer still needs unit tests for its own logic; the provider still needs unit tests for its rules.
- It is not a substitute for **integration tests**. The provider still needs to test that its persistence / serdes / security / async work; the consumer still needs to test that its HTTP client wires correctly. Contract tests sit on top.
- It is not a substitute for **end-to-end tests entirely**. A handful of smoke e2e tests are still useful for "does the deploy actually work?". Contract tests replace the *bulk* of compatibility e2e, not the smoke pass.
- It does not test **business behaviour** beyond the request/response shape. It checks that the consumer-expected interaction is satisfied; the rules behind it belong in unit / acceptance tests of either side.

## When contract testing pays

The economics of contract testing are very clear, and they apply when **all** the following hold:

1. **Multiple services** with independent release cycles. Two services owned by one team, deployed together — slice tests on each side are enough; the contract artefact is bureaucracy.
2. **Multiple teams** — the contract artefact becomes the team-to-team interface, replacing "ping the other team's tech lead before we deploy".
3. **Independent deployability** — the goal is that consumer can deploy without provider's permission and vice versa, *as long as* the contract still holds. Without contract tests, that promise is hollow.
4. **A meaningful API surface** — REST or gRPC or Kafka — between the services. If the interaction is one heartbeat ping, the contract artefact is overkill.
5. **The cost of a cross-service incompatibility is high** — a broken contract causes a real production incident, not just a recoverable retry. If the cost is low, contract tests are insurance the team doesn't need.

The signature payoff is the **deploy gate**: at deploy time, can-i-deploy answers "is this version compatible with everything currently in production?" — without spinning up an e2e environment. That answer is worth the entire contract-test infrastructure.

## When contract testing does NOT pay

Be honest. Contract testing has real costs — a broker to run, a learning curve, tests on both sides, contract evolution discipline. Don't pay it where it doesn't return value.

- **A monolith with no in-process service boundaries** — there is no consumer / provider pair to contract. Slice tests are sufficient.
- **One service total** — same reason. There's nothing to contract with.
- **Two services owned by one team, deployed together** — the artefact adds nothing over `test-integration` slice tests on each side and a shared types module.
- **A very stable internal API that hasn't changed in two years** — the maintenance cost of the contract tests exceeds the protection they provide. A small set of smoke tests is enough.
- **Throw-away integrations** — a one-off data import, a temporary glue service, a prototype. Contract tests are an investment that doesn't pay back inside the lifetime.
- **External APIs you do not control** — you cannot run provider verification on Stripe, GitHub, or a partner's API. You can still write **consumer-driven contract tests** as documentation of your expectations and run them against a recorded WireMock fixture; but the "provider proves it satisfies the contract" half is gone.

Pact's own docs say this explicitly: *"if you don't have multiple services with independent release cycles, you probably don't need Pact."* That guidance is correct. Apply it.

## Pact vs Spring Cloud Contract — pick one

Both produce contract artefacts and verify them on both sides. The pick depends on **ecosystem fit**, not on which has more features (they have comparable feature surfaces for the typical case).

| Dimension | Pact JVM | Spring Cloud Contract |
|---|---|---|
| Origin | Pact Foundation, language-agnostic, dominant in polyglot setups | Spring team, JVM-only in practice |
| Contract authoring | Consumer test *generates* the pact (consumer-driven, by construction) | Contract written by hand (Groovy / YAML / Kotlin DSL) in the **provider** repo, by convention |
| Mock for consumer | Pact-generated HTTP mock | SCC-generated WireMock stub or messaging stub |
| Provider verification | Provider replays pacts from broker, sets state via provider state handlers | SCC plugin **generates** JUnit test classes from the contract; provider runs them |
| Storage | Pact Broker / Pactflow (purpose-built — webhooks, can-i-deploy, matrix view) | Maven / Gradle artifact (the provider publishes a stubs JAR) |
| Webhook-driven CI | First-class — broker triggers consumer pipeline when provider verification succeeds for a new version | Available but not first-class |
| Polyglot consumers | First-class — Ruby, JS, Go, Python, .NET, Rust all consume Pact contracts | JVM-only consumers in practice |
| Kafka / message contracts | `MessagePact` — well-supported, mature | `message` blocks in the contract DSL — well-supported, idiomatic for Spring + Kafka |
| Learning curve | Steeper if new to CDC; broker setup non-trivial | Lower if already on Spring; contracts feel like Spring tests |
| Right when | Polyglot estate, multi-team, broker-as-source-of-truth wanted | Spring-only estate, team prefers in-house tooling, no broker appetite |

**Default**: Pact for polyglot or multi-team estates; SCC for a Spring-only estate where the team is allergic to extra infrastructure. Both are correct. Don't run both at the same time for the same pair of services — it's noise.

## The contract-test pipeline

```
┌────────────────────┐
│  Consumer CI       │   1. Consumer test runs against mock provider.
│                    │      → Pact file generated.
│  - Run consumer    │   2. Publish pact to broker, tagged with consumer
│    test (mock      │      version + branch.
│    provider)       │
│  - Publish pact    │
└─────────┬──────────┘
          │  pact published
          ▼
┌────────────────────┐
│   Pact Broker      │   3. Broker stores the pact, indexed by consumer
│   (Pactflow)       │      version, provider, and branch.
│                    │   4. Broker triggers provider's CI (webhook) on
│                    │      new pact arrival, optionally.
└─────────┬──────────┘
          │  webhook / pull
          ▼
┌────────────────────┐
│  Provider CI       │   5. Provider verification job: pull pacts for
│                    │      this provider, replay each against real
│  - Pull pacts      │      provider, set state via @State methods,
│  - Stand up real   │      report PASS / FAIL back to broker.
│    provider        │   6. Broker records: provider version V_p satisfies
│  - Replay + verify │      consumer version V_c.
│  - Publish result  │
└─────────┬──────────┘
          │  result published
          ▼
┌────────────────────┐
│  Deploy pipeline   │   7. Before deploying provider V_p, run:
│                    │      `pact-broker can-i-deploy --pacticipant
│  - can-i-deploy    │       provider --version V_p --to-environment prod`
│  - Block on FAIL   │   8. Broker answers: compatible with every currently
└────────────────────┘      -deployed consumer? PASS → deploy. FAIL → halt.
```

The two ends of the pipeline are the asymmetric properties that make CDC valuable:

- The **consumer** owns the contract — it expresses what it needs. The provider does not get to invent the contract on the consumer's behalf.
- The **provider** owns the verification — it proves it satisfies *every* current consumer. If a consumer's expectations are impossible, that's a conversation, not a unilateral break.

## Anti-patterns

- **Contract tests inside a monolith.** The two "services" are in-process modules. Contract tests add nothing; slice tests of each module's API surface plus a shared types module is sufficient.
- **Contract tests covering everything the provider does.** A contract test should cover only **the interactions the consumer actually performs**. Don't write a contract test for an endpoint no consumer calls — that's an integration test masquerading as a contract.
- **Manually editing pact files.** Pact files are *generated artefacts*. Hand-edits get overwritten next time the consumer test runs. If the expectation needs adjusting, adjust the consumer test.
- **No broker — pacts shared via email / git / Slack.** Without a broker, the version matrix is unmanaged, can-i-deploy doesn't exist, and webhook-triggered CI doesn't exist. The infrastructure of a broker is what makes contract testing scale; without it, you have hand-managed copies of JSON files and a slow regression to "let's just deploy and see".
- **Provider verification not part of provider's CI gate.** If verification runs in a nightly job, the feedback loop is 24 hours and the provider can ship breaking changes for a full day before anyone notices. Verification is a PR-gate.
- **Asserting on provider implementation details in the contract.** "The provider must return field `internalSeq` of type Long" — only assert on what the consumer actually reads. Over-specified contracts break on every legitimate provider refactor and erode trust.
- **One pact per consumer-provider pair containing 80 interactions.** Pacts are *cumulative within a test class* but the whole consumer should not specify every possible interaction in one file. Split by consumer responsibility (one pact per consuming use case), or your provider verification job becomes a 20-minute serial replay.
- **Treating the contract as the design.** Contract tests *verify* an API; they don't *design* it. `api-design-principles` and the conversation between teams designs it. Don't use Pact as a design tool — it makes for adversarial contracts.
- **Skipping can-i-deploy and relying on PR-gate verification only.** PR-gate verification proves *this version* satisfied the contracts at *test time*. By deploy time, new consumer pacts may have arrived. can-i-deploy is the deploy-time check; skipping it means you can pass CI and still break production.
- **Same contract test for sync and async paths.** Pact `RequestResponsePact` and `MessagePact` are different artefacts for a reason. A REST contract and a Kafka contract are two contracts, even if the data is the same.

## Related skills

| Skill | Why related |
|---|---|
| `test` | Router skill — picks `test-contract` for cross-service compatibility questions. |
| `test-strategy` | Picks the suite shape; contract tests sit *next to* the chosen shape, not inside it. |
| `test-principles` | Per-test discipline (F.I.R.S.T., BUILD-OPERATE-CHECK, naming) — applies to contract tests too. |
| `test-unit`, `test-integration`, `test-acceptance` | The other layers; contract tests do not replace them. |
| `test-architecture` | Module / boundary fitness (ArchUnit, Modulith) — internal version of the cross-service boundary discipline that CDC enforces externally. |
| `api-design-principles` | Designs the API; contract tests verify it. |
| `microservices-patterns-deep` | Independent deployability and team autonomy — the *why* behind contract testing. |
| `messaging-rabbitmq-spring` | Message-broker patterns; contract tests for async flows verify schema + semantics. |
| `ddd-context-mapping` | Contracts between bounded contexts — the conceptual home of CDC; the contract test is the executable form of a context-mapping pattern (customer/supplier, conformist, anti-corruption layer). |
| `methodology-verification` | After running contract tests, quote the broker / verification output — "the broker says compatible" is the evidence, not vibes. |
| `methodology-karpathy-guidelines` | §4 verifiable success criteria — can-i-deploy IS the verifiable success criterion for cross-service compatibility. |
| `debugging-systematic` | When a provider verification fails, root-cause from the pact file backwards. |

## Limitations

- **Contract tests verify the shape and semantics of an interaction; they do not verify performance, latency, or business correctness.** A provider that satisfies every pact and returns 200 in 50 seconds is still "passing" contract tests. Pair with perf / SLO testing.
- **Contract tests assume the consumer and provider can both run their own CI.** For a SaaS provider you do not control, only the consumer half works — you can document expectations, but you cannot run provider verification.
- **The broker is a single point of trust.** If the broker is wrong (stale data, missed webhook, misconfigured environment tag), can-i-deploy gives a wrong answer. Treat broker uptime as production.
- **Contract evolution is non-trivial.** Adding a new required field, narrowing a type, or changing an error code is a breaking change requiring a deprecation flow. CDC tools surface the breakage but they do not manage the social process of evolving the contract.
- **Over-specification.** A common failure mode: the consumer test asserts on more than it actually needs (every field, exact types, exact strings). This makes every legitimate provider change look like a contract break. Discipline matters; the consumer-side test must assert on **what the consumer actually reads**, nothing more.
- **Not a substitute for a thoughtful API design.** Contract tests pin down whatever API the team agreed; they don't make a bad API good. `api-design-principles` first; contract tests second.
- **Setup cost is real.** A broker, two CI integrations, a deploy gate, training the team. For a small estate, that cost outweighs the benefit. Be honest about the inflection point — usually around 4-6 services with independent release cycles.
