#!/usr/bin/env bash
# Usage: tracking-validate-stage-transition.sh <from> <to>
# Validates per-stage state transition (same machine for all 5 stages).
# Allowed:
#   pending      → in-progress | skipped
#   in-progress  → need-approve | pause | skipped
#   pause        → in-progress | skipped
#   need-approve → approved | in-progress
#   approved     → in-progress | skipped
#   skipped      → in-progress
# Exit 0 + "valid"; 1 + diagnostic on invalid; 2 on bad args.

set -eu

from=${1:-}
to=${2:-}

if [ -z "$from" ] || [ -z "$to" ]; then
  echo "tracking-validate-stage-transition: missing args (need <from> <to>)" >&2
  exit 2
fi

valid_states="pending in-progress need-approve approved pause skipped"
for s in "$from" "$to"; do
  if ! printf ' %s ' "$valid_states" | grep -q " $s "; then
    echo "tracking-validate-stage-transition: '$s' is not a valid state (one of: $valid_states)" >&2
    exit 2
  fi
done

case "$from" in
  pending)      allowed="in-progress skipped" ;;
  in-progress)  allowed="need-approve pause skipped" ;;
  pause)        allowed="in-progress skipped" ;;
  need-approve) allowed="approved in-progress" ;;
  approved)     allowed="in-progress skipped" ;;
  skipped)      allowed="in-progress" ;;
  *)            allowed="" ;;
esac

if printf ' %s ' "$allowed" | grep -q " $to "; then
  echo "valid"
  exit 0
fi

echo "tracking-validate-stage-transition: '$from' → '$to' is not allowed (from '$from' allowed: $allowed)" >&2
exit 1
