# Per-Project Disable

Claude Code supports per-project plugin enable/disable natively. This document captures the operational details for `bushin-skills`.

## When to disable in a project

- The project's stack is far from Kotlin/Spring (e.g. a Rust microservice, a static site).
- You want a minimal-overhead session and the plugin's ~2.6k token idle cost is noticeable.
- You are testing whether a behaviour comes from this plugin or from elsewhere.

## How to disable

### Option 1 — `/plugin disable` from inside the project

```
cd ~/work/some-non-kotlin-project
claude code
> /plugin disable bushin-skills@reactivestudio
```

Claude Code writes the disable flag into the project's settings. Re-enable with `/plugin enable bushin-skills@reactivestudio`.

### Option 2 — edit `<project>/.claude/settings.json`

The exact key name is to be **verified during Phase 1 implementation** (Claude Code's schema has evolved). The expected form is one of:

```json
{ "disabledPlugins": ["bushin-skills@reactivestudio"] }
```
or
```json
{ "plugins": { "bushin-skills@reactivestudio": { "enabled": false } } }
```

This file lives in the project repo; commit it if the disable should apply to the whole team, otherwise put it in `<project>/.claude/settings.local.json` (gitignored).

## Inverse: enable only in projects that need it

The default is "plugin globally installed and active everywhere". If instead you want to **default off** and opt-in per-project, edit `~/.claude/settings.json`:

```json
{ "disabledPlugins": ["bushin-skills@reactivestudio"] }
```

Then in each project where you want it active, add an `enabledPlugins` override in `<project>/.claude/settings.json`. This is less common — the plugin is sized to be useful in most JVM-style projects.

## What persists when disabled

- `~/.claude/CLAUDE.md` — unaffected. It is a user-level file copied by `/setup-global-settings`, not auto-managed by the plugin.
- `~/.claude/settings.json` — unaffected. Same.
- The plugin's `agents/`, `commands/`, `skills/`, `hooks/` — **not active** in this project. They re-appear if the plugin is re-enabled.

## Cost of toggling

Free. The disable is purely declarative; no files move, no copies happen. The next `claude code` session in that project ignores the plugin.

## Phase 1 verification action

When `/plugin install` is first verified, confirm:

1. The exact JSON key name Claude Code uses (`disabledPlugins` vs `plugins[].enabled` vs other).
2. Whether the disable is per-user or per-project by default.
3. Update this document with the verified key.
