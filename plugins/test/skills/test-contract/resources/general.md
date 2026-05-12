# Consumer-Driven Contracts — Discipline, Language-Agnostic

The principles below apply equally to Pact (in any language), Spring Cloud Contract, Pact-Go, Pact-JS, custom contract harnesses built on OpenAPI + a verifier, and AsyncAPI / Protobuf-based message contracts. The tooling differs; the discipline does not.

---

## 1. The consumer-driven mindset

The single insight at the centre of CDC is this:

> The **consumer** specifies what it needs from the provider, as an executable artefact. The provider **proves** it can satisfy what every current consumer needs. Neither side invents a contract on the other's behalf.

Most pre-CDC integration testing inverts this: the provider publishes an OpenAPI document or a WSDL "for the consumers to use", consumers read it, and the provider's idea of the API becomes the law. The pre-CDC failure mode is well-known: the provider deprecates a field nobody is using, deploys, and three consumers break in production because the provider had no way to know who was reading what.

Consumer-driven inverts the flow:

- Consumer A says: *"I call `GET /orders/{id}` and I read `.id`, `.status`, `.totalAmount`."*
- Consumer B says: *"I call `GET /orders/{id}` and I read `.id`, `.customerId`, `.lines[].productId`."*
- The provider must satisfy **both** contracts to deploy. The union of all current consumer contracts *is* the effective public API.

The implication: when the provider wants to remove a field, it can — *as soon as no contract still references it*. Removing `.internalSeq` is safe if no consumer pact reads it. This is what makes the provider's evolution *safe and unilateral* — and that, more than anything, is what makes contract testing pay back.

---

## 2. The Pact-style flow (most CDC tools follow this)

The flow has five named steps. Names vary by tool; the steps are universal.

1. **Consumer test.** The consumer writes a test using a tool-provided **mock provider** (Pact: an HTTP mock; SCC: a WireMock stub from a contract; gRPC contract tools: a generated service stub). The consumer test exercises the consumer's own code; the mock provider returns the response the consumer claims to expect. **The pact file is a by-product of this test running.**

2. **Publish.** The pact is uploaded to a **broker** (or an artifact repository), tagged with the consumer name, version (typically the git SHA), and branch.

3. **Provider verification.** The provider's CI pulls the consumer pacts that target it. For each interaction in each pact: stand up the real provider, set up the data the contract requires via **provider state handlers**, replay the request, assert the response. Publish the result back to the broker.

4. **Reconciliation.** The broker now knows the matrix: which consumer versions are satisfied by which provider versions. This matrix is queryable.

5. **Deploy gate.** Before deploying a version, ask the broker: "is this version compatible with every counterpart currently in environment X?" — the **can-i-deploy** check. If yes, deploy. If no, halt.

Steps 1-2 happen in the consumer's repo. Steps 3-4 happen in the provider's repo. Step 5 happens in both — every deploy of either side runs it.

The flow has two crucial asymmetries:

- **Tests run independently.** Consumer CI does not need provider; provider CI does not need consumer. The broker is the only shared dependency.
- **Versions are explicit.** Every pact and every verification result is keyed by version. You can answer "what does prod look like?" by querying the broker, not by SSH-ing into a server.

---

## 3. HTTP contracts vs message contracts

Both are CDC; the mechanics differ.

**HTTP / REST / gRPC contracts** capture a synchronous request/response interaction. The consumer test makes an HTTP call against the mock provider; the pact records request shape + response shape. Provider verification replays the request against the real provider over real HTTP.

**Message contracts** (Kafka, RabbitMQ, SNS/SQS, NATS, AWS EventBridge) capture an asynchronous interaction. There's no request/response; there's a **message** the producer publishes that the consumer expects to be able to handle. The contract has two halves:

- **Consumer half**: "if a message with this shape arrives on this channel, my handler processes it correctly." The consumer test feeds a recorded message into the consumer's handler.
- **Producer half**: "when this domain event happens, I publish a message with this shape." The producer verification triggers the production path that emits the message and asserts the emitted message matches the contract.

Both Pact (`MessagePact`) and SCC (`message` blocks) support this. The discipline is identical: the consumer specifies what shape it expects, the producer proves it emits that shape.

Subtleties specific to messaging:

- **Channel / topic / queue** is part of the contract — a message on the right shape but the wrong topic is a break.
- **Headers** (Kafka headers, JMS properties, AMQP headers) are part of the contract if the consumer reads them.
- **Ordering, partitioning, idempotency keys** are *behavioural* properties usually outside the message contract — they belong in integration tests, not pacts.
- **Schema-registry-backed serdes (Avro, Protobuf)** can do half the job of a contract — they enforce schema compatibility. They do **not** enforce semantics (what the fields *mean*); CDC complements the schema registry.

---

## 4. Schema-only contracts vs behaviour-driven contracts

A spectrum:

| Type | What it asserts | Tool examples | Cost |
|---|---|---|---|
| **Schema-only** | Shape and types of a payload match a schema | OpenAPI + Swagger Validator, AsyncAPI + AsyncAPI Validator, JSON Schema, Protobuf + buf-breaking, Avro + schema registry | Low — usually a CI step |
| **Behaviour-driven** | Specific scenarios produce specific responses — including provider state setup, status codes, error shapes, conditional branches | Pact, Spring Cloud Contract | Higher — requires consumer + provider participation |

