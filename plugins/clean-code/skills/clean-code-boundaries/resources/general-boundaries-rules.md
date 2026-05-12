# General Boundary Rules (Martin, Ch. 8)

These are the chapter's rules — language- and framework-agnostic. The other resource files apply them to Kotlin and Spring/JPA.

## The tension

Every boundary has two sides with different incentives.

| Side | Wants |
|---|---|
| Provider (third-party, vendor, framework) | **Broad applicability** — every method, every overload, every edge case, so the API appeals to the widest possible audience. |
| Consumer (your code) | **Narrow shape** — exactly the operations the problem requires, in the vocabulary of the domain, with the safety the domain wants. |

These wants do not converge. The provider's `Map` has 19 methods (`clear()`, `putAll()`, `entrySet()`, ...); your domain wants exactly two (`byId(id)`, `register(sensor)`). Either you reconcile the tension once, at the seam, or your code reconciles it every time the boundary is crossed.

## Rule 1 — Wrap, don't pass

> "If you use a boundary interface like `Map`, keep it inside the class, or close family of classes, where it is used. Avoid returning it from, or accepting it as an argument to, public APIs." — Grenning

The chapter's canonical example: a raw `Map<String, Sensor>` passed around the codebase.

What goes wrong when you pass the boundary type:

- **Untargeted power.** Every caller gets every method, including the destructive ones (`clear()`).
- **No domain invariants.** "Only `Sensor` objects in this map" is a comment, not a constraint — any caller can `put` anything.
- **Casts and ceremony at every call site.** `as Sensor`, `?: error(...)`, null checks.
- **Future-tax.** When the boundary type changes (Java 5 generics, JDK 9 immutable collections, the vendor's API rename), every call site changes.

The fix: hide the boundary type behind a class. Public methods on that class take and return your domain types.

```pseudo
// ✗ Bad — boundary type leaks
public:
  fun getSensors(): Map<String, Sensor>
  fun addSensor(id: String, sensor: Sensor)

// ✓ Good — class owns the boundary
public:
  fun byId(id: SensorId): Sensor?
  fun register(sensor: Sensor)
private:
  field sensors: Map<String, Sensor>
```

**Scope rule:** the boundary type is allowed inside the class — and across a *close family* of classes that share the same boundary concern (e.g., a `repository` package's internal classes). It is *not* allowed outside that family.

> **Not every Map is the problem.** A local variable, a method-private field, a one-page utility — all fine. The rule attacks the boundary type leaking through **public APIs**, where it becomes everyone else's problem.

## Rule 2 — Explore via Learning Tests

When you adopt a third-party SDK, you have to learn how it works. The chapter's lesson: **do that learning in a test**, not in production code.

A learning test is a small `@Test` that calls the third-party API the way you intend to use it, asserts the behaviour you expect, and lives in your codebase forever.

**Why they earn their keep:**

| Benefit | What it actually buys |
|---|---|
| Encodes mental model | You'd read the docs anyway. Writing a test is barely more work and survives longer than memory. |
| Free regression suite | When the vendor releases a new version, run the learning tests in CI. Behavioural drift surfaces immediately, in isolation. |
| Shrinks debugging surface | When production code fails, you already know the vendor behaves as expected — focus on your code first. |
| Documents intended use | A test is precise documentation: this input produces that output. New team members read tests faster than docs. |

**The chapter's example.** Grenning's team wanted to use `log4j`. They wrote a test that called `Logger.getLogger("MyLogger").info("hello")` — and it failed because of a missing `Appender`. They added an `Appender` — failed again, missing output stream. They iterated until the test passed and they understood the API. They kept the tests. When log4j was upgraded, the tests verified the new version still behaved the way the old code expected.

**When to write a learning test:**

- Adopting an unfamiliar SDK.
- Investigating a poorly documented feature.
- Before bumping a dependency version (write learning tests *first*; then bump; the tests catch drift).
- When debugging a vendor edge case ("does `client.foo()` return null or throw on missing data?").

## Rule 3 — Wishful Interface for code that doesn't exist

When a collaborator hasn't been built yet — a teammate's service, a subsystem that's "coming next quarter", a vendor whose SDK isn't released — **define the interface you wish you had** and code against it now.

The chapter's example: the radio transmitter subsystem. The Transmitter team hadn't shipped. Grenning's team didn't want to be blocked. They asked themselves: *what would we say to a transmitter if we could?*

> Key the transmitter on the provided frequency and emit an analog representation of the data coming from this stream.

That became their interface — `Transmitter.transmit(frequency, stream)`. They coded the `CommunicationsController` against it. When the real subsystem shipped, they wrote a `TransmitterAdapter` to bridge the wishful interface to the real API.

**What this buys:**

- **You're not blocked.** Work proceeds on the client side without waiting for the unbuilt collaborator.
- **Client code stays clean.** It speaks domain — `transmitter.transmit(...)` — instead of vendor mechanics that don't exist yet.
- **Tests via a Fake.** Substitute a `FakeTransmitter` that records calls. No mocking of imaginary SDK shapes.
- **One bridge to write.** When the real thing arrives, the Adapter is the only new code; the rest of the system is unchanged.

This is the **Adapter pattern (GoF)**, applied to the seam between *you* and *not-you-yet*.

## Rule 4 — Clean boundaries have four properties

When the seam is right, you can name the four properties:

1. **Clear separation.** A reader can point to the boundary class and say "this is where third-party `X` lives." Outside that class, `X` is not mentioned.
2. **Few references.** The vendor type appears in a small, finite number of files. Bumping the SDK touches that small set, not the whole codebase.
3. **Tests at the seam.** Boundary tests (learning tests + Adapter integration tests) exercise the seam the way production code does. When the vendor drifts, you find out.
4. **Encoded expectations.** The tests are the contract: "this is what we assume the vendor does." When the assumption breaks, the test fails — not a customer.

If the seam misses any one of these, it isn't a boundary, it's a *boundary-shaped hole*.

## The Adapter Pattern in two paragraphs

The Adapter pattern (GoF) is the universal answer to "how do I make a class with the wrong shape look like the shape I want?" An Adapter implements your interface and forwards calls to the foreign API, translating types, errors, and semantics on the way through.

In a clean boundary, the Adapter is a **thin** class — typically a few methods, each a few lines: validate input, call the foreign API, translate the response (or the exception), return your domain type. If the Adapter is doing business logic, you've conflated translation with orchestration; split it.

## What "third-party" includes

The chapter's discussion uses `Map`, `log4j`, and an unfinished hardware subsystem as examples. The same rules apply to **anything you don't control**:

- A third-party library (Apache Commons, Guava, Jackson).
- A vendor SDK (AWS, Stripe, Slack, Twilio, GitHub, Salesforce, Auth0).
- A framework whose types you'd rather not braid into your domain (Spring `ResponseEntity`, JPA `@Entity`, Servlet API `HttpServletRequest`, JAX-RS `Response`).
- A subsystem owned by another team — same company, but you don't ship together.
- A standard you can't influence (a SOAP service, a GraphQL endpoint defined by a partner).
- Legacy code inside your own repo that you're slowly strangling out.

The discipline is the same: thin seam, wishful interface, learning tests, tests-at-the-seam.

## What "third-party" does *not* include

Some types feel foreign but don't need the wrapping ceremony:

- **Standard, stable JDK types** with no interesting alternative: `java.time.Instant`, `java.util.UUID`, `java.net.URI`. Wrapping `Instant` to "hide" `java.time` adds clutter without protecting against any plausible change.
- **Internal modules with a single consumer.** If module A imports module B and they ship together, an Adapter between them is ceremony. Apply the rule when the boundary is *external* to your team or *unstable* relative to your release cadence.
- **One-off scripts and tooling.** Boundary discipline is for code that lives. A throwaway migration script can use vendor types directly.

The rule is "depend on what you control, lest it end up controlling you" — applied with judgement, not asceticism.

## The four practices, summarised

| Practice | What it solves |
|---|---|
| **Wrap, don't pass** | Stops boundary types from leaking through your codebase. |
| **Learning tests** | Lets you adopt an unfamiliar SDK safely and catch drift on upgrade. |
| **Wishful interface + Adapter** | Unblocks you when a collaborator doesn't exist yet. |
| **Tests at the seam** | Guarantees the seam keeps working when either side changes. |

The four together produce a boundary that bends without breaking — and a codebase that survives the vendor's next major version.
