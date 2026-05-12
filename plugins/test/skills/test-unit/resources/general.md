# Unit Tests — Language-Agnostic Discipline

The vocabulary and mental model that the Kotlin / Spring tooling sits on top of. If you read only one file in this skill, read this one. Tooling changes; these principles don't.

> *The hard part of unit testing is not learning the framework. It's deciding what to put in a unit test in the first place, and how to phrase the check so the test pays its rent over the next five years of refactoring.*

## 1. What is a "unit"?

The classical Java answer — "a unit is a class" — does not survive contact with Kotlin, FP-flavoured services, or DDD aggregates. Two practical traditions:

- **Classicist / Detroit school** (Kent Beck, Martin Fowler in *Mocks Aren't Stubs*) — a "unit" is **a piece of behaviour**, exercised through whichever combination of classes naturally implements it. Real collaborators are preferred; doubles appear only at unavoidable seams (IO, time, randomness). This is the **sociable** style.
- **Mockist / London school** (Steve Freeman, Nat Pryce in *GOOT*) — a "unit" is **a class in isolation**, with every collaborator substituted by a mock. This is the **solitary** style and the "interaction-based" testing it implies.

Khorikov picks the classicist side and the house follows: **the default is sociable unit tests**. The unit is the behaviour, the collaborators are real, the doubles appear only at the seams that escape the JVM (clocks, randomness, IO ports, network).

### Why sociable wins for domain code

A behaviour-rich domain aggregate (`Order`) collaborates with `OrderLine`, `Money`, `OrderStatus`, `DomainEvent`. Mocking all of them to "isolate" `Order.submit(...)`:
- destroys readability (test is mostly `every { } returns …`),
- couples the test to the *interaction pattern* (which lines call what in which order),
- removes the test's ability to catch real bugs (`Money.add` returns the wrong currency → the mock would have returned anything you told it to).

The real `Money` running through the real `OrderLine` through `Order.submit()` *is* the unit. The test is **sociable** and high-value.

### When solitary still earns its place

Application services orchestrating multiple ports (repositories, publishers, clients) sometimes don't fit sociably — running the real publisher emits real events, the real repository hits a real DB. There:
- Substitute the *infrastructure ports* with **fakes** (in-memory repository, recording publisher).
- The *domain* collaborators (aggregates, value objects, services) remain real.

That's still mostly classicist; only the infrastructure is substituted. Pure-mockist (every collaborator is a `mockk<T>()`) is rarely the right choice — see §5.

## 2. The test-double taxonomy (Meszaros / Fowler)

Five names, distinct meanings. Get the vocabulary right and the tooling stops being confusing.

| Name | Behaviour | What it's for |
|---|---|---|
| **Dummy** | Argument that's required but never used. | Filling a parameter list when the test doesn't care. |
| **Stub** | Returns hard-coded values when called. | Forcing a collaborator to "produce" a specific input to the unit under test. |
| **Spy** | Wraps a real implementation and records calls. | Watching a real collaborator from a side. Rare in unit tests; somewhat smell-flavoured. |
| **Mock** | Pre-programmed with **expectations** about which calls should occur. Asserts on the calls. | When the *call itself* is the contract being checked (event published, audit recorded). |
| **Fake** | A working *real* implementation that takes a shortcut unsuitable for production (in-memory store, hash map "DB"). | Stateful collaborators the test exercises across multiple calls. |

**Practical positions**:
- **Mock vs Stub** — a stub answers; a mock judges. MockK's `every { } returns …` is a stub; `every { } returns …` paired with `verify { } / confirmVerified` makes it a mock. Use stubs by default. Promote to mock only when the *call* is the contract.
- **Mock vs Fake** — when the test exercises three or more operations on the same stateful collaborator (`save`, then `findById`, then `delete`), the chained `every { } returns …` is unreadable. A fake (`InMemoryOrderRepository`) is clearer, faster to write, and survives refactoring better.
- **Spy** — strongly smell-flavoured in unit tests. Reach for it only to characterise a legacy class you can't refactor.

## 3. The Khorikov classification — output / state / communication

Khorikov classifies *every* test by what it asserts on. This is the most important diagnostic question in the unit-test world.

### 3a. Output-based — the gold standard

The unit is a function (or method) that returns a value. The test passes input, asserts on the output. **Zero side effects**, zero mutation.

```text
result = unit(input)
assert result == expected
```

Pillar profile: **high on all four** (protection-against-regressions, refactor-resistance, fast-feedback, maintainability). The test couples to the *behaviour*, not the *implementation*.

**Where it fits**: pure functions, value objects, specifications, calculation methods, pure aggregate transitions returning a new state (`order.withLine(...)` returns a new `Order`).

If a piece of code *can* be made output-based — even via a small refactor (extract a pure function, accept time as a parameter, return new state instead of mutating) — it should be. The pillar gain is enormous.

### 3b. State-based — the workhorse

The unit mutates state. The test invokes the operation, then queries the state.

```text
unit.doX()
assert unit.state == expected
```

Pillar profile: **strong**, but slightly more coupled to internals than output-based. The test reads an internal query (`order.status`), which means a refactor of the query method breaks the test even if behaviour is preserved.

**Where it fits**: mutable aggregates (when the codebase's style is mutation rather than copy-and-return), state machines with implicit transitions, fakes whose state the test inspects.

**Trick**: make the query method *part of the public contract* (it's a domain query, not an internal getter), so a refactor that removes it is a real behavioural change. Then state-based tests gain refactor-resistance.

### 3c. Communication-based — the weakest

The unit produces no output and mutates no state the test can observe. Instead it *calls* a collaborator. The test asserts on the call.

```text
unit.doX()
verify(collaborator).receivedY()
```

Pillar profile: **weakest** — high coupling to the implementation's call pattern, easy to over-specify (`verify(exactly = 1) { … }`, `confirmVerified(...)` everywhere). A refactor that splits `doX` into two calls breaks the test even when behaviour is preserved.

**Where it fits**: when the **call IS the contract**. Publishing a domain event to an event publisher, writing an audit record, emitting a metric. The collaborator's role is *to be called*; that's the observable behaviour.

**Never** use communication-based when output-based or state-based would do. Common smell: a test that does `verify { repo.save(order) }` because the test author didn't know how else to check the operation worked. The answer is to make `save(order)` return the saved order (output-based) or to query the repo afterwards (state-based with the repository's *own* query).

### Rule of thumb

Walk the ladder, prefer the highest rung that fits the code:

1. **Can this be output-based?** (Function-shaped, returns a value, no side effects.) → Test on the return.
2. **Can this be state-based?** (Mutates state queryable via a domain method.) → Test on the state.
3. **Is the call itself the contract?** (Event published, audit recorded.) → Test on the call (mock + `verify`).

If none of the three fit cleanly, you're probably in the *Controllers* quadrant — move up a layer (integration / acceptance) rather than fighting at the unit level.

## 4. Test fixtures — builders, object mothers, factories

Three patterns; each shines in a different context.

### 4a. Test data builder (Java tradition)

A separate builder class with fluent setters: `OrderBuilder().withCustomer(...).withLine(...).build()`. Verbose; survives every language. Necessary in Java; redundant in Kotlin (a `data class` with named defaults IS a builder).

### 4b. Object mother

A central registry of "canonical" instances: `OrderMother.aDraftOrder()`, `OrderMother.aSubmittedOrderWith3Lines()`. Each mother method captures a *scenario*. Works well when the domain has well-known archetypes.

**Smell**: when the mother grows past ~10 methods, the maintenance cost beats the readability gain. Switch to factories with named overrides.

### 4c. Factory functions with named defaults

The modern idiom (Kotlin / Python / Scala). A single factory per type with defaults the test overrides only for the fields it cares about:

```kotlin
fun anOrder(
    id: OrderId = OrderId.random(),
    status: OrderStatus = DRAFT,
    lines: List<OrderLine> = listOf(anOrderLine()),
): Order = ...
```

Call site shows *only what's interesting*: `anOrder(status = SUBMITTED)`. This is the **default** in Kotlin codebases.

For *derived* fixtures, use `copy()`: `anOrder().copy(status = SUBMITTED)`. Pattern reads naturally.

### When each fits

| Pattern | Use when |
|---|---|
| Builder | Java; or Kotlin tests where many fields are co-validated (`build()` runs invariants) |
| Object mother | Domain has named archetypes well-known to the team |
| Factory function | Default for Kotlin / Python / Scala |

**Anti-patterns**:
- **Fixture factory in `src/main`** — fixtures are *test code*. They live in `src/test`. Production code should never have shortcuts bypassing invariants ("`Order.testInstance()`" is wrong).
- **Cryptic positional fixture** — `Order(UUID.randomUUID(), "Ada", null, null, false)` — the reader has no idea what's significant. Named factory.
- **Fixture factory that constructs via reflection** — bypasses constructor invariants. If your test starts with an aggregate in `SUBMITTED` state, reach `SUBMITTED` by calling the transition method (`aDraftOrder().submit(now)`), not by reflection.

## 5. Testing classes with collaborators — the seam-design ladder

When the unit has collaborators, the first question is *not* "mock or fake?" — it's "**is this the right seam?**". The ladder:

1. **Can I extract a pure function?** Pull the decision-heavy part out as a function that takes data and returns data. Test that as output-based. The remaining orchestration is thinner and often doesn't need its own unit test (it's now in the Controllers quadrant where integration is more informative).
2. **Can I make collaborators value objects?** Move the collaborator's data into the call signature; the collaborator becomes a parameter, not an injected dependency. (Often: `clock.instant()` becomes `at: Instant`.)
3. **Is the collaborator stateful and exercised multiple times by the test?** → **Fake**. In-memory implementation. The test reads naturally; the fake is reusable across tests.
4. **Is the collaborator side-effecting and the call IS the contract?** → **Mock** (communication-based).
5. **Is the collaborator a one-shot producer of a value the unit consumes?** → **Stub**. Force the input; assert on the output of the unit under test (output-based).

The order matters. Don't reach for mocks until you've considered steps 1–3.

### The 80 / 15 / 5 rule

In a healthy unit-test suite over a Domain-Model service:
- **~80%** of unit tests are over pure / output-based code (aggregates, value objects, algorithms). **No doubles at all.**
- **~15%** are state-based, sometimes using fakes.
- **~5%** are communication-based, using mocks where the call is the contract.

If your ratio is closer to *most tests use mocks*, the seam design is wrong (Controllers quadrant) or the production code mixes orchestration with decisions (extract the pure function).

## 6. Pure functions — the easiest case

Pure functions are unit-testing's gift:
- No setup beyond inputs.
- No teardown.
- Output-based by definition.
- Trivially parameterisable.
- Property-based testing earns its keep here.

If you find yourself paying a lot in test scaffolding, ask whether part of the code under test can be carved into a pure function. Often the answer is yes; the test then becomes a one-line `assertThat(pureFn(x, y)).isEqualTo(z)`.

## 7. Property-based testing — invariants over input classes

Three classes of code where property-based testing has very high ROI:

- **Algebraic properties** — commutativity, associativity, distributivity, idempotence, monotonicity. Money addition is commutative? `forAll(a, b) -> (a + b) == (b + a)`. Set union is associative? `forAll(s1, s2, s3) -> (s1 ∪ s2) ∪ s3 == s1 ∪ (s2 ∪ s3)`.
- **Round-trip / inverse** — encode-then-decode, serialise-then-deserialise, parse-then-format. `forAll(x) -> decode(encode(x)) == x`. Catches edge cases (unicode, empty strings, max int) you wouldn't write by hand.
- **Invariants under operations** — "the total never goes negative", "the timestamp never goes backwards", "the count of items in the basket equals the sum of item-quantities". Express the invariant; let the framework throw 100–1000 inputs at it.

**Reach for property-based tests as a complement, not a replacement.** A property test of "addition is commutative" + three example-based tests of named scenarios (`add zero`, `add negative`, `add overflow`) is the right combination. Example-based tests anchor the readability; property tests catch the edge cases.

Toolchain: Kotest's `forAll` / `checkAll` (JVM/Kotlin); jqwik (Java); Hypothesis (Python); ScalaCheck (Scala); QuickCheck (Haskell); fast-check (TS).

## 8. When NOT to write a unit test — Khorikov's quadrants applied

Two axes: **complexity** (how many decisions, branches, invariants) and **collaborator count** (how many dependencies).

```
                    high complexity
                          ▲
                          │
   Overcomplicated  ─────┼─────  Domain Model
   (refactor —             │  & Algorithms
    don't test)            │  (UNIT — highest ROI)
                          │
   ──────────────────────┼──────────────────────► many collaborators
                          │
   Trivial                 │  Controllers
   (don't test —          │  (INTEGRATION —
    getters, plain         │   unit-mocking is
    data, no logic)        │   mock setup)
                          │
                          ▼
                    low complexity
```

For each quadrant:

- **Domain Model & Algorithms (top-left)** — unit test. Highest ROI. Aggregates, value objects, specifications, pricing, scheduling. **This is what this skill is for.**
- **Trivial (bottom-left)** — *do not test at all*. A `data class Address(street, city)` with no invariants has nothing to assert. A one-line getter that exists for framework reasons (JPA) is plumbing. Don't write `addressGetter_returnsValue` for it. Coverage tools will whinge; the whinging is wrong.
- **Controllers (bottom-right)** — *do not unit-test*. Integration / slice tests cover the orchestration cheaply (real serialisation, real validation pipeline, real status codes). Unit-testing them means mocking six ports and asserting on the call pattern; the test is mostly setup, the cost-benefit is poor.
- **Overcomplicated (top-right)** — **refactor before testing**. A god service with 14 collaborators and 800 lines is not a test-writing problem; it's a design problem. Carve the decisions out as pure functions (move them to the top-left), and the residual orchestration becomes thin enough for integration coverage (move it to the bottom-right). Then the unit tests are easy.

**The most expensive mistake**: pyramid-shaped suite over an *anaemic* domain. The unit tests test data-bag entities (Trivial) — high coverage, zero protection. The orchestration (Controllers) is untested below `@SpringBootTest`. Real bugs slip through. The fix is **either** to push toward a behaviour-rich domain (the Khorikov path; aggregates earn unit tests) **or** to switch shape to Diamond (more integration, less unit; see `test-strategy`).

## 9. Anti-patterns at the unit layer (cross-language)

- **Mocking the thing under test.** `every { order.submit() } returns ...` is mocking the aggregate. The unit *is* `order`; mock its collaborators, not itself.
- **Mock-the-world.** Six mocks in `@BeforeEach`. The seam is too coarse. Step back: extract a pure function (move to top-left quadrant) or accept this is a Controllers test and move up a layer.
- **Testing the mock.** Test code that only asserts that MockK records the calls you told it to. MockK works. Delete.
- **Communication-based where output-based fits.** `verify { repo.save(order) }` when you could've made `save(order)` return the saved order. Make it return.
- **Testing private methods via reflection.** A private method's behaviour is reached through the public one. If you "need" to test it directly, it's probably misclassified — promote it to public-by-domain-purpose, or fold it into the caller and test the caller.
- **`testAllTransitions()` walking through a state machine in one method.** Each transition is a concept. Split.
- **Test that asserts on a log line.** Logs aren't contract. Either assert on the observable outcome the log reflects, or, if the log *is* the contract (rare, e.g. SOC-2 audit), capture log events properly via a log appender.
- **Test that sleeps.** `Thread.sleep(200)` is the F.I.R.S.T. canary. Either inject a `Clock` and advance it, or use a `runTest` virtual-time scheduler.
- **Shared mutable state across tests.** Static fields, singleton caches, JVM-global state. Tests pass in isolation, fail in suite. Find the leak; don't `@DirtiesContext` around it.
- **Snapshot-everything for non-serialised types.** Snapshot fits stable serialised contracts (JSON, HTML output). For an in-memory `Order`, write actual assertions.
- **Coverage as the goal.** 100% line coverage of trivial code is worse than 70% of decision-heavy code. The signal is mutation-test survival; see `test-architecture`.
- **`@Disabled` on a flaky test.** A disabled test is a deleted test. Either fix it or delete it; do not leave it as a "todo".
- **`try { … fail() } catch (e) { … }` instead of the library's `assertThrows<T>`.** Library catches it.

## 10. The "is this test worth keeping?" filter

For every test, ask Khorikov's four pillar questions:

1. **Does it catch real regressions?** (Or does it pass even when behaviour subtly breaks because everything's mocked?) If the test would still pass when the production code is broken, it has zero protection-against-regressions value. Mutation testing (`test-architecture`) gives a number; intuition usually suffices.
2. **Does it survive refactoring?** (Or does any internal change break it?) Tests that break on every refactor erode trust in the suite. Common cause: communication-based tests over-specifying call patterns.
3. **Is it fast?** (Run-on-save fast, not run-only-on-CI slow.) Slow tests don't run; tests that don't run don't catch bugs.
4. **Is it cheap to maintain?** (Or does every code change require updating this test?) Tests with a lot of mock setup are expensive; tests with a clear input → output structure are cheap.

A test that scores high on all four is keeper. A test that scores low on protection and refactor-resistance is *negative* value — delete it. A test that scores low on speed is a *test-tier* problem; move it to the integration tier or replace it with a smaller-scope unit.

## 11. Summary — the unit-layer mental model

| Question | Default answer |
|---|---|
| What is a "unit"? | A piece of behaviour, sociable by default. |
| What's the gold-standard test style? | Output-based (input → return value). |
| What if the code mutates state? | State-based; query the state via a domain method. |
| What if the call IS the contract? | Communication-based with a mock. Rare. |
| Mock or fake for a stateful collaborator? | Fake when the test exercises it across multiple calls. |
| Mock or stub for a producer collaborator? | Stub by default; promote to mock only when the call is the contract. |
| Fixture pattern? | Factory function with named defaults; `copy()` for derived. |
| What code earns a unit test? | Top-left quadrant — Domain Model & Algorithms. |
| What code does NOT earn one? | Trivial; Controllers; Overcomplicated (refactor first). |
| What property earns a property-based test? | Algebraic invariant; round-trip; invariant under operations. |
| How many mocks in a healthy test? | Zero by default; one if the call is the contract. Six = wrong seam. |

The Kotlin tooling that implements all of this lives in `kotlin.md`; the rare Spring case in `spring.md`.
