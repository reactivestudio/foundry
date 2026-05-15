# SRP — Single Responsibility

## The framing baseline gets wrong

The common misquote: **"one reason to change."** Martin's final wording is sharper:

> A module should be responsible to **one, and only one, actor.**

An *actor* is a group of stakeholders requesting the same kinds of changes. The actor framing is sharper because "one thing" is the rule for *functions*, not modules — and because **bug fixes and refactorings are not reasons to change** in the SRP sense. A class isn't violating SRP because it gets bugfixed often; it violates SRP when *different stakeholders* demand competing changes to it.

Ask **to whom** the module answers, not **how many things** it does, and not **how often** it changes.

## Accidental vs honest duplication

When two methods serving different actors share a helper, the instinct is DRY → extract. **Don't.** That's *accidental* duplication — two algorithms that look alike today but answer to different masters tomorrow. Extracting locks them together; the first divergent requirement breaks the other actor silently.

*Honest* duplication serves one actor in two places — safe to extract. The test is **who requests changes**, not **how the code looks right now**.

## Canonical violation

`Employee.calculatePay()` (CFO / accounting), `reportHours()` (COO / HR), `save()` (CTO / DBAs). Three actors, one module. Two symptoms follow:

1. **Accidental duplication.** A shared private helper (`regularHours()`) drifts under one actor's tuning and silently breaks the other. CFO tweaks for payroll; HR's report becomes wrong. The methods looked like the same algorithm; they were two algorithms that happened to coincide.
2. **Merge hotspot.** Teams from different domains land PRs on the same file every release.

## Fix shape

Split along actor lines over a passive data carrier: `PayCalculator`, `HourReporter`, `EmployeeRepository`, each over an `EmployeeData`. The shared "regular hours" calculation is now *allowed* to diverge — each actor's class computes it the way that actor needs. Deliberate, not accidental.

If callers want one entry point, wrap them in an **`EmployeeFacade`** — convenience, not a return to the god class.

## When NOT to split

One actor today, no second actor on the roadmap → **don't split**. *Speculative SRP* — splitting "in case another stakeholder shows up" — leaves the codebase worse than a cohesive monolith: more files, more jumps, the same change still touches everything because the actors never diverged. Wait for the second actor to *actually* arrive (a real change request from a different stakeholder), then split along the seam the change reveals. SRP rewards splits done with evidence, punishes splits done on speculation.

## Passive data with cross-actor fields

SRP is about **behavior** — methods that answer to actors. A passive data class with fields from multiple actors (`riskScore` set by fraud, `ledgerEntryId` set by accounting, the rest by payments) isn't strictly an SRP violation: no method serves two masters.

**But.** It is a real **merge hotspot** — every actor's PR touches the same file. Often the lighter fix is CODEOWNERS or separate annotation stores keyed by entity ID, not splitting the data class. Split only when cross-team friction has empirically caused incidents — speculative split of passive data costs as much as any other speculative split.

## Red flags

- One file shows up in PRs from teams in different domains.
- A private helper is called by methods that answer to different stakeholders.
- "I'm afraid to change X because Y might break, and Y is owned by another team."
- A merge conflict on a class recurs every release.
