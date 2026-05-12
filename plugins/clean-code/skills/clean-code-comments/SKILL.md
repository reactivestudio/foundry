---
name: clean-code-comments
description: "Comment discipline for Kotlin/Spring code — strong bias to delete, opinionated rules for when comments earn their keep (legal headers, explanation of intent, warning of consequences, amplification) versus the long list of anti-patterns (redundant Javadoc/KDoc, commented-out code, journal entries, mandated comments, position markers, attributions, mumbling, misleading, scary noise). Adapted from R. Martin's Clean Code Ch. 4 'Comments', filtered for what Kotlin already solves (KDoc replaces Javadoc, `@Deprecated` annotation replaces deprecation comments, `TODO()` function replaces some `// TODO` uses, sealed `when` exhaustiveness replaces explanatory comments) with house extensions on TODO discipline, KDoc on internal vs public APIs, and OpenAPI annotations replacing handler comments. Use when writing or reviewing comments in code, refactoring a comment-heavy file, deciding whether a KDoc block belongs on a class or function, cleaning up commented-out code, replacing TODO mumbling with issue-tracker references, auditing a module for comment hygiene, or pre-merge checking that comments explain *why* rather than restate *what*."
risk: safe
source: "Adapted from R. Martin, Clean Code (2008), ch. 4 'Comments', filtered for Kotlin/Spring + house rules"
date_added: "2026-05-12"
---

# Clean Code: Comment Discipline

> "Comments are, at best, a necessary evil. The proper use of comments is to compensate for our failure to express ourself in code." — R. Martin
>
> "Truth is in the code. A comment that lies costs more than no comment at all." — house rule.

Most comments are either redundant (restating what code already says), stale (the code moved on without them), or deflective (a comment instead of cleaner code). This skill encodes a strong bias to *delete* comments and rewrite the code so the comment is unnecessary. The remaining legitimate comments are documented as a short list of cases that genuinely earn their keep.

## Use this skill when
- Writing or reviewing a comment in code — the first question is always "should this exist?"
- Refactoring a file where comments outnumber code lines.
- Deciding whether a KDoc block belongs on a class or function.
- Cleaning up commented-out code (`//` blocks of disabled logic).
- Replacing `// TODO` mumbling with a real issue or owner.
- Auditing a module for KDoc / Javadoc hygiene before a release.
- Pre-merge check: every comment in the diff justifies its existence.

## Do not use this skill when
- Authoring legitimate documentation OUTSIDE code (README, ADR, runbook, architecture diagram). Those have different rules.
- Generating OpenAPI / Swagger docs from annotations — that's `api-design-principles`, not this skill.
- Writing or reviewing legal headers / SPDX identifiers — those are mandated by the org, not by this skill.

## Core stance (the six principles)

1. **The default is "no comment".** Code is the source of truth. If you have a choice between a comment and clearer code, pick clearer code.
2. **Comments explain *why*, not *what*.** What the code does is the code's job. Why this approach over alternatives, why this oddity, why now — those are legitimate comment topics.
3. **Comments lie because code changes faster than humans update them.** A stale comment is worse than no comment — it misleads with the authority of "documentation".
4. **Inaccurate comments are worse than no comments at all.** They delude, mislead, and set expectations that will never be fulfilled.
5. **A comment is a failure of expression.** When you reach for a comment, first ask: can I rename this function, extract this expression to a named variable, split this method, or use a typed enum / sealed class to make the comment unnecessary?
6. **Comments are not version control.** Use Git for history (`git blame`, `git log`); use issue trackers for TODOs; use ADRs for decision rationale; use READMEs for narrative. Don't smuggle any of these into source comments.

## Good comments — when they earn their keep

The 8 categories that survive scrutiny. Full examples in `resources/when-comments-earn-their-keep.md`.

| Category | Use for | Caveat |
|---|---|---|
| **Legal** | Copyright headers, SPDX-License-Identifier | Reference an external `LICENSE` file; don't paste the whole licence |
| **Informative** | Basic info a function name can't carry (e.g., regex format intent) | First try renaming; only comment if renaming doesn't fit |
| **Explanation of Intent** | The *why* behind a non-obvious decision | The most legitimate category — most worthwhile comments live here |
| **Clarification** | Translating an obscure third-party return value or argument | Rare; if the API is yours, fix the API instead |
| **Warning of Consequences** | "Don't run this in prod" / "Not thread-safe by design" | Often better as a `@Deprecated` / `@Disabled` annotation with reason |
| **TODO** | Work known to be deferred | Must include issue ID or owner; otherwise it's mumbling |
| **Amplification** | Marking something easily missed (e.g., "the `.trim()` is load-bearing") | Use sparingly; better — write a named helper |
| **Public API KDoc** | Library / SDK boundary documentation | Required at the public boundary; off by default inside internal services |

## Bad comments — anti-patterns

The 18+ patterns that don't earn their keep. Full catalog in `resources/comment-anti-patterns.md`.

