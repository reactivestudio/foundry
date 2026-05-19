---
name: spec-propose
description: "Core entry: create change + author all four artifacts from a description, in current context. NOT for empty scaffolds."
allowed-tools: Read Write Glob Grep Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/change-name-validate.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/validate-structural.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/status.sh:*) Bash(mkdir:*) Bash(test:*) Bash(ls:*) AskUserQuestion
---

Create a change folder and author all four artifacts (`proposal.md`, `specs/<cap>/spec.md` deltas, `design.md`, `tasks.md`) in **the current Claude context** — no subagent delegation. The current assistant does the writing so the user can chain follow-up agents or take over directly.

Argument: `<description>` (required, sentence or short paragraph).

Activate skills `spec-format`, `spec-delta-format`, `spec-lifecycle`, `spec-conventions`, `spec-standards`, `spec-validation` while running.

## Procedure

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
   - `tasks.md` — phases (typical: Setup / Implementation / Integration / Testing / Documentation), numbered tasks (`- [ ] 1.1 …`), one focused work session per task.

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
