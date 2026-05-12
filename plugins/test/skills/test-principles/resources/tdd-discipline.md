# TDD Discipline — When the Three Laws Apply, When They Bend

The Three Laws of TDD (see `martin-clean-code.md` §Rule 1) are the **default discipline**. They are not a religion. This file documents the cases where the default applies, the cases where it bends, and the related patterns for code-that-already-exists.

> "TDD is a default, not a contract. Apply it where it pays. Bend it where the cycle doesn't fit the work. Never bend it as an excuse to avoid testing." — house ethos

---

## The three laws — restated

1. **You may not write production code until you have written a failing unit test.**
2. **You may not write more of a unit test than is sufficient to fail** — *not compiling* counts as failing.
3. **You may not write more production code than is sufficient to pass the currently failing test.**

The cycle is **seconds long** — write a one-line failing test, write a one-line production change, watch it pass, write the next failing test. Hundreds of cycles per day produce **coverage by construction**.

---

## Why TDD works (when it does)

Two mechanisms, both worth understanding:

**1. Specification → implementation in time.** The test is written when behaviour is what matters; the implementation is written *to satisfy that behaviour*. This forces the production code to be *testable* — small seams, narrow signatures, observable outputs, few side effects. After-the-fact testing finds the production code untestable (no seams to mock cleanly) and either (a) hacks around it or (b) gives up.

**2. Continuous design feedback.** Each red-green cycle ends with the question: *was that easy to test? Where did the friction live?* Friction = design problem; address before the next cycle. Code that gets harder to test as it grows is code that's getting *worse*. TDD makes this signal loud.

---

## When the three laws apply cleanly

- Behaviour is **well-specified** before coding — an existing spec, a clear story, a precise bug repro.
- The code is in the **Domain Model & Algorithms** quadrant (Khorikov) — pure functions, value objects, aggregates with clear invariants.
- The team is **practised at TDD** — knows the cadence, knows when to stop.
- The change is **forward-engineering**, not maintenance — TDD is greenfield-flavoured by default.

In these cases, the cycle is the cheapest way to write the code. Skipping it costs more than running it.

---

## When the three laws bend

### Exception 1: Exploratory spikes

When the *problem shape* is unknown — you don't yet know what behaviour you want, you're prototyping to learn — TDD's first law cannot apply. You can't write a failing test for behaviour you haven't decided on.

