# Trade-off Analysis

> Every architectural decision is a trade. The goal of this file is to make the trade explicit before you commit to it.

## The trade-off mindset

For every option, write down four things — not three, not five:

1. **What it costs** — build effort, run cost, learning curve, operational load.
2. **What it buys** — which quality attribute it improves, by how much.
3. **What it forecloses** — options it makes harder or impossible later.
4. **What it defers** — complexity you're choosing not to take on now (and the trigger that will force you to).

A "decision" without these four answers is a guess.

## Option comparison template

For each non-trivial decision, list at least 2 options and compare them on the same axes. Use this template — fill in only the rows that matter for the dominant quality attributes.

```markdown
## Decision: <one-line statement of the choice>

### Context
- **Problem**: <what we are solving>
- **Top 3 quality attributes (in order)**: <e.g., 1. evolvability, 2. p99 latency, 3. operational simplicity>
- **Constraints**: <team, time, budget, compliance, existing stack>

### Options

| Option | Build cost | Run cost | Buys (the top attribute) | Forecloses | Defers | Reversibility |
|---|---|---|---|---|---|---|
| A. Status quo + small fix | Low | Same | Marginal improvement | Nothing | Real fix to later | Two-way door |
| B. Targeted refactor | Medium | Same | Real improvement on attr #1 | Some attr #3 | Migration to attr #2 | Two-way door |
| C. Full re-architecture | High | Lower long-term | Strong on all 3 | A and B (sunk cost) | Nothing | One-way door (data migration) |

### Decision
**Chosen**: <option letter and one-line>

### Rationale
1. <Reason tied to the dominant quality attribute>
2. <Reason tied to a constraint>
3. <Reason a cheaper option was rejected — be honest>

### Trade-offs accepted
- <What we are giving up — be specific>
- <Why this is acceptable — tie to the bottom-3 attributes>

### Consequences
- **Positive**: <benefits we gain>
- **Negative**: <costs / risks we accept>
- **Mitigation**: <how we will address the negatives, if at all>

### Revisit trigger
- <A specific metric or event: "p95 > 200ms", "second integration vendor", "team > 10", "regulated tenant onboarded">
```

## Choosing between options — heuristics

### When two options look close, prefer:
- **The reversible one.** Two-way doors are cheap to walk back through; one-way doors are not.
- **The one with the cheaper run cost.** Build cost is paid once; run cost is paid forever.
- **The one that defers commitment.** Optionality has value if the future is uncertain.
- **The one your team can actually operate.** Sophistication you cannot debug on a Sunday night is a liability.

### Beware false dichotomies
Most "X vs. Y" debates have a third option: "X now, with a seam that lets us add Y later when the trigger fires." Generate this option deliberately — it's often the right answer.

### Beware status-quo bias
"Do nothing" is a real option and often the right one. But it is also the easiest option to choose without examining, so audit it: what does *not* deciding actually cost over the lifetime of the system?

## What gets written down

This skill produces the **analysis** — the option comparison, the trade-off, the rationale. The polished **artifact** (an ADR with full metadata, status, supersession history, etc.) is the job of the `architecture-decision-records` skill. Use the template above as a working document; promote it to a numbered ADR once the decision is final.

## What good rationale looks like

Bad rationale (any one of these is a red flag):

- "Industry best practice." → Whose industry? Which problem?
- "It's what we know." → Did we evaluate the alternative honestly?
- "Future-proof." → For which future, with what evidence?
- "Scalable." → To what scale, on which axis, at what cost?
- "Clean / elegant / proper." → Aesthetic, not engineering.

Good rationale ties the choice to a named quality attribute, a named constraint, or a named requirement. If your rationale can't survive the question "compared to what, and at what cost?", rewrite it.
