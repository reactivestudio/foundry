#!/usr/bin/env bash
# line-count.sh — generic line-count gate.
#
# Used by stage artifact gates (CRISPY §4 design ≤220, §5 structure ≤100,
# NO-VIBES §6 sub-agent response ≤30).
#
# By default counts only "content" lines:
#   - skips blank lines
#   - skips lines that are pure whitespace
#   - skips markdown comment lines starting with `<!--`
#   - skips lines that are only a heading separator like `---`
# Pass --raw to disable filtering and count every line.
#
# Exit codes:
#   0  — within limit
#   1  — over limit (PRINTS report to stderr)
#   64 — usage error

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: line-count.sh [--raw] <file> <max>
EOF
  exit 64
}

raw=0
if [[ "${1:-}" == "--raw" ]]; then
  raw=1
  shift
fi

[[ $# -eq 2 ]] || usage
file="$1"
max="$2"

[[ "$max" =~ ^[0-9]+$ ]] \
  || { echo "max must be a positive integer, got: $max" >&2; exit 64; }
[[ -f "$file" ]] || { echo "not found: $file" >&2; exit 64; }

if (( raw )); then
  line_count=$(wc -l < "$file" | tr -d ' ')
else
  line_count=$(grep -cE '[^[:space:]]' "$file" || true)
  # subtract markdown comment-only lines and standalone separators
  noise_line_count=$(grep -cE '^[[:space:]]*(<!--|---[[:space:]]*$)' "$file" || true)
  line_count=$((line_count - noise_line_count))
  (( line_count < 0 )) && line_count=0
fi

if (( line_count > max )); then
  echo "line-count FAIL: $file has $line_count content lines (max $max)" >&2
  exit 1
fi

echo "line-count PASS: $file = $line_count / $max"