**Pattern**:
1. Spike — write throwaway code, get the shape clear.
2. **Throw away** the spike (don't graduate it).
3. **Write tests first** for the production version, applying TDD properly.

The deadly mistake: graduating spike code to production *without* tests because "it works on my branch". Spike code has the design pressure of "make it work once"; production code has the design pressure of "make it maintainable for years". They are not the same code.

### Exception 2: Characterisation tests for legacy code

When working on a class that exists, has no tests, and you must change it — TDD's first law inverts. You don't have a behavioural spec; you have **the existing behaviour**, and you need to pin it down before changing anything.

**Pattern** (M. Feathers, *Working Effectively with Legacy Code*):
1. Pick the smallest reasonable seam (a single public method).
2. Write a **characterisation test**: call the method with a specific input, observe the output, write the assertion based on what you saw.
3. Repeat for the inputs you care about until the *current* behaviour is pinned.
4. Now refactor under the characterisation tests; they catch any unintended change.
5. As clean structure emerges, replace characterisation tests with proper unit tests.

**The difference from TDD**: characterisation tests assert on *what is*, not *what should be*. They may pin bugs. That's fine — you're refactoring, not changing behaviour. Once the refactor is done, fix the bugs (with proper TDD this time).

### Exception 3: Framework-callback code

Some code is genuinely hard to unit-test because the framework owns the seam — JPA criteria builders, generated proto handlers, Spring `BeanPostProcessor`s, native interop. Forcing a unit test bends the production code into a shape that pleases the test but isn't the right design.

**Pattern**: accept a **slice test** (`@DataJpaTest`, `@WebMvcTest`, etc.) or an **integration test** as the first test. The slice is the framework's own seam; you're trusting the framework where the framework owns. Inside the framework's seam, apply normal TDD when you next change the code.

### Exception 4: Performance / load tests

A benchmark micro-test legitimately reads closer to the metal — it has different readers (perf engineers), different rules (sustained allocations matter), different cadence (you don't run benchmarks on every save). TDD's "test before code" pattern doesn't apply because the goal is to measure existing code, not specify new behaviour.

**Pattern**: write JMH benchmarks separately from the unit suite. They live in `benchmark/` or `src/jmh/`, run on a gated CI tier, and follow their own discipline.

### Exception 5: Code that exists *only* to verify behaviour at a layer you can't normally reach

For example, a Spring profile that *only* exists for a smoke test; a test-only configuration; a fixture-loading utility. TDD's first law is satisfied by the layer above it (the test that uses it); the utility itself doesn't earn its own tests.

**Pattern**: write the higher-layer test first; only build the utility if the test forces it. The utility's correctness shows up in the test that uses it; if all uses pass, the utility works.

---

## When TDD is the wrong frame entirely

TDD assumes **you control the production design**. The pattern degrades when:

- **You're writing UI tests that drive a real browser.** The cycle isn't seconds-long; it's minutes-long with flakiness. Apply different discipline (Page Object Model, journey tests). TDD is fine for the underlying business logic that the UI invokes.
- **You're writing tests against an unstable third party.** Mock the third party (`test-contract`), TDD against the mock. The cycle is healthy again.
- **You're testing infrastructure / Kubernetes / Terraform.** TDD doesn't fit; use declarative validation / dry-runs / policy-as-code.
- **You're integrating two systems whose contract is unsettled.** Contract test first (`test-contract`); TDD comes after the contract stabilises.

In these cases, the *spirit* of TDD (write the test first, let it drive the design) still applies — but the *micro-cycle* doesn't.

---

## The cadence — how fast should the cycle be?

Martin's claim: **seconds**. A failing test, ten lines of production code, green, next test.

In practice:
- **For pure domain code**: the seconds-cycle is achievable. Write a test for one invariant, write the `require` that satisfies it, green. Move on.
- **For service-level code with collaborators**: the cycle is **minutes**, not seconds. You spend time deciding what to mock, what the seam should be.
- **For slice tests with Testcontainers**: the cycle is **tens of seconds** per round. Still TDD-flavoured, but slower.
- **For integration tests across multiple services**: the cycle is **minutes-to-an-hour**. TDD applies to the design seam (decide what to test first), not the cycle time.

If the cycle is in the *minutes-to-hours* range, two things might be wrong: (1) the test is at the wrong layer for the work — split into smaller pieces, each TDD-cycled at its right layer; or (2) the production code is in the Overcomplicated quadrant — refactor first.

---

## TDD-flavoured patterns that are not the strict three laws

### Test-Last with Coverage Floor

Write the production code in a small commit, then immediately follow with the tests. Enforce a coverage floor (e.g. CI fails below 80%) to ensure the tests get written.

**Cost**: misses the design-pressure benefit. The production code wasn't shaped by the test; it's shaped by intuition + hope. Often the seams are wrong and the tests are 80% mock setup.

**Use case**: teams not yet practised at TDD. As a transitional discipline, beats "no tests".

### Test-Concurrent (Spec + Code in One Commit)

Write the test and the production code together, but not the test *first*. The discipline: the test and the code ship in the **same commit**, and the test must fail without the code.

**Cost**: loses the second-of-design-pressure but keeps test-as-spec.

**Use case**: experienced teams. In practice indistinguishable from strict TDD; the order of typing doesn't matter, the order of thinking does.

### Test-After with Mutation Floor

Write code first, tests after, then run mutation testing (`test-architecture` covers Pitest). Each surviving mutation = a missing test; iterate until the kill rate passes a threshold (e.g. 80%).

**Cost**: highest in upfront work and CI time. Highest in actual test quality (mutation testing is the most reliable indicator that tests really catch bugs).

**Use case**: critical / financial / safety-critical code where coverage isn't enough. The mutation-kill rate is the protection-against-regressions pillar made measurable.

---

## TDD and Khorikov's quadrants

TDD pays differently in each quadrant:

- **Domain Model & Algorithms** — TDD pays the most. The seam is small, the cycle is fast, the tests are durable.
- **Trivial** — TDD doesn't pay; there's nothing to specify.
- **Controllers** — TDD pays for the *contract* (input → output) but not for the *internals*. Write an integration test first; let it drive the controller's signature.
- **Overcomplicated** — TDD *cannot* apply until refactored. Characterise first, then refactor toward Domain Model + Controllers, then TDD applies.

---

## TDD vs. design-up-front — they don't contradict

A common misreading: "TDD means never design up front". False. TDD means **don't write production code until the next behaviour is pinned down by a test**. That doesn't preclude:

- Sketching architecture before coding (`architecture-patterns` skill).
- Drawing aggregates and bounded contexts before coding (`ddd-tactical-patterns`).
- Designing the API contract before implementing (`api-design-principles`).
- Choosing the test pyramid shape (`test-strategy`).

Design at the **architecture** level happens up front. Design at the **per-method** level happens in the TDD cycle. The two are different scales.

---

## Anti-patterns at the TDD discipline level

- **TDD as religion**: refusing to ship until 100% TDD-derived. Cost: blocked exploratory work, blocked legacy maintenance.
- **TDD as ritual**: writing the test, writing the production code that obviously satisfies it (without thinking about edge cases), making it green, moving on. Misses the *design feedback* mechanism.
- **TDD-then-delete**: writing tests during development, deleting them before commit because "they're scaffolding". The scaffolding is the safety net for the next refactor. Don't delete.
- **TDD with weak assertions**: writing tests that pass with `assertNotNull(result)` — green tick, no real protection. The Khorikov pillars apply *during* the TDD cycle, not after.
- **TDD with shared state**: `@BeforeAll` setting up a fixture that all tests mutate. Tests pass green, but they're not Independent (Martin Rule 11) — randomise the order in CI to catch.
- **TDD on the wrong layer**: writing a unit test for behaviour that's actually a controller / integration concern. The test passes, the behaviour isn't covered, the production bug ships.

---

## How to teach TDD in a team

(For tech leads.)

1. **Pair with someone fluent in TDD** for a week. Watch the cycle. Then drive while they observe and call out missed cycles.
2. **Adopt TDD on a single greenfield module first**. Let the team see it work where it pays before applying to legacy.
3. **Resist the "100% TDD" mandate**. Mandates create resentment; demonstrate-the-value beats decree.
4. **Pair TDD with mutation testing**. The mutation report is the objective measure of whether the TDD tests are actually testing.
5. **Allow exceptions explicitly**. "We're spiking — no tests this week, will rewrite for production." The discipline is to *consciously* opt out, not silently abandon.

---

## TDD checklist for a single feature

Before starting:
- [ ] What behaviour am I adding? In one sentence.
- [ ] What layer does the test belong at? (Khorikov quadrant → layer)
- [ ] What's the smallest failing test I can write?

During:
- [ ] Test fails (or doesn't compile).
- [ ] Minimum production code to pass.
- [ ] Green.
- [ ] Refactor if there's duplication or smell.
- [ ] Repeat for the next behaviour.

After:
- [ ] All tests pass.
- [ ] The list of test names tells the story of the feature.
- [ ] No tests are commented out / `@Disabled` / dead.

If any item is unchecked, the cycle isn't complete.

---

## Summary

- **TDD is the default.** Strict three laws when behaviour is clear, code is in Domain Model & Algorithms, team is practised.
- **TDD bends, doesn't break.** Spikes, characterisation tests, slice tests, perf tests each follow their own rhythm — but each preserves *the spirit*: test pins behaviour before behaviour changes.
- **TDD without Khorikov is half-hearted.** A perfectly-cycled TDD suite of low-pillar tests has the same negative value as an after-the-fact suite of low-pillar tests. The pillars apply to every test, TDD or not.
- **TDD without Martin Rule 11 is fragile.** Independent tests are non-negotiable; TDD doesn't change that.
- **TDD without discipline is theatre.** Test → code → green, move on. Yes — but the test must protect against real regressions, and the code must be designed (not just written to please the test). Both matter.
