---
name: methodology-clarifying-questions
description: "Format and pacing for clarifying questions before implementing. Use when a request has multiple plausible interpretations, undefined scope, missing acceptance criteria, unclear constraints, or unstated safety/reversibility — and a quick discovery read of configs / recent commits / docs won't resolve the ambiguity. Provides numbered multiple-choice questions with defaults and a `defaults` fast-path, so the user can confirm assumptions with one word instead of writing a paragraph."
risk: safe
source: community
---

# Ask Questions If Underspecified

## When to Use
Use this skill when a request has multiple plausible interpretations or key details (objective, scope, constraints, environment, or safety) are unclear.

## When NOT to Use

- **The request is already clear.** Don't manufacture ambiguity to look thorough.
- **A quick discovery read would answer it.** Configs, recent commits, existing patterns, docs — read first, ask only what's genuinely missing.
- **Trivial, reversible tasks.** A small two-way-door change doesn't need a clarification round; do it and confirm after.
- **The user said "use your best judgment" / "proceed with assumptions" / "just do it".** Surface the assumptions inline in the response instead — that's `karpathy-guidelines` §2 (Assumption Surfacing) territory.
- **Exploratory or research tasks** where answers will emerge from a short discovery read better than from asking.
- **The clarification is a stalling tactic.** If you find yourself asking to defer hard work, do the work instead.

## Goal

Ask the minimum set of clarifying questions needed to avoid wrong work; do not start implementing until the must-have questions are answered (or the user explicitly approves proceeding with stated assumptions).

## Workflow

### 1) Decide whether the request is underspecified

Treat a request as underspecified if after exploring how to perform the work, some or all of the following are not clear:
- Define the objective (what should change vs stay the same)
- Define "done" (acceptance criteria, examples, edge cases)
- Define scope (which files/components/users are in/out)
- Define constraints (compatibility, performance, style, deps, time)
- Identify environment (language/runtime versions, OS, build/test runner)
- Clarify safety/reversibility (data migration, rollout/rollback, risk)

If multiple plausible interpretations exist, assume it is underspecified.

### 2) Ask must-have questions first (keep it small)

Ask 1-5 questions in the first pass. Prefer questions that eliminate whole branches of work.

Make questions easy to answer:
- Optimize for scannability (short, numbered questions; avoid paragraphs)
- Offer multiple-choice options when possible
- Suggest reasonable defaults when appropriate (mark them clearly as the default/recommended choice; bold the recommended choice in the list, or if you present options in a code block, put a bold "Recommended" line immediately above the block and also tag defaults inside the block)
- Include a fast-path response (e.g., reply `defaults` to accept all recommended/default choices)
- Include a low-friction "not sure" option when helpful (e.g., "Not sure - use default")
- Separate "Need to know" from "Nice to know" if that reduces friction
- Structure options so the user can respond with compact decisions (e.g., `1b 2a 3c`); restate the chosen options in plain language to confirm

### 3) Pause before acting

Until must-have answers arrive:
- Do not run commands, edit files, or produce a detailed plan that depends on unknowns
- Do perform a clearly labeled, low-risk discovery step only if it does not commit you to a direction (e.g., inspect repo structure, read relevant config files)

If the user explicitly asks you to proceed without answers:
- State your assumptions as a short numbered list
- Ask for confirmation; proceed only after they confirm or correct them

### 4) Confirm interpretation, then proceed

Once you have answers, restate the requirements in 1-3 sentences (including key constraints and what success looks like), then start work.

## Question templates

- "Before I start, I need: (1) ..., (2) ..., (3) .... If you don't care about (2), I will assume ...."
- "Which of these should it be? A) ... B) ... C) ... (pick one)"
- "What would you consider 'done'? For example: ..."
- "Any constraints I must follow (versions, performance, style, deps)? If none, I will target the existing project defaults."
- Use numbered questions with lettered options and a clear reply format


```text
1) Scope?
a) Minimal change (default)
b) Refactor while touching the area
c) Not sure - use default
2) Compatibility target?
a) Current project defaults (default)
b) Also support older versions: <specify>
c) Not sure - use default

Reply with: defaults (or 1a 2a)
```


## Anti-patterns

- Don't ask questions you can answer with a quick, low-risk discovery read (e.g., configs, existing patterns, docs).
- Don't ask open-ended questions if a tight multiple-choice or yes/no would eliminate ambiguity faster.

## Limitations
- Don't use as a stalling tactic. Aim for one round of must-have questions and proceed once they're answered — repeated clarification loops shift work onto the user without paying off.
- A low-risk discovery read (configs, existing patterns, recent commits) usually beats asking. Save questions for genuine ambiguity.
- The `defaults` fast-path only works when the proposed defaults are good faith — if you secretly want the user to pick differently, ask outright instead of stacking the question.
