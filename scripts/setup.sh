#!/usr/bin/env bash
# setup.sh — idempotent scaffold of .foundry/ in the target project (cwd).
#
# Creates:
#   .foundry/changes/{backlog,in-progress,done,declined}/.gitkeep
#   .foundry/changes/.template/{tracking.yaml,proposal.md}
#
# Templates are copied from the plugin's source-of-truth at
# ${CLAUDE_PLUGIN_ROOT}/.template/. User may edit the target copy to
# customize per-project; subsequent setup runs do NOT overwrite.
#
# Safe to re-run.

set -euo pipefail

FOUNDRY_ROOT="${FOUNDRY_ROOT:-$PWD/.foundry}"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SRC_TEMPLATE="$PLUGIN_ROOT/.template"

if [[ ! -d "$SRC_TEMPLATE" ]]; then
  echo "no template source at $SRC_TEMPLATE" >&2
  echo "(set CLAUDE_PLUGIN_ROOT or run from inside the plugin)" >&2
  exit 2
fi

# bucket dirs with .gitkeep
for b in backlog in-progress done declined; do
  mkdir -p "$FOUNDRY_ROOT/changes/$b"
  [[ -f "$FOUNDRY_ROOT/changes/$b/.gitkeep" ]] || : > "$FOUNDRY_ROOT/changes/$b/.gitkeep"
done

# .template dir — copy each file only if missing (idempotent, user-editable)
mkdir -p "$FOUNDRY_ROOT/changes/.template"
for src in "$SRC_TEMPLATE"/*; do
  name=$(basename "$src")
  dst="$FOUNDRY_ROOT/changes/.template/$name"
  [[ -f "$dst" ]] || cp "$src" "$dst"
done

cat <<EOF
foundry scaffold ready: $FOUNDRY_ROOT

  changes/
    backlog/      — proposed but not started
    in-progress/  — active work (one at a time)
    done/         — completed (terminal)
    declined/     — abandoned (with reason)
    .template/    — tracking.yaml + proposal.md (edit to customize)

next: /foundry:change "your first idea"
EOF
