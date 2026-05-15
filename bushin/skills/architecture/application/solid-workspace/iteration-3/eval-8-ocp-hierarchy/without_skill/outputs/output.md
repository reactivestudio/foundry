# What "high-level" means in OCP

## Short answer

**The "closer to business policy" camp is right.** "More generic / more reused" is a side effect, not the definition.

In Robert C. Martin's formulation (which is where the wording in your question comes from — it's actually closer to DIP's phrasing, but the same hierarchy notion underpins OCP), **level is defined by distance from I/O**, i.e. how close a module sits to the application's core policy versus its mechanical details. A module is *higher level* when:

- It expresses **what the system does in business terms** (e.g. "approve a loan", "settle a trade", "calculate payroll").
- It **owns the abstractions** that lower-level modules implement (the interfaces / ports belong to the high-level module, not to the adapter).
- It can be **reasoned about without knowing** which DB, which HTTP framework, or which message broker is in use.

Reuse frequency is **not** the criterion. A logging utility is used by everything, but it is *low-level* — it talks about strings and sinks, not about policy. Conversely, a `LoanApprovalPolicy` may be used by exactly one caller and still be the highest-level thing in the codebase.

OCP's "protect higher-level from changes in lower-level" therefore means: **when the database vendor, the JSON library, or the HTTP framework changes, the rules of the business must not have to change**. The arrow of dependency points from detail to policy, never the reverse.

## Why people confuse the two

"Generic / reused" is a real and useful axis — it's just a *different* axis (call it the **stability** axis, per Martin's SAP). High-level modules *tend* to be stable and reused because policy changes less often than mechanism. But:

- Stable ≠ high-level. `StringUtils` is stable and widely reused; it is the lowest level imaginable.
- High-level ≠ widely reused. A domain aggregate may have exactly one user.

Conflating them produces bad designs: teams "promote" utility classes into the core because they're reused, and end up with the domain depending on `Jackson`-shaped DTOs.

## Concrete example — same codebase, both lenses

Suppose we have an **expense-reimbursement** service:

```
com.acme.expenses
├── policy/
│   ├── ReimbursementPolicy        (decides if/how much to reimburse)
│   ├── Expense                    (domain entity)
│   └── ApprovalRules              (per-grade limits, per-category caps)
├── application/
│   └── SubmitExpenseUseCase       (orchestrates the policy)
├── adapters/
│   ├── PostgresExpenseRepository
│   ├── SlackNotifier
│   └── HttpExpenseController
└── shared/
    ├── MoneyMath                  (rounding, currency conversion helpers)
    └── Clock                      (time abstraction)
```

### Interpretation A — "high-level = closer to business policy" (correct)

- **High-level:** `ReimbursementPolicy`, `ApprovalRules`, `Expense`, `SubmitExpenseUseCase`. These express *what the business decides*.
- **Low-level:** `PostgresExpenseRepository`, `SlackNotifier`, `HttpExpenseController`. These express *how the decision reaches the outside world*.

OCP applied: when Finance changes the rule "managers may approve up to $5k without VP sign-off" to "$8k", you edit `ApprovalRules`. When Ops migrates from Postgres to DynamoDB, **`ReimbursementPolicy` does not change a single line** — you write a new repository adapter behind the port that `policy/` already owns. The dependency arrow goes `adapters/ → policy/`, never the other way. That is exactly what "higher-level components are protected from changes in lower-level ones" buys you.

### Interpretation B — "high-level = more generic / more reused" (wrong, but illustrative)

Under this lens you'd rank modules like:

- **High-level:** `MoneyMath`, `Clock`, `SlackNotifier` (used from many places).
- **Low-level:** `ReimbursementPolicy` (used by exactly one use case).

Apply OCP this way and you get nonsense: you'd argue that `ReimbursementPolicy` must be protected from changes in `MoneyMath`, which is true but trivial, while leaving the *real* coupling — domain code reaching into Postgres-shaped rows — completely unaddressed. Worse, you'd be tempted to put `MoneyMath` "at the top" of the architecture and let the domain depend on its concrete API, which inverts the correct arrow.

The giveaway: under Interpretation B you can't explain **why** swapping Postgres for Dynamo should leave the policy untouched. Under Interpretation A that's the whole point.

## Recommendation

Settle the debate by adopting Martin's own working definition and put it in the team glossary:

> **Level = distance from input/output.** The further a module is from I/O and the closer it is to the business reason the system exists, the higher its level. Reuse count is irrelevant.

Then enforce it mechanically: a dependency-rule check (ArchUnit, Konsist, `import-linter`, or even a simple module-graph test) that forbids `policy/` and `application/` from importing anything in `adapters/` or third-party I/O libraries. Once the arrows are pinned, OCP follows almost for free — the only way a policy module *can* break is if you edit it, and the only reason to edit it is a genuine policy change.
