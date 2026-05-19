#!/usr/bin/env bash
# Usage: tracking-set-scope.sh <change-path> <scope> <by>
# Sets the `scope:` field in tracking.yaml + appends history entry.
# Valid scopes: product | project | feature | bugfix
# Output: <scope> on stdout.
# Exit 0 ok; 1 invalid scope; 2 bad args; 3 file missing.

set -eu

change_path=${1:-}
scope=${2:-}
by=${3:-}

if [ -z "$change_path" ] || [ -z "$scope" ] || [ -z "$by" ]; then
  echo "tracking-set-scope: missing args (need <change-path> <scope> <by>)" >&2
  exit 2
fi

valid_scopes="product project feature bugfix"
if ! printf ' %s ' "$valid_scopes" | grep -q " $scope "; then
  echo "tracking-set-scope: '$scope' is not a valid scope (one of: $valid_scopes)" >&2
  exit 1
fi

tracking="$change_path/tracking.yaml"
if [ ! -f "$tracking" ]; then
  echo "tracking-set-scope: tracking.yaml not found at $tracking" >&2
  exit 3
fi

# Rewrite scope: line. Format: `scope: <value>` or `scope: ""`.
tmp=$(mktemp "${TMPDIR:-/tmp}/tracking-set-scope.XXXXXX")
awk -v val="$scope" '
  /^scope:[[:space:]]*/ { printf "scope: %s\n", val; next }
  { print }
' "$tracking" > "$tmp"
mv "$tmp" "$tracking"

# Append history entry. Per plan: { stage: analysis, status: scope-set:<value>, by: <by> }.
now=$(date '+%Y-%m-%d %H:%M')
printf '  - { at: "%s", stage: analysis, status: "scope-set:%s", by: %s }\n' "$now" "$scope" "$by" >> "$tracking"

echo "$scope"
