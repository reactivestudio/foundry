# Context Discovery

> Before suggesting any architecture, gather context. The cost of designing for the wrong problem is far higher than the cost of asking five extra questions up front.

## Question hierarchy (ask in this order)

You usually do not need all of these. Start at the top and stop when you have enough to rule out the obviously-wrong options.

### 1. Scale (now and in 12 months)
- How many users / tenants today? In 12 months?
- Data volume? (MB → GB → TB → PB)
- Read vs. write ratio?
- Transaction rate? (per second / per minute / per day)
- Peak / off-peak shape? Is the load steady or bursty?

### 2. Team
- Solo developer, small team, or multi-team?
- Distributed or co-located?
- Senior-heavy or junior-heavy?
- Existing expertise on the stack you're considering?
- Who will operate this in production?

### 3. Timeline & lifecycle
- MVP / prototype, or long-term product?
- Time-to-market pressure?
- Expected lifespan (months, years, decade)?
- One-time deliverable or living system that evolves?

### 4. Domain
- CRUD-heavy or business-rule-heavy?
- Strong invariants (financial, legal, safety-critical)?
- Real-time / synchronous, or async / eventual?
- Compliance / regulatory load (PCI, HIPAA, SOC2, GDPR)?
- Multi-tenant? Per-tenant isolation requirements?

### 5. Constraints
- Budget (build time, ongoing run cost)?
- Existing tech stack you must integrate with (or cannot touch)?
- Existing contracts (public APIs, vendor SLAs, regulator filings)?
- Hard deadlines tied to external events (regulator, customer go-live, partner launch)?
- Organizational constraints (only one team owns this; cannot hire; cannot adopt a new language)?

## Top-3 quality attributes (the most important question)

Almost every architectural decision is a trade between competing quality attributes. **Force yourself to name the top 3 that matter for this system, in order.** Examples:

| Quality attribute | Looks like |
|---|---|
| **Latency (p50 / p95 / p99)** | "Every API call must answer in under 200 ms p99." |
| **Throughput** | "100k events/sec ingest, sustained." |
| **Availability** | "99.95% over 30 days; no single deploy may cause downtime." |
| **Consistency** | "Money movement must be linearizable; reads after writes must reflect the write." |
| **Durability** | "No accepted write may be lost, even with two simultaneous node failures." |
| **Evolvability** | "We will change the data model 10× in year 1." |
| **Operational simplicity** | "One on-call engineer per 100 services is the budget." |
| **Cost** | "Infra cost per active user must stay under $X/mo." |
| **Security posture** | "Compromise of any one service may not leak tenant data." |
| **Time-to-feature** | "Adding a new vendor integration must take ≤ 1 sprint." |

If you cannot rank these for the system at hand, you are not ready to choose an architecture — go back to stakeholders. Picking everything as "important" is the same as picking nothing as important; you will get a design optimized for none of them.

## Quality attributes that lose

Naming the top 3 forces you to name the bottom 3 — the ones you will explicitly trade away. Saying "we'll accept higher latency to get stronger consistency" is a real decision; saying "we want everything" is a refusal to decide.

## Project classification matrix

A rough sanity check once you have the answers above. Most systems are not exactly any of these — the matrix is for calibration, not prescription.

| Dimension | Prototype | Small product | Mid-size system | Large / regulated |
|---|---|---|---|---|
| Users | < 1k | 1k–100k | 100k–1M | 1M+ |
| Team | Solo | 2–10 | 10–50 | 50+ |
| Timeline | Weeks | Months | Years | Years (regulated lifecycle) |
| Lifespan | Throw-away likely | Living product | Long-lived | Long-lived + compliance |
| Architecture | Simplest that works | Modular monolith | Modular monolith → selective extraction | Multiple services + ops investment |
| Patterns | Minimal | Selective DDD / events | DDD, CQRS where read/write diverges | Comprehensive (DDD, CQRS, event-driven, mesh) |
| Operational burden | Negligible | Low | Real (on-call, dashboards) | Major (SRE function, runbooks) |

## When to stop asking

You have enough context when you can answer all four of these in one or two sentences:

1. What does success look like for this system in production?
2. What are the top 3 quality attributes, in order?
3. What constraints rule out the "obvious" answer?
4. What is the cheapest credible option, and why isn't it good enough?

If any of those four still drift into "it depends" — keep asking.
