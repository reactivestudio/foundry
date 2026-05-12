# Review Checklists

> One checklist per concern area. Walk them in order. A checked item is one with **evidence** — file/path, design-doc paragraph, or runtime observation. Unchecked items are not failures; they're "I couldn't confirm" — flag them as findings or as scope gaps.

These checklists are the structural pass (§1) and the quality-attribute pass (§2–6) referenced from `SKILL.md`. The full smell catalog lives in `smells.md`.

---

## §1. Boundaries & coupling

### Module / context boundaries
- [ ] Each module / bounded context has a documented purpose in one sentence.
- [ ] The boundary is **defended by the type system** (separate packages, enforced visibility, ArchUnit / Modulith verifier), not only by convention.
- [ ] Cross-context calls go through a published contract (events, ports, API), not through internal types.
- [ ] No two contexts write to the same database table.
- [ ] No context reads another context's internal columns directly (only published views / contracts).

### Dependency direction
- [ ] Domain code does not import framework / persistence / vendor types.
- [ ] Adapter code may depend on domain ports, but never the reverse.
- [ ] No cyclic module dependencies (direct or transitive).
- [ ] If using a layering style (Onion / Clean), the inward-pointing rule is enforced (architectural test in CI).
- [ ] Contracts published to other modules expose only stable types (IDs, value objects, events) — no entities, no persistence types, no vendor enums.

### Coupling shape
- [ ] No "god service" — one module accounting for > ~50% of writes or > ~7 entities.
- [ ] Most features touch ≤ 2 contexts; if every feature touches > 3, the boundaries are wrong.
- [ ] Cross-cutting concerns (logging, tracing, security) are added by infrastructure / aspects, not duplicated in every service.
- [ ] No layer-skipping — controllers → services → domain → ports (or whatever the agreed flow is) is honored.

---

## §2. Data ownership & integration

### Ownership
- [ ] Every piece of data has exactly one writer.
- [ ] Read access by other modules is via published contract or read model, not direct table access.
- [ ] Shared / reference data (lookups, country codes, currencies) has a documented owner.
- [ ] No "we'll figure out ownership later" tables.

### Integration shape
- [ ] Each cross-service / cross-context call is documented: contract, idempotency, retry behaviour, timeout, fallback.
- [ ] Async paths use the right tool for the job (in-process events / queue / log) — see `smells.md §2.3, §2.4`.
- [ ] Outbox or equivalent pattern in use where transactional consistency + external publication is needed.
- [ ] Retried operations are idempotent (especially anything touching money, third parties, or notifications).
- [ ] Events crossing context boundaries use published-language types, not internal entities.

### Persistence shape
- [ ] Each persistence store has a documented reason for being part of the stack.
- [ ] Polyglot persistence is justified by workload divergence, not by team preference.
- [ ] Migrations are backward-compatible (zero-downtime path documented for every breaking change).
- [ ] Indexes have a documented query that justifies them; unused indexes are removed.

---

## §3. Quality attributes

Walk this section once per dominant NFR identified at scope time. For each, the design must have an **answer** with evidence — not just an aspiration.

