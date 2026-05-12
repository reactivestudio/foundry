# Architectural Smell Catalog

> A smell is not a bug. It is a *pattern of evidence* that the design has drifted from what it should be. Each entry has a detector (how to spot it), why it hurts (what it costs), and severity guidance (when it earns Critical vs. Major vs. Minor).

## How to use this file

1. Walk the catalog top-to-bottom on the system under review.
2. For each smell, scan for the detector signal. If absent, move on.
3. If present, capture: **location** (file/path/diagram section), **evidence** (concrete observation, not "feels wrong"), **severity** (using the guidance below), **recommendation** (smallest change that addresses the smell).

A smell with no concrete evidence is not a finding — it's a hunch. Hunches go in "Suggestions" at most.

---

## §1. Boundary & coupling smells

### 1.1 Distributed monolith
- **Detector**: Multiple deployable services, but releasing one forces coordinated release of N others. Cross-service calls in nearly every request path. Schema changes ripple across repositories.
- **Why it hurts**: All the operational cost of distributed systems (network, partial failure, deploy choreography) with none of the benefits (independent evolution, fault isolation, team autonomy).
- **Severity guidance**: 🔴 Critical if deploys already block on coordination; 🟠 Major if the coupling is structural but rare in practice.

### 1.2 God service / god aggregate
- **Detector**: One module owns > ~50% of writes, or > ~7 entities, or > ~30% of the codebase. Most cross-module calls terminate here.
- **Why it hurts**: Single point of contention. Blast radius of any change is huge. Hard to staff (one team becomes a bottleneck). Hard to evolve (every change risks every consumer).
- **Severity guidance**: 🟠 Major in most cases; 🔴 Critical if the god service is also a single point of failure with no fallback.

### 1.3 Hidden coupling via shared DB
- **Detector**: Two modules write the same table, or one module reads another's internal columns/schema, or schema changes require coordinated PRs across modules.
- **Why it hurts**: The "boundary" between modules is fiction — the database is the real coupling. Schema migrations break adjacent modules silently. Refactoring requires lockstep changes.
- **Severity guidance**: 🔴 Critical if shared schema spans bounded contexts; 🟠 Major if it's within one context but across modules.

### 1.4 Layer-skipping
- **Detector**: Controllers / HTTP handlers calling repositories or persistence code directly, bypassing service / domain / use-case layers. Or domain code calling adapters directly.
- **Why it hurts**: Either the skipped layer is useless and should be deleted, or the skip is a bug that bypasses business rules. Either way, the layering is dishonest.
- **Severity guidance**: 🟠 Major if invariants live in the skipped layer; 🟡 Minor if the layer is purely structural and the skip doesn't lose anything (and consider deleting the layer).

### 1.5 Reversed dependency direction
- **Detector**: Domain code imports framework / persistence / vendor types. `@Entity` annotations on classes the domain uses as concepts. Domain tests require a Spring context or a database.
- **Why it hurts**: Domain rules become coupled to ORM lifecycle / framework conventions. Refactors cascade outward instead of inward. Testing the domain requires booting half the world.
- **Severity guidance**: 🟠 Major in long-lived domains; 🟡 Minor in CRUD-heavy modules where the domain layer is light.

### 1.6 Cyclic module dependencies
- **Detector**: Module A → B and B → A (directly or transitively). Cycles in the package / module graph.
- **Why it hurts**: Modules cannot be reasoned about in isolation. Refactoring becomes "big-bang" because nothing can be touched alone. Build / class-loading order issues. Modulith verifier failures.
- **Severity guidance**: 🟠 Major; 🔴 Critical if the cycle crosses bounded contexts.

### 1.7 Leaky abstraction
- **Detector**: A contract / domain / port type exposes framework, vendor, or persistence concepts (e.g., a `Repository` interface returning JPA-managed entities; a public DTO containing vendor enums).
- **Why it hurts**: The abstraction does not pay for itself — swap cost is just moved one layer out, not removed. Consumers couple to the leaked type.
- **Severity guidance**: 🟠 Major if the leaked type is on a published contract; 🟡 Minor if internal to a single module.