Schema-only is **necessary but not sufficient**. The OpenAPI doc may say `total: number, required`; what it doesn't say is "when the order has no lines, the response is `400 with code=EMPTY_ORDER`". The consumer might depend on that specific error code; a schema validator won't catch its removal.

A common pragmatic shape:

- **OpenAPI as the schema floor** — verified in CI on every commit. The schema is generated from the controllers (via Springdoc), so it's never stale.
- **Pact / SCC for the behavioural contracts** — only for the *interactions consumers actually depend on*. Not every endpoint, not every branch — just what's load-bearing.

OpenAPI + Pact-for-the-load-bearing-cases is a defensible middle ground for teams who want most of the value at a fraction of the maintenance.

---

## 5. Versioning, compatibility windows, deprecation

Contracts evolve. Consumers evolve. Providers evolve. CDC tools surface compatibility breakage; they do not negotiate the social process. The team must.

**Versioning.** Every pact and every provider version is keyed by a unique identifier — by convention, the git SHA. Pact / SCC also support **tags** (typically `main`, `prod`, `staging`, `feat-foo`) which describe *where* a version is currently deployed. The matrix lookup uses tags: "compatible with everything in `prod`?".

**Compatibility windows.** A typical policy: a provider version must be compatible with all consumer pacts currently tagged `prod`. When a consumer publishes a new pact (e.g. requires a new field), the provider can either:

1. Already satisfy it (no-op — the provider was forward-compatible).
2. Implement and deploy support; the consumer can deploy *after* the provider's `prod` tag has been updated.

The can-i-deploy gate enforces this ordering automatically. The consumer cannot deploy a pact-breaking new version until the provider's `prod` version satisfies it.

**Deprecation flow** (the most useful CDC pattern in practice):

1. Provider decides to remove field `X`.
2. Provider talks to consumers (or simply queries the broker — "which consumers currently read `X`?").
3. Each consumer that reads `X` stops reading it; deploys; the new consumer pact no longer specifies `X`.
4. Once **all** consumer pacts on `prod` no longer specify `X`, the provider can remove it.
5. Provider's can-i-deploy passes; provider deploys.

Without CDC, step 2 is a Slack message; step 4 is "I hope". With CDC, both are queries against the broker. The deprecation flow is no longer guesswork.

---

## 6. The broker — central source of truth

The broker is what turns CDC from "two interesting tests" into "an operating model".

What the broker stores:

- **Pacts**, indexed by `(consumer, consumer-version, branch)` and `(provider)`.
- **Verification results**, indexed by `(consumer-version, provider-version, success/failure, timestamp)`.
- **Deployments / environment tags** — "this version is currently in `prod`".
- **Webhook configurations** — fire when a new pact arrives for provider P; fire when verification succeeds for consumer C.

What the broker exposes:

- **The matrix view** — for any (consumer, provider) pair, what versions are compatible.
- **can-i-deploy** — the deploy-time query.
- **Webhooks** — trigger provider CI on new pact arrival; trigger consumer CI on provider release.
- **Notifications** — pact change feed, failed-verification alerts.

The two production options:

- **Pact Broker (open source)** — self-hosted; you run it.
- **Pactflow (SaaS)** — managed; the team behind Pact.

Both have feature parity for the core matrix + can-i-deploy. Pactflow adds bidirectional contracts (mixing Pact with OpenAPI), a hosted UI, and SSO. The decision is operational, not technical.

A common mistake: **running CDC without a broker, sharing pacts via Git or email**. This works for a single pair of services for one quarter; it falls apart the moment there are 5 consumers, 3 environments, and a deploy gate. The broker is not optional infrastructure — it is the contract-test substrate.

---

## 7. can-i-deploy — the deploy-time check

The single most valuable artefact of a working CDC setup:

```bash
pact-broker can-i-deploy \
  --pacticipant order-service \
  --version $GIT_SHA \
  --to-environment production
```

This returns:

- `Computer says yes` → safe to deploy. Every relevant consumer (or provider) version in `production` is compatible with this version.
- `Computer says no` → halt. The output names the incompatible counterpart and the specific interaction.

`can-i-deploy` is meant to be wired into the deploy pipeline as a **hard gate**:

```yaml
# deploy.yml (CI pseudocode)
- name: contract check
  run: pact-broker can-i-deploy --pacticipant order-service --version $GIT_SHA --to-environment production
- name: deploy
  run: ./deploy.sh
```

Without can-i-deploy, the rest of CDC is documentation. With it, the team has a tested guarantee: nothing breaks production *because of a cross-service incompatibility*. (Plenty of other things still break production. CDC narrows one category.)

---

## 8. Contract test failure modes and how to debug

A failing consumer test: usually the consumer is asserting on its own behaviour, not the contract. Treat as a normal test failure.

A failing **provider verification** is the interesting case. The flow:

