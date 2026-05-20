#!/usr/bin/env bash
# stage-state-machine.sh — pure state-machine logic for change stage states.
# No filesystem operations. Knows the allowed transitions and the set of states.
#
# Usage:
#   stage-state-machine.sh validate --from <state> --to <state>
#   stage-state-machine.sh states
#   stage-state-machine.sh allowed-from --state <state>
#
# Exit codes (validate):
#   0 — valid
#   1 — invalid transition
#   2 — bad args / unknown state

set -eu

# === state set + transitions table ===
# States: pending | in-progress | need-approve | approved | pause | skipped
#
# Allowed transitions:
#   pending      → in-progress | skipped
#   in-progress  → need-approve | pause | skipped
#   pause        → in-progress | skipped
#   need-approve → approved | in-progress       (in-progress = rework after rejection)
#   approved     → in-progress | skipped         (back-edge: later stage flags rework)
#   skipped      → in-progress                   (rare: stage reclassified as needed)

VALID_STATES="pending in-progress need-approve approved pause skipped"

allowed_from_state() {
  case "$1" in
    pending)      echo "in-progress skipped" ;;
    in-progress)  echo "need-approve pause skipped" ;;
    pause)        echo "in-progress skipped" ;;
    need-approve) echo "approved in-progress" ;;
    approved)     echo "in-progress skipped" ;;
    skipped)      echo "in-progress" ;;
    *)            echo "" ;;
  esac
}

is_valid_state() {
  printf ' %s ' "$VALID_STATES" | grep -q " $1 "
}

# === subcommands ===

cmd_validate() {
  local from="" to=""
  while [ $# -gt 0 ]; do
    case ${1:-} in
      --from) shift; from=${1:-} ;;
      --to)   shift; to=${1:-} ;;
      *) echo "stage-state-machine validate: unknown arg '$1'" >&2; exit 2 ;;
    esac
    shift || true
  done
  if [ -z "$from" ] || [ -z "$to" ]; then
    echo "stage-state-machine validate: missing --from and/or --to" >&2
    exit 2
  fi
  for s in "$from" "$to"; do
    if ! is_valid_state "$s"; then
      echo "stage-state-machine validate: '$s' is not a valid state (one of: $VALID_STATES)" >&2
      exit 2
    fi
  done
  local allowed
  allowed=$(allowed_from_state "$from")
  if printf ' %s ' "$allowed" | grep -q " $to "; then
    echo "valid"
    exit 0
  fi
  echo "stage-state-machine validate: '$from' → '$to' is not allowed (from '$from' allowed: $allowed)" >&2
  exit 1
}

cmd_states() {
  printf '%s\n' $VALID_STATES
}

cmd_allowed_from() {
  local from=""
  while [ $# -gt 0 ]; do
    case ${1:-} in
      --state) shift; from=${1:-} ;;
      *) echo "stage-state-machine allowed-from: unknown arg '$1'" >&2; exit 2 ;;
    esac
    shift || true
  done
  if [ -z "$from" ]; then
    echo "stage-state-machine allowed-from: missing --state" >&2
    exit 2
  fi
  if ! is_valid_state "$from"; then
    echo "stage-state-machine allowed-from: '$from' is not a valid state" >&2
    exit 2
  fi
  local allowed
  allowed=$(allowed_from_state "$from")
  [ -n "$allowed" ] && printf '%s\n' $allowed
}

usage() {
  cat >&2 <<EOF
Usage: stage-state-machine.sh <subcommand> [options]

Subcommands:
  validate --from <state> --to <state>   Validate a transition (exit 0 valid, 1 invalid)
  states                                 List all valid states
  allowed-from --state <state>           List states reachable from <state>

States: $VALID_STATES
EOF
}

sub=${1:-}
shift || true
case "$sub" in
  validate)     cmd_validate "$@" ;;
  states)       cmd_states ;;
  allowed-from) cmd_allowed_from "$@" ;;
  -h|--help|"") usage; [ -z "$sub" ] && exit 2 || exit 0 ;;
  *) echo "stage-state-machine: unknown subcommand '$sub'" >&2; usage; exit 2 ;;
esac
