# SRP — Single Responsibility

## The framing baseline gets wrong

The common misquote: **"one reason to change."** Martin's final wording is sharper:

> A module should be responsible to **one, and only one, actor.**

An *actor* is a group of stakeholders requesting the same kinds of changes. The actor framing is sharper because "reason to change" silently includes bug fixes and refactorings (vacuous), and "one thing" is the rule for *functions*, not modules.

Ask **to whom** the module answers, not **how many things** it does.

## Canonical violation

`Employee.calculatePay()` (CFO / accounting), `reportHours()` (COO / HR), `save()` (CTO / DBAs). Three actors, one module. Two symptoms follow:

1. **Accidental duplication.** A shared private helper (`regularHours()`) drifts under one actor's tuning and silently breaks the other. CFO tweaks for payroll; HR's report becomes wrong. The methods looked like the same algorithm; they were two algorithms that happened to coincide.
2. **Merge hotspot.** Teams from different domains land PRs on the same file every release.

## Fix shape

Split along actor lines over a passive data carrier: `PayCalculator`, `HourReporter`, `EmployeeRepository`, each over an `EmployeeData`. The shared "regular hours" calculation is now *allowed* to diverge — each actor's class computes it the way that actor needs. Deliberate, not accidental.

If callers want one entry point, wrap them in an **`EmployeeFacade`** — convenience, not a return to the god class.

## Red flags

- One file shows up in PRs from teams in different domains.
- A private helper is called by methods that answer to different stakeholders.
- "I'm afraid to change X because Y might break, and Y is owned by another team."
- A merge conflict on a class recurs every release.
