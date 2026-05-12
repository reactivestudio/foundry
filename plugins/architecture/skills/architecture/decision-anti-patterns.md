# Decision Anti-Patterns

> Most bad architectures are not the result of bad decisions — they are the result of bad *deciding*. This file catalogs the recurring mistakes in how architectural choices get made.

## The three questions (before any non-trivial decision)

Before picking any pattern, store, framework, or service:

1. **Problem solved**: What *specific* problem does this solve that we have today (not in some imagined future)?
2. **Simpler alternative**: Is there a cheaper option that gets us ≥ 80% of the benefit?
3. **Deferred complexity**: Can we add this *later* when the trigger fires, instead of now?

If you cannot answer all three crisply, stop deciding and go back to discovery.

---

## Anti-patterns in the choice itself

### 1. Resume-driven design
**Signal**: The proponent recently saw a conference talk / read a book / left a job where the tech was used.
**Why it hurts**: Optimizes for the architect's career, not the system's fit. The team inherits operational cost from a choice driven by external incentives.
**Fix**: Force the rationale to name a quality attribute, not a technology. "We need X because *latency*" beats "we need X because *Kafka*."

### 2. Hype-driven
**Signal**: "Everyone is doing X" or "X is the modern way."
**Why it hurts**: Decouples the choice from the problem. Industry consensus is a useful prior, not a reason.
**Fix**: Ask "what *specifically* does X solve here that the boring alternative does not?"

### 3. Single-option "decision"
**Signal**: One option is presented as inevitable; no alternatives appear in the analysis.
**Why it hurts**: Decisions reduce to justifications. Trade-offs become invisible, so cost becomes invisible.
**Fix**: Always generate ≥ 2 real options, including the cheapest credible one ("status quo + small fix").

### 4. Premature optimization for scale you don't have
**Signal**: Designing for 100k users when you have 100; multi-region for one office; sharding for 10 GB of data.
**Why it hurts**: Pays huge complexity cost up front for capacity you won't use, while delaying the actual product.
**Fix**: Design for the next 12 months, with explicit revisit triggers for the next jump.

### 5. Premature pattern application
**Signal**: Introducing CQRS / event sourcing / microservices / clean architecture "because we might need it."
**Why it hurts**: Patterns trade simplicity for flexibility. Buying flexibility you don't need is paying for an option that never gets exercised.
**Fix**: Start simple. Add the pattern when the pain it cures actually exists.

### 6. Missing revisit trigger
**Signal**: "We'll switch / refactor / extract when needed" — without naming the metric that means "needed."
**Why it hurts**: "When needed" is never. The decision ossifies. The right-now-good-enough choice becomes the forever-stuck-with choice.
**Fix**: Every decision gets a concrete trigger: a metric ("p95 > 200ms"), an event ("second tenant onboarded"), a count ("team > 10").

### 7. Reversibility blindness
**Signal**: Same amount of agonizing for `pickAColor()` and `pickAStorageEngine()`.
**Why it hurts**: Two-way doors deserve speed (cost of being wrong is small); one-way doors deserve deliberation (cost of being wrong is large). Reversing them wastes time and creates risk.
**Fix**: Classify each decision upfront. Two-way: act. One-way: deliberate, write the ADR, get a second opinion.

### 8. Solving for the loudest voice
**Signal**: The decision tracks the most senior / most opinionated person in the room rather than the requirements.
**Why it hurts**: Authority is not analysis. Loud preferences become invisible defaults that nobody re-examines.
**Fix**: Insist that rationale ties to a quality attribute or constraint, not to "X thinks." Disagree-and-commit is fine; deciding-by-decibel is not.

### 9. Status-quo blindness
**Signal**: "Do nothing" is never explicitly compared — it just loses by omission.
**Why it hurts**: Often the cheapest option *is* status quo, and the proposed change cannot honestly beat it.
**Fix**: Always include the do-nothing option in the comparison. Force it to lose on the merits.

### 10. The "everyone wins" trap
**Signal**: The analysis claims the chosen option is best on every quality attribute.
**Why it hurts**: Either the analysis is dishonest, or the alternatives were strawmen. There is always a trade.
**Fix**: Name what the chosen option *loses* on. If you cannot, the analysis is incomplete.

---

## Pattern-specific anti-patterns

Mistakes that recur for specific patterns. The fix is almost always "use the simpler thing until the simpler thing actually hurts."

| Pattern | Anti-pattern | Simpler alternative |
|---|---|---|
| **Microservices** | Premature splitting before bounded contexts are stable. | Modular monolith first; extract a service only when team size + scale need actually require it. |
| **Clean / Hexagonal architecture** | Interfaces for every class "in case we swap implementations." | Concrete classes first; introduce interfaces at the seams that actually need them. |
| **Event sourcing** | Adopted for the audit trail. | Append-only audit log table. Event sourcing is for replayable state, not for "we want history." |
| **CQRS** | Split read/write models when reads and writes share shape. | Single model. Adopt CQRS when read patterns genuinely diverge from write patterns. |
| **Repository pattern** | Wrapping Spring Data JPA `JpaRepository` in another `*Repository` "for testability." | Use Spring Data repositories directly; introduce a domain repository interface only when the domain has invariants that should not depend on the persistence library. |
| **Saga / orchestration** | Distributed sagas for workflows that fit in one transaction. | Single-DB transaction. Sagas exist for cross-service consistency, not for in-service workflow. |
| **GraphQL** | Adopted "for flexibility" with one consumer. | REST. GraphQL pays off with many heterogeneous clients, not one. |
| **Service mesh** | Installed before there are services to mesh. | Application-level retries and timeouts; mesh becomes worth it past ~10 services with mTLS / traffic-shaping needs. |
| **Kafka** | Used as a queue for in-process or near-real-time workflows. | Spring Modulith events (in-process) or RabbitMQ (cross-service queue). Kafka is for durable streams and replay. |

---

## Anti-patterns in the *process* of deciding

### Bikeshedding
The team spends an hour on the name of the module and five minutes on the decision to introduce it.
**Fix**: Spend deliberation proportional to reversibility. Names are two-way doors; architectural commitments are not.

### Late binding to constraints
The constraints get discovered halfway through the design — usually because nobody asked the right people at the start.
**Fix**: Constraints first, options second. If you can't list the top 3 constraints in one sentence each, you don't know them yet.

### Architecture astronauting
The discussion floats free of any specific user story, query, or workflow.
**Fix**: Tie every option to a concrete scenario: "this user does X, the system answers in Y, the data flow is Z."

### Death by analysis
Three options become twelve, then a matrix, then a sub-matrix. The decision never happens.
**Fix**: Cap options at 3–5. Time-box the analysis. Accept that "good enough now" beats "perfect later."

### Sunk-cost decisions
"We already built half of this, so we'll keep going." The half-built architecture biases the choice.
**Fix**: At decision time, treat sunk cost as zero. Ask "if we were starting today, what would we choose?" If the answer differs, the right move is usually to switch.
