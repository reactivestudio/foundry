# Code Smells Catalog

Diagnostic format per smell: **Symptom → Diagnosis → Fix sketch → When NOT to fix → Owner sibling for the deep dive.**

Use this file when you've identified that something is wrong with messy code and want to:

- name the smell precisely, and
- know which sibling clean-code-* skill owns the full Kotlin before/after refactor.

The fix sketches here are deliberately one-paragraph. For the worked Kotlin examples with edge cases — follow the **Owner** cross-reference.

---

## 1. Long method

**Symptom:** A function over ~30 lines, scrolling required to read it.

**Diagnosis:** "Long" is the visible symptom; the disease is "does multiple things at multiple levels of abstraction." A 25-line linear function that does one thing is fine.

**Fix sketch:** Extract orchestration on top, named steps below (the stepdown rule). The top of the function reads like a table of contents; private helpers underneath provide the detail.

**When NOT to fix:** Length alone, with no multiple-things problem, is a non-smell. A `when` over 12 sealed variants can be 30 lines and still optimal.

**Owner:** `clean-code-functions`

---

## 2. Deep nesting (pyramid of doom)

**Symptom:** Four or more levels of indentation; control flow descends and snakes back up.

**Diagnosis:** Each level is a precondition the reader has to keep on the stack.

**Fix sketch:** Guard clauses; return early on the failure cases at the top, leave the happy path flat at the bottom.

**When NOT to fix:** Genuinely nested computations (matrix loops, tree walks) may legitimately nest 2–3 levels.

**Owner:** `clean-code-functions`

---

## 3. Long parameter list / flag arguments

**Symptom:** Four or more parameters; especially same-typed runs (`String, String, String`). Or a `Boolean` argument that switches the function's behaviour.

**Diagnosis:** Either the function does two things (boolean argument), or the parameters belong together in a value object.

**Fix sketch:** Group cohesive parameters into a `data class` request type — validate once at its constructor. Split a flag-argument function into two named functions (`sendNotification` and `sendUrgentNotification`), or replace the boolean with a named `enum`.

**Owner:** `clean-code-functions` (arity, flag arguments); `clean-code-objects-and-data` (request-type discipline)

---

## 4. Primitive obsession

**Symptom:** `String` used for `Email`, `UserId`, `PhoneNumber`. `Long` used as both cents and milliseconds. The compiler can't distinguish `userId` from `orderId` when both are `UUID`.

**Diagnosis:** The domain has named concepts; the code carries them as raw primitives, so the type system can't help.

**Fix sketch:** `@JvmInline value class` per concept (`OrderId(val value: UUID)`, `Email(val value: String)`). No runtime cost — the compiler inlines the wrapper. Validation lives in the value class's `init` block.

**When NOT to fix:** One-off scripts, single-use parameters. The ceremony costs more than the safety.

**Owner:** `clean-code-objects-and-data` (value-object discipline); `clean-code-naming` (value-class naming conventions)

---

## 5. Train wreck (Law of Demeter violation)

**Symptom:** `a.b().c().d().e()` — the caller drills through three classes' internals.

**Diagnosis:** The caller knows too much about `a`'s internal structure. Change anything in the chain and every caller breaks.

**Fix sketch:** **Tell, don't ask.** Ask what the caller was going to *do* with the chain's result, and put that operation on `a`. If `a` isn't yours to modify (third-party type, generated code), the same fix lands as an **extension function** in your code. Splitting the chain into temporary variables is *not* a fix — it's the same violation, spelled out longer.

**When NOT to fix:** Plain data structures (DTOs, configuration objects) — Demeter doesn't apply; `?.` chains on DTOs are fine. Fluent builders / DSLs — the type of every link is the same builder. Stdlib collection pipelines — values flowing through, not internals being navigated.

**Owner:** `clean-code-objects-and-data`

---

## 6. Feature envy

**Symptom:** A method in class `A` reads/uses fields and methods of class `B` far more than its own.

**Diagnosis:** The method is in the wrong class.

**Fix sketch:** Move it to `B`. If `B` is a `data class` you don't want to bloat (or a vendor type you don't own), an **extension function** on `B` is the Kotlin equivalent of "move the method."

**Owner:** `clean-code-objects-and-data`

---

## 7. `when` / `if` chains on type

**Symptom:** `when (event) { is OrderCreated -> ...; is OrderPaid -> ...; else -> error("unknown") }` repeated in three different places.

**Diagnosis:** Open hierarchy where it should be closed. New variant means hunting every `when` to update — and the `else` branch hides the bugs you missed.

**Fix sketch:** `sealed interface` / `sealed class` for the hierarchy. The `when` becomes exhaustive — no `else` needed; the compiler errors when a new variant isn't handled.

**When NOT to fix:** Truly open extension points (plugin systems, third-party variants) — keep them as `interface` / open `class`.

