# Tactical → Strategic Bridge

Open when tactical fixes (better aggregate, cleaner events, tighter repository) keep coming back to the same place. That recurrence is the strategic signal: the **bounded context** is wrong, not the aggregate inside it.

## Three escalation signals

Each is independent. Any one of them is enough to stop patching the aggregate and zoom out.

### 1. The same aggregate appears in two services with conflicting invariants

`Order` in fulfilment requires line items; `Order` in invoicing requires a customer billing address; the two diverge over time and tactical fixes (factory variants, optional fields, `if (...) require(...)`) accumulate.

**What it really means:** you have **two bounded contexts**, each with its own concept that happens to share a name. The unified `Order` is the artefact of one shared database, not of the business.

**The strategic move:** split into `FulfilmentOrder` and `InvoicingOrder` — two types, two contexts, with a translation layer between them. The shared database table is OK; the shared *domain type* is the problem.

### 2. Cross-aggregate transactional saves keep returning

You apply [anti-pattern #9](anti-patterns.md#9-cross-aggregate-transactional-save) once, the cross-aggregate save reappears in another spot. You apply it twice, three times. Each fix is correct locally, but the cause is upstream.

**What it really means:** the boundaries between contexts are drawn in the wrong places. The "two aggregates" are being asked to enforce a rule that only makes sense if they're in **the same context**.

**The strategic move:** redraw the context map. Either merge the two contexts (they were one) or accept the eventual-consistency contract once, system-wide, instead of fighting it at each call site.

### 3. The same word means different things in different methods

`status` on `Customer` means "active/inactive/blocked" in onboarding, "delinquent/in-good-standing" in billing, "subscriber/lapsed/churned" in marketing. Each team reads the field, sees their meaning, and adds a method with the wrong precondition.

**What it really means:** **ubiquitous language is leaking across contexts**. There is no single `Customer.status` — there are three customer concepts that share one row.

**The strategic move:** name the words by context. Inside the billing context, the type is `BillingCustomer` with a `BillingStatus`. Inside onboarding, `OnboardingCustomer` with an `OnboardingStatus`. They're translated at the seam; they're not the same type.

## What strategic DDD does (2-line primer)

Strategic DDD is the layer above tactical: it draws the **lines between contexts** and decides their **relationship type** (anti-corruption layer, customer/supplier, conformist, open-host, published language). Tactical patterns are how you build inside one context; strategic patterns are how multiple contexts talk to each other without one infecting another's language.

## Where to go next

There is **no `ddd-strategic` skill in this plugin yet** — when one is added, this file will be the bridge to it. Until then, recognise the signal and treat it as design work *above* the current task: stop applying tactical fixes; pause to map the contexts; resume tactical work inside the redrawn boundary.

The canonical reference until the skill exists: E. Evans, *Domain-Driven Design* (2003), Part IV (Strategic Design), especially chapters 14-16; V. Vernon, *Implementing Domain-Driven Design* (2013), chapters 2-3.
