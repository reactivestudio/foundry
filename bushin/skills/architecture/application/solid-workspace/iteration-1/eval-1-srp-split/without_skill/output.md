# OrderService Split — Design Review

## Diagnosis: yes, split it

A 600-line `OrderService` with `calculateTotal()`, `sendConfirmationEmail()`, `updateInventory()`, `persistToDatabase()`, and `formatInvoicePdf()` is a textbook **Single Responsibility Principle (SRP)** violation. Each of those methods answers to a different **actor / axis of change**:

| Method | Actor / reason to change |
|---|---|
| `calculateTotal()` | Finance / pricing rules, tax, discounts |
| `sendConfirmationEmail()` | Marketing / messaging, email template, SMTP provider |
| `updateInventory()` | Warehouse / stock system, reservation rules |
| `persistToDatabase()` | DBA / schema, ORM, storage tech |
| `formatInvoicePdf()` | Accounting / legal layout, PDF library |

SRP (Martin's formulation) says a module should have **one reason to change**. Today, a tax-law update, an SMTP migration, a schema change, and a PDF redesign all touch the same file — guaranteeing merge conflicts, fragile tests, and creeping coupling between unrelated concerns.

## Proposed split

Decompose along those axes, keeping `OrderService` as a thin **application/orchestration service** that coordinates the others:

```
OrderService              # use-case orchestrator: placeOrder(), cancelOrder()
├── PricingCalculator     # calculateTotal(), tax, discounts — pure, easy to unit-test
├── OrderRepository       # persistence (interface in domain, impl in infra)
├── InventoryService      # reserve/release stock (likely calls a bounded context)
├── OrderNotifier         # sendConfirmationEmail() — behind a Notifier port
└── InvoiceRenderer       # formatInvoicePdf() — behind a DocumentRenderer port
```

This also satisfies **Dependency Inversion**: `OrderService` depends on interfaces (`Notifier`, `InvoiceRenderer`, `OrderRepository`) rather than SMTP/JDBC/PDF libraries directly, so each collaborator can be swapped or stubbed in tests.

## Why these specific seams

- **Pure vs. I/O.** `PricingCalculator` is pure; the rest are I/O. Isolating pure logic gives you fast, deterministic unit tests.
- **Bounded contexts.** Inventory and notifications likely belong to other contexts; the seam prepares you to extract them (message bus, service call) without rewriting `OrderService`.
- **Persistence ignorance.** Hiding `persistToDatabase()` behind `OrderRepository` lets the domain stay framework-free.

## What stays in `OrderService`

The **use case**: validate input, call `PricingCalculator`, reserve via `InventoryService`, save via `OrderRepository`, then dispatch `OrderNotifier` and `InvoiceRenderer` — ideally via a domain event so side effects don't bloat the happy path.

## Pragmatic guardrail

Don't over-engineer: if your team is two people and the class is stable, six classes can be overkill. The split is justified here because each method clearly has a distinct stakeholder and change cadence — that's the SRP smell, not line count alone.
