---
name: clean-code-classes
description: "Use for any class review or split — size, cohesion, 25-word test. NOT for SOLID/functions."
---

# Clean Code — Classes

Mechanical procedures for sizing and splitting classes. The value is in applying them consistently, not in their philosophy.

## When to use

- A class name ends in `Manager`, `Helper`, `Util`, `Processor`, `Super`, or bare `Service`.
- A class has 20+ instance variables, 70+ public methods, or 500+ lines.
- Private methods are called only by a subset of public methods — a class is trying to escape.
- Reviewing a class for design, or auditing a module before merging.

## When NOT to use

- Task is **inside a function** → `code/clean-code-functions`.
- SOLID at principle scope → `architecture/application/solid/`.
- Framework-enforced shape (`@Entity`, gRPC stub, DTO) — accept the shape, isolate it.
- Naming alone → `code/clean-code-naming`.

## Output template — when reviewing a class

Structure the response as:

1. **25-word verdict.** Write the purpose in ≤25 words. Pass / fail; if fails, point to the forbidden conjunction.
2. **Size & cohesion summary.** Public methods, instance variables, file lines. List cohesion clusters.
3. **Smells found.** Match against the weasel red list and the smell→fix lookup.
4. **Action plan.** Numbered, in execution order: characterisation tests → cluster(s) to extract → renames.

If the class passes all checks, say so — don't invent problems.

## Core checks

**25-word test.** Write the class's purpose in one ≤25-word sentence without `and` / `or` / `if` / `but`. Each forbidden conjunction is a separate concern — a separate class. Apply to the name first, then the description.

**Cohesion clustering.** For each instance field, list the methods that touch it. Fields-touched-by-the-same-methods are a cluster — a candidate class. *Falling cohesion after function-extraction is the signal to split, not a defect of the refactoring.*

**Visibility for tests.** Test-access hierarchy: drive through public API → module-internal → never `public`. If a test seam needs `public`, the class probably wants to be split — the test is reaching for something that deserves its own class.

**Size targets.** Heuristics, not laws. A cohesive aggregate may legitimately exceed these if all parts touch one invariant.

| Metric | Target | Action when exceeded |
|---|---|---|
| Reasons to change | exactly 1 | Split along the axis of change |
| Public methods | ~< 10 | Look for cohesion subsets |
| Instance variables | ~< 7 | Look for a value object trying to escape |
| File lines | ≤ ~500 | Long files usually contain multiple classes |

## Weasel suffix red list

The vague name is the *result* of a vague concern — fix the concern, not the name. *Renaming `FooManager` to `FooService` is theatre.*

| Suffix | What it really says | Fix |
|---|---|---|
| `*Manager` | "manages what, exactly?" | Pull the verb out: `OrderSubmitter`, `SessionAuthenticator` |
| `*Processor` | "processes which input, how?" | Specific verb: `PaymentApprover`, `BatchReconciler` |
| `*Handler` | "handles what?" | Verb + subject: `OrderEventConsumer` |
| `*Helper` / `*Util` | "helps with anything" | The missing class; or top-level / extension functions |
| `*Super*` | self-aware admission of size | Always a smell — split |
| Plain `*Service` | bag-of-methods | OK for orchestrators (load → call → save); not the default |

## Smell → fix lookup

| Smell | Fix |
|---|---|
| Field used by only one method | Value object trying to escape, or method belongs on another class. |
| Private helper used by 2 of 7 public methods | Those 2 + their fields = separate class. |
| Service with 5 unrelated use cases | Split by use case: one class per verb. |
| 30 instance variables | Group related into value objects (`Address`, `Period`, `MoneyRange`). |
| Test needs `@VisibleForTesting public` | Drive through public API, use module-internal, or extract a class with a legitimate public surface. |

## Refactoring recipe

1. **Characterisation tests first.** Pin current behaviour. Green.
2. **List public methods**, cluster by which fields they touch.
3. **25-word test each cluster** — is it one concern?
4. **Extract** — move cluster's methods and fields into a new class. Re-run tests.
5. **Rename** — extracted class shouldn't end in `Manager` / `Helper`.

*Never change behaviour and structure in the same step.* Stop when each class passes the 25-word test — not when files are short.

## Practices

`resources/practices.md` — worked end-to-end review (`OrderService`) plus bad/best examples for the rules above.

## Source

R. C. Martin, *Clean Code*, ch. 10. SOLID at principle scope: `architecture/application/solid/`.
