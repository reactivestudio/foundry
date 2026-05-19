---
name: spec-archive
description: "Archive merge order RENAMED→REMOVED→MODIFIED→ADDED, date collisions, bulk, force flags. NOT for authoring deltas."
---

# spec-archive

`/spec-archive` and `/spec-sync` merge a change's deltas into the canonical specs. Archive additionally relocates the change folder into the historical archive directory with a date prefix. This skill describes the merge algorithm, edge cases, and force flags.

## When to use

- Implementing `/spec-archive` or `/spec-sync`.
- Diagnosing a merge failure or unexpected post-merge state.
- Explaining collision-resolution / bulk-archive semantics.

## Merge algorithm

For each `.spec/changes/<name>/specs/<cap>/spec.md` (delta file):

1. **Read** the delta + the canonical `.spec/specs/<cap>/spec.md`. If the canonical file doesn't exist yet, treat it as a stub with `## Purpose` and `## Requirements` and only ADDED entries from the delta can apply.

2. **RENAMED first** — for each `FROM`/`TO` pair: find the `### Requirement: <FROM>` block in canonical and rewrite the header to `### Requirement: <TO>`.

3. **REMOVED next** — for each `- ### Requirement: <Name>` entry: find that requirement block (header to next `###` or `##`) and delete it entirely.

4. **MODIFIED next** — for each `### Requirement: <Name>` block in the delta's MODIFIED section: find the same-named block in canonical and replace it **whole** (header + body + scenarios) with the delta's version.

5. **ADDED last** — append each `### Requirement: <Name>` block (with all its scenarios) to the end of the `## Requirements` section in canonical.

Write the merged file back atomically (write to tmp, `mv`).

## Edge cases

- **Multiple capabilities per change** — iterate the merge over each `changes/<name>/specs/<cap>/spec.md` independently.

- **Delta references unknown MODIFIED name** — pre-merge semantic validation catches this (`SEMANTIC_MODIFIED_UNKNOWN`). Do **not** silently treat as ADDED.

- **Concurrent changes touching the same requirement** — if change A's archive renamed/removed a requirement and change B's MODIFIED still references the old name, the archive of B fails. Resolution: edit B's delta to use the new name, then re-archive.

- **Stacking via `/spec-sync`** — sync merges into canonical without moving the change folder. Useful for mid-work checkpoints; subsequent deltas in the same change reference the updated canonical state.

- **Line-based merge, not AST** — boundaries are detected by `### Requirement: ` markers; everything between two such markers is the block (including nested `####`/`#####` headings, scenarios, code fences). Whitespace and inner formatting are preserved verbatim during MODIFIED replacements.

- **Code-fence limitation** — because the parser is line-based, a line like `### Requirement: Example` inside a triple-backtick code fence is **still treated as a real requirement header** by `parse-delta.sh`, `parse-spec.sh`, and merge logic. Do not quote `### Requirement: …` or `#### Scenario: …` inside fenced blocks within your specs or deltas; use HTML-escaped (`&#35;&#35;&#35; Requirement:`) or restructure prose. Same limitation exists in upstream openspec.

- **`/spec-sync` is not idempotent on ADDED** — running sync twice with the same deltas appends the ADDED requirement blocks **again** (no name-based dedup). Run sync once per delta state; if you need to re-sync, first remove the duplicated entries from canonical or revert via git.

- **No locking / last-writer-wins** — concurrent `/spec-apply`, `/spec-sync`, or `/spec-archive` runs on the same change are undefined; the last writer wins, the loser's edits are silently discarded. Coordinate via discipline (one operator per active change) or git worktrees.

## Relocation

After a successful merge, `/spec-archive` calls `scripts/spec/archive-relocate.sh <name>`. This moves `.spec/changes/<name>/` → `.spec/changes/archive/YYYY-MM-DD-<name>/` using today's local date.

- **Same-day collision** — if `archive/YYYY-MM-DD-<name>/` already exists, the script appends `-2`, `-3`, … up to `-999`. Beyond 999 → exit 1.

- **Cross-day re-use of name** — allowed; the date prefix differentiates.

## Force flags

| Flag | Behaviour |
|---|---|
| `-y` / `--yes` | Skip the "proceed?" confirmation prompt. |
| `--bulk <n1> <n2> ...` | Archive multiple changes atomically. Validate **all** first; if any fails, no merges happen. Then merge each in order; if any merge fails mid-way, prior merges remain (cannot roll back), but no subsequent merge proceeds — surface the partial state loudly. |
| `--skip-specs` | Skip the merge step entirely; only relocate the folder. Useful for changes that documented an investigation without altering canonical specs. |
| `--no-validate` | Run merge despite ERROR-level validation findings. Always warn loudly; reserved for recovery from inconsistent states. |

## Procedure

1. Resolve target list. If `--bulk`, all names; else single name (or infer from cwd if only one active change exists).
2. Run pre-merge validation (`spec-validation`) on each target. Abort if any ERROR (unless `--no-validate`).
3. For each target in order:
   1. If not `--skip-specs`: for each delta capability, apply the merge algorithm above. Stage to tmp file, then `mv`.
   2. Call `archive-relocate.sh <name>` to move the change folder.
   3. Report `archived: <name> → archive/<date>-<name>[-N]/`.
4. Final summary: archived names, any merges performed, any collisions resolved with `-N` suffix.

## When NOT to use

- Authoring deltas → `spec-delta-format`.
- Validation rule reference → `spec-validation`.
- Status / dependency graph → `spec-lifecycle`.
- Listing / inspection → use bash helpers directly (`list-changes.sh`).

## Anti-patterns

- Merging ADDED before MODIFIED — order matters; would duplicate names if MODIFIED renames internally.
- Skipping pre-merge validation. Always validate before touching canonical specs.
- Treating `--no-validate` as the default. It's a recovery tool, not a workflow shortcut.
- Editing canonical specs by hand mid-archive. Either complete the archive or abort it; don't half-merge.
