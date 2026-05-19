#!/usr/bin/env bash
# Usage: tasks-progress.sh <tasks.md>
# Output: "<done>/<total>" on stdout (e.g. "3/7"). Empty input -> "0/0".
# Counts only top-level "- [x]" / "- [X]" / "- [ ]" lines (and nested ones too — any line matching the pattern).
# Exit 0 on success; 2 on bad usage.

set -eu

file=${1:-}
if [ -z "$file" ]; then
  echo "tasks-progress: missing file argument" >&2
  exit 2
fi
if [ ! -f "$file" ]; then
  echo "0/0"
  exit 0
fi

done_count=$(grep -cE '^[[:space:]]*[-*][[:space:]]+\[[xX]\]' "$file" || true)
total_count=$(grep -cE '^[[:space:]]*[-*][[:space:]]+\[[[:space:]xX]\]' "$file" || true)
echo "${done_count:-0}/${total_count:-0}"
