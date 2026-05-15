Your teammates who say "closer to business policy" are right. The "more generic / more reused" reading is the common misconception OCP explicitly warns against.

## The rule, precisely

Martin's hierarchy of protection defines **level = distance from input/output**, not generality or reuse count. Higher-level = closer to business rules, further from I/O, more stable. A policy class buried deep in the call graph is *high*-level even if only one caller invokes it. A `JsonUtils` imported by 200 files is *low*-level — it sits near I/O and gets reused widely, but it's not policy.

Why this matters: if you sort by "generic/reused," you'll happily let domain code import a widely-used HTTP client or ORM helper, because it feels foundational. That's exactly the arrow OCP forbids — volatile I/O-adjacent code reaching up into stable policy.

## Same codebase, both interpretations

Take an order-pricing system with `PriceQuoteService` (computes discounts/taxes per business rules), `OrderRepository` (Postgres), `QuoteFormatter` (renders JSON/PDF), and `MoneyUtils` (currency math, used by ~everything).

**Wrong reading — "high-level = generic/reused":**
`MoneyUtils` is treated as the top of the hierarchy because it's reused everywhere. `PriceQuoteService` is seen as a mid-tier consumer. Result: when finance asks to support a new currency rounding rule, edits ripple through `MoneyUtils` and every caller. Worse, `PriceQuoteService` is allowed to import `OrderRepository` directly "because the repo is also pretty generic." DB schema churn now climbs into pricing policy. Red flag from the skill: *"a DB schema change propagates up into use-case classes."*

**Right reading — "high-level = closer to policy, further from I/O":**
`PriceQuoteService` is the high-level component. `OrderRepository` and `QuoteFormatter` are low-level (they sit at the I/O edge). `MoneyUtils` is also low-level — it's a leaf utility, not policy. Source-code dependencies point *toward* `PriceQuoteService`: the service defines an `OrderLookup` port it owns; the Postgres repo implements it. Adding a PDF output channel or swapping Postgres for DynamoDB touches zero lines of `PriceQuoteService`. That's OCP holding.

## Concrete test you can apply in review

Ask: *"If I rewrite this class from scratch in a different language/framework, does the business still work the same?"* If yes, it's high-level — protect it. If no (it's about HTTP, SQL, file formats, currency formatting), it's low-level — it must depend inward, never the reverse.

Reuse count is irrelevant to that question.
