# OCP — Open-Closed Principle

## Definition

**"A software artifact should be open for extension but closed for modification."**

Extend behavior without modifying the artifact. Martin calls this "the most fundamental reason that we study software architecture." Architecture exists primarily to make extension cheap and modification rare.

## What it's NOT

- "Closed for modification" ≠ frozen forever. It means closed against the **kinds of change extension is supposed to handle**. Genuine bug fixes and policy edits inside the artifact still happen.
- OCP doesn't require interfaces everywhere — only at boundaries where change must be absorbed.

## Canonical example

Version 1: a financial summary as a web page — scrollable, negative numbers in red. Version 2: the same data printed in black-and-white, paginated, with headers and footers, negatives in parentheses. A good architecture changes **as little of the existing code as possible** to ship v2 — ideally zero.

## Solution shape

- **SRP first** to separate analysis (what the report says) from presentation (how it's shown).
- **DIP** to point dependencies away from volatile peripherals (UI, DB) toward the stable core.
- Layered responsibilities: an **Interactor** owns business policy, a **Controller** translates input, **Presenters** format for an output mode (web, print), **Views** render. A **Gateway** supplies raw data.
- Interfaces invert dependencies at every boundary — the data gateway, the presenter, and a request type that protects the controller from the interactor's internals.

## Two mechanisms

1. **Directional control** — pick the direction in which source-code dependencies point so changes in volatile code don't reach into stable code. (DIP is the lever.)
2. **Information hiding** — interfaces hide internals so callers don't inherit transitive dependencies. Even if A must call B, A should not see B's collaborators.

## Hierarchy of protection

The further a component is from input/output, the more protected it is. "Level" = distance from inputs and outputs. Higher level ⇒ more abstract, more stable, closer to business rules. Organize components into a dependency hierarchy that **protects higher-level components from changes in lower-level components**.

## Anti-pattern

```kotlin
class ReportService(private val db: Database) {
    fun render(req: ReportRequest): String {
        val rows = db.query("SELECT ... FROM ledger ...")       // direct infra dep
        return if (req.web) renderHtmlWithRedNegatives(rows)    // branch on output
        else                renderTextWithParensNegatives(rows)
    }
}
// Adding a CSV channel forces editing ReportService.
// A schema change in `ledger` forces editing ReportService.
```

## Good pattern

```kotlin
interface FinancialDataGateway {
    fun load(req: ReportRequest): ReportData
}

interface FinancialReportPresenter {
    fun present(data: ReportData)
}

class FinancialReportInteractor(
    private val gateway: FinancialDataGateway,
    private val presenter: FinancialReportPresenter,
) {
    fun run(req: ReportRequest) {
        presenter.present(gateway.load(req))
    }
}

// New output channel = new presenter; interactor untouched.
class WebPresenter   : FinancialReportPresenter { /* ... */ }
class PrintPresenter : FinancialReportPresenter { /* ... */ }
class CsvPresenter   : FinancialReportPresenter { /* ... */ }
```

## Red flags

- Adding a new output channel requires editing the core domain.
- A DB schema change propagates up into use-case classes.
- A use-case class `import`s from a web framework, ORM, or HTTP client directly.
- One file is touched by both "new feature" and "swap dependency" tasks — boundary missing.
