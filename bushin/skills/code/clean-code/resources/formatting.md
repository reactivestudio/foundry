# Formatting — let tooling enforce, judge what tooling can't

Most formatting rules are mechanical and belong in a config + auto-formatter, not in code review. The job here is to (a) set up the tooling once, (b) catch the few smells the tooling can't.

## The tooling stack (default for Kotlin/Spring)

- **ktlint** (official Kotlin style) or **ktfmt** (deterministic, Facebook/Google flavour) — pick one team-wide.
- **Spotless** as the Gradle wrapper that runs the formatter.
- **detekt** for additional formatting rules + smell rules.
- **`.editorconfig`** as the cross-tool source of truth (line width, indent, etc.).
- **Pre-commit hook** + **CI gate** (`./gradlew spotlessCheck`) — if the gate is optional, it doesn't exist.

Once the gate is in place, **don't bikeshed formatting in code review**. The formatter is correct by definition.

## Thresholds the formatter doesn't always enforce

| Metric | Target | When exceeded |
|---|---|---|
| Line width | ≤ 120 chars | Break on argument boundaries, named arguments, or extract a local. |
| File size | ≤ 200 lines (max ~500) | The file contains multiple classes. Split. |
| Indent depth | ≤ 3 levels | Guard clauses + extract method. |
| Blank lines between methods | exactly 1 | Tooling auto-fixes. |
| Blank lines inside a method | 0 or 1 to separate sections | 2+ blank lines = function does 2+ things. Split. |

## Anti-patterns the formatter can't always catch

- **Manual column alignment.** Aligning `=`, `:`, or `->` across declarations emphasises the wrong axis and breaks every reformat. The formatter is alignment-off; don't fight it.
- **Collapsed single-line `if`/`for`/`while` bodies.** `if (cond) doX()` hides scope. Expand to a block.
- **Useless KDoc breaking related pairs.** A `/** ... */` between two related field declarations breaks the visual pair. Either keep the pair tight, or move the comment above the pair with a blank line separator.
- **Reformatting a file you're touching for a bugfix.** Open a separate "reformat" PR; commit it via `.git-blame-ignore-revs` so `git blame` stays useful.
- **Caller and callee at opposite ends of the file.** Stepdown: put the callee just below the caller.

## Anti-patterns in formatting work itself

- **Litigating style in PR review when there's a formatter.** Run the formatter, move on.
- **Mixing formatter changes with semantic changes** in one commit. Reformat commits do one thing.
- **Skipping the CI gate "just for this PR".** The gate is what makes the rules survive turnover.
- **Treating expression bodies (`fun x() = ...`) as a goal.** Single-expression form is a *reward* for a function that genuinely is one expression — not a target.
- **Adopting Clean Code's Java conventions verbatim in Kotlin.** Martin's "instance vars at top of class" is shaped by Java field declarations. Kotlin's primary constructor *is* the place.
