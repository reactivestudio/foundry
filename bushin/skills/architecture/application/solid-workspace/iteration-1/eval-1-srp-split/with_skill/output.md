# Split the 600-line `OrderService` — yes. Primarily SRP, with DIP and OCP doing the actual carrying.

## Diagnosis

Line count isn't the smell — the **actors** are. Walk the five methods and ask *to whom does this answer?*

| Method | Actor |
|---|---|
| `calculateTotal()` | Finance / pricing rules (CFO-style stakeholder) |
| `sendConfirmationEmail()` | Marketing / customer-comms |
| `updateInventory()` | Operations / warehouse |
| `persistToDatabase()` | DBA / platform |
| `formatInvoicePdf()` | Finance presentation (or a separate billing/PDF stakeholder) |

That's **four or five distinct actors in one module**. By Martin's sharper SRP wording — "responsible to one, and only one, actor" — this is the canonical violation, structurally identical to the `Employee.calculatePay/reportHours/save` example. Expect the classic symptoms: **accidental duplication** (e.g. a private `lineItems()` helper used by both `calculateTotal` and `formatInvoicePdf`, then tweaked for tax rules and silently breaking the PDF), and a **merge hotspot** where finance, ops, and platform teams collide on the same file every release.

## The split

Pull the responsibilities apart along actor lines, with a thin **Order** entity (or `OrderData`) holding the state:

- `OrderTotalCalculator` — pricing/tax/discount policy. Pure domain.
- `InventoryUpdater` — operations policy; talks to an `InventoryGateway`.
- `ConfirmationNotifier` — comms; depends on a `Mailer` abstraction.
- `OrderRepository` (interface) + `JpaOrderRepository` (impl) — persistence.
- `InvoicePdfPresenter` — formatting only; takes a finalized `InvoiceView`.

If callers want one entry point, wrap them in an **`OrderFacade`** that delegates. Facade is a convenience, not a return to the god class.

## Why DIP and OCP also apply

- **`persistToDatabase()`** is a textbook DIP violation if `OrderService` names a concrete ORM/JDBC client. The domain (`OrderTotalCalculator`, the use case) must depend on an `OrderRepository` *interface owned by the domain*; the concrete `JpaOrderRepository` lives in infrastructure and is wired in the composition root (`main`). Source-code deps cross the curve toward the abstract side; flow of control crosses the other way at runtime — that's the **inversion**.
- **`formatInvoicePdf()` + `sendConfirmationEmail()`** are output channels. Today PDF and email; tomorrow CSV, push notification, S3. Keep them behind `InvoicePresenter` / `Notifier` interfaces so **adding a channel doesn't modify the core** — OCP's "open for extension, closed for modification." The Interactor (use case) is the stable high-level component; presenters and gateways are volatile peripherals protected on the other side of an interface.

## The shape you end up with

```
OrderInteractor (use case)
  ├── OrderRepository        (interface; impl in infra)
  ├── InventoryGateway       (interface; impl in infra)
  ├── Notifier               (interface; SmtpNotifier / SesNotifier)
  └── InvoicePresenter       (interface; PdfPresenter / HtmlPresenter)
```

Concrete classes are named **only in the composition root**. The 600-line file becomes ~5 small classes whose change-drivers no longer collide.
