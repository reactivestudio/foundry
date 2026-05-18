# Comments — strong bias to delete

Default: no comment. Code is the source of truth. If a comment is needed to explain *what* code does, the names failed — fix the names. Comments that survive scrutiny explain *why*.

## Output template — when reviewing comments

For each comment in the diff:

1. **Earned its keep?** Match against the 8 categories below.
2. **If yes**, accept. **If no**, identify the anti-pattern and fix the underlying code or delete.

## The 8 categories that earn their keep

| Category | Use for | Caveat |
|---|---|---|
| **Legal** | Copyright headers, SPDX identifier | Reference external `LICENSE` file; don't paste the whole licence |
| **Informative** | Info a function name can't carry (regex format intent, unit assumed by a literal) | Try renaming first; comment only if rename doesn't fit |
| **Intent (the WHY)** | The non-obvious decision: *why this approach over alternatives* | The most legitimate category — most worthwhile comments live here |
| **Clarification** | Translating an obscure third-party return value | If the API is yours, fix the API instead |
| **Warning of Consequences** | "Not thread-safe by design", "don't run in prod" | Often better as `@Deprecated` / `@Disabled` with reason |
| **TODO** | Work known to be deferred | Must include OWNER or ISSUE-ID — otherwise mumbling |
| **Amplification** | Marking something easily missed (`.trim()` is load-bearing) | Use sparingly; better, extract a named helper |
| **Public API KDoc** | Library / SDK boundary docs | Required at *public* boundary; off by default for `internal` / `private` |

## Anti-patterns — delete or fix the code

| Anti-pattern | Signal | Fix |
|---|---|---|
| **Commented-out code** | `// val x = ...` left in the repo | Delete. Git remembers. |
| **Mumbling** | Comment that only made sense to the author at that moment | Rewrite to stand alone, or delete |
| **Redundant** | KDoc paraphrasing the signature ("returns the day of the month") | Delete |
| **Misleading** | The comment claims something the code doesn't do | Delete (and fix the code) |
| **Mandated** | Every method has KDoc because policy requires it | Drop the policy; KDoc only where it earns its keep |
| **Journal** | `// 11-Oct-2001 — refactored by DG` in file header | Use Git |
| **Noise** | `// Default constructor`, `/** the day */` | Delete |
| **Position markers** | `// ////// HELPERS //////`, IntelliJ `// region` | Group with extracted classes/files instead |
| **Closing-brace comments** | `} // for` / `} // if` | Function too long — split it |
| **Attributions / bylines** | `/* Added by Rick */` | Use Git |
| **HTML in comments** | `&lt;pre&gt;...&lt;/pre&gt;` smuggled into KDoc | KDoc uses Markdown |
| **Nonlocal info** | Method comment talks about a config setting elsewhere | Move to where the setting lives, or delete |
| **Too much info** | Wall of RFC text inside the comment | Link to the RFC instead |
| **Inobvious connection** | Comment is correct but relationship to code is unclear | Rewrite or delete |
| **Function-header on short function** | A 3-line function with a 6-line KDoc | The signature carries everything |
| **KDoc on nonpublic code** | KDoc on `private` / `internal` classes nobody outside the module sees | Off by default; rare exceptions for complex invariants |
| **TODO without owner / issue** | `// TODO fix this later` | Add `// TODO(DEV-1234): ...`; or delete |
| **Comment instead of a function/variable** | `// check if employee is eligible` over a complex `if` | Extract to `employee.isEligibleForFullBenefits()` |

## House rules

1. **Bias to delete.** If you hesitate, the answer is no.
2. **TODO discipline.** Every `// TODO` must include `(OWNER)` or `(ISSUE-ID)`. Orphan TODOs are removed in the next sweep.
3. **KDoc gates on visibility.** Public API (library, SDK, published module) → KDoc required. `internal` / `private` → KDoc only when the *why* is non-obvious. Default off.
4. **Annotations over commentary.** Prefer `@Deprecated(message, replaceWith, level)` to a "deprecation" comment. Prefer `@Suppress("X")` paired with a one-line rationale.
5. **No `// region` folding in production code.** If a class needs region-folding to be readable, it needs splitting.
6. **Logging is not commentary.** `log.info("Order submitted")` describes a *runtime event*, not the *static* code path.

## Anti-patterns in commenting work itself

- **Bulk-deleting comments without reading them.** A few comments are load-bearing; sweep with judgement, not regex.
- **Auto-generating KDoc with IDE shortcuts.** Empty `@param` stubs are the canonical Mandated-comments smell.
- **Adding comments because review asked you to "explain" the code.** The reviewer is signalling "this code is unclear" — fix the code, not the documentation.
- **Removing a comment without checking if the code still tells the story.** Sometimes the comment was the only signal that odd-looking code was odd-on-purpose. Replace with a clearer rewrite or with a test.
