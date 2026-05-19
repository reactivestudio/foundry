---
name: spec-list
description: "List active changes / specs / standards / archive (flag-gated). NOT for showing a single item — use /spec-show."
allowed-tools: Read Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/list-changes.sh:*) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/list-specs.sh:*) Bash(ls:*) Bash(wc:*) Bash(find:*)
---

List items inside `.spec/`. Four modes:
- Default — active changes with task progress.
- `--specs` — canonical capability specs with requirement counts.
- `--standards` — long-lived documents in `.spec/standards/`.
- `--archive` — archived changes (newest first).

Accepted args: `--specs`, `--standards`, `--archive`, `--sort recent|name`.

## Procedure

1. Parse args. Default sort: `recent` (for `--archive`) or no sort for `--standards`/`--specs`.

2. Dispatch:
   - `--specs` → `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/list-specs.sh`.
   - `--archive` → `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/list-changes.sh --archive --sort <sort>`.
   - `--standards` → `Bash`: `ls .spec/standards/*.md 2>/dev/null` (or `find .spec/standards -maxdepth 1 -name '*.md'`). For each file, get size via `wc -c`.
   - Default → `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/list-changes.sh --sort <sort>`.

3. Render markdown.

## Output formats

**Changes (default / `--archive`)**:

```
| change | tasks | last modified | path |
|---|---|---|---|
| add-dark-mode | 5/7 | 2026-05-18 | .spec/changes/add-dark-mode/ |
```

**Specs (`--specs`)**:

```
| capability | requirements | path |
|---|---|---|
| user-auth | 8 | .spec/specs/user-auth/spec.md |
```

**Standards (`--standards`)**:

```
| document | size | path |
|---|---|---|
| stack.md | 1.2 KB | .spec/standards/stack.md |
| anti-patterns.md | 540 B | .spec/standards/anti-patterns.md |
```

If the queried directory is empty → report `"no <items> found"`.

## Important

- For `--archive`, convert epoch mtimes from `list-changes.sh` to `YYYY-MM-DD`.
- `--standards` filters to top-level `*.md` (no recursion). README.md (the scaffold one-pager) is included unless the user has deleted it.
- Combining flags (e.g. `--specs --archive`) is not supported; pick one mode.
