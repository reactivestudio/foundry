#!/usr/bin/env bash
# Usage: roadmap-set-task-state.sh <roadmap-path> <id> <new-state>
# Atomically rewrites the **State:** field of one task inside roadmap.md.
# Valid states: pending | in-progress | done | blocked | rejected
# Output: <new-state> on stdout.
# Exit 0 ok; 1 task not found; 2 bad args; 3 invalid state / file missing.

set -eu

roadmap=${1:-}
id=${2:-}
new_state=${3:-}

if [ -z "$roadmap" ] || [ -z "$id" ] || [ -z "$new_state" ]; then
  echo "roadmap-set-task-state: missing args (need <roadmap-path> <id> <new-state>)" >&2
  exit 2
fi
if [ ! -f "$roadmap" ]; then
  echo "roadmap-set-task-state: file not found at $roadmap" >&2
  exit 3
fi

valid_states="pending in-progress done blocked rejected"
if ! printf ' %s ' "$valid_states" | grep -q " $new_state "; then
  echo "roadmap-set-task-state: '$new_state' is not a valid task state (one of: $valid_states)" >&2
  exit 3
fi

tmp=$(mktemp "${TMPDIR:-/tmp}/roadmap-set-task-state.XXXXXX")
awk -v want="$id" -v val="$new_state" '
  BEGIN { in_task = 0; replaced = 0 }
  /^## [A-Za-z]?[0-9]+(\.[0-9]+)*\. / {
    # Extract this block'\''s ID.
    s = substr($0, 4)
    pos = index(s, ". ")
    cur_id = substr(s, 1, pos - 1)
    in_task = (cur_id == want) ? 1 : 0
    print; next
  }
  /^## / { in_task = 0; print; next }
  /^# /  { in_task = 0; print; next }
  in_task && /^- \*\*State:\*\*/ {
    print "- **State:** " val
    replaced = 1
    next
  }
  { print }
  END { if (!replaced) exit 1 }
' "$roadmap" > "$tmp" || {
  rm -f "$tmp"
  echo "roadmap-set-task-state: task '$id' not found in $roadmap" >&2
  exit 1
}

mv "$tmp" "$roadmap"
echo "$new_state"
