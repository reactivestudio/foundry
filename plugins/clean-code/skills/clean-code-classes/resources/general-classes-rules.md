# General class rules — Martin Ch. 10 in canonical form

This is the language-agnostic foundation: what Ch. 10 of *Clean Code* says, condensed and cross-referenced. Read this when you need the canon rather than the Kotlin/Spring slice — when reviewing a Java codebase, when explaining the rules to a teammate, or when stepping back from the framework specifics to see the underlying principle.

## 1. Class organisation — the newspaper structure

A class is read top-down, like a newspaper article. The **top** of the file establishes context and gives the most important information; the **bottom** holds the supporting detail.

**Canonical order:**

1. **Public static constants** (`public static final` in Java) — facts that don't change, used by callers and by the class itself.
2. **Private static variables** — class-level mutable state, used by all instances. Rare; treat as a smell unless genuinely class-scoped.
3. **Private instance variables** — the class's state.
4. **Public methods** — the API, in narrative order: the entry points the reader is looking for first.
5. **Private utilities** — each placed **directly after the public method that first calls it** (the *stepdown rule* from Ch. 3). The reader can stop descending when they've understood enough.

> *"We like to put the private utilities called by a public function right after the public function itself. This follows the stepdown rule and helps the program read like a newspaper article."* — Martin

The stepdown rule is class-level here, function-level in Ch. 3. Both rest on the same intuition: code should be readable in the order it is encountered, with high-intent calls before low-intent mechanics.

## 2. Encapsulation — privacy is the default, looseness is the exception

> *"We like to keep our variables and utility functions private, but we're not fanatic about it. Sometimes we need to make a variable or utility function protected so that it can be accessed by a test. For us, tests rule."* — Martin

Privacy is the *default*; looseness is **a last resort** for testability. The hierarchy of preference, from best to worst:

1. **Public API of the class**. A test that drives through the public methods is the strongest evidence the class works.
2. **Package-private / module-internal access** (Java package-private, Kotlin `internal`). Visible inside the module, invisible outside. Use for test seams that can't be driven through the public API.
3. **`protected`**. Less ideal — exposes to subclasses too, not just tests. Sometimes the only choice in Java without packages.
4. **`public` fields** — **never** for testability. A public field discards the invariant; that's not loosening, that's surrender.

The rule of thumb: if a test seam means making something `public`, the class probably wants to be split — the thing the test wants to reach is a separate responsibility that deserves its own class with a clean public API.

## 3. Classes should be small — measured by responsibilities, not lines

Function size is counted in lines; class size is counted in **responsibilities**. A 30-method class with one responsibility is smaller than a 5-method class with three.

Martin's *SuperDashboard* example (70 public methods) is the obvious god class. But the more dangerous version is the *small-looking* god class:

```
class SuperDashboard {
    Component getLastFocusedComponent()
    void      setLastFocused(Component)
    int       getMajorVersionNumber()
    int       getMinorVersionNumber()
    int       getBuildNumber()
}
```

Five methods. Looks fine. But it tracks **two unrelated things** — focus state and version information. Two reasons to change ⇒ two classes.

## 4. The 25-word, no-and/or/but description test

> *"We should also be able to write a brief description of the class in about 25 words, without using the words 'if,' 'and,' 'or,' or 'but.' How would we describe the SuperDashboard? 'The SuperDashboard provides access to the component that last held the focus, **and** it also allows us to track the version and build numbers.' The first 'and' is a hint that SuperDashboard has too many responsibilities."* — Martin

This test is mechanical and surprisingly powerful:

1. Write the class's purpose in one sentence.
2. Cap the sentence at ~25 words.
3. Reject any sentence containing `if`, `and`, `or`, `but`.
4. Each forbidden conjunction is a separate responsibility — and a separate class.

Apply it to **the name** first. If you can't name the class without slashing it (`OrderManagerAndAuditor`) or generalising it into mush (`OrderSystem`), you have multiple responsibilities. Apply it to **a written description** second — to catch the cases where the name *sounds* singular but the behaviour isn't (`OrderService` that submits orders, exports CSV, and recomputes statistics).

### Weasel suffixes

Names that telegraph aggregation:

- `Manager` — manages what, exactly?
- `Processor` — processes which input, in what sense?
- `Helper` / `Util` — helps with anything; coherent with nothing.
- `Super*` — a self-aware admission of size.
- Plain `Service` with no domain qualifier — a Spring-style smell when the class has crept beyond one use case.

The vague name is the *result* of a vague responsibility. Don't fix it by renaming; fix it by splitting.

## 5. Single Responsibility Principle — one reason to change

> *"The Single Responsibility Principle (SRP) states that a class or module should have one, and only one, reason to change."* — Martin

