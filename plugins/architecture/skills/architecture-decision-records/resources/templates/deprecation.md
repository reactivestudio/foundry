# Deprecation / Supersession Template

Use when reversing or replacing a previous decision. A deprecation ADR is one of the most valuable kinds in the trail — it preserves *what changed* and *why we changed our minds*. Without it, future engineers re-litigate the same choice every 18 months.

The rule: never silently delete or rewrite an accepted ADR. Write a new one that supersedes it, mark the old one Deprecated.

```markdown
# ADR-NNNN: <Deprecate / Replace / Reverse> <previous-decision-name>

## Status

Accepted (Supersedes ADR-MMMM)
Date: YYYY-MM-DD
Deciders: @alice, @bob

## Context

ADR-MMMM (<original date>) chose <previous decision> because <previous rationale, short>.
Since then:
- <What changed in the world (load, vendor, regulation, team)>
- <What changed in our understanding (the previous con turned out to be bigger / the pro turned out smaller)>
- <What new option became viable / what original option became untenable>

## Decision

<Replace / Deprecate / Reverse> the previous choice. Adopt <new option> instead.

## Why now (rather than earlier or later)

<What is the forcing function? An incident? A vendor EOL? A scaling threshold crossed?
A regulatory deadline? Be explicit — this section is the most likely to fade from memory.>

## Migration plan

1. **Phase 1** (Week 1-2): <Set up new path, dual-write or shadow-traffic if possible>
2. **Phase 2** (Week 3-4): <Backfill / migrate data, validate consistency>
3. **Phase 3** (Week 5): <Switch reads to new>
4. **Phase 4** (Week 6+): <Decommission old>

## Consequences

### Positive
- <What this buys that the previous decision didn't>

### Negative
- <Migration cost, downtime risk, training>

### Risks
- <What could go wrong; mitigations>

## Lessons learned

<This section is the highest-leverage one in a deprecation ADR. Honestly capture what
the previous decision got wrong — not to assign blame, but to update the team's
estimation calibration.>

- The <previous con> turned out to be <worse / less severe> than estimated because <…>.
- The <previous pro> turned out to be <smaller / harder to realize> because <…>.
- <Something the original ADR didn't consider that we now think it should have>.

## Related decisions

- Supersedes ADR-MMMM
- Related: ADR-KKKK, ADR-LLLL
```

## Required additions over a normal ADR

- **Pointer to the superseded ADR.** Bidirectional: the old one is marked Deprecated with a forward-pointer; the new one's Status names what it supersedes.
- **"Why now"** — the most informative section. The previous ADR was made under conditions; the new one is made under new conditions. Naming the conditions clearly is the difference between a deprecation that reads honest and one that reads political.
- **"Lessons learned"** — capture the *estimation error*, not just the new decision. Future ADRs benefit from knowing where the previous one went wrong in its trade-off math.

## Anti-pattern to avoid

- **Silent deletion.** Editing the old ADR's body to say "we changed our minds" loses the historical record. The old ADR's content was correct at the time it was written; preserve it. Add the Deprecated marker; write the new ADR; cross-link.
- **Polite revisionism.** "We've evolved our thinking" with no concrete naming of what changed. Be specific — vague deprecation rationale is the seed of the next bad decision.
