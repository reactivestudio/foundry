# ADR 0001 — Symlinks over marketplace plugins

- **Status:** Accepted
- **Date:** 2026-05-13
- **Deciders:** repo owner (solo)

## Context

Claude Code supports a "plugin marketplace" mechanism: a `marketplace.json` declares plugins, users add the marketplace URL to settings, then enable/disable plugins via `/plugin` commands. An earlier version of this repository (commit `041cadd`) used this approach with 7 plugins and 51 skills.

Alternative mechanisms for attaching configuration to projects:
1. **Marketplace plugins** — native Claude Code mechanism.
2. **CLI script + symlinks** — `claude-init` creates relative symlinks from this repo into `~/.claude/` and `<project>/.claude/`.
3. **Manual copy** — README instructions to copy files by hand.
4. **CLI script + file copy** — like (2) but copy instead of link.

## Decision

Use **CLI script + relative symlinks**.

## Rationale

| Factor | Marketplace | Symlinks (chosen) | Manual copy | CLI + copy |
|---|---|---|---|---|
| Native to Claude Code | ✓ | ✗ | ✗ | ✗ |
| Per-project component selection | weak (all-or-nothing per plugin) | strong | strong | strong |
| Updates propagate via `git pull` | yes (after `/plugin update`) | **instant** | **no** (re-copy needed) | no (re-run needed) |
| Solo-user maintenance cost | high (plugin.json per group) | low | trivial | medium |
| Reversibility | via `/plugin disable` | `rm -rf .claude/` | manual | needs uninstall logic |
| Discoverability of what's wired up | indirect (plugin list) | `ls -la .claude/` shows symlinks | unclear | unclear |

Symlinks win on the only dimension that matters daily: **a fix to `architect.md` is live in every project on the next `git pull` here, without touching any project**. Marketplace updates require a re-sync per project. Copy-based approaches require re-copy per project.

The marketplace mechanism is built for *distributing to others* (`/plugin install` from a community marketplace). It is overhead for a single-user, single-machine setup.

## Consequences

- The repo must live at a stable path on disk. Moving it breaks every linked project — but `find ~/work -lname '*claude/components*'` finds them and re-creating symlinks is mechanical.
- Mergeable configs (`.mcp.json`, `settings.json`) can't be symlinked when multiple components contribute. We use `jq` to generate them (see ADR 0003).
- Loss of the marketplace's native `/plugin` UI. We accept this — `claude-init` replaces it.

## Reconsider when

- The repo needs to be shared with other developers as an installable distribution.
- Claude Code adds first-class support for symlinked overlays (would let us drop our CLI entirely).
- The symlink approach starts producing accidents on Windows (currently not a target).
