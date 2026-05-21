#!/usr/bin/env bash
# tracking.sh — all operations on a change's tracking.yaml.
# Uses stage-state-machine.sh for transition validation.
#
# Usage:
#   tracking.sh get-stage      --change <path> --stage <name>
#   tracking.sh set-stage      --change <path> --stage <name> --state <s> --by <who>
#   tracking.sh get-scope      --change <path>
#   tracking.sh set-scope      --change <path> --scope <s> --by <who>
#   tracking.sh derive-status  --change <path>
#   tracking.sh active-stage   --change <path>
#   tracking.sh decline        --change <path> --reason <r> --by <who>
#   tracking.sh append-history --change <path> --stage <s> --status <st> --by <who>
#   tracking.sh sync-status    --change <path>
#
# Stages (5):       refinement design decomposition implementation verification
# Stage states (6): pending in-progress need-approve approved pause skipped
# Scopes (4):       product project feature bugfix
# Statuses (4):     backlog in-progress done declined
#                   (declined is set by `decline` subcommand; others are derived from stages)

set -eu

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
STATE_MACHINE="$SELF_DIR/stage-state-machine.sh"

VALID_STAGES="refinement design decomposition implementation verification"
VALID_SCOPES="product project feature bugfix"

# === helpers ===

require_args() {
  local sub=$1; shift
  while [ $# -gt 0 ]; do
    local flag=${1%%|*}
    local val=${1#*|}
    if [ -z "$val" ]; then
      echo "tracking $sub: missing $flag" >&2
      exit 2
    fi
    shift
  done
}

require_file() {
  local f=$1
  if [ ! -f "$f" ]; then
    echo "tracking: file not found at $f" >&2
    exit 3
  fi
}

# Read one stage's value from tracking.yaml (portable awk).
read_stage() {
  local tracking=$1 stage=$2
  awk -v want="$stage" '
    /^stages:[[:space:]]*$/ { in_stages = 1; next }
    in_stages && /^[^[:space:]]/ { in_stages = 0 }
    in_stages && /^[[:space:]]+[a-z_-]+:[[:space:]]+[a-z-]+[[:space:]]*$/ {
      n = split($0, parts, ":")
      key = parts[1]; val = parts[2]
      gsub(/[[:space:]]/, "", key)
      gsub(/[[:space:]]/, "", val)
      if (key == want) { print val; exit }
    }
  ' "$tracking"
}

read_scope() {
  awk '/^scope:[[:space:]]*/ {
    sub(/^scope:[[:space:]]*/, "", $0)
    gsub(/"/, "", $0)
    print
    exit
  }' "$1"
}

read_decline_reason() {
  awk '/^decline_reason:[[:space:]]/ {
    sub(/^decline_reason:[[:space:]]*/, "", $0)
    print
    exit
  }' "$1"
}

now_ts() { date '+%Y-%m-%d %H:%M:%S'; }

# Append a history entry to tracking.yaml.
append_history_entry() {
  local tracking=$1 stage=$2 status=$3 by=$4
  printf '  - { at: "%s", stage: %s, status: %s, by: %s }\n' "$(now_ts)" "$stage" "$status" "$by" >> "$tracking"
}

# Append a history entry with a quoted status (for values containing ':' or spaces).
append_history_entry_quoted() {
  local tracking=$1 stage=$2 status=$3 by=$4
  printf '  - { at: "%s", stage: %s, status: "%s", by: %s }\n' "$(now_ts)" "$stage" "$status" "$by" >> "$tracking"
}

# Atomic single-stage value rewrite (preserves indentation/alignment).
rewrite_stage() {
  local tracking=$1 stage=$2 new_state=$3
  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/tracking.XXXXXX")
  awk -v want="$stage" -v val="$new_state" '
    BEGIN { in_stages = 0 }
    /^stages:[[:space:]]*$/ { in_stages = 1; print; next }
    in_stages && /^[^[:space:]]/ { in_stages = 0 }
    in_stages && /^[[:space:]]+[a-z_-]+:[[:space:]]+[a-z-]+[[:space:]]*$/ {
      line = $0
      if (match(line, /^[[:space:]]+[a-z_-]+:[[:space:]]+/) > 0) {
        key_line = $0
        sub(/:[[:space:]]+.*$/, "", key_line)
        key_name = key_line
        sub(/^[[:space:]]+/, "", key_name)
        if (key_name == want) {
          prefix = substr(line, 1, RLENGTH)
          print prefix val
          next
        }
      }
    }
    { print }
  ' "$tracking" > "$tmp"
  mv "$tmp" "$tracking"
}

# Compute status from current yaml state (no I/O write).
# Echoes: backlog | in-progress | done | declined
compute_status() {
  local tracking=$1
  local declined_reason
  declined_reason=$(read_decline_reason "$tracking")
  if [ -n "$declined_reason" ]; then
    echo declined
    return
  fi
  local impl verif
  impl=$(read_stage "$tracking" implementation)
  verif=$(read_stage "$tracking" verification)
  case "$impl" in
    in-progress|need-approve) echo in-progress; return ;;
  esac
  case "$verif" in
    in-progress|need-approve) echo in-progress; return ;;
  esac
  case "$impl" in
    approved|skipped)
      case "$verif" in
        approved|skipped) echo done; return ;;
      esac
      ;;
  esac
  echo backlog
}