**Owner:** `clean-code-functions` (polymorphism vs. switching on type)

---

## 8. Dead code

**Symptom:** Unused parameters, unreachable branches, commented-out blocks, methods called from nowhere.

**Diagnosis:** Dead code lies about what the system does. Maintenance still has to read it. IDE inspections often miss it.

**Fix sketch:** Delete it. Git remembers.

**When NOT to fix:** If the dead code is outside your current change scope — flag it for a separate task; don't drift-scope the PR. (Same reason the refactoring loop says "one smell, one fix, one commit.")

**Owner:** Universal — applies wherever the dead code lives.

---

## 9. Needless complexity / premature abstraction

**Symptom:** Strategy pattern with one implementation. Factory wrapping a single constructor. Interface with one implementer. Generic type parameter only ever substituted with `Any`.

**Diagnosis:** Abstraction built for a future need that never came. The cost (indirection, ceremony, reader confusion) is paid every day; the benefit (swap-out) is never used.

**Fix sketch:** Inline. Make it concrete. Extract the abstraction *when* the second concrete case actually shows up — and you'll know what its real shape should be at that point.

**Owner:** `clean-code-classes` (OCP misuse); `clean-code-systems` (DI overuse)

---

## 10. Comment-as-failed-name

**Symptom:** A comment explaining WHAT non-obvious code does, immediately above it.

**Diagnosis:** The names failed; the code can't speak for itself.

**Fix sketch:** Rename the variable/function or extract a helper so the comment becomes redundant; then delete the comment. Comments documenting **WHY** (non-obvious business rule, legal note, performance trick, regex intent) stay.

**Owner:** `clean-code-comments` (which comments earn their keep); `clean-code-naming` (naming for intent)

---

## 11. God class / fat service

**Symptom:** A `UserService` with 30 methods doing CRUD + auth + profile + notifications + audit + billing.

**Diagnosis:** Multiple responsibilities — multiple reasons to change.

**Fix sketch:** Split by responsibility. In Spring, multiple small `@Service` classes is fine — DI keeps wiring cheap.

**Owner:** `clean-code-classes`

---

## 12. Anemic domain / hybrid class

**Symptom:** A JPA `@Entity` with only `var` fields and bean accessors, all logic living in a service. Or a class with both public mutable fields and business methods that act on them.

**Diagnosis:** Anemic = data without behaviour; hybrid = behaviour without encapsulation. Either way, the invariants the class is supposed to enforce live elsewhere and aren't really enforced.

**Fix sketch:** Pick one shape — pure data (read-only `data class`, no methods beyond mappers) or behaviour-rich aggregate (private mutable state, public methods enforcing invariants). Never both.

**Owner:** `clean-code-objects-and-data`

---

## 13. `data class` for a JPA `@Entity`

**Symptom:** `@Entity data class User(...)`.

**Diagnosis:** Hibernate proxies break field-based `equals`/`hashCode` (lazy loading triggers at the wrong moment). State-based equality is wrong for entities — entity identity is the `id`, not the state. `hashCode` over fields changes when state changes → breaks `HashSet` / `HashMap` membership.

**Fix sketch:** Regular `class` with `id`-based equality for JPA entities. `data class` stays for VOs, DTOs, and domain events.

**Owner:** `clean-code-objects-and-data`

---

## 14. `!!` everywhere

**Symptom:** Code peppered with `!!` non-null assertions.

**Diagnosis:** The type system was right (`T?`); the author overrode it. Every `!!` is a potential NPE in production with an unhelpful stack trace.

**Fix sketch:** `?:` with a meaningful default, or `requireNotNull(x) { "..." }` with a real error message, or restructure so the value is non-null by construction.

**Owner:** `clean-code-error-handling` (the `kotlin-specific-error-handling.md` resource also has the Detekt rule that lints `!!` to zero).

---

## 15. Mutable state where immutable would do

**Symptom:** `var` everywhere; `MutableList` exposed publicly from a class.

**Diagnosis:** Mutation is an escape route around the aggregate's invariants — anyone holding the list can corrupt the state.

**Fix sketch:** Prefer `val` and read-only collection types (`List<T>`, not `MutableList<T>`) on public APIs. The aggregate keeps mutable state private and controls mutation through methods that enforce invariants.

**Owner:** `clean-code-objects-and-data` (aggregate boundaries); `clean-code-classes` (encapsulation)

---

## How to use this file

1. Read the **Symptom** column to match what you see in the messy code.
2. Confirm with the **Diagnosis** — does this code actually have the underlying problem, or just look superficially similar?
3. For the full Kotlin before/after with edge cases — follow the **Owner** cross-reference.
4. Apply **one smell, one fix, one commit** (see `SKILL.md` for the cadence rules).
5. Re-read the diff before merge: is the change *only* about this smell, or did unrelated improvements sneak in?
