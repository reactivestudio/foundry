#!/usr/bin/env bash
# Usage: tracking-set-stage.sh <change-path> <stage> <new-state> <by>
# Atomically updates one stage's state in tracking.yaml + appends history entry.
# Validates transition via tracking-validate-stage-transition.sh.
# Output: <new-state> on stdout.
# Exit 0 ok; 1 invalid transition; 2 bad args; 3 file missing.

set -eu

change_path=${1:-}
stage=${2:-}
new_state=${3:-}
by=${4:-}

if [ -z "$change_path" ] || [ -z "$stage" ] || [ -z "$new_state" ] || [ -z "$by" ]; then
  echo "tracking-set-stage: missing args (need <change-path> <stage> <new-state> <by>)" >&2
  exit 2
fi

tracking="$change_path/tracking.yaml"
if [ ! -f "$tracking" ]; then
  echo "tracking-set-stage: tracking.yaml not found at $tracking" >&2
  exit 3
fi

self_dir=$(cd "$(dirname "$0")" && pwd)

# 1. Read current state.
current=$("$self_dir/tracking-get-stage.sh" "$change_path" "$stage")

# 2. Validate transition (idempotent self-set is allowed silently).
#    Validator writes diagnostic to stderr on failure; we suppress stdout ("valid").
if [ "$current" != "$new_state" ]; then
  if ! "$self_dir/tracking-validate-stage-transition.sh" "$current" "$new_state" >/dev/null; then
    exit 1
  fi
fi

# 3. Atomic rewrite of stages: block (preserve indentation/alignment of value column).
tmp=$(mktemp "${TMPDIR:-/tmp}/tracking-set-stage.XXXXXX")
awk -v want="$stage" -v val="$new_state" '
  BEGIN { in_stages = 0 }
  /^stages:[[:space:]]*$/ { in_stages = 1; print; next }
  in_stages && /^[^[:space:]]/ { in_stages = 0 }
  in_stages && /^[[:space:]]+[a-z_-]+:[[:space:]]+[a-z-]+[[:space:]]*$/ {
    # Split into "  key:" and value parts; preserve "  key:<spaces>" prefix.
    line = $0
    if (match(line, /^[[:space:]]+[a-z_-]+:[[:space:]]+/) > 0) {
      key_line = $0
      sub(/:[[:space:]]+.*$/, "", key_line)
      key_name = key_line
      sub(/^[[:space:]]+/, "", key_name)
      if (key_name == want) {
        # Reconstruct: prefix (everything up to and including the spaces after colon) + new value.
        prefix = substr(line, 1, RLENGTH)
        print prefix val
        next
      }
    }
  }
  { print }
' "$tracking" > "$tmp"

mv "$tmp" "$tracking"

# 4. Append history entry (always last section in tracking.yaml).
now=$(date '+%Y-%m-%d %H:%M')
printf '  - { at: "%s", stage: %s, status: %s, by: %s }\n' "$now" "$stage" "$new_state" "$by" >> "$tracking"

echo "$new_state"
