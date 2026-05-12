# When Comments Earn Their Keep

The 8 legitimate categories from Martin Ch. 4, with Kotlin/Spring examples and house refinements. For anti-patterns see `comment-anti-patterns.md`; for Kotlin-specific syntax see `kotlin-spring-comments.md`.

> The only truly good comment is the comment you found a way not to write. — Martin

Each category has:
- **Principle** — when this comment type is legitimate
- **Good** — Kotlin example showing it earning its keep
- **First try** — what to attempt *before* keeping the comment
- **House refinement** (where applicable)

---

## Category 1: Legal Comments

**Principle**: Copyright headers, SPDX-License-Identifier, license references at the top of each source file when required by the org.

**Good**:
```kotlin
// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Example Corp.

package com.example.platform.checkout.domain
```

**First try**: Reference an external `LICENSE` file at the repo root rather than pasting the full license text into every file.

**House refinement**: Prefer SPDX one-liner + `LICENSE` file at the root over multi-line block headers. IDE/tools collapse SPDX automatically; multi-line headers add clutter without value.

---

## Category 2: Informative Comments

**Principle**: Comment provides basic information the function name can't carry — typically the format expected by a regex, the structure of a string contract, etc.

**Good**:
```kotlin
// Matches "Tue, 02 Apr 2003 22:18:49 GMT" — RFC 7231 §7.1.1.1
private val HTTP_DATE_PATTERN = Regex(
    """[SMTWF][a-z]{2},\s\d{2}\s[JFMASOND][a-z]{2}\s\d{4}\s\d{2}:\d{2}:\d{2}\sGMT"""
)
```

**First try**: Rename the constant to carry the information.

```kotlin
// Better — name carries the standard reference; comment becomes redundant
private val RFC_7231_HTTP_DATE_PATTERN = Regex(...)
```

**House refinement**: If the name + standard reference (RFC number, ISO number) carries the meaning, the comment is unnecessary. Keep the comment only when the format is non-obvious to a reader who already knows the standard.

---

## Category 3: Explanation of Intent — the *why*

**Principle**: The most legitimate category. The comment explains a non-obvious decision that affects the structure of the code.

**Good**:
```kotlin
class WikiPagePath(val names: List<String>) : Comparable<Any> {
    override fun compareTo(other: Any): Int {
        if (other is WikiPagePath) {
            return names.joinToString("").compareTo(other.names.joinToString(""))
        }
        // we sort same-type higher because this class owns the canonical comparator;
        // other types are placed before us so they don't pollute ordering
        return 1
    }
}
```

The comment explains the *decision*; the code alone doesn't tell you that mixing types was considered and intentionally biased.

**Good** (concurrency rationale):
```kotlin
@Test
fun `widget builder is thread-safe under concurrent adds`() {
    // 25_000 threads is an attempt to provoke a race; lower counts pass even on broken code
    val failFlag = AtomicBoolean(false)
    repeat(25_000) {
        Thread { /* hammer the builder */ }.start()
    }
    assertFalse(failFlag.get())
}
```

**First try**: Express the intent in a name or a small method that *carries* the intent (`tryToProvokeRaceConditions(25_000)`). When neither fits, the comment earns its keep.

**House refinement**: Intent comments are the workhorse of legitimate commentary. When you write one, make sure it says *why* the choice was made — not what the code does, but why this choice over alternatives. "Sort same-type higher because we own the canonical comparator" beats "// returns 1 if not same type".

---

## Category 4: Clarification

**Principle**: Translates an obscure third-party argument or return value when you cannot change the API.

**Good**:
```kotlin
@Test
fun testCompareTo() {
    val a  = PathParser.parse("PageA")
    val ab = PathParser.parse("PageA.PageB")
    val b  = PathParser.parse("PageB")

    assertTrue(a.compareTo(a)  == 0)   // a == a
    assertTrue(a.compareTo(b)  == -1)  // a <  b
    assertTrue(ab.compareTo(a) == 1)   // ab >  a
}
```

The clarification makes a dense list of assertions readable.

**First try**: Replace with named expectations.
```kotlin
@Test
fun testCompareTo() {
    val a  = PathParser.parse("PageA")
    val b  = PathParser.parse("PageB")
    val ab = PathParser.parse("PageA.PageB")

    assertThat(a).isEqualByComparingTo(a)
    assertThat(a).isLessThan(b)
    assertThat(ab).isGreaterThan(a)
}
```

**House refinement**: AssertJ matchers (`isLessThan`, `isEqualByComparingTo`) usually obsolete clarification comments. Keep the comments only when the matcher would be the noisier choice.

---

## Category 5: Warning of Consequences

**Principle**: Warns the next reader about a non-obvious operational consequence (slow, not thread-safe, intentionally test-skipped, requires special setup).

**Good** (test that takes too long):
```kotlin
@Test
@Disabled("Takes ~5 min — run only when investigating perf regressions")
fun reallyBigFileResponse() { ... }
```

