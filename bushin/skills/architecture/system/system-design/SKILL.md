---
name: system-design
description: "Distributed-system design + review: NFRs → capacity → boxes → bottlenecks → scale. FAANG-rubric. NOT for class shape."
---

# System Design

Designing distributed systems from non-functional requirements: services, data stores, queues, scaling tactics. Sits *above* SOLID — `solid` shapes what's inside the boxes; this skill picks the boxes. Iteration is the job — later phases routinely send you back, that's not a flaw.

Each `resources/<x>.md` focuses on **the parts of system design baseline knowledge gets wrong**: per-operation consistency vs per-system, what CAP actually trades during a partition, idempotency over the exactly-once lie, when *not* to scale.

## When to use

- Designing a new service / subsystem / feature from scratch.
- Reviewing someone else's design in a doc / PR / ADR.
- Preparing for or running a FAANG-style system-design interview.
- Sizing a launch ("can this handle Black Friday?") via capacity estimation.

## The 7 phases

| # | Phase | Output | Resource |
|---|---|---|---|
| 1 | Clarify | FRs + NFR table with **numbers** | [design-process](resources/design-process.md) |
| 2 | Estimate | QPS, storage, bandwidth, peak ×3–5 | [capacity-estimation](resources/capacity-estimation.md) |
| 3 | High-level | 5–7 box diagram | [design-process](resources/design-process.md) |
| 4 | Component | Per box: responsibility, API, failure mode | [design-process](resources/design-process.md) |
| 5 | Detail | Data model, IDs, contracts, algorithms | [design-process](resources/design-process.md) |
| 6 | Bottlenecks | Named breaking points + thresholds | [pattern-library](resources/pattern-library.md) |
| 7 | Scale | "At 10×: do X" — a migration *path*, not a built-out architecture | [pattern-library](resources/pattern-library.md) |

## Procedure

1. **Pin NFRs as numbers.** "Fast" → "p99 ≤ 200ms". No numbers = no design, only theatre.
2. **Estimate before drawing.** 30 s of arithmetic rules out 100 architectures. ([capacity-estimation](resources/capacity-estimation.md))
3. **5–7 boxes; per-box failure mode.** Refuse premature depth; a box without a stated failure mode is decoration.
4. **Hunt the breaking point before scaling.** Hot key, sync chain, ID generator, connection pool — they break before CPU does. ([pattern-library](resources/pattern-library.md))
5. **Name every trade-off as you commit.** "Cache-aside; cost is stale reads up to TTL." Unnamed trade-offs = decoration. ([tradeoff-framework](resources/tradeoff-framework.md))

## Restraint defaults

Most system-design damage is **eager reach** for distributed tools. Defaults when tempted:

- **Sharding?** No, until single-node arithmetic shows it must fail. Postgres + LB handles more than most assume.
- **Microservices?** No, until org-scale, deploy independence, or independent-scaling pressure is real. They solve *organisational* problems, not technical ones.
- **Cache?** No, until measured read cost is the bottleneck. Stampede, invalidation, cold-start are real costs.
- **Strong consistency on a read path?** No, unless correctness demands it. 90% of reads tolerate seconds of staleness.
- **Queue / event?** **Yes** — async-by-default for non-correctness paths. Sync only what correctness requires.

Each speculative shard / split / cache taxes every future read and write — another failure mode, another consistency model, another operational surface. Default is **no**; wait for evidence (measured load, named bottleneck, real deploy-independence pressure).

## Review output

Three sections — the second is what separates careful review from naive review:

1. **Findings** — concrete gaps. NFRs without numbers; missing arithmetic; named bottlenecks; sync chains; missing idempotency on retried ops; hot-partition risk.
2. **Non-findings** — what *looks* wrong but isn't. Always check: eventual consistency on a display path; 1-hour cache TTL on tolerable-staleness data; single-region for a 99.9% SLO; monolith for a small team.
3. **Refactor sketch** — minimal change to address findings. Don't replatform.

## Quick red flags

- No capacity numbers — it's a vibe, not a design.
- "We need microservices" stated as a goal (not derived from NFRs).
- Strong consistency by default everywhere; cache with no staleness budget.
- Synchronous chains 5 services deep — latency stacks; one slow dep takes them all.
- "Exactly-once delivery" claimed, or retried ops without an idempotency key — both silent-duplicate traps.

## FAANG interview rubric

- **Clarify first** — FRs + NFRs + scale before drawing. Skipping is the #1 fail signal.
- **Show estimation** — arithmetic on paper reveals internalised hardware costs.
- **Deep-dive the interviewer's pick** — not every box.
- **Name trade-offs as you choose** — owning the cost is the senior signal.
- **Hunt the obvious bottleneck unprompted** — ID gen, hot key, sync chain.
- **Refine when challenged** — defending a flawed design is the loud junior signal.

## When NOT to use

- Class / module structure → `solid` (the level below).
- Method-level ownership / smells → `grasp`.
- Naming, functions, comments → `clean-code`.
