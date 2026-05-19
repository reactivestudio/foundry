---
name: spec-continue
description: "Author the next missing artifact for an active change, in current context. NOT for one-shot generation."
allowed-tools: Read Write Glob Grep Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/status.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/validate-structural.sh:*) Bash(ls:*) AskUserQuestion
---

Generate **exactly one** missing artifact (the next in dependency order `proposal → specs → design → tasks`) for an active change, in the current assistant's context. No subagent delegation.

Argument: `<change-name>` (optional; inferred when only one active change exists).

## Procedure

0. **Load format rules first (MANDATORY).** `Read` these skill bodies before generating any artifact — they fix the exact markdown shape required by the structural validator:
   - `${CLAUDE_PLUGIN_ROOT}/skills/spec/format/SKILL.md`
   - `${CLAUDE_PLUGIN_ROOT}/skills/spec/delta-format/SKILL.md`
   - `${CLAUDE_PLUGIN_ROOT}/skills/spec/conventions/SKILL.md`
   - `${CLAUDE_PLUGIN_ROOT}/skills/spec/lifecycle/SKILL.md`
   - `${CLAUDE_PLUGIN_ROOT}/skills/spec/standards/SKILL.md`

   Sanity checks before writing: delta sections are `## ADDED Requirements` (not `## ADDED`); requirement headers are `### Requirement:` (3 `#`); scenarios are `#### Scenario:` (4 `#`); ADDED/MODIFIED bodies include `SHALL`/`MUST`/`SHOULD`/`MAY`; RENAMED uses `- FROM: \`### Requirement: ...\`` / `- TO: \`### Requirement: ...\``.

1. **Resolve change name.**
   - Supplied → use.
   - Else `Bash`: `ls .spec/changes/` (filter `archive`). One → use. Multiple → AskUserQuestion with chips. Zero → report `"no active changes; run /spec-new or /spec-propose first"`.

2. **Determine next artifact.** `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/status.sh <name>`. Parse TSV; find the first artifact in `proposal → specs → design → tasks` order with state `[ ]`.
   - All `[x]` → `"all artifacts present; run /spec-validate or /spec-apply"`.
   - Any `[-]` (blocked) → report which upstream dependency is missing and stop.

3. **Load context.** Read into current conversation:
   - `.spec/project.md`.
   - `.spec/config.yaml` (extract `rules.<target-artifact>` and `context:`).
   - `.spec/standards/*.md` (all, via `Glob`).
   - Existing artifacts in `.spec/changes/<name>/` (so the new artifact references them).
   - For `specs` step, also read `.spec/specs/<cap>/spec.md` for capabilities mentioned in `proposal.md`.

4. **Author the one artifact** in the current context. Apply `spec-format` / `spec-delta-format` rules + matching `rules.<artifact>` list. RFC 2119 keywords in spec deltas. Exactly four `#` for `#### Scenario:`.

5. **Self-check.** If the artifact is a delta spec, `Bash`: `validate-structural.sh <file> --kind delta`. Fix any ERROR before reporting.

6. **Verify.** Re-run `status.sh <name>` and confirm the target artifact moved to `[x]`.

7. **Report**:
   ```
   /spec-continue:
     change: <name>
     artifact authored: <proposal|specs|design|tasks>
     files written: <list>
     structural: PASS | n/a
     standards consulted: <list>
     next: <next missing artifact, or 'all complete — run /spec-validate'>
   ```

## Important

- One artifact per invocation. Multiple in a row = repeat the command (or use `/spec-propose` for a fresh full pass).
- Never overwrite an already-`[x]` artifact without explicit user confirmation.
- For `specs` step, the agent enumerates capabilities from `proposal.md`'s "Affected capabilities" list. If that list is missing/ambiguous → ask the user before authoring.
