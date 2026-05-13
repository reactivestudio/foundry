# Wizard Flow (`claude-init`)

This document is the *spec* for the project wizard. The implementation in `bin/claude-init` must follow this flow exactly.

## Invocation

```
$ /path/to/claude/bin/claude-init [--dry-run] [--reconfigure]
```

- No arguments: standard interactive run from current working directory.
- `--dry-run`: print all actions without writing.
- `--reconfigure`: skip detection step, ask every question even if defaults are obvious.

The wizard's CWD must be the **project root** (the directory that will contain `.claude/` and `.mcp.json`). The wizard does not change directories.

## Steps

### 1. Banner and target detection

```
claude-init — Personal Claude Code configuration wizard
Target: /Volumes/Work/www/VL/some-project

→ Detecting stack...
  ✓ build.gradle.kts found → Kotlin (Gradle)
  ✓ org.springframework.boot in build.gradle.kts → Spring Boot
```

Detection rules:
- `build.gradle.kts` or `build.gradle` → Kotlin/JVM.
- `pom.xml` → Maven JVM project.
- `org.springframework.boot` substring in build file → Spring Boot.
- `.gitignore` absent → warn (project should be a git repo).

Detection results pre-fill answers; user can override.

### 2. Stack questions

```
? Stack: Kotlin? [Y/n]
? Framework: Spring Boot? [Y/n]
? Architecture: DDD patterns? [y/N]
? Heavy testing focus? [Y/n]
? Project type: [1=microservice / 2=library / 3=cli] (default: 1)
```

Answers are stored in shell variables; nothing is written yet.

### 3. Component selection

Based on answers, the wizard pre-selects components but lets the user toggle. Format: bracketed checkboxes, space to toggle, enter to confirm.

```
? Select agents to enable:
  [x] code-reviewer           (always recommended)
  [x] troubleshooter          (always recommended)
  [x] spring-boot-specialist  (because Spring Boot = yes)
  [x] ddd-modeler             (because DDD = yes)
  [ ] kotlin-specialist       (skip; covered by spring-boot-specialist)
  [ ] security-reviewer
  [ ] test-strategist         (because heavy testing = yes — recommended)
```

```
? Select project commands:
  [x] /review
  [x] /scaffold-service
  [x] /scaffold-endpoint
  [ ] /scaffold-aggregate     (because DDD = yes — recommended)
  [x] /test-gap
  [ ] /trace
```

```
? Select rules:
  [x] kotlin-idioms
  [x] spring-boot-conventions
  [x] ddd-boundaries
  [x] testing-discipline
  [ ] security-baseline
  [ ] core-engineering        (use global CLAUDE.md instead)
```

```
? Select MCP servers:
  [x] filesystem
  [x] git
  [ ] postgres
  [ ] github
  [ ] context7
```

### 4. Conflict detection

If `.claude/` exists with non-symlink content, or `.mcp.json` exists with non-managed content:

```
! Existing .claude/agents/code-reviewer.md is not a symlink.
! Existing .mcp.json was not created by claude-init.

Choose:
  1) Backup existing files to .claude.bak/ and proceed
  2) Skip conflicting files
  3) Abort
```

### 5. Execution

The wizard creates `.claude/{agents,commands,rules}` as needed, then:

For each selected symlinkable component:
```
ln -s ../../../<repo>/components/agents/code-reviewer.md .claude/agents/code-reviewer.md
```

Relative paths are computed from project root to repo. If the repo is at `/Users/me/code/claude` and the project is at `/Users/me/work/proj`, the symlink target is `../../code/claude/components/agents/code-reviewer.md` (resolved via `realpath --relative-to`).

For mergeable configs (Phase 6):
```
jq -s 'reduce .[] as $f ({}; .mcpServers += $f.mcpServers)' \
   components/mcp/filesystem.json components/mcp/git.json \
   > .mcp.json
```

A managed marker is written into `.mcp.json` so future runs can detect it.

### 6. Summary

```
Done. Created:
  4 agents, 4 commands, 4 rules, 2 MCP servers.

Re-run with --reconfigure to change the selection.
Update components: git -C /path/to/claude pull
```

If `.claude/` is not in project `.gitignore`:
```
Note: .claude/ is not in .gitignore. Add it if you don't want to commit configs.
```

## Idempotency

Running the wizard twice with the same answers must produce the same state, no warnings, no duplicate work. Symlinks already pointing to the correct target are silently kept.

## Reversibility

There is no `claude-init --uninstall`. To remove: `rm -rf .claude/ .mcp.json` from the project root. Symlinks have no side effects on the repo.

## Out of scope

- No locking. If two `claude-init` runs race in the same directory, last writer wins.
- No partial updates ("just update agents, leave commands"). Re-run the full wizard.
- No interactive editing of frontmatter or content from the wizard. Edit component files in the repo.
