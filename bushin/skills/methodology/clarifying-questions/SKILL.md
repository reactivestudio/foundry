---
name: clarifying-questions
description: "Ask N targeted questions before coding when spec is vague/unscoped. NOT for trivial fixes."
---

# Clarifying Questions

When the request has multiple valid interpretations, undefined edge cases, or hidden assumptions — stop and ask. Code written on the wrong premise is wasted code.

## When to use

- Spec leaves an interface choice (REST vs GraphQL, sync vs async, in-memory vs persisted).
- Requirements imply edge cases the user didn't mention (empty inputs, concurrent access, large data).
- "Make X better" / "fix Y" without measurable success criteria.
- Refactor request where scope (this function vs this module vs the whole feature) is unclear.

## Procedure

1. **Read the request twice.** Identify each phrase that admits more than one reasonable interpretation.

2. **List ambiguity points internally** before asking. Don't broadcast the full list to the user — that's noise.

3. **Frame ≤5 questions.** Each one a binary or short-list choice. Avoid open-ended "what do you want?".
   - Bad: "What's your preferred approach?"
   - Good: "Sync HTTP call or async queue?"

4. **Recommend a default in each question.** Mark it `(Recommended)`. The user can accept-by-silence; you didn't shift the entire load to them.

5. **Use the right channel:**
   - In plan mode → `AskUserQuestion` (structured chips).
   - Outside plan mode → plain text questions inline.

6. **Don't proceed on assumption.** If the user dismisses questions or doesn't answer, pause, restate the assumption you're about to make, and proceed only if it's clearly low-risk.

## When NOT to use

- Trivial tasks with a single obvious interpretation (rename, format, typo fix).
- The user explicitly asked for speed ("just do it, fastest way").
- Information you can answer yourself by reading the codebase. Read first; ask only what code can't tell you.

## Anti-patterns

- Listing every ambiguity. Pick the load-bearing ones.
- Open-ended questions. Frame choices.
- Asking after you've started coding. Ask before, not mid-implementation.
- Sycophantic preamble ("Great question!"). Just ask.
