# SOLID — Best Practices, Heuristics, Refactor Recipes

Actionable playbook over the principles. Heuristics for noticing trouble, decision rules for picking the fix, the canonical refactor order when multiple violations stack, and a PR-review checklist you can run mechanically.

For the principle definitions, see `theory.md`. For Kotlin idioms, see `kotlin.md`. For Spring usage, see `spring-boot.md`. For specific anti-patterns, see `bad-practices.md`.

---

## The "reason to change" prompt (SRP)

For every class, finish: *"This class would change if ___"*.

- One reason → SRP-compliant.
- Need to use "**or**" → multiple responsibilities → split.

Example completion: *"This class would change if the registration policy changes **or** the welcome email template changes **or** the password rules change"* → three responsibilities → split into three classes.

The prompt scales:

- For a function: *"This function would change if ___"*.
- For a module: *"This module would change if ___"*.
- For a service boundary: *"This service would have a different on-call team if ___"*.

---

## The "wait for the second case" rule (OCP)

Don't introduce a sealed hierarchy / strategy interface / abstract factory until you have the **second concrete case**. With one variant:

- The hierarchy has one branch — pure overhead.
- The interface has one impl — substitution is theoretical.
- Tests can't substitute, because there's nothing to substitute.

The cost of *introducing* OCP after the second case appears is one IDE refactor (extract interface, push members down). The cost of *removing* premature OCP is several. Bias toward the smaller cost.

