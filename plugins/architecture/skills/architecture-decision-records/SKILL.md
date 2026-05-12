---
name: architecture-decision-records
description: "Writing, formatting, indexing, superseding, and managing the lifecycle of ADR documents. Use ONLY when the deliverable is an ADR artifact — writing a new one, picking a template (MADR / lightweight / Y-statement / deprecation / RFC), superseding an existing decision, generating or updating an ADR index, automating with adr-tools, or reviewing an ADR draft for completeness. For making the underlying decision itself (surfacing requirements, comparing options, weighing trade-offs), use the `architecture` skill — this skill is for the artifact, not the decision."
risk: safe
source: custom
---

# Architecture Decision Records

> "An ADR is not the decision — it's the receipt. Its job is to keep the *why* alive past the moment of choosing."

The decision-making work (requirements, options, trade-offs) belongs in `architecture`. This skill is for the artifact: format, lifecycle, index, automation. A good ADR makes future engineers able to *reverse* a decision honestly, by giving them the original context to compare against.

## Use this skill when
- Writing a new ADR document for a decision that has already been made (or is close to it).
- Picking which template fits the decision shape (full MADR / lightweight / Y-statement / deprecation / RFC).
- Superseding a previous ADR — both writing the new one and marking the old as Deprecated.
- Generating or updating the ADR index (`docs/adr/README.md`).
- Setting up `adr-tools` automation in a new repository.
- Reviewing an ADR draft against a completeness checklist (status, drivers, alternatives, consequences, revisit trigger).

## Do not use this skill when
- The work is **deciding** which option to pick (requirements, options, trade-offs) → `architecture`. Come back here once the decision is converging.
- The work is **reviewing** an existing system's architecture for smells → `architect-review`.
- The change is small, local, and reversible — a two-way door doesn't need an ADR. ADRs cost time; spend the cost on one-way doors.
- There's no real decision — routine maintenance, version bumps, bug fixes. An ADR for "we upgraded a patch version" is noise.

## Pick a template

| Template | Use when | File |
|---|---|---|
| **MADR (full)** | Non-trivial decision, ≥ 2 real alternatives, one-way door, durable. | `resources/templates/madr.md` |
| **Lightweight** | Real decision but small enough that MADR is ceremony. Two-way door, ≤ 1 day to implement. | `resources/templates/lightweight.md` |
| **Y-statement** | The shape of the trade-off is the message; single paragraph form. | `resources/templates/y-statement.md` |
| **Deprecation / Supersession** | Reversing or replacing a previous ADR. Must preserve the old one's content. | `resources/templates/deprecation.md` |
| **RFC** | Proposal stage — multiple alternatives need exploration, open questions need stakeholder input *before* any ADR is final. | `resources/templates/rfc.md` |

**Default**: MADR for one-way doors, Lightweight for two-way doors. Y-statement and RFC are special-purpose. Deprecation is mandatory when reversing.

## ADR lifecycle

```
   Proposed ────► Accepted ────► Deprecated
       │                            ▲
       ▼                            │
    Rejected                   Superseded by ADR-MMMM
```

- **Proposed** — drafted, under review, not yet authoritative.
- **Accepted** — the team has agreed; implementation may proceed.
- **Rejected** — considered and explicitly not adopted. Keep the document — rejected decisions are valuable history.
- **Deprecated** — still in effect but flagged as no longer the preferred path. Often a stepping stone to Superseded.
- **Superseded by ADR-MMMM** — a newer ADR replaces this one. The pointer is bidirectional: the new ADR's status declares what it supersedes.

## Directory structure

```
docs/
└── adr/
    ├── README.md                       # Index (regenerable from filenames)
    ├── template.md                     # Team's chosen template (copy of one above)
    ├── 0001-use-postgresql.md          # Accepted
    ├── 0002-caching-strategy.md        # Accepted
    ├── 0003-mongodb-user-profiles.md   # [DEPRECATED]
    └── 0020-deprecate-mongodb.md       # Supersedes 0003
```

Filenames: `NNNN-kebab-case-title.md`. Numbers are append-only — never renumber. Status lives inside the file, not in the filename.

## Index format

