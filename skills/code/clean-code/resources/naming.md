# Naming — variables, functions, classes

For bad/best examples, see `naming-practices.md`.

## Output template — when reviewing names

For each name in the diff:
1. **Does the name reveal intent?** (would a comment be needed?)
2. **Match against red list and stack-noise table** below.
3. **Action.** Rename to a concrete domain word; expose hidden verbs; drop noise suffixes.

## MUST-check before closing the review

Pass through this list explicitly — don't stop after the obvious ones. These are the names that read past easily because the eye expects them.

- [ ] Every `get*` is side-effect-free? (else rename `getOrCreate*` or restructure — Rule N7)
- [ ] Conversion methods come in symmetric pairs? (`toDomain` ↔ `fromRow`, never `toDomain` + `mapBack`)
- [ ] No double negation? (`isNotInactive`, `hasNoErrors` → `isActive`, `isValid`)
- [ ] No `And`/`Or` conjunctions in class names? (split, or find a higher-level concept)
- [ ] No stack-noise suffix (`*Entity`/`*Dto`/`*Manager`/`*Helper`/`*Impl`/`*Service` as default) in public API?
- [ ] No empty placeholder names (`data`/`info`/`item`/`o`/`u`/`d`/`tmp`/`theList`)?

## House defaults

The biggest naming smell is reaching wider than needed.

- **One word, then two.** Default to a single domain noun (`Order`, `Reservation`, `Payment`). A second word must add domain meaning, not synonym noise — `PurchaseOrder` vs `SalesOrder` is legitimate when both exist; `OrderEntity` is not. Three+ words is almost always a smell.
- **No negated booleans.** `isEnabled`, not `isNotDisabled`. Double-negation in conditionals (`if (!isNotDisabled)`) is unforgivable.
- **No conjunctions in class names.** `OrderAndPaymentValidator` splits into two classes, or finds a higher-level concept (`CheckoutValidator`).
- **Conversion methods come in pairs.** `toDomain` ↔ `fromRow`, never `toDomain` + `mapBack`. Symmetry signals the inverse.
- **Side effects belong in the name.** A `get*` that opens a socket or constructs lies — make it `getOrCreate*` or restructure (lazy property, explicit factory).
- **Match level of abstraction.** Name shouldn't commit to a specific implementation — `Modem.connect(locator)` outlives `Modem.dial(phoneNumber)` when cable arrives.
- **Length tracks scope.** `i` in a tight loop is fine; a class field with the same name is not.

## Red list — words that promise nothing

Replace with a concrete domain term every time.

| Forbidden | What it really says | Replace with |
|---|---|---|
| `Item` | "I didn't think about what this is" | `OrderLine`, `Reservation`, `MenuEntry` |
| `Data` / `Info` / `Object` / `Thing` | empty noun, tautology | concrete domain word |
| `Detail` / `Details` | usually = Info | `ShippingAddress`, not `ShippingDetails` |
| `Element` | XML flashback | `Node`, `OrderLine` |
| `Manager` / `Handler` / `Processor` | verb is hidden inside | `*er` from the verb: `Submitter`, `Reconciler`, `Approver` |
| `Helper` / `Util` / `Utils` | bag of unrelated functions | extension functions or the missing class |
| `Common` / `Base*` | dumping ground / inheritance for its own sake | distribute by topic; prefer composition |

## Stack-noise suffixes (modern Hungarian)

Encode layer or container type — not intent.

| Suffix | Default action | Tolerated when |
|---|---|---|
| `*Entity` | remove | persistence row — prefer `*Row` |
| `*Dto` | remove | pre-existing project-wide convention |
| `*Model` / `*Bean` / `*Object` / `*Data` / `*Info` | always remove | — |
| `*Impl` | remove | two valid implementations; mark by specificity (`JpaOrderRepository`, not `OrderRepositoryImpl`) |
| `*Service` | not as a default | genuine application-layer orchestrator (load → call → save) |

## Additional disciplines

- **One word per concept across the codebase.** Pick `find` *or* `fetch` *or* `get` — not all three for the same operation. Same for `controller` / `manager` / `driver` filling one role.
- **Don't pun.** Same word, different semantics misleads. `add` for arithmetic ≠ `add` for "append to a collection" — the second should be `insert` or `append`.
- **Add context via class extraction.** A bare `state` variable is opaque; inside an `Address` class the same field is obvious. Group via classes; prefix (`addrState`) only as a fallback.
- **No gratuitous prefix-spam.** Don't tag every class with `GSD…` because the project is "Gas Station Deluxe". Differentiate only when types actually collide (`PostalAddress`, `MacAddress`, `WebAddress`).

## Renaming

Don't fear it. Tooling makes the change cheap and atomic. A rename surprises someone exactly the way any improvement does — pay that cost and move on.
