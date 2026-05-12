# Architecture Review — Report Template

> The structure below is the minimum. Skip a section only by explicitly noting "N/A — <reason>"; do not omit silently.

---

```markdown
# Architecture Review: <subject>

> **Reviewer**: <name / role / agent>
> **Date**: <YYYY-MM-DD>
> **Subject version**: <commit hash / RFC version / design-doc revision>

## Scope

- **In scope**: <modules / services / design docs / PRs under review>
- **Out of scope**: <what we explicitly did not look at>
- **Dominant concerns** (in order): <e.g. 1. evolvability, 2. p99 latency, 3. operational simplicity>
- **Calibration**: <prototype | small product | mid-size | regulated / large — affects severity thresholds>
- **Time budget**: <how long the review took / was given>

## Summary

<2–3 sentences. Overall shape verdict. Examples:>

- "The module boundaries are sound and the dependency direction is clean. The main risk is data ownership: two contexts both write `events.event_log`, which is the source of the recurring schema-coordination pain. Two Critical findings, four Major, eight Minor."
- "Greenfield design is in good shape on Phase-1 concerns. The biggest gap is operational readiness (Phase 5) — no rollback story, no SLOs. Recommend a follow-up pass after the runbook is drafted."

## Findings

> Group by severity, highest first. Within each severity, order by impact. Cite **evidence** (file path, line, design-doc section, runtime observation) — not adjectives.

### 🔴 Critical

> Will cause an incident, data loss, security breach, or block delivery. Fix before merge / before ship.

#### C1. <Short title — usually the smell name + location>
- **Smell**: <link to `smells.md` entry if applicable — e.g. "Hidden coupling via shared DB (smells §1.3)">
- **Evidence**: <file:line, design-doc paragraph, query result, or runtime observation>
- **Why it hurts**: <one-sentence consequence>
- **Recommendation**: <smallest change that resolves the finding — concrete next step>
- **Owner / tracking**: <issue link, owner, target sprint — fill in if known>

### 🟠 Major

> Will hurt later (perf, security, evolvability) but not block. Fix this sprint, or open a tracking issue.

#### M1. <title>
- **Smell**: …
- **Evidence**: …
- **Why it hurts**: …
- **Recommendation**: …

### 🟡 Minor

> Local risk, consistency issue, or process smell. Fix opportunistically.

#### m1. <title>
- **Evidence**: …
- **Recommendation**: …

### 💭 Suggestions

> Opinion, not finding. Useful pattern or simplification. Author's call.

- **<title>**: <observation + suggested direction>

## What's working well

> 2–4 bullets. Reviews are not just bad news — calling out what's right helps the team protect it.

- ✅ <thing 1 — be specific, e.g. "Bounded-context boundaries are enforced by ArchUnit tests in CI">
- ✅ <thing 2>

## Recommended next steps

> Optional but useful — a short prioritized action list, distinct from the per-finding recommendations.

1. <Highest-leverage action — usually addresses ≥ 1 Critical>
2. <Next — usually a Major + Minor cluster>
3. <Process / tooling improvement that prevents recurrence (e.g. add Modulith verifier)>

## Out-of-scope observations

> Things noticed that don't belong in this review but should not be forgotten. Don't expand the review here — note and move on.

- <observation — usually filed as a tracking issue or referred to another skill / review>

---

## Review meta

- **Smells walked**: §1.x, §2.x, … (which sections of `smells.md` were applied; mark "N/A — <reason>" for skipped sections)
- **Checklists walked**: §1, §2, … (which sections of `checklists.md` were applied)
- **Follow-up needed**: <e.g. "Re-review after multi-tenant change lands" / "Security deep audit via /security-review">
```

---

## Variants

### Short review (single PR, < 30 min)
Drop "Recommended next steps" and "Out-of-scope observations." Keep Scope + Summary + Findings + What's working well. Anything ≤ Minor is acceptable to bundle into one paragraph.

### Pre-merge gate
Foreground **Critical** and **Major** in the summary. Decision belongs at the top: "Merge blocked — 2 Critical" or "Merge OK — 0 Critical, 3 Major filed as tracking issues."

### Periodic system review (quarterly)
Add a section "Drift since last review" comparing against the previous report's findings: which were fixed, which deferred, which got worse. Trend is more useful than absolute state.

### RFC / design-doc review (no code yet)
The structural smells (`smells.md §1, §3, §4`) are applicable. Operational-readiness checks (`checklists.md §5`) become "what is the plan?" — note as Suggestions, not as findings.

---

## Style notes

- **Findings are about the artifact, not the author.** Replace "you forgot" with "the design does not declare." Keep it neutral.
- **Evidence beats adjectives.** "Tight coupling" is not a finding; "module A imports `b/internal/Repo.kt:42`" is.
- **Recommendations are surgical.** The smallest change that addresses the finding. If the smallest change is a rewrite, your review has slipped into redesign — stop and re-scope.
- **Severity is a gradient, not a sentiment.** Don't soften Critical to Major to be nice; don't inflate Minor to Major to seem thorough. Use the definitions in `SKILL.md`.
- **End on what works.** Always. The team can't optimize what they don't know is right.
