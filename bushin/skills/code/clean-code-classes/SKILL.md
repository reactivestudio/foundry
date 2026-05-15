---
name: clean-code-classes
description: "Class design: size, cohesion, layout, when to split. NOT for SOLID or function-level."
---

# Clean Code — Classes

A class is a noun in the system's story. Most long-lived codebases get painful at the class level — files that grew one method at a time, weasel-suffixed aggregations, anaemic data holders next to procedural services. This skill is the discipline for **class shape and size** — when to split, what belongs together, how much to expose. SOLID at principle scope (SRP/OCP/LSP/ISP/DIP) is covered separately in `solid/`.

## When to use

- Designing a new class — what is its *one* concern, before the first member is written?
- Reviewing a class that grew past one screen — measure concerns, not lines.
- A class name ends in `Manager`, `Helper`, `Util`, `Processor`, `Super`, or bare `Service`.
- 25-word description needs `and` / `or` / `if` / `but`.
- Private methods are called only by a subset of public methods and touch only a subset of fields — a class is trying to escape.
- A class has 20+ instance variables, 70+ public methods, or 500+ lines.
- Auditing a module before merging — does each class have one reason to change?

## When NOT to use

- The task is **inside a function** — defer to `code/clean-code-functions` (future skill).
- SOLID-specific violations at principle scope — see `code/solid/`.
- The shape is framework-enforced (`@Entity`, gRPC stub, Jackson DTO) — accept the shape and isolate it.
- The class is a one-line value wrapper or a generated class.
- Cross-module / cross-context design — see `architecture/`.
- Naming alone — see `code/clean-code-naming`.

## House defaults

- **Privacy by default.** Loosen for tests only as last resort. Hierarchy: drive through public API → module-internal / package-private → protected → **never** public for testability — that's surrender, not loosening.
- **Weasel suffix ban.** `Manager`, `Helper`, `Util`, `Processor`, `Super*`, bare `Service` — almost always hide aggregated concerns. Renaming without splitting is theatre — fix the concern first.
- **25-word, no `and`/`or`/`if`/`but` test.** Each forbidden conjunction = a separate class. Apply to the name first, then to a written description.
- **Many small classes have the same total complexity as a few big ones**, but labelled. Don't resist the file count — resist the lack of labels.
- **Characterisation tests first, refactor second.** Never change behaviour and structure simultaneously.

## Size & shape — quick targets

Heuristics, not laws. A cohesive aggregate may legitimately have 15 fields and 20 methods if all touch the same invariant.

| Metric | Target | Action when exceeded |
|---|---|---|
| Reasons to change | exactly 1 | Split along the axis of change |
| 25-word description | no `and`/`or`/`if`/`but` | Each forbidden conjunction = a separate class |
| Public methods | ~< 10 | Look for cohesion subsets — separate classes |
| Instance variables | ~< 7 | Look for a value object trying to escape (`Address`, `Period`, `MoneyRange`) |
| Cohesion: methods using each field | ≥ ~50% | Falling cohesion = subset is a new class |
| File lines | ≤ ~500 | Long files usually contain multiple classes |

## Weasel suffix red list

The vague name is the *result* of a vague concern — fix the concern first.

| Suffix | What it really says | Fix |
|---|---|---|
| `*Manager` | "manages what, exactly?" | Verb buried inside — pull it out: `OrderSubmitter`, `SessionAuthenticator` |
| `*Processor` | "processes which input, how?" | Specific verb: `PaymentApprover`, `BatchReconciler` |
| `*Handler` | "handles what?" | Verb + subject: `OrderEventConsumer` |
| `*Helper` / `*Util` | "helps with anything" | The missing class; or top-level / extension functions |
| `*Super*` | self-aware admission of size | Always a smell — split |
| Plain `*Service` (no domain qualifier) | bag-of-methods | Acceptable for genuine orchestrators (load → call → save); not the default |

## Smell → fix quick reference

| Smell | Fix |
|---|---|
| Class with 70 public methods | Cluster methods by field usage; each cluster is a class. |
| Name ends in `Manager` / `Helper` / `Util` / `Processor` | Find the real concern; rename to that domain noun. If no single one, split. |
| 25-word description needs `and` / `or` | One class per `and`. |
| 5 methods, 2 unrelated concerns | Still too big. Split. |
| Field used by only one method | Value object trying to escape, or method belongs on another class. |
| Private helper used only by 2 of 7 public methods | Those 2 methods + their fields are a separate class. |
| Service with 5 unrelated use cases (`submit` / `cancel` / `refund` / `export` / `recompute`) | Split by use case: one class per verb. |
| 30 instance variables | Group related ones into value objects (`Address`, `Period`, `MoneyRange`). |
| Test needs `@VisibleForTesting public` | Either drive through public API, or use module-internal visibility, or extract a class with a legitimate public surface. |

## Core principles

Ten condensed. Full WHY in `resources/theory.md`.

1. **Newspaper / stepdown layout.** Constants → state → constructor → public API → private helpers, each helper directly after its first caller.
2. **Privacy by default.** Test seam hierarchy: public API → internal → protected → never public.
3. **Size = concerns, not lines.** A 30-method class with one concern is smaller than a 5-method one with two.
4. **25-word test.** No `and`/`or`/`if`/`but` in the description.
5. **Weasel suffix smell.** `Manager`/`Helper`/`Util`/`Processor`/`Super` hide aggregated concerns.
6. **High cohesion.** Methods touch most fields. Cluster fields by their users; clusters become classes.
7. **Falling cohesion = signal to split**, not a defect of extraction.
8. **Many small classes** = same total complexity, but labelled.
9. **Characterisation tests first**, refactor second.
10. **Stop at one concern per class**, not at short files.

## Refactoring a god class — mechanical recipe

1. **Add characterisation tests** around the original behaviour. Run, green.
2. **List every public method.** Cluster them by which fields they touch.
3. **Re-read each cluster** with the 25-word test — is the cluster name actually one concern?
4. **Extract** — move the cluster's methods and fields into a new class. Re-run tests.
5. **Rename** — the extracted class's name shouldn't end in `Manager`/`Helper`.
6. **Repeat** until each class passes the 25-word test.

## Practices

`resources/practices.md` — bad/best example catalog organised by topic (small-looking god class, low-cohesion split, stepdown layout, visibility tree, god service by use case, too-many-fields → value object, refactoring recipe in action).

## Source

Adapted from R. C. Martin, *Clean Code*, ch. 10 "Classes". SOLID at principle scope (SRP/OCP/LSP/ISP/DIP) is covered in `code/solid/`. Stack-specific class shaping (Kotlin / Spring / JPA / DDD) deferred to skills in those categories.