**Good** (thread-safety note):
```kotlin
/**
 * Returns a fresh [SimpleDateFormat] per call.
 *
 * @implNote `SimpleDateFormat` is not thread-safe; sharing instances across threads
 * causes silent corruption. Always construct per use.
 */
fun standardHttpDateFormat(): SimpleDateFormat = ...
```

**First try**: Use an annotation (`@Disabled(reason)`, `@Deprecated(message)`, `@Suppress("X") // reason: ...`) that the toolchain understands. Plain comments work, but annotations integrate with reporting.

**House refinement**: A `@Disabled` test without a `reason` argument is a smell — the reason *is* the warning. Same for `@Suppress` without an explanation.

---

## Category 6: TODO Comments

**Principle**: Mark deferred work — code that exists in a known-incomplete state. Modern IDEs and CI surface TODOs automatically; treat them as queryable inventory.

**Good**:
```kotlin
// TODO(DEV-1234): retire after the V2 migration completes (target: Q3)
protected fun makeLegacyVersion(): VersionInfo? = null
```

**Good** (Kotlin's `TODO()` function for stubs that should crash if hit):
```kotlin
fun applyDiscount(order: Order, code: DiscountCode): Money =
    TODO("DEV-1234: discount engine not yet wired")
```

**First try**: Move the TODO into the issue tracker if it's larger than a one-line note. A `// TODO` that needs paragraphs of context belongs in a ticket.

**House refinement**:
- Every `// TODO` must include an **owner** (`(@username)`) or an **issue ID** (`(DEV-1234)`). Orphan TODOs get swept.
- TODOs that have aged past a release cycle without movement are stale — either do them or delete them.
- Prefer `TODO("reason")` (the Kotlin stdlib function that throws `NotImplementedError`) for unimplemented stubs that should fail loudly if hit at runtime. Plain `// TODO` comments are for documented intent without runtime enforcement.

---

## Category 7: Amplification

**Principle**: Marks something easily missed — small code that has outsized importance.

**Good**:
```kotlin
val listItemContent = match.groupValues[3].trim()
// the .trim() is load-bearing — leading spaces would let this match the parent list,
// causing infinite recursion in buildList()
ListItemWidget(this, listItemContent, level + 1)
```

**First try**: Extract a named helper that carries the importance.
```kotlin
val listItemContent = match.groupValues[3].withoutLeadingWhitespaceToAvoidRecursion()
// no comment needed — the name carries the intent
```

**House refinement**: Amplification is the comment category most often eliminable by extracting a named method. Try the extraction first; keep the comment only if the helper name would be even uglier than the comment.

---

## Category 8: Public API KDoc (Javadoc equivalent in Kotlin)

**Principle**: Required at *library / SDK / published-module* boundaries. Optional inside internal services.

**Good** (library boundary):
```kotlin
/**
 * Validates and parses an email address into the [Email] value object.
 *
 * @param raw the raw input string; leading/trailing whitespace is trimmed
 * @return the parsed [Email]
 * @throws InvalidEmailException if the input is malformed (no `@`, multiple `@`, etc.)
 *
 * @sample com.example.samples.parseEmailSample
 */
fun parseEmail(raw: String): Email = ...
```

**Bad** (KDoc on internal service code that nobody outside the module reads):
```kotlin
/**
 * Submits the order.
 *
 * @param orderId the order id
 * @return the submitted order
 */
internal fun submit(orderId: OrderId): Order { ... }
```

The internal KDoc adds zero — the signature already carries everything.

**First try**: Apply the visibility gate. Is this `public` and crossing a published-module boundary? Yes → KDoc. No → default to no KDoc unless there's a non-obvious *why* to document.

**House refinement**:
- **Public API boundary** → KDoc required, with `@param` / `@return` / `@throws` / `@sample` where applicable.
- **Internal** / `internal` modifier → KDoc only on classes/methods with non-obvious invariants or operational gotchas.
- **Private** → KDoc almost never; the function/class is small enough to read.
- KDoc that just paraphrases the signature is "Redundant Comments" — see `comment-anti-patterns.md` §B2.

---

## Summary checklist — keep this comment?

Before keeping any comment, run this list:

- [ ] Is the comment a **legal header** (SPDX, copyright)? → keep
- [ ] Does it explain **why** (not *what*)? → keep
- [ ] Does it **warn** about a consequence not visible from the code? → keep (or convert to annotation)
- [ ] Is it a **TODO** with owner / issue ID and an active timeline? → keep
- [ ] Does it **amplify** subtle but load-bearing code, and can't be eliminated by extraction? → keep
- [ ] Is it on a **public-API boundary** (library / SDK)? → keep as KDoc with full tags
- [ ] Does it **clarify** a third-party API you cannot change? → keep, sparingly
- [ ] Anything else? → almost certainly delete; see `comment-anti-patterns.md`
