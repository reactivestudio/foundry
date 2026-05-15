# Aggregate Boundary Checklist

Open when sizing a new aggregate or stress-testing an existing one. The six items below test the boundary from different angles; **two or more failures means the boundary is wrong** — don't patch around it, redraw.

Each item: **Signal** (what to look at) → **Diagnostic question** (the test) → **If failing** (the corrective).

---

## 1. Transactional invariants stay inside

**Signal:** a business rule that must hold *at the moment of writing*.

**Diagnostic question:** can this rule be violated if the relevant data spans two writes?

**If failing:** either the aggregate is too small (data the rule needs lives outside it — merge), or the rule isn't actually a write-time invariant (it can be enforced as a projection / read-time check / reconciliation — relax it).

---

## 2. Eventual rules cross via domain events

**Signal:** "when X happens in aggregate A, Y should eventually update in aggregate B."

**Diagnostic question:** does the current code wire A and B together synchronously (direct call, shared transaction, repository injection)?

**If failing:** introduce a domain event on A. Let a listener on the B side react. The system accepts that B may lag A by a short interval; the business has to confirm that's OK. (If the business says "no, must be atomic" — see item 6.)

---

## 3. The root is the only entry point

**Signal:** application code that calls `aggregate.someChild.changeSomething()` or that injects a repository for an inner entity.

**Diagnostic question:** could a caller, today, modify the aggregate's internal state without going through a method on the root?

**If failing:** make inner entities package-private / `internal`; remove their separate repository; expose a root-level method that performs the change. The root is now the only door; every change runs through its invariants.

---

## 4. Cross-aggregate references are IDs

**Signal:** an aggregate has a field typed as another aggregate (`Order.customer: Customer`); business code navigates across (`order.customer.address.city`).

**Diagnostic question:** can the referenced aggregate be loaded, modified, or rolled back independently of this one?

**If failing:** change the field type from the aggregate to its ID type (`Order.customerId: CustomerId`). Callers that previously navigated through the pointer now load the other aggregate explicitly when needed — and the seam between the two contexts is now visible at every use site.

---

## 5. The aggregate fits in memory

**Signal:** loading the root pulls in thousands of child rows; tests are slow; queries fan out into N+1; teams "fix" by tuning fetch graphs.

**Diagnostic question:** what's the worst-case child count for a single aggregate instance in production?

**If failing:** if children are themselves modifiable units of work, lift them into their own aggregate root, referenced from the original by ID. If they're truly part of one invariant but high-cardinality, ask whether the invariant must be enforced write-time at all (see item 1).

---

## 6. One command writes one aggregate per transaction

**Signal:** an application service method (or one `@Transactional` boundary) writes to two aggregates.

**Diagnostic question:** if the second write fails, can the system tolerate the first one having succeeded?

**If failing — three honest options:**

1. The boundary is wrong. The two aggregates are really one — merge.
2. The consistency rule is wrong. It doesn't have to be atomic — accept eventual consistency via an event on aggregate A, handler updates B.
3. Both are right and you need a process manager / saga. Make the orchestration explicit; the business has to accept the eventual-consistency contract.

Cross-aggregate `@Transactional` is not a fix — it's silent breakage waiting on a production incident.

---

## After the checklist

If two or more items failed, the priority is **the boundary itself**, not the surrounding code. Patching call sites while leaving the boundary wrong produces a model where the *symptoms* shift around (cross-aggregate save becomes a saga, becomes a transaction script, becomes an outbox) without the *cause* moving.

If only one item failed, fix the local violation and stop. Over-correcting from a single signal is how aggregates collapse into one big god-cluster or splinter into per-field micro-aggregates.
