#!/usr/bin/env bash
# Usage: tracking-get-stage.sh <change-path> <stage>
# Reads a single stage state from <change-path>/tracking.yaml.
# Output: stage state (one of pending|in-progress|need-approve|approved|pause|skipped).
# Exit 0 ok; 2 bad args; 3 tracking.yaml missing; 4 stage not found / unparseable.

set -eu

change_path=${1:-}
stage=${2:-}

if [ -z "$change_path" ] || [ -z "$stage" ]; then
  echo "tracking-get-stage: missing args (need <change-path> <stage>)" >&2
  exit 2
fi

tracking="$change_path/tracking.yaml"
if [ ! -f "$tracking" ]; then
  echo "tracking-get-stage: tracking.yaml not found at $tracking" >&2
  exit 3
fi

# Parse: find `stages:` block, then within it find `^  <stage>:[[:space:]]+<value>`.
# Portable awk (no gawk-specific match() with array).
value=$(awk -v want="$stage" '
  /^stages:[[:space:]]*$/ { in_stages = 1; next }
  in_stages && /^[^[:space:]]/ { in_stages = 0 }
  in_stages && /^[[:space:]]+[a-z_-]+:[[:space:]]+[a-z-]+[[:space:]]*$/ {
    n = split($0, parts, ":")
    key = parts[1]; val = parts[2]
    gsub(/[[:space:]]/, "", key)
    gsub(/[[:space:]]/, "", val)
    if (key == want) { print val; exit }
  }
' "$tracking")

if [ -z "$value" ]; then
  echo "tracking-get-stage: stage '$stage' not found in $tracking" >&2
  exit 4
fi

printf '%s\n' "$value"