### 1.8 Conway's Law violation
- **Detector**: Module / service boundaries cut across team boundaries — one service is owned by three teams, or one team owns ten unrelated services.
- **Why it hurts**: Every change requires cross-team coordination. Decisions stall. Quality slips at the seams nobody fully owns.
- **Severity guidance**: 🟠 Major; flag as 🔴 Critical when there's no owner for a service in production.

---

## §2. Data & integration smells

### 2.1 Single-store reflex
- **Detector**: All workloads (OLTP, search, analytics, time-series, document) on one engine (usually Postgres), even when one workload visibly fights the store (slow LIKE %x%, missing GIN index, hot tables full-scanned for analytics).
- **Why it hurts**: OLTP suffers from analytical queries; analytics is slow because Postgres isn't a column store; indexes multiply to compensate, slowing writes.
- **Severity guidance**: 🟠 Major when the wrong-tool pain is measurable; 🟡 Minor when it's still hypothetical.

### 2.2 Polyglot for-its-own-sake
- **Detector**: Mongo + Postgres + Elasticsearch + Clickhouse + Redis, but the workloads do not justify each store. Each store has < 10% of the data.
- **Why it hurts**: Operational cost (backups, monitoring, on-call expertise) scales linearly with stores. Cross-store consistency becomes a problem you invented yourself.
- **Severity guidance**: 🟡 Minor; 🟠 Major if the team is fewer than one expert per store.

### 2.3 Async-for-async-sake
- **Detector**: A synchronous workflow wrapped in a message queue with no real decoupling need (single producer, single consumer, no replay, no buffering).
- **Why it hurts**: Eventual consistency cost without the eventual benefit. Debugging becomes harder. Error paths multiply (retry, DLQ).
- **Severity guidance**: 🟡 Minor; 🟠 Major if it's also a hidden coupling point (consumer outage stops the producer).

### 2.4 Sync-for-async-need
- **Detector**: A user-visible HTTP request blocks on a slow downstream (third-party API, batch job, ML model). p99 spikes correlate with downstream availability.
- **Why it hurts**: Cascading failures — downstream slowness becomes upstream slowness, then upstream timeouts, then upstream outage.
- **Severity guidance**: 🟠 Major; 🔴 Critical if the downstream has a known SLA worse than the upstream's promised SLA.

### 2.5 N+1 by design
- **Detector**: A query in a loop, or a `forEach { fetchById(...) }`, or a controller method that fans out per-item DB calls.
- **Why it hurts**: Latency multiplied by N, with no upper bound on N. Looks fine in test data and dies in production.
- **Severity guidance**: 🟠 Major; 🔴 Critical if N is user-controlled (request body decides the fanout).

### 2.6 Boundary-leaking events
- **Detector**: Domain events published with internal types (entities, ORM-managed objects, vendor payloads), or events that consumers must understand internal aggregates to interpret.
- **Why it hurts**: Consumers are coupled to producer internals through the event payload. The event becomes a leak, not an abstraction.
- **Severity guidance**: 🟠 Major; 🔴 Critical if events cross bounded contexts.

### 2.7 Missing idempotency on retried operations
- **Detector**: An endpoint or consumer that retries on failure, but a duplicate delivery would cause a duplicate side effect (double charge, double email, double row).
- **Why it hurts**: At-least-once delivery is the norm in distributed systems; without idempotency, retries cause data corruption. Manifests as rare, hard-to-reproduce duplicates.
- **Severity guidance**: 🔴 Critical for money / external side effects; 🟠 Major for internal state.

---

## §3. Domain & responsibility smells

### 3.1 Anemic domain model
- **Detector**: Entities are getter/setter bags with no behaviour. Business rules live in services / handlers / "managers." `if (...) throw ...` validation scattered across callers.
- **Why it hurts**: Invariants are not enforced where the data lives. Every caller re-implements them — usually inconsistently. New consumers forget rules existing consumers handle.
- **Severity guidance**: 🟠 Major in domain-rich modules; 🟡 Minor in CRUD-heavy ones where there is little domain logic to anemic-ify.

