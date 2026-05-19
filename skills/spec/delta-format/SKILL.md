---
name: spec-delta-format
description: "Delta spec sections: ADDED/MODIFIED/REMOVED/RENAMED, FROM/TO format, merge order. NOT for canonical specs."
---

# spec-delta-format

Delta specs live in `.spec/changes/<change>/specs/<capability>/spec.md`. They express **changes** to a canonical spec, not the full spec. On archive/sync, deltas are merged into the canonical `.spec/specs/<capability>/spec.md`.

## When to use

- Authoring change deltas inside `/spec-propose`, `/spec-new`, `/spec-continue`.
- Reading deltas before `/spec-archive` or `/spec-sync` to plan the merge.
- Validating deltas via `/spec-validate`.

## Sections

Four section types. **At least one** must appear per delta file. A given requirement name **may not appear in more than one section**.

```markdown
## ADDED Requirements

### Requirement: <New name>
The system SHALL <normative clause — RFC 2119 required>.

#### Scenario: <name>
- **GIVEN** ...
- **WHEN** ...
- **THEN** ...

## MODIFIED Requirements

### Requirement: <Exact existing name in main spec>
<full replacement body — this REPLACES the entire requirement, not a partial diff>

#### Scenario: <name>
- **GIVEN** ...
- **WHEN** ...
- **THEN** ...

## REMOVED Requirements

- ### Requirement: <Name to remove>
- ### Requirement: <Another to remove>

## RENAMED Requirements

- FROM: `### Requirement: <Old name>`
- TO: `### Requirement: <New name>`

- FROM: `### Requirement: <Another old>`
- TO: `### Requirement: <Another new>`
```

## Merge order (enforced)

When `/spec-archive` or `/spec-sync` merges deltas into the canonical spec:

1. **RENAMED** — rename in place. Subsequent operations refer to the **new** name.
2. **REMOVED** — delete the named requirement blocks.
3. **MODIFIED** — replace requirement body (matched by name).
4. **ADDED** — append new requirement blocks at the end of `## Requirements`.

Within a single delta file, if a requirement is RENAMED, any MODIFIED entry that targets it must use the **new** name.

## Rules (binding)

- At least one of the four sections per file.
- ADDED / MODIFIED requirement bodies must include `SHALL` / `MUST` / `SHOULD` / `MAY`.
- MODIFIED includes the **full** new requirement body (header + clauses + scenarios). No partial diffs.
- REMOVED entries are dash-prefixed: `- ### Requirement: <Name>`.
- RENAMED entries are exactly:
  - `- FROM: \`### Requirement: <Old>\``
  - `- TO: \`### Requirement: <New>\``
- No name appears in two sections of the same file (e.g. ADDED + MODIFIED → ERROR).
- Empty section header without entries → WARNING.

## Procedure (authoring)

1. Read the current canonical spec (`.spec/specs/<cap>/spec.md`).
2. Decide which operations describe the change: new requirements → ADDED, behaviour changes → MODIFIED, deprecations → REMOVED, name fixes → RENAMED.
3. For MODIFIED, copy the existing requirement header **exactly** (or, if also RENAMED, the new header).
4. For each ADDED / MODIFIED requirement, include at least one scenario and one RFC 2119 keyword.
5. Run `/spec-validate <change>` — the structural pass catches almost all formatting issues.

## When NOT to use

- Authoring the canonical spec itself → `spec-format`.
- Writing the proposal / design / tasks markdown → `spec-lifecycle` + the agent.
- Decoding merge / archive operations end-to-end → `spec-archive`.

## Anti-patterns

- Partial MODIFIED bodies — confuse merge; always write the full replacement.
- MODIFIED referring to a name that was RENAMED earlier in the same file (must reference the new name).
- Cross-section duplication — most often appears when ADDED + MODIFIED are confused; the requirement is either new (ADDED) or pre-existing (MODIFIED).
- RENAMED without backticks around `### Requirement: <Name>` — fails the strict format check.
