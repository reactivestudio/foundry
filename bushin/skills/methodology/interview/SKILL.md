---
name: interview
description: "Adversarial Q&A to stress-test plan/design, one question at a time. NOT for shipping code."
---

# Interview

Interrogate the user about a plan or design until you reach shared understanding. Walk down each branch of the decision tree, resolving dependencies one-by-one. The goal is to find weak assumptions before they become weak code.

_Adapted from Matt Pocock's [`grill-me`](https://github.com/mattpocock/skills/blob/main/skills/productivity/grill-me/SKILL.md) skill._

## When to use

- User says "grill me", "interview me", "stress-test this plan", "challenge my design".
- Plan mode in progress and you sense unresolved tradeoffs the user hasn't named.
- Design review on a fresh spec — before any code is written.

## Procedure

1. **One question at a time.** Never batch multiple questions in one turn. Wait for each answer before moving on.

2. **Walk the tree.** Each answer opens new branches. Map dependencies: don't ask leaf questions while the root is unresolved.

3. **Recommend an answer.** For every question, propose what you'd choose and why. The user agrees, refines, or rejects — but never sees a Socratic vacuum.

4. **Codebase before user.** If the answer is discoverable by reading code/docs, read first and report findings instead of asking.

5. **Hold the line on weak answers.** If the user gives "I don't know" or "doesn't matter", flag the open branch, document the assumption, move on.

6. **Stop when the tree is fully resolved.** Summarize the decisions and dependencies; hand off to the next phase (plan-writing, code).

## When NOT to use

- Shipping production code. This is a pre-implementation skill.
- Trivial tasks where there's no real decision tree.
- User has explicitly committed to a direction and just wants execution.
