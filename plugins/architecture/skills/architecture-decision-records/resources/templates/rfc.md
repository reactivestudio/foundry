# RFC-Style Template

Use for *proposals* — decisions still under discussion, larger in scope than a single ADR, with open questions that need team / stakeholder input before becoming an accepted ADR.

An RFC graduates into one or more ADRs once decisions are made. RFCs are explicitly *not* final — they document the proposal phase, not the decision.

```markdown
# RFC-NNNN: <Proposal title>

## Status

Draft | Under Review | Accepted (split into ADR-XXXX, ADR-YYYY) | Rejected | Withdrawn
Date: YYYY-MM-DD
Author(s): @alice, @bob
Reviewers requested: @charlie, @diana, @team-payments

## Summary

<2-4 sentences. The shortest description of what is being proposed and why. A reader
should know whether to keep reading after this section.>

## Motivation

<What problem are we solving? What can we currently not do, or do poorly?
Tie to concrete pain — incidents, customer complaints, scaling bottlenecks, audit findings.>

Current challenges:
1. <Concrete pain>
2. <Concrete pain>
3. <Concrete pain>

## Detailed design

<The body of the proposal. How would this work?
Diagrams, code shapes, data models, sequence diagrams, API stubs.
This is the section reviewers will spend the most time on.>

## Drawbacks

<Be honest about what this costs.>

- <Cost: learning curve, complexity, ops burden>
- <Risk: what could go wrong>
- <Trade-off: what we'd give up>

## Alternatives

<Two or three real alternatives, each with a paragraph.>

1. **<Alternative>** — <Pros / cons / when this would be the right answer>
2. **<Alternative>** — …
3. **Do nothing** (always include this) — <What's the cost of the status quo? Be honest about how bad it actually is.>

## Open questions

<The questions that still need answering before this can become an ADR.
This section is the *purpose* of the RFC — list the things the reviewers should
weigh in on.>

- [ ] <Open question>
- [ ] <Open question>
- [ ] <Open question>

## Unresolved decisions

<Decisions that this proposal explicitly defers. Useful for keeping scope tight —
"we will decide X separately later" is better than X silently becoming part of the
proposal.>

## Implementation plan

<If accepted, how would this roll out?>

1. Prototype phase (<duration>): <scope>
2. Team training / migration prep (<duration>): <scope>
3. Full implementation (<duration>): <scope>
4. Monitoring and follow-up (ongoing)

## Success criteria

<How will we know this worked? What metric or observation would confirm the proposal
was right? What would suggest it wasn't?>

## References

- <External patterns, vendor docs, similar implementations elsewhere>
- <Internal design docs, related ADRs, dashboards>
```

## When to write an RFC vs. an ADR

**RFC** is appropriate when:
- The scope is bigger than one decision (introducing event sourcing, restructuring auth, adopting a new platform).
- Multiple alternatives need real exploration, not just listing.
- Open questions need stakeholder input before any decision is final.
- The decision needs explicit team / cross-team buy-in before implementation.

**ADR** is appropriate when:
- The decision is made (or close to made).
- The alternatives are clear and the trade-off is the message.
- The audience is future readers, not current debaters.

## Graduation from RFC to ADR

When an RFC reaches consensus, write one or more ADRs that capture the decisions made. The RFC stays in the trail with status `Accepted (split into ADR-XXXX, ADR-YYYY)`. The ADRs reference the RFC for full motivation context.

A rejected or withdrawn RFC is also valuable — it's evidence the team considered a path and chose not to take it. Keep it. Mark the status.
