#!/usr/bin/env bash
# state-machine.sh — bucket transition rules + serial invariant.
#
# Buckets: backlog | in-progress | done | declined
#
# Allowed transitions:
#   backlog     → in-progress  (requires: no other in-progress)
#   backlog     → done         (skip-in-progress for trivial changes)
#   backlog     → declined     (requires: reason)
#   in-progress → done
#   in-progress → declined     (requires: reason)
#   in-progress → backlog      (revert; logged)
#   declined    → backlog      (revive)
#
# Disallowed (terminal):
#   done → *
#
# All checks against $FOUNDRY_ROOT/changes/ (default: $PWD/.foundry).

set -euo pipefail

FOUNDRY_ROOT="${FOUNDRY_ROOT:-$PWD/.foundry}"
CHANGES_DIR="$FOUNDRY_ROOT/changes"

# shellcheck source=lib/constants.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/constants.sh"

usage() {
  cat >&2 <<'EOF'
usage:
  state-machine.sh validate-bucket <from> <to> [reason]
  state-machine.sh check-serial [excluded-slug]
  state-machine.sh list-buckets
EOF
  exit 64
}

is_valid_bucket() {
  local b="$1"
  for v in "${BUCKETS[@]}"; do
    [[ "$b" == "$v" ]] && return 0
  done
  return 1
}

cmd_validate_bucket() {
  local from="$1" to="$2"
  local reason="${3:-}"

  if ! is_valid_bucket "$from"; then
    echo "invalid from-bucket: $from" >&2
    return 2
  fi
  if ! is_valid_bucket "$to"; then
    echo "invalid to-bucket: $to" >&2
    return 2
  fi
  if [[ "$from" == "$to" ]]; then
    echo "no-op: from == to == $from" >&2
    return 2
  fi

  # Separator ':' between from/to — bash-safe. Avoid '→' (locale-dependent
  # multibyte parsing) and '->' (parser sees '>' as redirect operator).
  case "$from:$to" in
    backlog:in-progress|backlog:done|backlog:declined) : ;;
    in-progress:done|in-progress:declined|in-progress:backlog) : ;;
    declined:backlog) : ;;
    done:*)
      echo "terminal: cannot leave 'done'" >&2
      return 1 ;;
    *)
      echo "disallowed transition: $from -> $to" >&2
      return 1 ;;
  esac

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
  local exclude="${1:-}"
  local dir="$CHANGES_DIR/in-progress"
  [[ -d "$dir" ]] || return 0
  local count=0
  shopt -s nullglob
  for entry in "$dir"/*/; do
    local slug; slug=$(basename "$entry")
    [[ "$slug" == "$exclude" ]] && continue
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

main() {
  [[ $# -lt 1 ]] && usage
  local sub="$1"; shift
  case "$sub" in
    validate-bucket) [[ $# -ge 2 && $# -le 3 ]] || usage; cmd_validate_bucket "$@" ;;
    check-serial)    [[ $# -le 1 ]] || usage; cmd_check_serial "$@" ;;
    list-buckets)    [[ $# -eq 0 ]] || usage; cmd_list_buckets ;;
    *)               usage ;;
  esac
}

main "$@"