SRP is both a **definition** (responsibility = axis of change) and a **size guideline** (one responsibility per class). It is **the most abused OO principle** because:

> *"Getting software to work and making software clean are two very different activities. Most of us have limited room in our heads, so we focus on getting our code to work more than organization and cleanliness. ... The problem is that too many of us think that we are done once the program works."* — Martin

The discipline is **two-phase**: write code to work, then refactor for SRP. Skipping the second phase is the dominant failure mode.

### Common SRP violations

- A class that changes when **business rules** change *and* when **persistence format** changes. (E.g., an `@Entity` with business methods.)
- A class that changes when **the input format** changes *and* when **the algorithm** changes. (E.g., `Parser` that also computes statistics.)
- A class that changes when **a new variant** is added *and* when **an existing variant's logic** is changed. (E.g., the `Sql` class from Ch. 10's worked example.)

### Why people resist SRP

> *"At the same time, many developers fear that a large number of small, single-purpose classes makes it more difficult to understand the bigger picture. They are concerned that they must navigate from class to class in order to figure out how a larger piece of work gets accomplished. However, a system with many small classes has no more moving parts than a system with a few large classes."* — Martin

The same complexity exists either way; the question is whether it is *labelled* (small classes with focused names) or *unlabelled* (everything in one class). Labelled is easier to navigate, even if there are more files.

## 6. Cohesion — methods and fields hang together

> *"Classes should have a small number of instance variables. Each of the methods of a class should manipulate one or more of those variables. In general the more variables a method manipulates the more cohesive that method is to its class. A class in which each variable is used by each method is maximally cohesive."* — Martin

Maximal cohesion is rare and not even always desirable. The practical bar is: **methods and fields cluster around the same axis of meaning**. The *Stack* example in Ch. 10 is a clean baseline:

```
class Stack {
    private int topOfStack;
    private List<Integer> elements;

    int  size()           // uses topOfStack
    void push(int)        // uses topOfStack, elements
    int  pop()            // uses topOfStack, elements
}
```

Of three methods, two use both fields; the third uses one. That's cohesive.

### The cohesion signal — falling cohesion means a class is splitting

> *"The strategy of keeping functions small and keeping parameter lists short can sometimes lead to a proliferation of instance variables that are used by a subset of methods. When this happens, it almost always means that there is at least one other class trying to get out of the larger class. You should try to separate the variables and methods into two or more classes such that the new classes are more cohesive."* — Martin

The mechanical recipe:

1. List instance variables.
2. For each variable, list the methods that touch it.
3. Look for **clusters** — groups of variables touched by the same group of methods, with little overlap between clusters.
4. Each cluster is a candidate class.

If the cohesion score is dropping over time, the class is *becoming* two classes. Refactor before the methods drift further apart.

## 7. Many small classes — the consequence, not the goal

The chain of reasoning:

1. Functions should be small (Ch. 3).
2. Small functions often need values that were once local to a big function.
3. Promoting those locals to instance variables makes extraction easy.
4. But it lowers cohesion — the instance variables are now shared by an arbitrary subset of methods.
5. **That falling cohesion is the signal to split the class** — not a defect of the refactoring.

> *"So breaking a large function into many smaller functions often gives us the opportunity to split several smaller classes out as well. This gives our program a much better organization and a more transparent structure."* — Martin

The **PrintPrimes** refactoring in Ch. 10 is the worked example: one big function with many locals becomes three classes (`PrimePrinter` for execution, `RowColumnPagePrinter` for formatting, `PrimeGenerator` for the algorithm). The refactored program is *longer* but easier to read, because each piece has one job and a focused name.

## 8. Organising for change — OCP

> *"In a clean system we organize our classes so as to reduce the risk of change. ... Classes should be open for extension but closed for modification."* — Martin

The *Sql* worked example demonstrates the pattern:

**Before** — a single `Sql` class with one public method per statement type, plus private helpers `selectWithCriteria`, `valuesList`, etc.:

- Adding `update` means editing `Sql` and risking every existing statement.
- Changing how `select` works means editing `Sql` and risking the unrelated statements.
- The private helpers are clues: `selectWithCriteria` only applies to one statement type — it doesn't belong on the same class.

**After** — `abstract class Sql` with `generate()`, and one subclass per statement type (`CreateSql`, `SelectSql`, `InsertSql`, `SelectWithCriteriaSql`, ...). Common helpers (`Where`, `ColumnList`) become their own utility classes:

- Adding `UpdateSql` means **writing a new subclass** — no existing class changes.
- Changing `Select` means **editing exactly one subclass** — no risk to insert/create/delete.
- Each subclass is small enough that one reading is enough to understand it.

