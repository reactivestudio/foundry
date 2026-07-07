#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# state-machine.sh — bucket transition rules + serial invariant.
#
# Buckets: backlog | in-progress | done | declined
#
# Allowed transitions (single source: bucket_transitions_from below):
#   backlog     → in-progress  start   (requires: no other in-progress)
#   backlog     → done         done    (skip-in-progress for trivial changes)
#   backlog     → declined     decline (requires: reason)
#   in-progress → done         finish
#   in-progress → backlog      pause   (revert; logged)
#   in-progress → declined     decline (requires: reason)
#   declined    → backlog      revive
#
# Disallowed (terminal):
#   done → *
#
# All checks against $FOUNDRY_ROOT/changes/ (default: $PWD/.foundry).

set -euo pipefail

FOUNDRY_ROOT="${FOUNDRY_ROOT:-$PWD/.foundry}"
CHANGES_DIR="$FOUNDRY_ROOT/changes"

# shellcheck source=../config/constants.sh
. "$(dirname "${BASH_SOURCE[0]}")/../config/constants.sh"

usage() {
  cat >&2 <<'EOF'
usage:
  state-machine.sh validate-bucket <from> <to> [reason]
  state-machine.sh check-serial [excluded-slug]
  state-machine.sh list-buckets
  state-machine.sh transitions-from <bucket>   # "<to>\t<verb>" per line
EOF
  exit 64
}

bucket_valid() {
  local bucket="$1" known_bucket
  for known_bucket in "${BUCKETS[@]}"; do
    [[ "$bucket" == "$known_bucket" ]] && return 0
  done
  return 1
}

# THE transition table — the only place allowed moves are written down.
# One line per transition: "<to-bucket>\t<verb>", in canonical
# presentation order.  validate-bucket checks against this list, and
# commands/pages render next-step hints and action bars straight from
# it, so the UI can never drift from the machine.  The verb is the
# CRISPY lifecycle word for the move; the backlog→done skip path keeps
# the plain verb "done".
bucket_transitions_from() {
  case "$1" in
    backlog)
      printf 'in-progress\tstart\n'
      printf 'done\tdone\n'
      printf 'declined\tdecline\n' ;;
    in-progress)
      printf 'done\tfinish\n'
      printf 'backlog\tpause\n'
      printf 'declined\tdecline\n' ;;
    declined)
      printf 'backlog\trevive\n' ;;
    done)
      : ;;  # terminal — no way out
  esac
}

cmd_validate_bucket() {
  local from="$1" to="$2"
  local reason="${3:-}"

  if ! bucket_valid "$from"; then
    echo "invalid from-bucket: $from" >&2
    return 2
  fi
  if ! bucket_valid "$to"; then
    echo "invalid to-bucket: $to" >&2
    return 2
  fi
  if [[ "$from" == "$to" ]]; then
    echo "no-op: from == to == $from" >&2
    return 2
  fi

  if [[ "$from" == "done" ]]; then
    echo "terminal: cannot leave 'done'" >&2
    return 1
  fi
  if ! bucket_transitions_from "$from" | cut -f1 | grep -qx "$to"; then
    echo "disallowed transition: $from -> $to" >&2
    return 1
  fi

  if [[ "$to" == "declined" && -z "$reason" ]]; then
    echo "transition to 'declined' requires a reason" >&2
    return 1
  fi

  if [[ "$to" == "in-progress" ]]; then
    if ! cmd_check_serial "${EXCLUDE_SLUG:-}"; then
      return 1
    fi
  fi

  return 0
}

# Returns 0 iff zero changes (excluding $1, if given) are in in-progress.
cmd_check_serial() {
  local excluded_slug="${1:-}"
  local dir="$CHANGES_DIR/in-progress"
  [[ -d "$dir" ]] || return 0
  local count=0
  shopt -s nullglob
  for entry in "$dir"/*/; do
    local slug; slug=$(basename "$entry")
    [[ "$slug" == "$excluded_slug" ]] && continue
    count=$((count + 1))
    echo "  in-progress: $slug" >&2
  done
  shopt -u nullglob
  if (( count > 0 )); then
    echo "serial invariant: $count change(s) already in-progress" >&2
    return 1
  fi
  return 0
}

cmd_list_buckets() {
  printf '%s\n' "${BUCKETS[@]}"
}

# Print allowed transitions out of a bucket — "<to>\t<verb>" per line,
# nothing for terminal buckets.  Consumed by commands/show_change.sh
# (next hints) and pages/detail_page.sh (action bar).
cmd_transitions_from() {
  local from="$1"
  if ! bucket_valid "$from"; then
    echo "invalid bucket: $from" >&2
    return 2
  fi
  bucket_transitions_from "$from"
}

main() {
  [[ $# -lt 1 ]] && usage
  local subcommand="$1"; shift
  case "$subcommand" in
    validate-bucket)  [[ $# -ge 2 && $# -le 3 ]] || usage; cmd_validate_bucket "$@" ;;
    check-serial)     [[ $# -le 1 ]] || usage; cmd_check_serial "$@" ;;
    list-buckets)     [[ $# -eq 0 ]] || usage; cmd_list_buckets ;;
    transitions-from) [[ $# -eq 1 ]] || usage; cmd_transitions_from "$@" ;;
    *)               usage ;;
  esac
}

main "$@"
