#!/usr/bin/env bash
# setup.sh — idempotent scaffold of .foundry/ in the target project (cwd).
#
# Creates:
#   .foundry/changes/{backlog,in-progress,done,declined,.template}/
#   .foundry/changes/.template/{tracking.yaml,proposal.md}
#   .foundry/changes/<bucket>/.gitkeep
#
# Safe to re-run: never overwrites existing files, only creates what's missing.

set -euo pipefail

FOUNDRY_ROOT="${FOUNDRY_ROOT:-$PWD/.foundry}"

mkdir -p "$FOUNDRY_ROOT/changes/.template"
for b in backlog in-progress done declined; do
  mkdir -p "$FOUNDRY_ROOT/changes/$b"
  [[ -f "$FOUNDRY_ROOT/changes/$b/.gitkeep" ]] || : > "$FOUNDRY_ROOT/changes/$b/.gitkeep"
done

tpl_tracking="$FOUNDRY_ROOT/changes/.template/tracking.yaml"
if [[ ! -f "$tpl_tracking" ]]; then
  cat > "$tpl_tracking" <<'EOF'
slug: SLUG
title: TITLE
status: backlog
created_at: TIMESTAMP
updated_at: TIMESTAMP
EOF
fi

tpl_proposal="$FOUNDRY_ROOT/changes/.template/proposal.md"
if [[ ! -f "$tpl_proposal" ]]; then
  cat > "$tpl_proposal" <<'EOF'
# TITLE

## Problem
<one paragraph: что не так / что нужно>

## Constraints
-

## Out of scope
-

## Notes
EOF
fi

cat <<EOF
foundry scaffold ready: $FOUNDRY_ROOT

  changes/
    backlog/      — proposed but not started
    in-progress/  — active work (one at a time)
    done/         — completed (terminal)
    declined/     — abandoned (with reason)
    .template/    — tracking.yaml + proposal.md skeletons

next: /foundry:change "your first idea"
EOF