# Rewrite the top-level `status:` line in tracking.yaml to match computed value.
sync_status_field() {
  local tracking=$1
  local computed
  computed=$(compute_status "$tracking")
  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/tracking-status.XXXXXX")
  awk -v val="$computed" '
    /^status:[[:space:]]/ { print "status: " val; next }
    { print }
  ' "$tracking" > "$tmp"
  mv "$tmp" "$tracking"
}

# === subcommand: get-stage ===

cmd_get_stage() {
  local change="" stage=""
  while [ $# -gt 0 ]; do
    case ${1:-} in
      --change) shift; change=${1:-} ;;
      --stage)  shift; stage=${1:-} ;;
      *) echo "tracking get-stage: unknown arg '$1'" >&2; exit 2 ;;
    esac
    shift || true
  done
  require_args get-stage "--change|$change" "--stage|$stage"
  local tracking="$change/tracking.yaml"
  require_file "$tracking"
  local val
  val=$(read_stage "$tracking" "$stage")
  if [ -z "$val" ]; then
    echo "tracking get-stage: stage '$stage' not found in $tracking" >&2
    exit 4
  fi
  printf '%s\n' "$val"
}

# === subcommand: set-stage ===

cmd_set_stage() {
  local change="" stage="" new_state="" by=""
  while [ $# -gt 0 ]; do
    case ${1:-} in
      --change) shift; change=${1:-} ;;
      --stage)  shift; stage=${1:-} ;;
      --state)  shift; new_state=${1:-} ;;
      --by)     shift; by=${1:-} ;;
      *) echo "tracking set-stage: unknown arg '$1'" >&2; exit 2 ;;
    esac
    shift || true
  done
  require_args set-stage "--change|$change" "--stage|$stage" "--state|$new_state" "--by|$by"
  local tracking="$change/tracking.yaml"
  require_file "$tracking"
  local current
  current=$(read_stage "$tracking" "$stage")
  if [ -z "$current" ]; then
    echo "tracking set-stage: stage '$stage' not found in $tracking" >&2
    exit 4
  fi
  if [ "$current" != "$new_state" ]; then
    if ! "$STATE_MACHINE" validate --from "$current" --to "$new_state" >/dev/null; then
      exit 1
    fi
    rewrite_stage "$tracking" "$stage" "$new_state"
  fi
  append_history_entry "$tracking" "$stage" "$new_state" "$by"
  sync_status_field "$tracking"
  echo "$new_state"
}

# === subcommand: get-scope ===

cmd_get_scope() {
  local change=""
  while [ $# -gt 0 ]; do
    case ${1:-} in
      --change) shift; change=${1:-} ;;
      *) echo "tracking get-scope: unknown arg '$1'" >&2; exit 2 ;;
    esac
    shift || true
  done
  require_args get-scope "--change|$change"
  local tracking="$change/tracking.yaml"
  require_file "$tracking"
  read_scope "$tracking"
}

# === subcommand: set-scope ===

cmd_set_scope() {
  local change="" scope="" by=""
  while [ $# -gt 0 ]; do
    case ${1:-} in
      --change) shift; change=${1:-} ;;
      --scope)  shift; scope=${1:-} ;;
      --by)     shift; by=${1:-} ;;
      *) echo "tracking set-scope: unknown arg '$1'" >&2; exit 2 ;;
    esac
    shift || true
  done
  require_args set-scope "--change|$change" "--scope|$scope" "--by|$by"
  if ! printf ' %s ' "$VALID_SCOPES" | grep -q " $scope "; then
    echo "tracking set-scope: '$scope' is not a valid scope (one of: $VALID_SCOPES)" >&2
    exit 1
  fi
  local tracking="$change/tracking.yaml"
  require_file "$tracking"
  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/tracking-scope.XXXXXX")
  awk -v val="$scope" '
    /^scope:[[:space:]]*/ { printf "scope: %s\n", val; next }
    { print }
  ' "$tracking" > "$tmp"
  mv "$tmp" "$tracking"
  append_history_entry_quoted "$tracking" refinement "scope-set:$scope" "$by"
  echo "$scope"
}

# === subcommand: derive-status (was: derive-bucket) ===

cmd_derive_status() {
  local change=""
  while [ $# -gt 0 ]; do
    case ${1:-} in
      --change) shift; change=${1:-} ;;
      *) echo "tracking derive-status: unknown arg '$1'" >&2; exit 2 ;;
    esac
    shift || true
  done
  require_args derive-status "--change|$change"
  local tracking="$change/tracking.yaml"
  require_file "$tracking"
  compute_status "$tracking"
}

