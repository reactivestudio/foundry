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
#   tracking.sh derive-stage   --change <path>
#   tracking.sh sync           --change <path>     # syncs both status: and stage: fields
#   tracking.sh sync-status    --change <path>     # alias of sync
#   tracking.sh decline        --change <path> --reason <r> --by <who>
#   tracking.sh append-history --change <path> --stage <s> --status <st> --by <who>
#
# Stages (6):       refinement design decomposition implementation verification termination
# Stage states (8): estimation required skipped pending in-progress review completed rejected
# Scopes (4):       product project feature bugfix
# Statuses (4):     backlog in-progress done declined
#
# YAML schema (flat): top-level keys for each stage; no nested `stages:` block.
# Top-level `status:` and `stage:` are derived from stage values + decline_reason.

set -eu

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
STATE_MACHINE="$SELF_DIR/stage-state-machine.sh"
ROADMAP="$SELF_DIR/roadmap.sh"

VALID_STAGES="refinement design decomposition implementation verification termination"
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

is_valid_stage() {
  printf ' %s ' "$VALID_STAGES" | grep -q " $1 "
}

# Read one stage's value from tracking.yaml (flat top-level key).
read_stage() {
  local tracking=$1 stage=$2
  awk -v want="$stage" '
    $0 ~ "^"want":[[:space:]]+[a-z-]+[[:space:]]*$" {
      sub("^"want":[[:space:]]+", "", $0)
      gsub(/[[:space:]]/, "", $0)
      print
      exit
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
    $0 ~ "^"want":[[:space:]]+[a-z-]+[[:space:]]*$" {
      # Preserve key + colon + whitespace, replace value.
      line = $0
      if (match(line, "^"want":[[:space:]]+") > 0) {
        prefix = substr(line, 1, RLENGTH)
        print prefix val
        next
      }
    }
    { print }
  ' "$tracking" > "$tmp"
  mv "$tmp" "$tracking"
}

# Compute status from current yaml state (no I/O write).
# Echoes: backlog | in-progress | done | declined
#
# Rules (in order):
#   1. decline_reason present → declined
#   2. implementation ∈ {estimation, required} → backlog (impl not yet active)
#   3. all of {implementation, verification, termination} ∈ {completed, skipped} → done
#   4. otherwise → in-progress
#
# Key invariant: once implementation moves past {estimation, required} the
# change is "in motion" and stays `in-progress` (or moves to `done`) — it does
# NOT slide back to `backlog`. A `pending` (= blocked) impl still counts as
# in-progress for bucket purposes. `rejected` likewise stays `in-progress`
# pending upstream-stage rework.
compute_status() {
  local tracking=$1
  local declined_reason
  declined_reason=$(read_decline_reason "$tracking")
  if [ -n "$declined_reason" ]; then
    echo declined
    return
  fi
  local impl verif term
  impl=$(read_stage "$tracking" implementation)
  verif=$(read_stage "$tracking" verification)
  term=$(read_stage "$tracking" termination)
  case "$impl" in
    estimation|required) echo backlog; return ;;
  esac
  case "$impl"  in completed|skipped) ;; *) echo in-progress; return ;; esac
  case "$verif" in completed|skipped) ;; *) echo in-progress; return ;; esac
  case "$term"  in completed|skipped) ;; *) echo in-progress; return ;; esac
  echo done
}

# Compute current active stage. A stage is "active" if its state is anything
# other than {completed, skipped} — i.e. work is still due on it. The active
# stage is the first such stage in canonical order. If all stages are
# completed/skipped (typically a `done` change), echo "none".
compute_stage() {
  local tracking=$1 s state
  for s in $VALID_STAGES; do
    state=$(read_stage "$tracking" "$s")
    case "$state" in
      completed|skipped) continue ;;
      *) echo "$s"; return ;;
    esac
  done
  echo none
}

