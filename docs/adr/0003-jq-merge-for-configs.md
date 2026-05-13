# ADR 0003 — jq-based merge for mergeable configs

- **Status:** Accepted
- **Date:** 2026-05-13
- **Deciders:** repo owner (solo)

## Context

Some Claude Code configuration files are *mergeable*: they have multiple independent contributors that must all land in a single target file. Specifically:

- `.mcp.json` — one project, many MCP servers (filesystem, git, postgres, github, …). Each server is a component.
- `settings.json` — model routing, permissions, hooks. Different concerns contribute different keys.

These files **cannot be symlinked** when more than one component contributes: only one symlink can exist at a path, so the last component wins.

Options considered:

1. **jq merge with managed marker** — components store JSON fragments. The wizard merges selected fragments into the target file via `jq` and writes a marker key (`"$managed": "claude-init"`) so future runs detect prior provenance.
2. **Native CLI commands** — for MCP use `claude mcp add postgres ...` instead of writing `.mcp.json`. For other configs use whatever native command exists.
3. **Hybrid (1 contributor → symlink, N → merge)** — single contributor case becomes a symlink; multiple contributors trigger merge.
4. **Precomposed files** — `settings.kotlin+ddd.json`, etc., committed for every combination.

## Decision

Use **jq merge with managed marker** (option 1).

## Rationale

Option 2 (native CLI) is appealing but coverage is incomplete: model routing and arbitrary settings keys have no native CLI; hooks have no native CLI; and the native commands don't give us a "delete what we installed, leave the rest" guarantee. Two semantics for uninstall is a worse user experience than one.

Option 3 (hybrid) introduces branching in `claude-init` for marginal benefit. The simple case is already simple under jq merge: it's just a one-input merge.

Option 4 (precomposed) is combinatorially infeasible.

Trade-offs:

| Factor | jq merge (chosen) | Native CLI | Hybrid | Precomposed |
|---|---|---|---|---|
| Multi-source composition | ✓ | ✓ | ✓ | ✓ (per combo) |
| Single dependency added | jq | claude CLI | jq | none |
| Uninstall removes only ours | via marker | partial | via marker | trivial |
| Combinatorial blowup | none | none | none | severe |
| Works for hooks, routing | ✓ | ✗ | ✓ | ✓ |

## Marker design

The wizard writes one extra key alongside the real config:

```json
{
  "$managed": {
    "by": "claude-init",
    "components": ["mcp/filesystem", "mcp/git", "mcp/postgres"],
    "generated_at": "2026-05-13T15:42:11Z"
  },
  "mcpServers": { ... }
}
```

Conflict detection on re-run is then a 1-key lookup. If the marker is missing, the file is user-authored and the wizard offers to back it up.

## Consequences

- The wizard requires `jq` (which is already common, often pre-installed on macOS via Homebrew).
- Components for mergeable configs are *fragments*, not full files. They follow a documented shape (e.g., MCP fragments are objects with a single `mcpServers` key).
- The marker is a JSON Schema convention, not a Claude Code feature. Claude Code itself ignores the `$managed` key. We must verify this holds across Claude Code versions.
- Backup-on-conflict logic lives in `bin/lib/jq-merge.sh`. It writes to `.claude.bak/<timestamp>/`.

## Reconsider when

- Claude Code adds first-class merge semantics for these files (overlay directories, includes).
- The marker key starts colliding with a future Claude Code feature.
- A non-JSON config file needs the same treatment (would force us to pick a per-format merger).
