# MADR Template (Standard, full)

The default for non-trivial decisions. Use when the decision is durable, touches multiple stakeholders, or is irreversible (one-way door).

When the decision is small and local, use `lightweight.md` instead. When it's a proposal-stage open question, use `rfc.md`.

```markdown
# ADR-NNNN: <Short, decision-shaped title — verb in past or present tense>

## Status

Proposed | Accepted | Deprecated | Superseded by [ADR-MMMM]
Date: YYYY-MM-DD
Deciders: @alice, @bob

## Context

<Why we needed to decide. What's the problem, what's the forcing function, what changed.
Concrete enough that someone new to the team can follow. Avoid abstract justifications;
prefer load numbers, deadline dates, contract names, customer asks.>

## Decision Drivers

* **Must / should / nice to have** — name the constraint, not the wish.
* Order them — drivers higher up break ties.
* Drivers that lost should still appear (so future readers see what was traded).

## Considered Options

### Option 1: <name>
- **Pros**: <what it buys — tie to drivers>
- **Cons**: <what it costs — be honest>
- **Reversibility**: two-way door | one-way door
- **When this would be the right answer**: <conditions that would flip the decision>

### Option 2: <name>
- **Pros**: …
- **Cons**: …
- **Reversibility**: …
- **When this would be the right answer**: …

### Option 3: Status quo + small fix (always include this option)
- **Pros**: …
- **Cons**: …

## Decision

**Chosen**: <Option N — short name>

## Rationale

1. <Reason tied to the highest-ranked driver>
2. <Reason tied to a constraint>
3. <Reason a cheaper option lost — be honest>

## Trade-offs accepted

- <What we are giving up — be specific>
- <Why this is acceptable — tie to the bottom-ranked drivers>

## Consequences

### Positive
- <Concrete benefit, with the driver it satisfies>

### Negative
- <Concrete cost, with mitigation>

### Risks
- <Risk + mitigation plan, or "accepted">

## Revisit trigger

- <A specific metric or event that should make us reopen this decision: "p95 > 200ms", "second tenant onboarded", "team > 10", "regulator filing required">

## Implementation notes

- <Pointers to follow-up tickets, libraries, conventions>

## Related decisions

- <ADR-MMMM — superseded by this / supersedes this / complements this>

## References

- <External docs, benchmarks, internal design docs, vendor pages>
```

## Sizing guidance

- **2 pages max** in printed form. If yours is longer, split or move detail to a linked design doc.
- **Decision Drivers** is the most-skipped section that hurts most when missing. A "decision" without drivers is a justification.
- **Revisit trigger** is the second most-skipped. A decision without a revisit trigger ossifies; nobody dares change it.