1. **Read the verification output.** It names the consumer, the consumer version, the specific interaction (`given...when...then...`), and the diff between expected and actual response.
2. **Is the consumer's expectation correct?** If the consumer is asserting on a field it doesn't actually use, this is over-specification on the consumer side. Fix the consumer test.
3. **Is the provider's behaviour correct?** If the provider has genuinely broken the API, decide: roll back the breaking change, or coordinate a deprecation flow with the consumer.
4. **Is the provider state set up correctly?** A common failure: the consumer's interaction expects `given a paid order`, but the provider's `@State("a paid order")` handler created a draft order. The verification fails because the state didn't match. Fix the state handler.
5. **Is there a schema vs semantics mismatch?** The schema says `totalAmount: number`; the provider returns `1500` (cents) but the consumer expected `15.00` (dollars). The schema passes; the semantics break. Fix the contract to specify units.

The broker stores the verification artefacts; debugging usually starts by opening the failed verification in the broker UI, not by re-running.

Common failure-mode patterns:

- **"The pact didn't change, why is verification suddenly failing?"** → The provider changed. Run `git log` on the production code path involved. Usually a recent commit removed a field, changed an error code, or modified an exception mapping.
- **"It works locally but fails in CI."** → Provider state handler depends on something CI-specific: time zone, hostname, environment variable, cached data. Make state handlers self-contained.
- **"It passes verification but breaks in production."** → The contract was under-specified. The consumer reads a field the contract didn't pin down, the provider changed it, contract verification couldn't catch it. Tighten the consumer test.
- **"It passes verification but the consumer breaks anyway."** → The consumer changed *its* expectations without updating the pact. Almost always a developer who hand-edited the pact or skipped the consumer test. Don't hand-edit pacts.

---

## 9. When CDC is overkill — Pact's own guidance

Pact's documentation is admirably honest: *"if you don't have multiple services with independent release cycles, you probably don't need Pact."* The full list of CDC anti-fits:

- **A single service.** Nothing to contract with.
- **A monolith.** In-process module boundaries do not warrant cross-service contract tests — `test-architecture` (ArchUnit / Modulith) is the right tool.
- **A single team owning both sides, deploying together.** A shared types module + slice tests on each side is cheaper and equally informative.
- **A very stable API that hasn't changed in two years.** Maintenance of pacts exceeds the regression-protection they provide; a small set of smoke / integration tests is enough.
- **External APIs you don't own.** You cannot run provider verification on a third-party API. Document expectations via consumer-side pacts (still useful as documentation) but the can-i-deploy gate is meaningless against an external.
- **Throw-away services.** Investment doesn't recoup inside the lifetime.
- **GraphQL.** Pact has support for GraphQL but the contract surface is fundamentally different (clients query the fields they need, the server schema is the contract). Persisted-queries + schema-diffing tools (Apollo Studio, Hasura) are usually a better fit.

Be honest about the inflection point. Most teams introducing CDC do it too early (one service, hopeful) or too late (a dozen services with broken e2e cycles, painful). The signature signal that you've hit the inflection point: **two recent production incidents caused by cross-service incompatibility that an e2e test in staging didn't catch**. At that point CDC pays back fast.

---

## 10. Anti-patterns

- **Provider-driven contracts.** The provider writes the contract and tells the consumer "you must satisfy this". This is back-to-front; the consumer specifies its needs, not the other way around. The artefact may be a Pact file, but the *flow* is no longer consumer-driven and the benefits collapse.
- **Over-specified consumer expectations.** The consumer asserts on every field, exact types, exact strings, exact error messages. Every legitimate provider refactor looks like a contract break. The discipline: assert only on what the consumer **actually reads** — usually a small subset of the response.
- **One mega-pact with 80 interactions.** Splits poorly across teams and runs serially in provider verification. Split by consumer responsibility / use case.
- **Hand-editing pacts.** Pacts are generated artefacts. Hand-edits are silently overwritten on the next consumer test run. If the expectation needs adjusting, adjust the consumer test.
- **Skipping the broker.** Pacts in Git or email work for a single pair, briefly, then fail to scale. Invest in the broker — it's not optional.
- **Provider verification as a nightly job.** Feedback is 24h; breakages ship for a day. Verification is PR-gate.
- **No can-i-deploy.** PR-gate verification proves *test-time* compatibility. By deploy time, new pacts may have arrived. can-i-deploy is the deploy-time check; skipping it means CI passes and production breaks.
- **Pact for what should be an integration test.** A test that requires real DB rows, real Kafka serdes, real Spring Security wiring — Pact is the wrong tool. Slice tests / integration tests on each side; Pact only for the cross-service *interface*.
- **Pact for what should be an architecture test.** Cross-module boundaries inside one service belong to `test-architecture` (ArchUnit / Modulith), not Pact.
- **Treating the broker as ephemeral.** If the broker is down or the data is lost, can-i-deploy fails open or fails closed depending on configuration — either way, the deploy pipeline is degraded. Treat the broker as production infrastructure.
- **Letting the contract suite drift unmaintained.** Outdated pacts referencing removed consumers; failed verifications nobody investigates; a "broken main" that the team has stopped looking at. The contract suite must be tended like any other production system.
