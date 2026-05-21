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
# States: estimation | required | skipped | pending | in-progress | review | completed | rejected
#
# Semantics:
#   estimation  — initial; deciding whether this stage is needed for this change.
#   required    — decided needed, not yet active (waiting on caller / scheduling).
#   skipped     — decided not needed for this change (terminal-for-stage).
#   pending     — needed and started, but currently blocked by an external factor.
#   in-progress — active work by the owning agent.
#   review      — artifact ready, awaiting user / peer review.
#   completed   — review approved (terminal-for-stage).
#   rejected    — unrealizable as currently scoped; requires upstream stages to be
#                 revisited (compromise / clarification). Re-entry happens via the
#                 upstream stage flipping back to in-progress; this stage returns to
#                 in-progress (or required) once unblocked.
#
# Allowed transitions:
#   estimation   → required | skipped | in-progress    (in-progress = decide+start in one step)
#   required     → pending | in-progress | skipped
#   pending      → in-progress | required | skipped     (unblock, re-eval need, or de-scope)
#   in-progress  → review | pending | rejected | skipped
#   review       → completed | in-progress | rejected
#   completed    → in-progress | rejected               (back-edges from downstream)
#   skipped      → required | in-progress                (reclassified as needed)
#   rejected     → required | in-progress                (upstream fixed, resume)
#
# estimation is initial-only — no transition returns to it.

VALID_STATES="estimation required skipped pending in-progress review completed rejected"

allowed_from_state() {
  case "$1" in
    estimation)  echo "required skipped in-progress" ;;
    required)    echo "pending in-progress skipped" ;;
    pending)     echo "in-progress required skipped" ;;
    in-progress) echo "review pending rejected skipped" ;;
    review)      echo "completed in-progress rejected" ;;
    completed)   echo "in-progress rejected" ;;
    skipped)     echo "required in-progress" ;;
    rejected)    echo "required in-progress" ;;
    *)           echo "" ;;
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
