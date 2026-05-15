---
name: clean-code-classes
description: "Use for any class review or split — size, cohesion, 25-word test. NOT for SOLID/functions."
---

# Clean Code — Classes

A class is a noun in the system's story. Most long-lived codebases get painful at the class level — files that grew one method at a time, weasel-suffixed aggregations, anaemic data holders next to procedural services. This skill is the discipline for **class shape and size** — when to split, what belongs together, how much to expose. Many small classes have the same total complexity as a few big ones, but labelled.

## When to use

- Designing a new class — what is its *one* concern, before the first member is written?
- Reviewing a class that grew past one screen — measure concerns, not lines.
- A class name ends in `Manager`, `Helper`, `Util`, `Processor`, `Super`, or bare `Service`.
- Private methods are called only by a subset of public methods — a class is trying to escape.
- A class has 20+ instance variables, 70+ public methods, or 500+ lines.
- Auditing a module before merging — does each class have one reason to change?

## When NOT to use

- The task is **inside a function** — defer to `code/clean-code-functions` (when it lands).
- SOLID-specific violations at principle scope — see `architecture/application/solid/`.
- The shape is framework-enforced (`@Entity`, gRPC stub, Jackson DTO) — accept the shape, isolate it.
- The class is a one-line value wrapper or a generated class.
- Cross-module / cross-context design — see `architecture/`.
- Naming alone — see `code/clean-code-naming`.

## Output template — when reviewing a class

Structure the review response as:

1. **25-word verdict.** Write the class's purpose in ≤25 words. Pass / fail; if fails, point to the forbidden conjunction (`and` / `or` / `if` / `but`).
2. **Size & cohesion summary.** Public method count, instance variable count, file lines. List cohesion clusters (which methods + fields move together).
3. **Smells found.** Match against the weasel red list and the smell→fix lookup below.
4. **Action plan.** Numbered, in execution order: characterisation tests first → cluster(s) to extract with proposed new class names → renames after the split.

If the class passes all checks, say so explicitly — don't invent problems.

## Core checks

**25-word test.** Write the class's purpose in one ≤25-word sentence without `and` / `or` / `if` / `but`. Each forbidden conjunction is a separate concern — a separate class. Apply to the name first, then to the description.

**Cohesion clustering.** For each instance field, list the methods that touch it. Clusters of fields-touched-by-the-same-methods are candidate classes. *Falling cohesion* after function-extraction (small methods promote locals to fields) is the **signal to split**, not a defect of the refactoring.

**Visibility tree.** Test-access hierarchy: public API → module-internal / package → protected → **never** public. A `public` field for testability is surrender, not loosening — if the test seam needs it, the class probably wants to be split.

**Size targets.** Heuristics, not laws. A cohesive aggregate may legitimately exceed these if all parts touch one invariant.

| Metric | Target | Action when exceeded |
|---|---|---|
| Reasons to change | exactly 1 | Split along the axis of change |
| Public methods | ~< 10 | Look for cohesion subsets |
| Instance variables | ~< 7 | Look for a value object trying to escape |
| Cohesion: methods using each field | ≥ ~50% | Falling cohesion = subset is a new class |
| File lines | ≤ ~500 | Long files usually contain multiple classes |

## Weasel suffix red list

The vague name is the *result* of a vague concern — fix the concern, not the name. Renaming `FooManager` to `FooService` and declaring victory is theatre.

| Suffix | What it really says | Fix |
|---|---|---|
| `*Manager` | "manages what, exactly?" | Verb buried inside — pull it out: `OrderSubmitter`, `SessionAuthenticator` |
| `*Processor` | "processes which input, how?" | Specific verb: `PaymentApprover`, `BatchReconciler` |
| `*Handler` | "handles what?" | Verb + subject: `OrderEventConsumer` |
| `*Helper` / `*Util` | "helps with anything" | The missing class; or top-level / extension functions |
| `*Super*` | self-aware admission of size | Always a smell — split |
| Plain `*Service` (no domain qualifier) | bag-of-methods | Acceptable for genuine orchestrators (load → call → save); not the default |

## Smell → fix lookup

| Smell | Fix |
|---|---|
| Class with 70 public methods | Cluster methods by field usage; each cluster is a class. |
| 5 methods, 2 unrelated concerns | Still too big. Split. |
| Field used by only one method | Value object trying to escape, or method belongs on another class. |
| Private helper used only by 2 of 7 public methods | Those 2 methods + their fields are a separate class. |
| Service with 5 unrelated use cases | Split by use case: one class per verb. |
| 30 instance variables | Group related into value objects (`Address`, `Period`, `MoneyRange`). |
| Test needs `@VisibleForTesting public` | Drive through public API, or use module-internal visibility, or extract a class with a legitimate public surface. |

## Refactoring a god class — mechanical recipe

1. **Characterisation tests first.** Pin current behaviour. Run, green.
2. **List every public method**, cluster by which fields they touch.
3. **Re-read each cluster** with the 25-word test — is the cluster name actually one concern?
4. **Extract** — move the cluster's methods and fields into a new class. Re-run tests.
5. **Rename** — the extracted class's name shouldn't end in `Manager` / `Helper`.
6. **Repeat** until each class passes the 25-word test. Stop at one concern per class, not at short files.

Never change behaviour and structure in the same step.

## Class layout — stepdown

Inside each class: constants → state → constructor → public API → private helpers, each helper directly after its first caller. The reader can stop descending when they've understood enough.

## Practices

`resources/practices.md` — worked end-to-end review walkthrough plus bad/best example catalog. For the WHY behind each check, see `resources/theory.md`.

## Source

Adapted from R. C. Martin, *Clean Code*, ch. 10 "Classes". SOLID at principle scope (SRP/OCP/LSP/ISP/DIP) lives in `architecture/application/solid/`.
