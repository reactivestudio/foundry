---
name: spec-naming
description: Naming, layout, slug rules for foundry changes. Use when generating a slug from a title, naming a stage artifact, or creating any file under .foundry/.
---

# Conventions

## Slug

A slug uniquely names a change inside `.foundry/changes/<bucket>/`. It is the directory name and the `slug:` field in `tracking.yaml`.

**Rules** (enforced by `change.sh new`):

- Regex: `^[a-z0-9]+(-[a-z0-9]+)*$`
- Length: 1–60 chars (target ≤40 for readability)
- ASCII only — no Cyrillic, no underscores, no dots
- Globally unique across all four buckets

**Generation guideline** (when a command generates from a title):

- Pick **semantic content**, not first-N words. `"Rate limiting for /api/orders"` → `add-rate-limiting`, not `rate-limiting-for-api-orders`.
- Prefix with the **verb of intent** when natural: `add-`, `fix-`, `refactor-`, `remove-`, `migrate-`, `extract-`. Helps scan a bucket.
- Drop articles, prepositions, file-extension noise.
- Three to five words usually hits the sweet spot.

**Examples:**

| Title | Good slug | Bad slug |
|---|---|---|
| Rate limiting for /api/orders | `add-rate-limiting` | `rate-limiting-for-api-orders` |
| Fix flaky kafka consumer test | `fix-flaky-kafka-test` | `fix-flaky-kafka-consumer-test-issue` |
| Migrate auth from JWT to OAuth2 | `migrate-auth-to-oauth2` | `migrate-from-jwt-to-oauth-two` |
| Remove dead PaymentService stub | `remove-paymentservice-stub` | `payment_service_dead_code` |

## Title

- Free text, single line, ≤120 chars
- Imperative form when natural ("Rate limiting for X", "Fix flaky Y")
- Not used by tooling for routing — slugs are the keys

## File layout inside a change directory

```
.foundry/changes/<bucket>/<slug>/
  tracking.yaml      — flat YAML state (always present)
  history.log        — TSV append-only event log (always present)
  proposal.md        — user-authored framing (created on `change new`)
  questions.md       — Phase 3+ stage artifact
  research.md        — Phase 3+
  design.md          — Phase 4+
  …                  — further stage artifacts accrue here
```

Phase 1 only guarantees `tracking.yaml`, `history.log`, `proposal.md`.

## Artifact naming

Use **noun** filenames for artifacts: `proposal.md`, `research.md`, `design.md`. Avoid verb forms (`propose.md`, `research`, `design`) — they mix tense with file purpose and don't sort as well.

Avoid the word **"spec"** in artifact filenames ([NO-VIBES §8](../../../roadmap/NO-VIBES.md) — semantically diffused). Use the CRISPY-canon names (`questions`, `research`, `design`, `structure`, `plan`, `implement`, `verify`) instead.

## Foundry root vs target project

- **Plugin code** lives under `${CLAUDE_PLUGIN_ROOT}/` (scripts, skills, commands)
- **Change state** lives under `<target-project>/.foundry/changes/`
- `FOUNDRY_ROOT` env var can override the default `$PWD/.foundry` location (useful for tests)
