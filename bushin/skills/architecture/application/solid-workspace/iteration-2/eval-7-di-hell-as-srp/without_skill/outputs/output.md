# No. Hiding the parameters is treating the symptom. Split the class.

A 9-arg constructor is not a DI-ergonomics problem. It's the compiler telling you `ReportGenerator` has too many reasons to change — i.e. it's violating **SRP**. ServiceLocator and "fat builder" both make the smell quieter without removing it, and ServiceLocator additionally makes the smell harder to detect later. Don't do either as the primary fix.

## Why ServiceLocator is the wrong answer

- It turns **explicit** dependencies (constructor args, visible to the compiler and to every reader) into **implicit** ones (hidden lookups inside method bodies). The class now lies about what it needs.
- It defeats the main benefit of constructor injection: you can no longer tell, from the type's public surface, what collaborators it touches. Tests get harder, not easier — you must stub a global registry instead of passing fakes.
- It's widely considered an anti-pattern (Mark Seemann's "Dependency Injection in .NET" makes the canonical case). The 9 dependencies don't disappear; they just stop being auditable.

## Why a builder is only a cosmetic fix

A builder hides the call-site noise (`new ReportGenerator.Builder().repoA(...).repoB(...)...build()`), but the class still:
- has 9 fields,
- has 9 reasons to change (any of those collaborators evolving forces a re-test of the whole generator),
- is still hard to unit-test because every test must wire 9 fakes,
- still violates SRP.

Use a builder when a class legitimately has many **optional** configuration values (e.g. an HTTP client). It is not the answer to "I have too many required collaborators."

## What the 9 deps are actually telling you

Five repositories + two services in one class almost always means `ReportGenerator` is doing several jobs stacked on top of each other. Typical decomposition:

1. **Data gathering** — a `ReportDataLoader` (or several, one per bounded slice of data) owns the repositories. Returns a plain `ReportData` DTO.
2. **Business calculation / aggregation** — a `ReportCalculator` takes `ReportData`, returns `ReportModel`. Pure, no I/O, trivially testable.
3. **Rendering / formatting** — a `ReportRenderer` turns `ReportModel` into the output format (PDF/HTML/CSV).
4. **Orchestration** — the now-thin `ReportGenerator` depends on **3 collaborators**: loader, calculator, renderer. Plus logger/config if genuinely needed.

After that split, each piece has 2–4 deps, each has one reason to change, and each is testable in isolation. The 9 original dependencies are still in the system — they just live in the class that actually uses them.

## Concrete recommendation

1. List the 9 deps and group them by **the operation that uses them**. You'll almost certainly see 2–4 clusters.
2. Extract each cluster into its own collaborator with a focused interface.
3. `ReportGenerator` keeps only the cluster-level collaborators (likely 3–4 args). If it's still too wide, repeat.
4. Leave the logger as-is (cross-cutting; or move it behind an aspect/decorator if your stack supports it). Config: pass only the slice each collaborator needs, not the whole god-config.
5. Only **after** the split, if some leaf class still has many optional knobs, consider a builder there. Never reach for ServiceLocator.

The coworker's instinct ("the constructor is ugly") is right; their fix is wrong. The constructor is ugly because the class is doing too much — fix the class, not the constructor.