### 3.2 Primitive obsession at the domain edge
- **Detector**: Domain APIs accept `String userId`, `String currency`, `Long amount` — never `UserId`, `Currency`, `Money`. Validation is repeated at every call site.
- **Why it hurts**: Type system cannot help. Wrong-thing-as-string bugs become routine. Refactoring touches every call site.
- **Severity guidance**: 🟡 Minor mostly; 🟠 Major when the primitive carries unit ambiguity (cents vs. dollars, ms vs. s).

### 3.3 Smart UI / fat controller
- **Detector**: HTTP controllers contain business logic, multiple DB calls, branching on domain state, validation rules.
- **Why it hurts**: Logic cannot be reused (CLI, scheduler, message handler all duplicate it). Tests must boot the web layer. Concerns mix.
- **Severity guidance**: 🟠 Major; 🟡 Minor for genuinely thin systems where there is no other entry point.

### 3.4 Service-as-procedure
- **Detector**: One huge `*Service` class with 30+ public methods, each doing a different workflow. No coherent responsibility, no shared invariants.
- **Why it hurts**: The class is a namespace, not an object. Cohesion is zero. Touching one method risks the others.
- **Severity guidance**: 🟡 Minor; 🟠 Major if the same service is also doing transactional control flow ambiguously.

### 3.5 Cross-context coupling without an ACL
- **Detector**: One bounded context imports types from another directly. No anti-corruption layer, no published-language adapter.
- **Why it hurts**: A vocabulary change in the upstream context cascades into the downstream. Two domain models pretend to be one.
- **Severity guidance**: 🟠 Major; 🔴 Critical when the upstream is an external vendor (vendor model leaks into the core domain).

---

## §4. Change-resilience & evolvability smells

### 4.1 Missing seam for known change
- **Detector**: A change is on the roadmap (multi-tenancy, second integration vendor, new currency, new auth method), and the codebase has no place to add it without surgery in N modules.
- **Why it hurts**: Future cost compounds. Each pre-seam release makes the eventual change more expensive.
- **Severity guidance**: 🟠 Major; 🔴 Critical if the change is contractually committed (regulator, signed customer).

### 4.2 Anaemic ADRs / no revisit triggers
- **Detector**: ADRs exist but read as "we chose X." No "trade-offs accepted," no "revisit if Y."
- **Why it hurts**: Decisions ossify. New team members inherit the status quo as fact. Nobody dares change it because no one remembers why.
- **Severity guidance**: 🟡 Minor mostly; 🟠 Major in long-lived systems where decisions span team generations.

### 4.3 No ADR at all for a one-way door
- **Detector**: A major irreversible decision (persistence engine, public API contract, auth provider, cloud provider) with no documented rationale.
- **Why it hurts**: When the cost of the decision shows up in 18 months, the context is gone. Revisit becomes folklore.
- **Severity guidance**: 🟠 Major; 🔴 Critical for compliance-relevant decisions.

### 4.4 Reversibility blindness
- **Detector**: Easily-reversible decisions (in-process abstraction, internal helper) get the full ADR treatment; one-way doors (data model, public contract) get a Slack thread.
- **Why it hurts**: Decision cost is mis-allocated. Heavy process kills small changes; light process lets big changes slip.
- **Severity guidance**: 🟡 Minor process smell; 🟠 Major if a one-way door is currently in flight without proper deliberation.

### 4.5 Premature optimization for scale you don't have
- **Detector**: Sharding, multi-region, CQRS, microservices for a system with < 1k users / < 10 GB of data / one office.
- **Why it hurts**: Complexity tax paid every day for capacity never used. Slower delivery, harder onboarding, more bugs.
- **Severity guidance**: 🟠 Major if it's slowing the team measurably; 🟡 Minor if it's "extra complexity" that's stable.

### 4.6 Premature microservices
- **Detector**: Service count > (team size / 3), or services share owners, or every feature touches > 3 services.
- **Why it hurts**: Conway's Law violated. Ops cost (deploy, mesh, tracing) without organizational benefit. Coordination overhead replaces internal coupling.
- **Severity guidance**: 🟠 Major; 🔴 Critical when also a distributed monolith (1.1).

---

## §5. Quality-attribute & operational smells

### 5.1 Missing or untested failure mode
- **Detector**: No declared behaviour for partial failure (downstream down, message queue down, DB read-only, network partition). No chaos / failure-injection tests.
- **Why it hurts**: First production failure is also the first thought about failure. Recovery is improvised under pressure.
- **Severity guidance**: 🟠 Major; 🔴 Critical for systems with high availability SLOs.

