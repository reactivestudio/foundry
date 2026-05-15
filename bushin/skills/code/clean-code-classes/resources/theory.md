# Clean Code — Classes Theory

Full reasoning behind each principle in `../SKILL.md`. Read this when you want the WHY. For concrete patterns, see `practices.md`. For SOLID at principle scope, see `architecture/application/solid/`.

## T1. Newspaper / stepdown layout

A class is read top-down, like a newspaper article. The top establishes context; the body holds the API; the bottom holds the supporting detail.

Canonical order:

1. Public static constants — facts that don't change.
2. Private static / instance state — the class's data.
3. Constructors — how to build it.
4. Public methods — the API, in narrative order: the entry points readers look for first.
5. Private utilities — each placed directly after the public method that first calls it.

The reader can stop descending when they've understood enough. The stepdown rule applies at function scope and at class scope — both rest on the intuition that high-intent calls should appear before low-intent mechanics.

## T2. Privacy by default; loosen only for tests, last resort

Privacy is the *default*; looseness is **a last resort** for testability. The hierarchy, from best to worst:

1. **Public API of the class.** A test that drives through the public methods is the strongest evidence the class works.
2. **Module-internal / package-private access.** Visible inside the module, invisible outside. Use for test seams that can't be driven through the public API.
3. **`protected`.** Less ideal — exposes to subclasses too. Sometimes the only choice in languages without packages.
4. **`public` fields** — **never** for testability. A public field discards the invariant; that's surrender, not loosening.

Rule of thumb: if a test seam means making something `public`, the class probably wants to be split — the thing the test wants to reach is a separate concern that deserves its own class with a clean public API.

## T3. Size = concerns, not lines

Function size is counted in lines; class size is counted in **concerns**. A 30-method class with one concern is smaller than a 5-method class with three.

The dangerous version is the *small-looking* god class — five methods that look fine, but track two unrelated things (focus state and version information). Two reasons to change = two classes, regardless of method count.

## T4. The 25-word, no-and/or/but description test

> *"We should be able to write a brief description of the class in about 25 words, without using the words 'if', 'and', 'or', or 'but'."*

Mechanical test:

1. Write the class's purpose in one sentence, capped at ~25 words.
2. Reject any sentence containing `if`, `and`, `or`, `but`.
3. Each forbidden conjunction is a separate concern — a separate class.

Apply to the **name first**: if you can't name the class without slashing it (`OrderManagerAndAuditor`) or generalising into mush (`OrderSystem`), you have multiple concerns. Apply to **a written description second** — to catch cases where the name *sounds* singular but the behaviour isn't.

## T5. Weasel suffixes are smells

Names that telegraph aggregation:

- `Manager` — manages what, exactly?
- `Processor` — processes which input, in what sense?
- `Helper` / `Util` — helps with anything; coherent with nothing.
- `Super*` — a self-aware admission of size.
- Plain `Service` with no domain qualifier — a Spring-style smell when the class has crept beyond one use case.

The vague name is the *result* of a vague concern. Don't fix it by renaming; fix it by splitting. Renaming `FooManager` to `FooService` and declaring victory is theatre — the responsibility hadn't moved.

## T6. High cohesion — methods touch most fields

> *"Classes should have a small number of instance variables. Each of the methods of a class should manipulate one or more of those variables."*

Maximal cohesion (every method touches every field) is rare and not always desirable. The practical bar: **methods and fields cluster around the same axis of meaning**.

Mechanical test:

1. List instance variables.
2. For each variable, list the methods that touch it.
3. Look for **clusters** — groups of variables touched by the same group of methods, with little overlap.
4. Each cluster is a candidate class.

## T7. Falling cohesion = signal to split, not a defect

The chain:

1. Functions should be small (covered separately in `clean-code-functions`).
2. Small functions often need values that were once local to a big function.
3. Promoting those locals to instance variables makes extraction easy.
4. But it lowers cohesion — the instance variables are now shared by an arbitrary subset of methods.
5. **That falling cohesion is the signal to split the class**, not a defect of the refactoring.

Function extraction → field promotion → cohesion drop → class split. The cohesion drop is the marker that the work is incomplete, not the cost of a bad move.

## T8. Many small classes — the consequence, not the goal

Resistance to splitting usually shows up as "but then we'll have so many files". The argument is wrong: the same total complexity exists either way; the question is whether it is **labelled** (small classes with focused names) or **unlabelled** (everything in one class). Labelled is easier to navigate.

> *"A system with many small classes has no more moving parts than a system with a few large classes."*

The chain — small functions → field promotion → cohesion drop → class split — gives a *longer* program but an easier-to-read one, because each piece has one job and a focused name.

## T9. Characterisation tests first, refactor second

Splitting a god class is a multi-step transformation; every step needs a green test run.

> *"This was not a rewrite! ... The change was made by writing a test suite that verified the precise behavior of the first program. Then a myriad of tiny little changes were made, one at a time."*

Discipline:

- **Tests first.** Build a test suite that pins down current behaviour.
- **One small change at a time.** Extract a method. Run tests. Move a method to a new class. Run tests. Rename. Run tests.
- **Never change behaviour and structure together.** If a refactor needs a behaviour fix, do the structure step first (tests green), then the behaviour step (tests change, then code).

## T10. Stop when each class passes the 25-word test

The end condition for a class-split refactor is **one concern per class**, not short files. A small sealed root with its few subclasses in one file is idiomatic; spreading 30 unrelated methods across 6 files of 5 methods each, with all fields still shared as `internal`, achieves nothing.

Split by *cohesion cluster*, not by line count.