# === subcommand: sync-status (rewrite status field) ===

cmd_sync_status() {
  local change=""
  while [ $# -gt 0 ]; do
    case ${1:-} in
      --change) shift; change=${1:-} ;;
      *) echo "tracking sync-status: unknown arg '$1'" >&2; exit 2 ;;
    esac
    shift || true
  done
  require_args sync-status "--change|$change"
  local tracking="$change/tracking.yaml"
  require_file "$tracking"
  sync_status_field "$tracking"
  compute_status "$tracking"
}

# === subcommand: active-stage ===

cmd_active_stage() {
  local change=""
  while [ $# -gt 0 ]; do
    case ${1:-} in
      --change) shift; change=${1:-} ;;
      *) echo "tracking active-stage: unknown arg '$1'" >&2; exit 2 ;;
    esac
    shift || true
  done
  require_args active-stage "--change|$change"
  local tracking="$change/tracking.yaml"
  require_file "$tracking"
  local s
  for s in $VALID_STAGES; do
    local state
    state=$(read_stage "$tracking" "$s")
    case "$state" in
      approved|skipped) continue ;;
      *) echo "$s"; return ;;
    esac
  done
  echo ""
}

# === subcommand: decline ===

cmd_decline() {
  local change="" reason="" by=""
  while [ $# -gt 0 ]; do
    case ${1:-} in
      --change) shift; change=${1:-} ;;
      --reason) shift; reason=${1:-} ;;
      --by)     shift; by=${1:-} ;;
      *) echo "tracking decline: unknown arg '$1'" >&2; exit 2 ;;
    esac
    shift || true
  done
  require_args decline "--change|$change" "--reason|$reason" "--by|$by"
  local tracking="$change/tracking.yaml"
  require_file "$tracking"
  local reason_escaped
  reason_escaped=$(printf '%s' "$reason" | sed 's/"/\\"/g')
  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/tracking-decline.XXXXXX")
  awk -v reason="$reason_escaped" '
    BEGIN { inserted = 0 }
    /^decline_reason:[[:space:]]/ {
      printf "decline_reason: \"%s\"\n", reason
      inserted = 1; next
    }
    /^history:[[:space:]]*$/ && !inserted {
      printf "decline_reason: \"%s\"\n", reason
      inserted = 1; print; next
    }
    { print }
    END {
      if (!inserted) printf "decline_reason: \"%s\"\n", reason
    }
  ' "$tracking" > "$tmp"
  mv "$tmp" "$tracking"
  append_history_entry "$tracking" lifecycle declined "$by"
  sync_status_field "$tracking"
}

# === subcommand: append-history (utility) ===

cmd_append_history() {
  local change="" stage="" status="" by=""
  while [ $# -gt 0 ]; do
    case ${1:-} in
      --change) shift; change=${1:-} ;;
      --stage)  shift; stage=${1:-} ;;
      --status) shift; status=${1:-} ;;
      --by)     shift; by=${1:-} ;;
      *) echo "tracking append-history: unknown arg '$1'" >&2; exit 2 ;;
    esac
    shift || true
  done
  require_args append-history "--change|$change" "--stage|$stage" "--status|$status" "--by|$by"
  local tracking="$change/tracking.yaml"
  require_file "$tracking"
  case "$status" in
    *:*|*\ *) append_history_entry_quoted "$tracking" "$stage" "$status" "$by" ;;
    *)        append_history_entry         "$tracking" "$stage" "$status" "$by" ;;
  esac
}

usage() {
  cat >&2 <<EOF
Usage: tracking.sh <subcommand> [options]

Subcommands:
  get-stage      --change <path> --stage <name>
  set-stage      --change <path> --stage <name> --state <state> --by <who>
  get-scope      --change <path>
  set-scope      --change <path> --scope <scope> --by <who>
  derive-status  --change <path>
  sync-status    --change <path>
  active-stage   --change <path>
  decline        --change <path> --reason <reason> --by <who>
  append-history --change <path> --stage <stage> --status <status> --by <who>

Stages:     $VALID_STAGES
Scopes:     $VALID_SCOPES
Statuses:   backlog in-progress done declined
Stage states (see stage-state-machine.sh): pending in-progress need-approve approved pause skipped
EOF
}

sub=${1:-}
shift || true
case "$sub" in
  get-stage)      cmd_get_stage "$@" ;;
  set-stage)      cmd_set_stage "$@" ;;
  get-scope)      cmd_get_scope "$@" ;;
  set-scope)      cmd_set_scope "$@" ;;
  derive-status)  cmd_derive_status "$@" ;;
  sync-status)    cmd_sync_status "$@" ;;
  active-stage)   cmd_active_stage "$@" ;;
  decline)        cmd_decline "$@" ;;
  append-history) cmd_append_history "$@" ;;
  -h|--help|"")   usage; [ -z "$sub" ] && exit 2 || exit 0 ;;
  *) echo "tracking: unknown subcommand '$sub'" >&2; usage; exit 2 ;;
esac