# Rewrite top-level `status:` line.
sync_status_field() {
  local tracking=$1 computed tmp
  computed=$(compute_status "$tracking")
  tmp=$(mktemp "${TMPDIR:-/tmp}/tracking-status.XXXXXX")
  awk -v val="$computed" '
    /^status:[[:space:]]/ { print "status: " val; next }
    { print }
  ' "$tracking" > "$tmp"
  mv "$tmp" "$tracking"
}

# Rewrite top-level `stage:` line.
sync_stage_field() {
  local tracking=$1 computed tmp
  computed=$(compute_stage "$tracking")
  tmp=$(mktemp "${TMPDIR:-/tmp}/tracking-stage.XXXXXX")
  awk -v val="$computed" '
    /^stage:[[:space:]]/ { print "stage: " val; next }
    { print }
  ' "$tracking" > "$tmp"
  mv "$tmp" "$tracking"
}

# Rewrite top-level `updated_at:` line with current timestamp.
#
# Two modes:
#   - If `updated_at:` line exists → single-line replace (preserves position).
#   - If absent → insert right after `created_at:` (or, if that's also absent,
#     just before `history:`).
#
# Idempotent: subsequent calls re-write the same line.
sync_updated_at() {
  local tracking=$1 now tmp
  now=$(now_ts)
  tmp=$(mktemp "${TMPDIR:-/tmp}/tracking-updated.XXXXXX")
  if grep -q '^updated_at:[[:space:]]' "$tracking"; then
    # Replace existing line.
    awk -v val="$now" '
      /^updated_at:[[:space:]]/ { printf "updated_at: \"%s\"\n", val; next }
      { print }
    ' "$tracking" > "$tmp"
  else
    # Insert new line. Prefer right after created_at; fall back to right
    # before history:; last resort, append at EOF.
    awk -v val="$now" '
      BEGIN { inserted = 0 }
      {
        print
        if (!inserted && $0 ~ /^created_at:[[:space:]]/) {
          printf "updated_at: \"%s\"\n", val
          inserted = 1
        }
      }
      /^history:[[:space:]]*$/ && !inserted {
        # We already printed history: above; the line we want is now beforehand.
        # Since we cannot rewind in a single pass, fall back to appending at END.
      }
      END {
        if (!inserted) printf "updated_at: \"%s\"\n", val
      }
    ' "$tracking" > "$tmp"
  fi
  mv "$tmp" "$tracking"
}

# Rewrite top-level `progress:` line with current roadmap stats. Reads
# `<change_dir>/roadmap.md` (sibling of tracking.yaml) and runs
# `roadmap.sh status` to extract done/total. Writes `progress: "done/total"`.
# If roadmap.md is absent → `progress: "0/0"`.
#
# Insert / replace logic mirrors sync_updated_at.
sync_roadmap_progress() {
  local tracking=$1 change_dir roadmap_md stats done total progress tmp
  change_dir=$(dirname "$tracking")
  roadmap_md="$change_dir/roadmap.md"
  done=0
  total=0
  if [ -f "$roadmap_md" ]; then
    stats=$("$ROADMAP" status --roadmap "$roadmap_md" 2>/dev/null || echo "")
    if [ -n "$stats" ]; then
      done=$(printf '%s' "$stats" | tr ' ' '\n' | awk -F= '$1=="done"{print $2; exit}')
      total=$(printf '%s' "$stats" | tr ' ' '\n' | awk -F= '$1=="total"{print $2; exit}')
      [ -z "$done" ] && done=0
      [ -z "$total" ] && total=0
    fi
  fi
  progress="${done}/${total}"
  tmp=$(mktemp "${TMPDIR:-/tmp}/tracking-progress.XXXXXX")
  if grep -q '^progress:[[:space:]]' "$tracking"; then
    awk -v p="$progress" '
      /^progress:[[:space:]]/ { printf "progress: \"%s\"\n", p; next }
      { print }
    ' "$tracking" > "$tmp"
  else
    # Insert after updated_at: (preferred), else after created_at:, else
    # before history:, else EOF.
    awk -v p="$progress" '
      BEGIN { inserted = 0 }
      {
        print
        if (!inserted && $0 ~ /^updated_at:[[:space:]]/) {
          printf "progress: \"%s\"\n", p
          inserted = 1
        } else if (!inserted && $0 ~ /^created_at:[[:space:]]/) {
          # only fall back to created_at if no updated_at seen yet (we are
          # in single-pass, so just print here too; sync_updated_at always
          # inserts updated_at right after created_at, so this branch is
          # unreachable in practice — keep for safety).
        }
      }
      END {
        if (!inserted) printf "progress: \"%s\"\n", p
      }
    ' "$tracking" > "$tmp"
  fi
  mv "$tmp" "$tracking"
}