```markdown
# Architecture Decision Records

This directory contains ADRs for <Project Name>.

## Index

| ADR | Title | Status | Date |
|-----|-------|--------|------|
| 0001 | Use PostgreSQL as Primary Database | Accepted | 2024-01-10 |
| 0002 | Caching Strategy with Redis | Accepted | 2024-01-12 |
| 0003 | MongoDB for User Profiles | Deprecated (→ 0020) | 2023-06-15 |
| 0020 | Deprecate MongoDB | Accepted | 2024-01-15 |

## Creating a new ADR

1. Copy `template.md` to `NNNN-title-with-dashes.md` (next free number).
2. Fill in. Status: Proposed.
3. Open PR. Reviewers per `## Deciders`.
4. On merge, status → Accepted (or Rejected). Update this index.
```

## adr-tools automation

```bash
brew install adr-tools

adr init docs/adr                              # initialise directory
adr new "Use PostgreSQL as Primary Database"   # create new ADR
adr new -s 3 "Deprecate MongoDB"               # supersede ADR-0003
adr generate toc > docs/adr/README.md          # regenerate index
adr link 2 "Complements" 1 "Is complemented by" # bidirectional link
```

## Review checklist

Before merging an ADR, all of these should be answerable:

- [ ] Context names the *forcing function* — what triggered this decision, not just background.
- [ ] At least two real alternatives are listed (including "status quo + small fix").
- [ ] Decision drivers are ranked — drivers higher up break ties.
- [ ] Consequences include both positive AND negative — no all-upside ADRs.
- [ ] Reversibility is named (one-way door vs. two-way door).
- [ ] **Revisit trigger** is present — a metric or event that would force reconsideration. Without this, the decision ossifies.
- [ ] Related ADRs are linked (supersession, complementarity).
- [ ] Status is set correctly; if Superseded or Deprecated, the forward pointer exists.

## Anti-patterns in ADRs

| Anti-pattern | Why it hurts | Fix |
|---|---|---|
| **Single-option ADR** | The "decision" is a justification dressed up; trade-offs are invisible. | List ≥ 2 real options, including a cheap status-quo fallback. |
| **Missing revisit trigger** | Decision ossifies; team forgets the conditions and treats it as eternal. | Name a metric or event ("p95 > 200ms", "team > 10", "second tenant onboarded"). |
| **All-upside consequences** | Reader can't trust an ADR that only lists benefits — the trade was real. | Be honest about cost. The cost section is the credibility section. |
| **Silent edit of an accepted ADR** | Loses history; future readers think the new content was original. | Write a new ADR, mark the old as Deprecated, cross-link. |
| **ADR for a config change** | Noise dilutes the trail; future readers stop reading the index. | If the change isn't a real decision, don't write an ADR. The rule of thumb: would you defend this decision in 18 months? |
| **No revisit on Deprecated ADRs** | Old guidance keeps showing up in search; team follows stale rules. | Mark Deprecated promptly; cross-link the superseding ADR. |
| **Templates without team conventions** | Each ADR reinvents the section structure; consistency erodes. | Pick one template, copy to `docs/adr/template.md`, stick to it. |
| **ADR after the fact** | Decisions get rationalized post-implementation; alternatives that were never considered "look weak." | Write the ADR *during* the decision, not after. Late ADRs are a smell. |

## What this skill does NOT cover

- The **decision-making process** itself — surfacing requirements, generating options, comparing trade-offs. That is `architecture`'s job. This skill helps you write the receipt; `architecture` helps you make the choice.
- **Code-level review** of the implementation that follows the ADR — `architect-review` for structural review, `clean-code` / `/review` for code-level.

## Selective reading rule

| File | When to read |
|---|---|
| `resources/templates/madr.md` | Writing a full MADR — the default for non-trivial decisions. |
| `resources/templates/lightweight.md` | Writing a short ADR for a small, two-way-door decision. |
| `resources/templates/y-statement.md` | Single-paragraph format; the trade-off shape is the message. |
| `resources/templates/deprecation.md` | Reversing or replacing a previous ADR. |
| `resources/templates/rfc.md` | Proposal stage — open questions still need stakeholder input. |

## Related skills

| Skill | This not that |
|---|---|
| `architecture` | Make the decision (surface requirements, generate options, weigh trade-offs). This skill captures the result. |
| `architect-review` | Audit an existing design / ADR set for completeness, missing seams, smells. This skill writes ADRs; that one critiques them. |
| `architecture-patterns` | Pick the layout pattern (Layered / Onion / Clean / DDD). Often the subject of an ADR; not its format. |
| `ddd-strategic-design` | Bounded-context decisions — each context boundary is a one-way door and deserves an ADR. |
