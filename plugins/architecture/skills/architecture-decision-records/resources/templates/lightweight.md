# Lightweight ADR Template

Use when the decision is real but small enough that the full MADR template (`madr.md`) is overkill. Roughly: ≤ 2 alternatives considered, ≤ 1 day to implement, two-way door.

A lightweight ADR is still better than no ADR — it preserves the *why*, which is the part that rots first.

```markdown
# ADR-NNNN: <Short decision-shaped title>

**Status**: Accepted
**Date**: YYYY-MM-DD
**Deciders**: @alice, @bob

## Context

<2-4 sentences. What problem? Why now? What changed?>

## Decision

<1-3 sentences. What we chose, stated concretely. Names of libraries, files, conventions —
not abstract directions.>

## Consequences

**Good**: <One sentence or short list of what this buys.>

**Bad**: <One sentence or short list of what this costs.>

**Mitigations**: <If costs are non-trivial, what we'll do about them. Otherwise omit.>
```

## Worked example

```markdown
# ADR-0012: Adopt Spring Modulith for Bounded Contexts

**Status**: Accepted
**Date**: 2024-01-15
**Deciders**: @alice, @bob, @charlie

## Context

Our Spring Boot monolith has grown to 20+ packages with implicit dependencies between
domain areas. Cross-domain calls bypass intended boundaries, and we have no compile-time
enforcement of the module graph. Refactors leak across "modules" unpredictably.

## Decision

Adopt Spring Modulith. Define each bounded context as a top-level package under
`com.example.<context>`, communicate across contexts via `ApplicationEvent`s and a small
public `contract` package only. Add Modulith verification tests to CI.

## Consequences

**Good**: Compile-time and test-time enforcement of module boundaries, explicit event
flow, low-cost path to extracting services later.

**Bad**: Learning curve for the team, some boilerplate for events, refactor needed to
legalize current cross-package calls.

**Mitigations**: Pilot one context first, document the `contract` rules, add
`ApplicationModuleTest` to CI before opening Modulith adoption to other contexts.
```

## When NOT to use this template

- The decision is a one-way door (data migration, public contract, persistence engine swap) — use `madr.md`.
- There are > 2 viable alternatives that need real comparison — use `madr.md`.
- The decision needs sign-off from people outside the engineering team — use `madr.md` for the audit trail.
