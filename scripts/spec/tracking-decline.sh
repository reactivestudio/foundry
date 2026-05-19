#!/usr/bin/env bash
# Usage: tracking-decline.sh <change-path> <reason> <by>
# Sets `decline_reason:` field in tracking.yaml + appends `{ stage: _meta, status: declined }` history.
# Does NOT move the directory — that is change-move's responsibility.
# Output: nothing on stdout.
# Exit 0 ok; 2 bad args; 3 file missing.

set -eu

change_path=${1:-}
reason=${2:-}
by=${3:-}

if [ -z "$change_path" ] || [ -z "$reason" ] || [ -z "$by" ]; then
  echo "tracking-decline: missing args (need <change-path> <reason> <by>)" >&2
  exit 2
fi

tracking="$change_path/tracking.yaml"
if [ ! -f "$tracking" ]; then
  echo "tracking-decline: tracking.yaml not found at $tracking" >&2
  exit 3
fi

# Escape double quotes in reason for safe YAML inline string.
reason_escaped=$(printf '%s' "$reason" | sed 's/"/\\"/g')

# Insert decline_reason: line BEFORE the `history:` line (top-level scalar placement).
# If decline_reason already exists, replace it.
tmp=$(mktemp "${TMPDIR:-/tmp}/tracking-decline.XXXXXX")
awk -v reason="$reason_escaped" '
  BEGIN { inserted = 0 }
  /^decline_reason:[[:space:]]/ {
    printf "decline_reason: \"%s\"\n", reason
    inserted = 1
    next
  }
  /^history:[[:space:]]*$/ && !inserted {
    printf "decline_reason: \"%s\"\n", reason
    inserted = 1
    print
    next
  }
  { print }
  END {
    if (!inserted) {
      printf "decline_reason: \"%s\"\n", reason
    }
  }
' "$tracking" > "$tmp"
mv "$tmp" "$tracking"

# Append history entry.
now=$(date '+%Y-%m-%d %H:%M')
printf '  - { at: "%s", stage: _meta, status: declined, by: %s }\n' "$now" "$by" >> "$tracking"
