#!/usr/bin/env bash
# Usage: tracking-derive-bucket.sh <change-path>
# Computes the desired bucket (backlog | sprint | done) from current stages.
# Rules:
#   - implementation OR verification in {in-progress, need-approve} → sprint
#   - implementation in {approved, skipped} AND verification in {approved, skipped} → done
#   - otherwise → backlog
# Note: declined is set manually via change-move; not derived here.
# Note: pause does NOT trigger move — change stays where it is.
# Output: desired bucket name.
# Exit 0 ok; 3 file missing.

set -eu

change_path=${1:-}
if [ -z "$change_path" ]; then
  echo "tracking-derive-bucket: missing arg (need <change-path>)" >&2
  exit 2
fi

tracking="$change_path/tracking.yaml"
if [ ! -f "$tracking" ]; then
  echo "tracking-derive-bucket: tracking.yaml not found at $tracking" >&2
  exit 3
fi

self_dir=$(cd "$(dirname "$0")" && pwd)
impl=$("$self_dir/tracking-get-stage.sh" "$change_path" implementation)
verif=$("$self_dir/tracking-get-stage.sh" "$change_path" verification)

active_in_sprint() {
  case "$1" in
    in-progress|need-approve) return 0 ;;
    *) return 1 ;;
  esac
}

finished() {
  case "$1" in
    approved|skipped) return 0 ;;
    *) return 1 ;;
  esac
}

if active_in_sprint "$impl" || active_in_sprint "$verif"; then
  echo sprint
  exit 0
fi

if finished "$impl" && finished "$verif"; then
  echo done
  exit 0
fi

echo backlog