### 5.2 No observability for critical path
- **Detector**: Critical request path has no metrics, no structured logs, no traces. Operators have no way to answer "is it healthy?" or "where is it slow?" without code reading.
- **Why it hurts**: MTTR balloons. Regressions are detected by users, not dashboards.
- **Severity guidance**: 🟠 Major; 🔴 Critical for revenue-bearing paths.

### 5.3 Security as an afterthought
- **Detector**: Auth and authorization added late, scattered, or inconsistent. Tenants can read each other's data with the right URL. PII flows through logs.
- **Why it hurts**: Security boundaries built late are always porous. Compliance audits find the gaps eventually; attackers find them sooner.
- **Severity guidance**: 🔴 Critical for any tenant-isolation or PII smell; 🟠 Major for less acute gaps. Cross-link to `/security-review`.

### 5.4 No deploy / rollback story
- **Detector**: No documented way to roll back the deploy in < 10 minutes. Schema migrations are not backward-compatible. Deploys are scheduled around team availability.
- **Why it hurts**: Bad deploys become outages. Fear of deployment slows the team. Schema mistakes become surgery in production.
- **Severity guidance**: 🟠 Major; 🔴 Critical for systems with declared availability SLO.

### 5.5 Unbounded resource usage
- **Detector**: Endpoints that accept user-controlled `limit` / `page size` / `depth` with no cap. Queries that scan unbounded date ranges. Recursive operations with no depth limit.
- **Why it hurts**: One bad client (or one attacker) drives the system to OOM, timeout, or DoS itself. Capacity planning becomes guesswork.
- **Severity guidance**: 🟠 Major; 🔴 Critical for public / multi-tenant endpoints.

### 5.6 Hidden global state
- **Detector**: Singletons, thread-local context, "current user" magic, in-memory caches that survive request boundaries. Tests pass in isolation but fail in parallel.
- **Why it hurts**: Reasoning about behaviour requires knowing the whole state of the JVM. Flaky tests. Hard-to-diagnose production bugs.
- **Severity guidance**: 🟡 Minor for benign cases (configuration); 🟠 Major for mutable state.

### 5.7 Tight CI / no architectural test
- **Detector**: No ArchUnit / Modulith / dependency-test in CI. Boundaries enforced only by code review.
- **Why it hurts**: Review fatigue erodes the boundaries — small violations get waved through, then become the norm. The architecture quietly decays.
- **Severity guidance**: 🟡 Minor (a Suggestion is often enough): recommend adding ArchUnit or Modulith verifier tests.

---

## §6. Process & documentation smells

### 6.1 Architecture by accident
- **Detector**: No ADRs at all. No design docs. The architecture is whatever the code is.
- **Why it hurts**: New team members infer intent from code. Intent is lost. Refactors become risky because nobody knows what was deliberate.
- **Severity guidance**: 🟡 Minor early in a system; 🟠 Major past a year of life.

### 6.2 ADR sprawl
- **Detector**: 200 ADRs, half of them rubber-stamping naming conventions, no index, no superseded markers, no readme.
- **Why it hurts**: Decisions are unfindable. Real ADRs are buried under noise. Eventually treated as if there are none.
- **Severity guidance**: 🟡 Minor process smell. Suggest indexing and severity-grading the ADRs themselves.

### 6.3 Diagrams that lie
- **Detector**: Architecture diagram shows clean layers / boundaries that the actual codebase has not had for two years.
- **Why it hurts**: Onboarding teaches the wrong mental model. Decisions are made against the lie. Trust in documentation evaporates.
- **Severity guidance**: 🟡 Minor; 🟠 Major if the lying diagram is used for sales / compliance / regulator-facing material.

---

## When the catalog runs out

If you walk the entire catalog and find nothing, two possibilities:

1. The design is in genuinely good shape — say so explicitly in "What's working well." Reviews are not just bad news.
2. You scoped the review too narrowly or the catalog didn't fit this system — surface that ("smell catalog optimized for backend services; this is a CLI / library / data pipeline — please confirm scope").

Never invent findings to fill a section.
