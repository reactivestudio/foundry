#!/usr/bin/env bash
# Usage: tracking-active-stage.sh <change-path>
# Reports the first stage NOT in {approved, skipped} — i.e. the stage that needs work.
# Stage order: analysis → architecture → decomposition → implementation → verification
# Output: <stage-name> (e.g. "analysis") OR empty string if all stages approved/skipped.
# Exit 0 ok; 3 file missing.

set -eu

change_path=${1:-}
if [ -z "$change_path" ]; then
  echo "tracking-active-stage: missing arg (need <change-path>)" >&2
  exit 2
fi

tracking="$change_path/tracking.yaml"
if [ ! -f "$tracking" ]; then
  echo "tracking-active-stage: tracking.yaml not found at $tracking" >&2
  exit 3
fi

self_dir=$(cd "$(dirname "$0")" && pwd)

for stage in analysis architecture decomposition implementation verification; do
  state=$("$self_dir/tracking-get-stage.sh" "$change_path" "$stage")
  case "$state" in
    approved|skipped) continue ;;
    *) echo "$stage"; exit 0 ;;
  esac
done

# All stages approved or skipped.
echo ""
