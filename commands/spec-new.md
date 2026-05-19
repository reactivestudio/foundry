---
name: spec-new
description: "Create empty change scaffold at .spec/changes/<name>/. NOT for content generation."
allowed-tools: Read Write Bash(${CLAUDE_PLUGIN_ROOT}/scripts/spec/change-name-validate.sh:*) Bash(mkdir:*) Bash(test:*)
---

Create an empty scaffold for a new change at `.spec/changes/<name>/`. Does not generate content — see `/spec-propose` (one-shot) or `/spec-continue` (stepwise) for that.

Argument: `<change-name>` (required, kebab-case).

Activate skill `spec-conventions` for naming rules.

## Procedure

1. **Validate name**. `Bash`: `${CLAUDE_PLUGIN_ROOT}/scripts/spec/change-name-validate.sh <name>`. Exit non-zero → relay the diagnostic and stop.

2. **Create directories**. `Bash`: `mkdir -p .spec/changes/<name>/specs`.

3. **Write placeholders**:
   - `.spec/changes/<name>/proposal.md` — single H1 `# <Title-cased name> Proposal` + comment `<!-- Authored by /spec-propose or /spec-continue. -->`.
   - `.spec/changes/<name>/design.md` — `# <Title> Design` + the same comment.
   - `.spec/changes/<name>/tasks.md` — `# <Title> Tasks` + the same comment.
   (Title-case = first letter uppercase + spaces for hyphens.)

   **Do NOT** create any `specs/<cap>/spec.md` files; capabilities are discovered when proposal/design names them.

4. **Report**:
   ```
   /spec-new created:
   - .spec/changes/<name>/
   - .spec/changes/<name>/proposal.md (placeholder)
   - .spec/changes/<name>/design.md (placeholder)
   - .spec/changes/<name>/tasks.md (placeholder)
   - .spec/changes/<name>/specs/ (empty)

   Next: /spec-continue <name>  (or /spec-propose to regenerate with a description)
   ```

## Important

- The placeholders are intentionally minimal; the authoring commands (`/spec-propose`, `/spec-continue`, `/spec-continue`) overwrite them with real content.
- If the directory already exists, `change-name-validate.sh` fails — relay its message.
