# SRP — Single Responsibility Principle

## Definition

**"A module should be responsible to one, and only one, actor."**

Martin's earlier formulation — "one and only one reason to change" — is widely misquoted. The final form in *Clean Architecture* is sharper: the question is *to whom* the module answers, not how many things it does. An **actor** is a group of users or stakeholders that wants the same kinds of changes.

## What it's NOT

- Not "a module does one thing." That rule applies to **functions**, inside a module. SRP is one level up.
- Not about class size or method count.
- Not about bug fixes or refactorings — those aren't "reasons to change" in the SRP sense. The question is *which humans* drive change to this module.

## Canonical example

`Employee` exposes `calculatePay()` (owned by the CFO / accounting), `reportHours()` (owned by the COO / HR), and `save()` (owned by the CTO / DBAs). Three actors, one module — three teams whose edits collide in one file.

## Symptoms

1. **Accidental duplication.** `calculatePay()` and `reportHours()` both want "non-overtime hours," so they share a private helper. The CFO's team tweaks the helper for payroll. HR's report silently becomes wrong. The two methods looked like the same algorithm; they were really two algorithms that happened to coincide.
2. **Merge hotspot.** Teams editing the same file for unrelated reasons collide on every release.

## Anti-pattern

```kotlin
class Employee(private val data: EmployeeData) {
    fun calculatePay(): Money {                       // CFO
        val hours = regularHours()
        // payroll math
    }
    fun reportHours(): Hours {                        // COO
        return regularHours()
    }
    fun save(repository: EmployeeRepository) {        // CTO
        repository.persist(data)
    }
    private fun regularHours(): Hours {               // shared — the trap
        // CFO tweaks for payroll; HR's report silently breaks
    }
}
```

## Good pattern

```kotlin
class EmployeeData(
    val id: Long,
    val name: String,
    val payRate: Money,
    val timesheet: Timesheet,
)

class PayCalculator(private val data: EmployeeData) {
    fun calculatePay(): Money {                       // CFO's rules
        // payroll: regular hours × pay rate
    }
}

class HourReporter(private val data: EmployeeData) {
    fun reportHours(): Hours {                        // COO's rules
        // hours reporting may treat "regular" differently
    }
}

class EmployeeRepository {
    fun save(data: EmployeeData) { /* CTO's rules */ }
}

// Optional Facade if callers want one entry point.
class EmployeeFacade(/* the three above */) { /* delegates */ }
```

The shared "regular hours" calculation is now allowed to **diverge** — each actor's class computes it the way that actor needs. The duplication is deliberate, not accidental.

## Red flags

- One file shows up in PRs from teams in different domains (finance, ops, infra).
- A private helper is called by methods that answer to different stakeholders.
- "I'm afraid to change X because Y might break, and Y is owned by another team."
- A merge conflict on a class recurs every release.