# Sync all derived / auto-tracked fields.
sync_all() {
  sync_status_field "$1"
  sync_stage_field "$1"
  sync_updated_at "$1"
  sync_roadmap_progress "$1"
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
  if ! is_valid_stage "$stage"; then
    echo "tracking get-stage: '$stage' is not a valid stage (one of: $VALID_STAGES)" >&2
    exit 2
  fi
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
  if ! is_valid_stage "$stage"; then
    echo "tracking set-stage: '$stage' is not a valid stage (one of: $VALID_STAGES)" >&2
    exit 2
  fi
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
  sync_all "$tracking"
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
  # Note: scope recorded only in top-level `scope:` field — no history entry.
  # Refresh updated_at (sync_all is a superset that also re-asserts derived
  # status/stage — cheap and ensures the row's "updated" column is current).
  sync_all "$tracking"
  echo "$scope"
}

# === subcommand: derive-status ===

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

# === subcommand: derive-stage ===

cmd_derive_stage() {
  local change=""
  while [ $# -gt 0 ]; do
    case ${1:-} in
      --change) shift; change=${1:-} ;;
      *) echo "tracking derive-stage: unknown arg '$1'" >&2; exit 2 ;;
    esac
    shift || true
  done
  require_args derive-stage "--change|$change"
  local tracking="$change/tracking.yaml"
  require_file "$tracking"
  compute_stage "$tracking"
}

# === subcommand: sync (rewrites both status: and stage: fields) ===

cmd_sync() {
  local change=""
  while [ $# -gt 0 ]; do
    case ${1:-} in
      --change) shift; change=${1:-} ;;
      *) echo "tracking sync: unknown arg '$1'" >&2; exit 2 ;;
    esac
    shift || true
  done
  require_args sync "--change|$change"
  local tracking="$change/tracking.yaml"
  require_file "$tracking"
  sync_all "$tracking"
  printf '%s\t%s\n' "$(compute_status "$tracking")" "$(compute_stage "$tracking")"
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
  # Decline recorded only in top-level `decline_reason:` field — no history entry.
  sync_all "$tracking"
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
  derive-stage   --change <path>
  sync           --change <path>          # rewrites status: + stage: fields
  sync-status    --change <path>          # alias of sync
  decline        --change <path> --reason <reason> --by <who>
  append-history --change <path> --stage <stage> --status <status> --by <who>

Stages:     $VALID_STAGES
Scopes:     $VALID_SCOPES
Statuses:   backlog in-progress done declined
Stage states (see stage-state-machine.sh): pending in-progress need-approve approved pause skipped

YAML schema is flat — each stage is a top-level key.
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
  derive-stage)   cmd_derive_stage "$@" ;;
  sync)           cmd_sync "$@" ;;
  sync-status)    cmd_sync "$@" ;;
  decline)        cmd_decline "$@" ;;
  append-history) cmd_append_history "$@" ;;
  -h|--help|"")   usage; [ -z "$sub" ] && exit 2 || exit 0 ;;
  *) echo "tracking: unknown subcommand '$sub'" >&2; usage; exit 2 ;;
esac
