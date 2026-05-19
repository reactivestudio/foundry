---
name: spec-validate
description: "Validate spec(s)/change(s) structurally + semantically in current context. NOT for merging."
allowed-tools: Read Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/validate-structural.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/parse-spec.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/parse-delta.sh:*) Bash(test:*) Bash(ls:*) Bash(stat:*) Bash(find:*) Bash(wc:*)
---

Validate one or more `.spec/` artifacts. Structural pass via bash; semantic pass inline in the current context (no subagent delegation).

Arguments: `<id>` (capability or change name) | `--all` | `--specs` | `--changes`. Optional: `--strict` (promotes WARNINGs to ERRORs).

## Procedure

0. **Load rule reference first (MANDATORY).** `Read` these skill bodies before evaluating any file — they list every ERROR/WARNING code, severity, and how `--strict` promotes warnings:
   - `${CLAUDE_PLUGIN_ROOT}/skills/spec/validation/SKILL.md`
   - `${CLAUDE_PLUGIN_ROOT}/skills/spec/format/SKILL.md`
   - `${CLAUDE_PLUGIN_ROOT}/skills/spec/delta-format/SKILL.md`

1. **Resolve target list** based on arguments:
   - `<id>` and `test -d .spec/specs/<id>` → single canonical spec: `.spec/specs/<id>/spec.md`.
   - `<id>` and `test -d .spec/changes/<id>` → all delta specs in that change: `find .spec/changes/<id>/specs -name spec.md`.
   - `--all` → both `.spec/specs/**/spec.md` and `.spec/changes/*/specs/**/spec.md` (excluding archive).
   - `--specs` → only canonical specs.
   - `--changes` → only active deltas.

2. **Structural pass** (always). For each file, run:
   ```
   ${CLAUDE_PLUGIN_ROOT}/scripts/spec/validate-structural.sh <file> [--strict]
   ```
   Capture stderr (TSV findings) and exit code. Aggregate.

3. **Semantic pass** (in current context, no Task delegation):
   - For each delta file with a `## MODIFIED Requirements` section: Read the corresponding canonical `.spec/specs/<cap>/spec.md` and check that every MODIFIED requirement name exists in it. Missing → emit `SEMANTIC_MODIFIED_UNKNOWN` ERROR at the delta line.
   - For each delta with a `## RENAMED Requirements` section: collect FROM names; if any later entry in MODIFIED/REMOVED references a FROM name (instead of its TO), emit `SEMANTIC_RENAMED_CHAIN` ERROR.
   - When validating a change (or `--all`): `wc -c .spec/project.md` and `.spec/config.yaml` — if `project.md` > 50 KB or `config.yaml` > 50 KB, emit `CONTEXT_TOO_LARGE` WARNING.
   - When validating a change with `tasks.md`: count incomplete tasks via `tasks-progress.sh`; if archive is implied (e.g. caller pre-archive), surface `TASKS_INCOMPLETE` WARNING with current count.

4. **Aggregate verdict.**
   - Any ERROR → FAIL.
   - Under `--strict`, any WARNING → FAIL.
   - Else → PASS.

## Output format

```
## Targets
- <file or change>
...

## Findings
| severity | code | location | message |
| ERROR | DELTA_MISSING_NORMATIVE | .spec/changes/foo/specs/auth/spec.md:11 | requirement 'Dup' missing RFC 2119 keyword |
| WARNING | SPEC_PURPOSE_TOO_SHORT | .spec/specs/auth/spec.md:0 | Purpose body has 6 chars |
(or: "none")

## Counts
- errors: N
- warnings: M
- strict: yes|no

## Verdict
PASS | FAIL
```

## Important

- This command is read-only — it never edits files.
- The semantic pass is in-line, no `Task` calls. On large `--all` runs this can be slow; that's the price of the multi-agent-friendly architecture.
- `/spec-archive` calls this command internally as its pre-merge gate (with `--strict`).
