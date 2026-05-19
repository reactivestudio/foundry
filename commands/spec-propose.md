---
name: spec-propose
description: "Core entry: create change + author all four artifacts from a description, in current context. NOT for empty scaffolds."
allowed-tools: Read Write Glob Grep Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/change-name-validate.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/validate-structural.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/status.sh:*) Bash(mkdir:*) Bash(test:*) Bash(ls:*) AskUserQuestion
---

Create a change folder and author all four artifacts (`proposal.md`, `specs/<cap>/spec.md` deltas, `design.md`, `tasks.md`) in **the current Claude context** — no subagent delegation. The current assistant does the writing so the user can chain follow-up agents or take over directly.

Argument: `<description>` (required, sentence or short paragraph).

## Procedure

0. **Load format rules first (MANDATORY).** Before any other step, `Read` these skill bodies into the current context — they encode the exact markdown shape the generated artifacts MUST take. Without this step Claude will guess the delta format wrong and the structural validator will reject your output:
   - `${CLAUDE_PLUGIN_ROOT}/skills/spec/format/SKILL.md`
   - `${CLAUDE_PLUGIN_ROOT}/skills/spec/delta-format/SKILL.md`
   - `${CLAUDE_PLUGIN_ROOT}/skills/spec/conventions/SKILL.md`
   - `${CLAUDE_PLUGIN_ROOT}/skills/spec/lifecycle/SKILL.md`
   - `${CLAUDE_PLUGIN_ROOT}/skills/spec/standards/SKILL.md`

   Hard rules to internalise from these reads (sanity check before writing):
   - Delta sections are exactly `## ADDED Requirements`, `## MODIFIED Requirements`, `## REMOVED Requirements`, `## RENAMED Requirements` (each section header includes the word "Requirements").
   - Requirement header is `### Requirement: <Name>` — **exactly three** `#` characters.
   - Scenario header is `#### Scenario: <Name>` — **exactly four** `#` characters.
   - ADDED / MODIFIED bodies MUST contain `SHALL` / `MUST` / `SHOULD` / `MAY`.
   - RENAMED entries are `- FROM: \`### Requirement: <Old>\`` and `- TO: \`### Requirement: <New>\``.

1. **Derive change name.** Convert `<description>` to kebab-case (lowercase letters/digits/hyphens; start with a letter). Examples: `"Add dark mode"` → `add-dark-mode`. If the derived name is awkward, AskUserQuestion offering 2–3 alternatives.

2. **Validate name.** `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change-name-validate.sh <name>`. On failure relay the diagnostic and stop.

3. **Create scaffold.** `Bash`: `mkdir -p .spec/changes/<name>/specs`.

4. **Load context.** Read in this order, all into the current conversation:
   - `.spec/project.md` (project context).
   - `.spec/config.yaml` (extract `context:` and `rules.proposal/.spec/.design/.tasks`).
   - **Every** file under `.spec/standards/*.md` (long-lived constraints — stack, architecture, anti-patterns, etc.). Use `Glob` to enumerate.
   - For each capability the description plausibly touches, the canonical `.spec/specs/<cap>/spec.md` if it exists.

5. **Author four artifacts** in this order, in the current context — no `Task` calls. Each artifact must respect: (a) project context, (b) standards/, (c) the matching `rules.<artifact>` list from `config.yaml`.

   - `proposal.md` — sections: **Problem**, **Proposed solution**, **Affected capabilities** (list of capability names), **Non-goals**. Cite which standards rules constrained design choices.
   - For each affected capability, `specs/<cap>/spec.md` — **delta** spec using ADDED / MODIFIED / REMOVED / RENAMED sections per `spec-delta-format` skill. RFC 2119 keyword (`SHALL`/`MUST`/`SHOULD`/`MAY`) in every ADDED/MODIFIED body. `#### Scenario:` with exactly four `#`.
   - `design.md` — sections: **Architecture**, **Technical approach**, **Key decisions** (cite trade-offs), **Risks**, **Testing strategy**. Skip sections that aren't load-bearing for this change.
   - `tasks.md` — phases (typical: Setup / Implementation / Integration / Testing / Documentation), numbered tasks (`- [ ] 1.1 …`), one focused work session per task. **MUST include a final `## Quality gates` phase** with explicit task per applicable check. Detect commands from `CLAUDE.md`, build files (`build.gradle.kts`, `pom.xml`, `package.json`, `Makefile`, `Cargo.toml`, etc.); only include checks the project actually has:
     - `- [ ] N.1 Run \`<test command>\` — confirm green` (Gradle: `./gradlew test`; npm: `npm test`; Cargo: `cargo test`; …).
     - `- [ ] N.2 Run \`<lint command>\` — confirm clean` (Gradle: `./gradlew lintKotlin` / `ktlintCheck`; npm: `npm run lint`; …).
     - `- [ ] N.3 Run \`<typecheck command>\` — confirm zero errors` (Gradle: `./gradlew compileKotlin` if separate; npm: `npm run typecheck` / `tsc --noEmit`; …).
     - `- [ ] N.4 Run \`<format command>\` if mutating — confirm idempotent` (optional; Gradle: `./gradlew formatKotlin`).
     If a project has no detectable command for a check, omit that line — do NOT invent commands. These quality-gate tasks are flipped to `[x]` by `/spec-apply` only after the actual command exits green.

6. **Self-check structurally.** For each `specs/<cap>/spec.md` you wrote, `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/validate-structural.sh <file> --kind delta`. On any ERROR, fix the file and re-validate before the report.

7. **Verify all four artifacts present.** `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/status.sh <name>` — expect all `[x]`. Any `[ ]` or `[-]` means a self-check failed; fix and re-run.

8. **Report**:
   ```
   /spec-propose:
     change: <name>
     description: "<one-line summary>"
     capabilities touched: <list>
     artifacts: proposal.md, specs/<cap>/spec.md × N, design.md, tasks.md
     structural: PASS
     standards consulted: <list of .spec/standards/*.md you loaded>
     next: /spec-validate <name> --strict  →  /spec-apply <name>  →  /spec-archive <name> -y
   ```

## Important

- **No `Task` calls.** Everything in the current assistant's context. The user composes follow-up (delegate to `code-implementor`, run `architect`, open worktrees, etc.).
- `.spec/standards/*.md` are mandatory reads — they encode permanent project constraints. Skipping them produces specs that violate the project's worldview.
- If `.spec/` does not exist, abort with: `"run /setup to scaffold .spec/ first"`.
- The agent may surface ambiguities in a final "Open questions" section — relay them, do not invent answers.