### Two practical signals OCP refactoring is needed

1. **A private method applies only to a subset of public methods.** That subset is a separate concept.
2. **You are about to "open up" an existing class to add a feature.** Pause: is there a way to add a new class instead?

### When NOT to do OCP

> *"If the Sql class is deemed logically complete, then we need not worry about separating the responsibilities. If we won't need update functionality for the foreseeable future, then we should leave Sql alone."* — Martin

OCP is a response to **actual repeated change**, not a speculative defence against hypothetical change. Premature OCP is over-engineering. The trigger is: you've now opened this class twice for the same reason.

## 9. Isolating from change — DIP

> *"A client class depending upon concrete details is at risk when those details change. We can introduce interfaces and abstract classes to help isolate the impact of those details."* — Martin

The *Portfolio* worked example demonstrates the pattern:

**Before:**

```
class Portfolio {
    private TokyoStockExchange exchange;     // concrete dependency
    int value() { return exchange.currentPrice(symbol) * shares; }
}
```

The test for `Portfolio.value()` either has to hit Tokyo over the network (slow, flaky, non-deterministic) or has to mock `TokyoStockExchange` (coupled to its concrete API).

**After:**

```
interface StockExchange {
    int currentPrice(String symbol);
}

class Portfolio {
    private final StockExchange exchange;
    Portfolio(StockExchange exchange) { this.exchange = exchange; }
    int value() { return exchange.currentPrice(symbol) * shares; }
}

class TokyoStockExchange implements StockExchange { ... }  // production adapter

class FixedStockExchangeStub implements StockExchange {    // test fake
    void fix(String symbol, int price) { ... }
    public int currentPrice(String symbol) { ... }
}
```

The test is now trivial: build a `FixedStockExchangeStub`, fix `MSFT` at `100`, build `Portfolio(stub)`, add 5 shares of MSFT, expect a value of 500. No network, no mocking framework, no flakiness.

### What DIP is really about

> *"In essence, the DIP says that our classes should depend upon abstractions, not on concrete details."* — Martin

The abstraction lives **in your domain**, not in the framework or in the third-party library. `StockExchange` is named for what the *Portfolio* needs (`currentPrice(symbol)`), not for what Tokyo's API exposes (`getCurrentTickerInformation`). The adapter (`TokyoStockExchange`) translates the upstream-shaped API into your abstraction.

### Where DIP belongs

Apply DIP at **trust / change boundaries** — places where the concrete implementation can change *independently* of your code:

- External APIs (third-party services, vendor SDKs).
- The system clock, the random source, the file system.
- Persistence (the repository pattern is DIP applied to data access).
- Email, SMS, push, queue, cache, identity provider — anywhere "the same idea, a different provider" is plausible.

**Don't** apply DIP at every method call. Wrapping `String.trim()` behind a `StringTrimmer` interface is silly. The rule is *can this change independently and do I want to test code that doesn't care which implementation runs*?

## 10. The recipe — how to actually refactor

The chapter's worked examples are not rewrites. They're **stepwise transformations** under a green test suite:

1. **Characterisation tests first.** Build a test suite that pins down the current behaviour. Without it, every refactor is a guess. (See `clean-code-unit-tests` and Feathers, *Working Effectively With Legacy Code*.)
2. **One small change at a time.** Extract a method. Run the tests. Move a method to a new class. Run the tests. Rename. Run the tests.
3. **Don't change behaviour while changing structure.** If a refactor needs a behaviour fix, do the structure step first (tests green), then the behaviour step (test changes, then code).
4. **Stop when each class passes the 25-word test.** Not when the file is short. When the *responsibility* is one.

> *"This was not a rewrite! We did not start over from scratch and write the program over again. Indeed, if you look closely at the two different programs, you'll see that they use the same algorithm and mechanics to get their work done. The change was made by writing a test suite that verified the precise behavior of the first program. Then a myriad of tiny little changes were made, one at a time."* — Martin

## Cross-references

- Function-level discipline (Small, Stepdown, Do One Thing): `clean-code-functions`.
- Data vs. behaviour (Objects vs. Data Structures): `clean-code-objects-and-data`.
- Naming (Manager / Helper / Util / Service): `clean-code-naming`.
- Vertical/horizontal layout, file size targets: `clean-code-formatting`.
- Wrapping third-party APIs behind a port (the Tokyo example, extended): `clean-code-boundaries`.
- Characterisation tests before refactoring: `clean-code-unit-tests` and `methodology-verification`.
- SOLID at principle scope: `solid-principles`. GoF as patterns: `gof-patterns`. Responsibility assignment: `grasp-patterns`.
- Aggregate / repository / value-object shapes: `ddd-tactical-patterns`.