| Anti-pattern | Signal | Fix |
|---|---|---|
| **Commented-out code** | `// val x = ...` left in the repo | Delete it. Git remembers. Bar to keep: "I'll uncomment within this session." |
| **Mumbling** | Comment that only made sense to the author at the moment of writing | Either rewrite to stand alone, or delete |
| **Redundant** | KDoc that paraphrases the signature ("returns the day of the month") | Delete |
| **Misleading** | The comment claims something the code doesn't actually do | Delete (and fix the code) |
| **Mandated** | Every function / property has KDoc because policy requires it | Drop the policy; KDoc only where it earns its keep |
| **Journal** | `// 11-Oct-2001 — refactored by DG` lists in file header | Use Git |
| **Noise** | `// Default constructor`, `/** the day */` | Delete |
| **Position markers** | `// ////// HELPERS //////`, IntelliJ `// region` | Group with extracted classes / files instead |
| **Closing-brace comments** | `} // for` / `} // if` | Function too long — split it |
| **Attributions / bylines** | `/* Added by Rick */` | Use Git |
| **HTML in comments** | `&lt;pre&gt;...&lt;/pre&gt;` smuggled into KDoc | KDoc uses Markdown |
| **Nonlocal info** | A method's comment talks about a config setting elsewhere | Move the comment to where the setting lives, or delete |
| **Too much info** | A wall of RFC text inside the comment | Link to the RFC instead |
| **Inobvious connection** | The comment is correct but its relationship to the code is unclear | Rewrite or delete |
| **Function-header on short function** | A 3-line function with a 6-line KDoc | The signature carries everything |
| **KDoc on nonpublic code** | KDoc on `private` / `internal` classes nobody outside the module sees | Off by default; rare exceptions for genuinely complex invariants |
| **TODO without owner / issue** | `// TODO fix this later` | Add `// TODO(DEV-1234): ...` or move to issue tracker; delete otherwise |
| **Comment instead of a function/variable** | `// check if employee is eligible for full benefits` over a complex `if` | Extract to `employee.isEligibleForFullBenefits()` |

## House rules layer

Additions on top of Martin specific to Kotlin/Spring/modern tooling. Details in `resources/kotlin-spring-comments.md`.

1. **Bias to delete.** If you hesitate whether a comment should stay, the answer is no.
2. **TODO discipline.** Every `// TODO` must include `(OWNER)` or `(ISSUE-ID)`; orphan TODOs get removed in the next sweep.
3. **KDoc gates on visibility.** `public` API boundary (library, SDK, published module) → KDoc required. `internal` / `private` → KDoc only when the *why* is non-obvious. Default off.
4. **Annotations over commentary.** Prefer `@Deprecated(message, replaceWith, level)` to a "deprecation" comment. Prefer `@Suppress("X")` paired with a one-line rationale comment. Prefer `@Schema(description = ...)` on a DTO field to a parallel KDoc.
5. **`TODO()` function for unimplemented code.** Throws at runtime — surfaces the gap during the first hit. Better than `// TODO implement` for stubs you intend to fill.
6. **`@DisplayName` over comment in tests.** Sentence-style backticked test names already document intent.
7. **No `// region` folding in production code.** If a class needs region-folding to be readable, it needs splitting.
8. **Logging is not commentary.** `log.info("Order submitted")` describes a *runtime* event, not the *static* code path; don't use log calls as a substitute for a comment.

## Selective Reading Rule

| File | When to read |
|---|---|
| `resources/when-comments-earn-their-keep.md` | The 8 categories with full Kotlin examples and house refinements. Read when you're considering keeping a comment. |
| `resources/comment-anti-patterns.md` | The 18+ anti-patterns with detection signals and fixes. Read when reviewing comments in a diff, cleaning up legacy, or running a pre-merge sweep. |
| `resources/kotlin-spring-comments.md` | Kotlin-specific (KDoc syntax, `@Deprecated`, `@Suppress`, `TODO()` function, IntelliJ language injection) and Spring-specific (OpenAPI annotations, `@DisplayName`, JPA `@Comment`) commentary patterns. |

## Anti-patterns in commenting work itself

- **Bulk-deleting comments without reading them.** A few comments are load-bearing; sweep with judgement, not regex.
- **Auto-generating KDoc with IDE shortcuts.** Empty `@param` stubs are the canonical "Mandated comments" smell.
- **Adding comments because review asked you to "explain" the code.** The reviewer is signalling "this code is unclear" — fix the code, not the documentation.
- **Removing a comment without checking whether the code still tells the story.** Sometimes the comment was the only signal that odd-looking code was odd-on-purpose. Replace with a clearer rewrite or with a test.

## Related skills

| Skill | This not that |
|---|---|
| `clean-code-naming` | Comments often vanish when names get better; this skill is what to do with the comments themselves |
| `clean-code-functions` | Functions that need comments are usually too long; this skill handles the comments, that one handles the splitting |
| `clean-code-formatting` | Where to put surviving comments (top of file, above declaration); this skill is whether to write one at all |
| `clean-code` | Smell vocabulary and refactoring cadence; this skill is the deep dive on comments specifically |
| `api-design-principles` | OpenAPI / Swagger generation via annotations (machine-readable docs) — cross-references at the boundary |
| `karpathy-guidelines` | §3 surgical changes — don't rewrite comments you're not touching in unrelated PRs |
| `architecture-decision-records` | Where decision rationale belongs (ADR), not in scattered code comments |
| `ddd-strategic-design` | Glossary / ubiquitous-language documentation belongs in domain docs, not in code comments |

## Limitations

- KDoc / Javadoc generation policies vary by team — `public` API boundaries always documented, but the line between "public" and "internal" is judgement. Sample the existing codebase's conventions before reshaping comment hygiene wholesale.
- Some rules trade off: a tiny, deeply-nested team can carry less comment overhead than a large open-source library. Apply judgement.
- Stop and ask if the codebase has a *publication contract* (SDK, public library) — that changes which comments earn their keep.
