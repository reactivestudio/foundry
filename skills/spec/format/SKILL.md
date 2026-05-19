---
name: spec-format
description: "Canonical capability spec markdown: Purpose, Requirement, Scenario, RFC 2119. NOT for delta specs or validation rules."
---

# spec-format

Canonical spec lives at `.spec/specs/<capability>/spec.md`. One file per capability. Source of truth for current behaviour. AI tools read it; humans review it; archival merges write to it.

## When to use

- Writing a brand-new capability spec (no prior version exists).
- Reading a capability spec to understand current behaviour before authoring a delta.
- Reviewing a generated spec for correctness against the canonical format.
- Authoring `/spec-propose`, `/spec-new`, `/spec-continue` artifacts.

## Format

```markdown
# <Capability> Specification

## Purpose
<one paragraph, ≥ 50 non-whitespace chars; why this capability exists>

## Requirements

### Requirement: <Short imperative name>
The system SHALL <normative behaviour>. Use RFC 2119 keywords: SHALL, MUST, SHOULD, MAY.
Additional clauses can follow as separate sentences in the same paragraph.

#### Scenario: <Concrete situation>
- **GIVEN** <starting state, system or user>
- **WHEN** <event, action, or trigger>
- **THEN** <observable expected outcome>

#### Scenario: <Another case>
- **GIVEN** ...
- **WHEN** ...
- **THEN** ...

### Requirement: <Another requirement>
The system MUST ...

#### Scenario: ...
- **GIVEN** ...
- **WHEN** ...
- **THEN** ...
```

## Rules (binding)

- `## Purpose` is the first H2; body ≥ 50 non-whitespace chars.
- `## Requirements` is the second H2; everything below is requirements + scenarios.
- Each requirement: `### Requirement: <Name>` (exactly 3 `#`). Name is unique within the file.
- Each scenario: `#### Scenario: <Name>` (**exactly 4 `#`** — three or five is a parser-level ERROR).
- Each requirement has **≥ 1 scenario** (advisory WARNING if missing).
- Scenario body: bullets in order `**GIVEN**`, `**WHEN**`, `**THEN**`. Multiple `THEN`s allowed.
- Body of each requirement must include at least one RFC 2119 keyword: `SHALL`, `MUST`, `SHOULD`, `MAY` (or negative forms `SHALL NOT`, `MUST NOT`).

## Procedure (authoring)

1. Pick capability name in kebab-case (e.g. `user-auth`, `payment-processing`). One concern per capability.
2. Write `## Purpose` first — what value this capability delivers, not how. Two sentences max.
3. List requirements in roughly chronological/causal order. Each captures one user-facing behaviour or invariant.
4. For each requirement: name it with a short imperative ("Login", "Lockout after retries"), write the SHALL/MUST clause, then write at least one scenario covering the golden path.
5. Add edge-case scenarios where they materially shape implementation (timeouts, retries, concurrent access, malformed input).
6. Pass through `validate-structural.sh <file> --kind spec` (called by `/spec-validate`) before committing.

## When NOT to use

- Writing a **delta** spec inside a change folder → see `spec-delta-format`.
- Validation rules / severity reference → see `spec-validation`.
- Workflow questions (which artifact comes next, state transitions) → see `spec-lifecycle`.
- Naming / directory layout → see `spec-conventions`.

## Anti-patterns

- Scenarios written as prose, not GIVEN/WHEN/THEN bullets.
- Multiple capabilities crammed into one spec file (split by bounded concern).
- Implementation details (database tables, library names) in `## Purpose` — Purpose is about *why*, not *how*.
- Missing RFC 2119 keyword — leaves behaviour ambiguous, blocks `/spec-validate`.
- Five-hash `##### Scenario` headers — silent parser failure in upstream tooling, ERROR here.
