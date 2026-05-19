---
name: spec-conventions
description: "Naming (kebab-case), directory layout, task numbering for .spec/. NOT for content/format rules."
---

# spec-conventions

Naming and layout conventions for the `.spec/` subsystem. Independent of artifact content (which is covered by `spec-format` and `spec-delta-format`).

## When to use

- Validating user-supplied change names or capability names.
- Choosing a name for a new change or capability.
- Writing `tasks.md` (numbering and grouping).
- Deciding where a new file belongs inside `.spec/`.

## Directory layout

```
.spec/
├── project.md                              # project context (one paragraph + sections)
├── config.yaml                             # schema, optional context, per-artifact rules
├── standards/                              # long-lived freeform docs (no lifecycle)
│   ├── stack.md
│   ├── architecture.md
│   ├── best-practices.md
│   ├── anti-patterns.md
│   └── <custom>.md
├── specs/<capability>/spec.md              # one canonical file per capability
├── changes/<change-name>/
│   ├── proposal.md
│   ├── design.md
│   ├── tasks.md
│   └── specs/<capability>/spec.md          # one delta per touched capability
└── changes/archive/YYYY-MM-DD-<change-name>/
```

Two classes of content:

- **Source of truth (feature side)** — `.spec/specs/<cap>/spec.md`. Mutated via delta merges on `/spec-archive` and `/spec-sync`.
- **Source of truth (long-lived side)** — `.spec/standards/*.md`. Freeform, edited directly, never archived. Loaded by every context-loading command (`/spec-propose`, `/spec-continue`, `/spec-apply`). See `spec-standards`.

Everything under `changes/` (except `archive/`) is transient.

## Naming

- **Capabilities** (`specs/<capability>/`) — kebab-case, lowercase, hyphen-separated. One bounded concern per name. Examples: `user-auth`, `payment-processing`, `notification-preferences`. Avoid: `Auth`, `userAuth`, `user_auth`, `user-authentication-and-account-recovery` (too broad).

- **Change names** (`changes/<change-name>/`) — kebab-case. Imperative / descriptive. Examples: `add-dark-mode`, `fix-login-rate-limit`, `migrate-postgres-15`. Validated by `change-name-validate.sh`:
  - Must match `^[a-z][a-z0-9]*(-[a-z0-9]+)*$`.
  - Must not conflict with an existing active `.spec/changes/<name>/` (archive name re-use is allowed; date prefix differentiates).

- **Requirement names** (inside spec files) — Title Case, short imperative or noun phrase. Examples: `Login`, `Two-factor authentication`, `Lockout after retries`. Unique within a single spec file.

- **Scenario names** — concise prose, ≤ 60 chars. Examples: `Successful login`, `Token expired during refresh`, `Concurrent enrolment attempts`.

## tasks.md conventions

```markdown
# <Change title> Tasks

## Phase 1: <Theme>
- [ ] 1.1 <Concrete actionable step>
- [ ] 1.2 <Step>
  - [ ] 1.2.1 <Nested substep>
  - [ ] 1.2.2 <Substep>

## Phase 2: <Theme>
- [ ] 2.1 <Step>
- [ ] 2.2 <Step>

## Phase N: Quality gates
- [ ] N.1 Run `<test command>` — confirm green
- [ ] N.2 Run `<lint command>` — confirm clean
- [ ] N.3 Run `<typecheck command>` — confirm zero errors
```

- Top-level grouped by phase (Setup / Implementation / Integration / Testing / Documentation is a common pattern but not mandatory).
- Numbering: `<phase>.<task>[.<subtask>]`. Stable across edits; new tasks get fresh numbers, don't renumber.
- Each task is one verifiable step a person could check off after a focused work session.
- `- [ ]` = pending, `- [x]` = done (also `- [X]` accepted by `tasks-progress.sh`).

### Quality gates phase (MANDATORY)

The **final phase** of every `tasks.md` MUST be `## Quality gates` (or `## Quality checks` / `## CI gates` — name flexible, content fixed). One task per check the project actually has:

- run the test suite (Gradle: `./gradlew test`; npm: `npm test`; Cargo: `cargo test`; Go: `go test ./...`; …),
- run linters (Gradle: `./gradlew lintKotlin` / `ktlintCheck`; npm: `npm run lint`; Cargo: `cargo clippy`; Go: `golangci-lint run`; …),
- run typecheck if separate from compile (npm: `npm run typecheck` / `tsc --noEmit`; Python: `mypy`; …),
- run format check if mutating tools are present (Gradle: `./gradlew formatKotlin`; npm: `prettier --check`; …).

Detection: read `CLAUDE.md`, root build manifests (`build.gradle.kts`, `pom.xml`, `package.json`, `Cargo.toml`, `Makefile`, etc.) at authoring time and pick the commands the project actually uses. Do **not** invent commands the project doesn't have. If a project genuinely has zero of these (rare — pure docs repo), the Quality gates phase may be empty with a note `(no quality gates configured)`.

### `[x]` discipline (also documented in `/spec-apply`)

- Implementation tasks (`create`, `write`, `refactor`, `edit`) — flip `[x]` immediately after the Write/Edit action, even before tests are run. Test status is the next task's concern.
- Quality-gates tasks — flip `[x]` **only after** the actual command exits green. Failing run = stays `[ ]`, surface the failure.
- Never batch `[x]` updates at the end of a session — breaks interrupt-resume correctness and lies to the user about pace.

## Procedure (naming new artifacts)

1. Pick a candidate name in kebab-case.
2. For a change: run `scripts/spec/change-name-validate.sh <name>`. Fix until it returns `valid`.
3. For a capability: check `.spec/specs/<name>/` doesn't exist; if it does, decide whether you want to extend the existing capability or have a genuinely new one.
4. For a requirement: read the existing canonical spec; ensure the name isn't already taken in that file.

## When NOT to use

- Format / content rules of specs → `spec-format`, `spec-delta-format`.
- Validation severity → `spec-validation`.
- Lifecycle / status → `spec-lifecycle`.

## Anti-patterns

- Multiple capabilities under one `specs/<name>/spec.md` — split.
- A "fix-things" or "misc" change name — too vague to be useful in history.
- Renumbering existing `tasks.md` items when inserting new ones — breaks links and git blame.
- Re-using a capability name with a different scope ("user-auth" once meaning login, later meaning account recovery) — pick a new capability instead.
