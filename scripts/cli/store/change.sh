#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# change.sh — CRUD over changes in .foundry/changes/<bucket>/<slug>/
#
# Wraps tracking.sh + state-machine.sh. All filesystem mutations go through
# this script — never edit .foundry/ by hand.
#
# Deliberately NO file locking: foundry is a single-operator tool, and
# every multi-step write ends in an atomic mv (tracking.sh, index
# rebuilds) or IS an atomic mv (bucket moves).  Two racing invocations
# lose cleanly — the second mv fails with a visible error — instead of
# corrupting state.  Revisit only if the tool ever grows daemons.

set -euo pipefail

FOUNDRY_ROOT="${FOUNDRY_ROOT:-$PWD/.foundry}"
CHANGES_DIR="$FOUNDRY_ROOT/changes"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRACKING_SH="$SCRIPT_DIR/tracking.sh"
SM_SH="$SCRIPT_DIR/../spec/state-machine.sh"
# shellcheck source=template.sh
. "$SCRIPT_DIR/template.sh"
# shellcheck source=../config/constants.sh
. "$SCRIPT_DIR/../config/constants.sh"
# shellcheck source=index_cache.sh
. "$SCRIPT_DIR/index_cache.sh"

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

# Slug rules (slug_valid) live in spec/slug.sh; bucket lookup
# (query_bucket_of) in store/query.sh — shared with the sourced CLI
# components so the logic exists exactly once.
# shellcheck source=../spec/slug.sh
. "$SCRIPT_DIR/../spec/slug.sh"
# shellcheck source=query.sh
. "$SCRIPT_DIR/query.sh"

cmd_new() {
  require_foundry
  local slug="$1" title="$2"
  if ! slug_valid "$slug"; then
    echo "invalid slug: '$slug' (kebab-case, [a-z0-9-], ≤60 chars)" >&2
    exit 2
  fi
  local existing_bucket
  if existing_bucket=$(query_bucket_of "$slug" 2>/dev/null); then
    echo "slug already exists: $slug (in $existing_bucket)" >&2
    exit 2
  fi
  local dir="$CHANGES_DIR/backlog/$slug"
  "$TRACKING_SH" init "$dir" "$slug" "$title"
  # Re-read the title tracking.sh just wrote — it sanitizes newlines
  # and tabs out of free text, and the proposal heading and the index
  # entry below must carry the same canonical value.
  title=$("$TRACKING_SH" get "$dir" title)
  if [[ ! -f "$dir/proposal.md" ]]; then
    render_template \
      "$CHANGES_DIR/.template/proposal.md" \
      "$dir/proposal.md" \
      TITLE="$title"
  fi
  # Keep the backlog index in sync — pull the freshly-written
  # timestamps back from tracking.yaml so created_at / updated_at agree
  # with the per-slug file exactly (down to the second).
  local created_at updated_at
  created_at=$("$TRACKING_SH" get "$dir" created_at)
  updated_at=$("$TRACKING_SH" get "$dir" updated_at)
  index_add_entry backlog "$slug" "$title" "$created_at" "$updated_at"
  echo "created: $dir"
}

cmd_locate() {
  require_foundry
  query_bucket_of "$1" || { echo "not found: $1" >&2; exit 1; }
}

cmd_path() {
  require_foundry
  local slug="$1" bucket
  bucket=$(query_bucket_of "$slug") || { echo "not found: $slug" >&2; exit 1; }
  echo "$CHANGES_DIR/$bucket/$slug"
}

cmd_move() {
  require_foundry
  local slug="$1" to="$2"
  local reason="${3:-}"
  local from
  from=$(query_bucket_of "$slug") || { echo "not found: $slug" >&2; exit 1; }
  if [[ "$from" == "$to" ]]; then
    echo "already in $to: $slug" >&2
    exit 0
  fi
  # state-machine validation (serial check excludes self)
  EXCLUDE_SLUG="$slug" "$SM_SH" validate-bucket "$from" "$to" "$reason" \
    || { echo "transition rejected" >&2; exit 1; }

  local source_dir="$CHANGES_DIR/$from/$slug"
  local destination_dir="$CHANGES_DIR/$to/$slug"
  mv "$source_dir" "$destination_dir"
  "$TRACKING_SH" set "$destination_dir" status "$to"
  if [[ "$to" == "declined" ]]; then
    "$TRACKING_SH" set "$destination_dir" decline_reason "$reason"
  fi
  # Re-sync the two bucket indexes — pull post-bump timestamps from
  # tracking.yaml so the index agrees with the per-slug file.  status
  # and decline_reason aren't carried in the index schema (status is
  # implied by which bucket the entry lives in), so tracking.sh set
  # itself doesn't touch the index — only this single explicit edit
  # at the call-site does.
  index_remove_entry "$from" "$slug"
  local title created_at updated_at
  title=$("$TRACKING_SH"      get "$destination_dir" title)
  created_at=$("$TRACKING_SH" get "$destination_dir" created_at)
  updated_at=$("$TRACKING_SH" get "$destination_dir" updated_at)
  index_add_entry "$to" "$slug" "$title" "$created_at" "$updated_at"
  "$TRACKING_SH" history "$destination_dir" state-machine moved "$from->$to${reason:+ ($reason)}"
  echo "moved: $slug ($from -> $to)"
}

cmd_list() {
  require_foundry
  local bucket_filter="${1:-all}"
  local buckets=("${BUCKETS[@]}")
  if [[ "$bucket_filter" != "all" ]]; then
    buckets=("$bucket_filter")
  fi
  printf '%-12s  %-40s  %s\n' "BUCKET" "SLUG" "TITLE"
  printf '%-12s  %-40s  %s\n' "------" "----" "-----"
  shopt -s nullglob
  for bucket in "${buckets[@]}"; do
    [[ -d "$CHANGES_DIR/$bucket" ]] || continue
    for entry in "$CHANGES_DIR/$bucket"/*/; do
      local slug; slug=$(basename "$entry")
      local title; title=$("$TRACKING_SH" get "$entry" title 2>/dev/null || echo "?")
      printf '%-12s  %-40s  %s\n' "$bucket" "$slug" "$title"
    done
  done
  shopt -u nullglob
}

cmd_show() {
  require_foundry
  local slug="$1"
  local bucket; bucket=$(query_bucket_of "$slug") || { echo "not found: $slug" >&2; exit 1; }
  local dir="$CHANGES_DIR/$bucket/$slug"
  echo "=== $dir ==="
  cat "$dir/tracking.yaml"
  echo "--- recent history ---"
  "$TRACKING_SH" history-tail "$dir" 10
}

main() {
  [[ $# -lt 1 ]] && usage
  local subcommand="$1"; shift
  case "$subcommand" in
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