**Exception:** when you genuinely have a vendor seam in mind (e.g., wrapping a payment provider you'll likely swap), introduce the interface up front — but be honest with yourself, not aspirational.

---

## The "narrowest substitutable contract" rule (LSP)

For each `override`, ask the four LSP questions in order:

1. **Preconditions weakened?** (Or equal.) Don't demand more from inputs than the base does.
2. **Postconditions strengthened?** (Or equal.) Don't promise less than the base does.
3. **No new exceptions?** Don't throw what the base contract doesn't allow.
4. **Invariants preserved?** Whatever the base type asserts about its state holds in the subtype.

If any answer is "no", the override is wrong: change the override, change the base contract, or split the hierarchy.

**Quick visual check:** if the override has `!!`, narrows a parameter type, throws `UnsupportedOperationException`, or returns a more nullable type than the base — LSP is at risk. Pause and apply the four questions.

---

## The "every implementer uses every method" rule (ISP)

For every method on an interface, ask: *"Does every implementer use this?"*

- Yes → keep on the interface.
- No → either move the method off the interface (often it should be a function on the consumer or a strategy injected from outside), or split the interface.

A specific tactical version for repositories: split into `XReader` / `XWriter` / `XBulkOps` whenever read-only consumers, write-only consumers, and batch consumers are distinct.

---

## The "stable depends on volatile? wrong arrow" rule (DIP)

For every concrete class injected into another class, ask: *"Is this concrete more or less stable than the consumer?"*

- More stable → fine. (E.g., `Clock` injected as a concrete is fine; clocks don't change.)
- Less stable (a vendor SDK, a framework type, an infrastructure adapter) → DIP violation. Introduce an interface, depend on it.

For domain classes: scan imports. Any `org.springframework.*`, `org.hibernate.*`, `software.amazon.*`, `com.stripe.*` in `domain/` — DIP violation at architectural scale. Move the framework annotation up to the application service / repository adapter layer.

---

## Refactor order when multiple principles are violated

Real classes violate several principles at once. Fix in this order; each fix tends to dissolve the next:

1. **SRP first.** Split the god class into focused ones. The remaining violations often disappear: each piece needs only a small interface (ISP solves itself), depends on fewer things (DIP solves itself).
2. **DIP second.** Where infra still leaks into domain, introduce a port interface; place the impl in `infrastructure/`.
3. **ISP third.** Where an interface is fat at the point of use, split into role interfaces.
4. **OCP fourth.** Only when you have the second concrete case. Don't speculate.
5. **LSP always.** For each `override` introduced during the refactor, run the four LSP questions.

This ordering avoids the trap of introducing OCP-via-sealed-hierarchy on a class that should have been split first — you'd end up with a sealed hierarchy of god subclasses.

---

## Refactor recipes

### Recipe: god service → focused services

1. List the methods. Group by *which fields they touch* and *which dependencies they pull in*. Disjoint groups = separate responsibilities.
2. For each group, create a new `@Service` whose constructor takes only the dependencies that group needs.
3. Move the methods. The old service may still exist as a slim facade or be deleted entirely.
4. Update tests: each new service gets its own test class with smaller setup.
5. Verify: each new service has one reason to change (apply the prompt).

### Recipe: `when (type)` chain → sealed hierarchy

1. Extract the type variable into a sealed interface (or enum-with-behaviour, then promote to sealed).
2. Move each branch's body into the corresponding `data object` / `class` as a method.
3. Replace the `when` at the call site with `method.process(...)`.
4. Repeat for the other `when` chains on the same type.
5. Verify: adding a new variant requires only a new `data object` (no `when` to chase).

### Recipe: fat interface → role interfaces

1. List the methods on the fat interface. Group by *which client uses which*.
2. Create one role interface per client group: `XReader`, `XWriter`, `XBulkOps`, etc.
3. The original fat interface either disappears or remains as `interface X : XReader, XWriter, XBulkOps`.
4. Update each implementer to declare only the roles it honours. Stub overrides go away.
5. Update each consumer to depend on the smallest role.
6. Verify: no implementer throws `UnsupportedOperationException`; no consumer drags in unused methods.

### Recipe: concrete dep → DIP port

1. Identify the volatile class being injected (vendor SDK, infrastructure adapter, framework type).
2. Create a domain interface `Port` with the operations the consumer actually uses.
3. Wrap the volatile class in an adapter (`Adapter : Port`) in `infrastructure/`.
4. Change the consumer's constructor parameter from `Concrete` to `Port`.
5. Update Spring wiring (or `@Bean` config) so the adapter is provided where `Port` is requested.
6. Verify: the consumer's package has zero imports from the volatile package.

### Recipe: `Penguin.fly() throws` → split hierarchy

1. Identify the contract the subtype can't honour.
2. Move the offending method into a new sub-interface that only the capable subtypes implement.
3. Rebase the impossible subtype onto the base sans the offending method.
4. Update consumers: those that call the offending method now require the sub-interface.
5. Compiler enforces: no caller can ask the impossible subtype to do the impossible.

---

## PR-review checklist

A scan-the-diff routine. One pass per principle.

### SRP

- [ ] Any new class with > 5 constructor parameters? Investigate splitting.
- [ ] Any new class whose methods touch disjoint subsets of fields? Investigate splitting.
- [ ] Any class named `*Util`, `*Helper`, `*Manager`, `*Processor`? Rename per `clean-code-naming` and verify single responsibility.
- [ ] Any new method that mixes business logic with infrastructure orchestration (DB + email + payment in one method)? Split.

### OCP

- [ ] Any new `when (type)` chain? Check whether the same `when` exists elsewhere on the same type. If yes, refactor to sealed hierarchy.
- [ ] Any new sealed hierarchy with one implementation? Inline.
- [ ] Any feature requiring edits in 3+ places that should have been an extension point? Investigate.

### LSP

- [ ] Any new `override` with `!!` on a parameter? Narrowed precondition — fix.
- [ ] Any new `override` returning more-non-null than the base? Verify it's truly always non-null; otherwise honour the base.
- [ ] Any new `override` that throws? Check the base contract; if it's a new exception, document or wrap.
- [ ] Any subclass with `UnsupportedOperationException`? Split the hierarchy.

### ISP

- [ ] Any new interface with > 7 methods? Investigate splitting.
- [ ] Any new test fake throwing `UnsupportedOperationException` on a method the real impl supports? Interface is fat — segregate.
- [ ] Any consumer that injects a fat interface and calls < 30% of its methods? Inject a smaller role interface.

### DIP

- [ ] Any constructor injecting a concrete class where an interface exists? Inject the interface.
- [ ] Any `@Autowired lateinit var`? Convert to constructor injection.
- [ ] Any `domain/` file importing `org.springframework.*` or `org.hibernate.*` or `software.amazon.*`? Move the framework concern out of the domain.
- [ ] Any `new ConcreteVendorClient()` inside a service? Inject the abstraction.
- [ ] Any `ApplicationContext.getBean()` call? Replace with constructor injection.

### Spring-specific

- [ ] Any `@Transactional` on a private method? Doesn't work.
- [ ] Any self-call inside a `@Cacheable` / `@Transactional` bean? Bypasses the proxy.
- [ ] Any Kotlin Spring stereotype without `kotlin-spring` plugin enabled? AOP silently doesn't apply.

---

## Heuristics for "is this principle worth applying here?"

SOLID has a cost. Apply only when the benefit clears the bar.

- **SRP:** apply always when the class has > 1 reason to change. The benefit (test setup, change isolation) almost always exceeds cost.
- **OCP:** apply only when you have the second concrete case AND expect a third. With < 2 cases, leave the `when` chain.
- **LSP:** verify always; the cost of checking is seconds, the cost of a violation is debugging hours.
- **ISP:** apply when implementers stub or throw. With one implementer, ISP is theoretical — leave it.
- **DIP:** apply at every architectural seam (domain ↔ infrastructure, service ↔ vendor SDK, application ↔ framework). Skip at internal collaborations between focused classes within the same layer.

---

## Team conventions worth standardising

- **Constructor injection only.** No `@Autowired` field injection except in tests. Enforce with a Detekt or ArchUnit rule.
- **No framework imports in `domain/`.** Enforce with ArchUnit.
- **Sealed hierarchies for closed type-axes** (PaymentMethod, OrderStatus, NotificationChannel). Document the convention; reviewers check.
- **Repository per aggregate root,** segregated into reader / writer where read and write traffic differs.
- **Review checklist on PR template.** Auto-prompt the SOLID scan.

---

## When SOLID actively misleads

Three places where mechanical SOLID is the wrong call:

- **Tight loops in performance-critical paths.** Polymorphic dispatch, abstraction layers, and DI lookups all cost cycles. For hot paths, prefer concrete types and inlined logic — and document why.
- **One-off scripts and migration code.** A 200-line script that runs once and is deleted doesn't need SRP / OCP refactoring. Inline it.
- **Genuinely simple CRUD.** A controller that delegates to a single repository for one endpoint doesn't need an interface, doesn't need segregation, doesn't need OCP. The principles are tools; you're allowed to put the tools down when the problem doesn't need them.

The bias is toward *applying* SOLID, but the discipline is in *recognising* when not to.
