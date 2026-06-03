#!/usr/bin/env bash
# change.sh — CRUD over changes in .foundry/changes/<bucket>/<slug>/
#
# Wraps tracking.sh + state-machine.sh. All filesystem mutations go through
# this script — never edit .foundry/ by hand.

set -euo pipefail

FOUNDRY_ROOT="${FOUNDRY_ROOT:-$PWD/.foundry}"
CHANGES_DIR="$FOUNDRY_ROOT/changes"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRACKING_SH="$SCRIPT_DIR/tracking.sh"
SM_SH="$SCRIPT_DIR/state-machine.sh"
# shellcheck source=lib/render.sh
. "$SCRIPT_DIR/lib/render.sh"
# shellcheck source=lib/constants.sh
. "$SCRIPT_DIR/lib/constants.sh"
# shellcheck source=lib/index.sh
. "$SCRIPT_DIR/lib/index.sh"

usage() {
  cat >&2 <<'EOF'
usage:
  change.sh new <slug> <title>
  change.sh locate <slug>                          # prints bucket
  change.sh path <slug>                            # prints absolute dir
  change.sh move <slug> <to-bucket> [reason]
  change.sh list [bucket]                          # bucket=all by default
  change.sh show <slug>                            # tracking.yaml + recent history
EOF
  exit 64
}

require_foundry() {
  if [[ ! -d "$CHANGES_DIR" ]]; then
    echo "no .foundry/ at $FOUNDRY_ROOT — run /foundry:setup first" >&2
    exit 2
  fi
}

valid_slug() {
  [[ "$1" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] && (( ${#1} <= 60 ))
}

# Echo bucket containing slug, or empty + nonzero exit if not found.
find_bucket() {
  local slug="$1"
  for b in "${BUCKETS[@]}"; do
    if [[ -d "$CHANGES_DIR/$b/$slug" ]]; then
      echo "$b"
      return 0
    fi
  done
  return 1
}

cmd_new() {
  require_foundry
  local slug="$1" title="$2"
  if ! valid_slug "$slug"; then
    echo "invalid slug: '$slug' (kebab-case, [a-z0-9-], ≤60 chars)" >&2
    exit 2
  fi
  if find_bucket "$slug" >/dev/null 2>&1; then
    echo "slug already exists: $slug (in $(find_bucket "$slug"))" >&2
    exit 2
  fi
  local dir="$CHANGES_DIR/backlog/$slug"
  "$TRACKING_SH" init "$dir" "$slug" "$title"
  if [[ ! -f "$dir/proposal.md" ]]; then
    render_template \
      "$CHANGES_DIR/.template/proposal.md" \
      "$dir/proposal.md" \
      TITLE="$title"
  fi
  # Keep the backlog index in sync — pull the freshly-written
  # timestamps back from tracking.yaml so created_at / updated_at agree
  # with the per-slug file exactly (down to the second).
  local _ct _ut
  _ct=$("$TRACKING_SH" get "$dir" created_at)
  _ut=$("$TRACKING_SH" get "$dir" updated_at)
  index_add_entry backlog "$slug" "$title" "$_ct" "$_ut"
  echo "created: $dir"
}

cmd_locate() {
  require_foundry
  find_bucket "$1" || { echo "not found: $1" >&2; exit 1; }
}

cmd_path() {
  require_foundry
  local slug="$1" b
  b=$(find_bucket "$slug") || { echo "not found: $slug" >&2; exit 1; }
  echo "$CHANGES_DIR/$b/$slug"
}

cmd_move() {
  require_foundry
  local slug="$1" to="$2"
  local reason="${3:-}"
  local from
  from=$(find_bucket "$slug") || { echo "not found: $slug" >&2; exit 1; }
  if [[ "$from" == "$to" ]]; then
    echo "already in $to: $slug" >&2
    exit 0
  fi
  # state-machine validation (serial check excludes self)
  EXCLUDE_SLUG="$slug" "$SM_SH" validate-bucket "$from" "$to" "$reason" \
    || { echo "transition rejected" >&2; exit 1; }

  local src="$CHANGES_DIR/$from/$slug"
  local dst="$CHANGES_DIR/$to/$slug"
  mv "$src" "$dst"
  "$TRACKING_SH" set "$dst" status "$to"
  if [[ "$to" == "declined" ]]; then
    "$TRACKING_SH" set "$dst" decline_reason "$reason"
  fi
  # Re-sync the two bucket indexes — pull post-bump timestamps from
  # tracking.yaml so the index agrees with the per-slug file.  status
  # and decline_reason aren't carried in the index schema (status is
  # implied by which bucket the entry lives in), so tracking.sh set
  # itself doesn't touch the index — only this single explicit edit
  # at the call-site does.
  index_remove_entry "$from" "$slug"
  local _t _ct _ut
  _t=$("$TRACKING_SH"  get "$dst" title)
  _ct=$("$TRACKING_SH" get "$dst" created_at)
  _ut=$("$TRACKING_SH" get "$dst" updated_at)
  index_add_entry "$to" "$slug" "$_t" "$_ct" "$_ut"
  "$TRACKING_SH" history "$dst" state-machine moved "$from->$to${reason:+ ($reason)}"
  echo "moved: $slug ($from -> $to)"
}

cmd_list() {
  require_foundry
  local filter="${1:-all}"
  local buckets=("${BUCKETS[@]}")
  if [[ "$filter" != "all" ]]; then
    buckets=("$filter")
  fi
  printf '%-12s  %-40s  %s\n' "BUCKET" "SLUG" "TITLE"
  printf '%-12s  %-40s  %s\n' "------" "----" "-----"
  shopt -s nullglob
  for b in "${buckets[@]}"; do
    [[ -d "$CHANGES_DIR/$b" ]] || continue
    for entry in "$CHANGES_DIR/$b"/*/; do
      local slug; slug=$(basename "$entry")
      local title; title=$("$TRACKING_SH" get "$entry" title 2>/dev/null || echo "?")
      printf '%-12s  %-40s  %s\n' "$b" "$slug" "$title"
    done
  done
  shopt -u nullglob
}

cmd_show() {
  require_foundry
  local slug="$1"
  local b; b=$(find_bucket "$slug") || { echo "not found: $slug" >&2; exit 1; }
  local dir="$CHANGES_DIR/$b/$slug"
  echo "=== $dir ==="
  cat "$dir/tracking.yaml"
  echo "--- recent history ---"
  "$TRACKING_SH" history-tail "$dir" 10
}

main() {
  [[ $# -lt 1 ]] && usage
  local sub="$1"; shift
  case "$sub" in
    new)    [[ $# -eq 2 ]] || usage; cmd_new "$@" ;;
    locate) [[ $# -eq 1 ]] || usage; cmd_locate "$@" ;;
    path)   [[ $# -eq 1 ]] || usage; cmd_path "$@" ;;
    move)   [[ $# -ge 2 && $# -le 3 ]] || usage; cmd_move "$@" ;;
    list)   [[ $# -le 1 ]] || usage; cmd_list "$@" ;;
    show)   [[ $# -eq 1 ]] || usage; cmd_show "$@" ;;
    *)      usage ;;
  esac
}

main "$@"