### Performance (latency / throughput)
- [ ] Top 3 critical paths identified, with declared p50 / p95 / p99 budgets.
- [ ] Load tests / benchmarks exist that exercise the budgets (or there's a tracking issue to add them).
- [ ] No N+1 queries on critical paths (joins, batch fetches, or denormalized reads in place).
- [ ] Caching strategy chosen deliberately (or absence justified). Cache invalidation has a story.
- [ ] No unbounded fanout — paginated, batched, or capped.

### Scalability
- [ ] Stateless services where possible; state isolated and identified.
- [ ] Horizontal scaling is possible without coordination (or coordination is via the store, not via in-memory state).
- [ ] Database scaling path documented (read replicas, partitioning trigger, sharding plan if/when).
- [ ] Capacity headroom against expected 12-month load is positive.

### Availability & failure mode
- [ ] Each downstream dependency has a declared failure behaviour (timeout, retry, circuit breaker, fallback, fail-open vs. fail-closed).
- [ ] Critical paths have a documented behaviour under each downstream's failure.
- [ ] Deploys are rollback-able in < 10 min (or rollback procedure is documented).
- [ ] No single point of failure on the critical path (or risk is accepted explicitly with rationale).

### Consistency
- [ ] Each piece of data has a documented consistency level (strong, read-your-writes, eventual, causal).
- [ ] Eventual-consistency reads have a documented "how stale is acceptable" budget.
- [ ] Multi-step workflows that need atomicity use one transaction (or a saga with documented compensations).

### Security
- [ ] Authentication boundary is at the edge, not inside services.
- [ ] Authorization checks are at the layer that enforces invariants (usually domain / service), not only at the controller.
- [ ] Tenant isolation enforced in code AND tested (no "we trust the caller").
- [ ] No PII / credentials / tokens in logs, traces, or external error reports.
- [ ] Secrets via dedicated mechanism (Vault / cloud secret manager / env), never committed.
- [ ] OWASP API Top 10 reviewed for this service.
- [ ] For deep audits, recommend the dedicated security skill — this is the structural pass only.

### Observability
- [ ] Critical paths emit metrics (latency, error rate, throughput).
- [ ] Logs are structured (JSON / key-value), include trace ID / request ID, and exclude PII.
- [ ] Distributed tracing context propagates across service boundaries.
- [ ] Dashboards exist for the critical paths (or there's a tracking issue).
- [ ] SLOs declared and monitored where the system has external commitments.

---

## §4. Change resilience

- [ ] Known upcoming changes (multi-tenancy, second vendor, new region, new currency, new auth method) have an identified landing place — not "we'll figure it out."
- [ ] Public contracts are versioned, or versioning policy is declared ("we may break in major versions only").
- [ ] Deprecation path documented for anything currently being phased out.
- [ ] Feature flags / kill switches exist for risky changes.
- [ ] Reversibility is acknowledged: one-way doors (data migrations, contract changes, persistence-engine swaps) get the deliberation budget; two-way doors don't.

---

## §5. Operational readiness

- [ ] Health check / liveness / readiness endpoints exist and are honest (do not return OK when downstreams are down on the critical path).
- [ ] Deployment process documented (blue/green / canary / rolling).
- [ ] Rollback procedure documented and exercised.
- [ ] On-call runbook exists for known failure modes; alerts link to runbook entries.
- [ ] Resource limits (memory, CPU, threads, connections) are sized and enforced.
- [ ] Backup / restore procedure for stateful components is documented and tested.

---

## §6. Documentation & decision trail

- [ ] Non-obvious decisions are captured as ADRs.
- [ ] Each ADR has trade-offs, rationale, and a revisit trigger (not just "we chose X").
- [ ] An ADR index exists; superseded ADRs are marked.
- [ ] Architecture diagrams reflect the current code (no diagrams-that-lie).
- [ ] Onboarding docs let a new engineer understand the high-level shape in < 30 minutes.
- [ ] One-way-door decisions have ADRs; two-way doors don't need them.

---

## §7. Process smells (light pass — usually 💭 Suggestion)

- [ ] If there is no ArchUnit / Modulith verifier / dependency test in CI, recommend adding one.
- [ ] If ADRs exist but lack revisit triggers, recommend backfilling.
- [ ] If review cadence is unclear (this might be the first architecture review in 12 months), recommend a regular interval.

---

## Calibration: when to be strict vs. lenient

These checklists default to "production system, real load, real consequences." Adjust:

- **Prototype / spike**: §1–2 still matter (boundaries are cheap if drawn early). §3–5 are mostly aspirational at this stage — note them as Suggestions if missing.
- **Internal tool with one user**: §3 collapses to "latency is fine" and §5 to "if it breaks, the user notices." Don't manufacture critical findings for a low-stakes system.
- **Regulated / compliance-bearing**: §3 (security) and §6 (decision trail) become hard requirements. Many Minors become Majors.
- **Greenfield design review** (before code): §1–2 + §4 are the heart. §5 mostly becomes "what's the plan?"

Calibration is part of scope (Phase 1). State the calibration in the report's Scope section so the severity grades are interpretable.
