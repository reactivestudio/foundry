#!/usr/bin/env bash
# query.sh — read model over the change store.
#
# Source this file; do not execute it directly.
# Needs: BUCKETS (config/constants.sh), CHANGES_DIR, index_* (spec/index_cache.sh).
#
# Every list/page reads changes through these three functions; writes
# go through spec/change.sh only.

# Echo bucket containing slug or empty + exit 1.
query_bucket_of() {
  local slug="$1"
  local bucket
  # shellcheck disable=SC2153  # BUCKETS is sourced from config/constants.sh
  for bucket in "${BUCKETS[@]}"; do
    [[ -d "$CHANGES_DIR/$bucket/$slug" ]] && { echo "$bucket"; return 0; }
  done
  return 1
}

# Emit a TSV row per change:
#   bucket  slug  title  age_str  updated_epoch  created_epoch
#
# Reads from per-bucket .index.yaml (built by scripts/cli/spec/index_cache.sh) —
# one awk fork per bucket instead of N×3 grep|sed forks per slug.
# When an expected index is missing (first launch after upgrade, or
# someone deleted the file) we rebuild it lazily before reading; the
# explicit `foundry sync` action item rebuilds all four unconditionally.
query_rows() {
  local filter="${1:-all}"
  local buckets=("${BUCKETS[@]}")
  [[ "$filter" != "all" ]] && buckets=("$filter")
  local now; now=$(date -u +%s)
  local bucket slug title created_epoch updated_epoch delta age
  for bucket in "${buckets[@]}"; do
    [[ -d "$CHANGES_DIR/$bucket" ]] || continue
    [[ -f "$CHANGES_DIR/$bucket/.index.yaml" ]] || index_rebuild_bucket "$bucket"
    # index columns: slug, title, created_iso, updated_iso (both unused
    # here — the epochs carry the same fact), created_epoch, updated_epoch
    while IFS=$'\t' read -r slug title _ _ created_epoch updated_epoch; do
      [[ -z "$slug" ]] && continue
      if [[ -n "$updated_epoch" && "$updated_epoch" != "0" ]]; then
        delta=$(( now - updated_epoch ))
        if   (( delta < 60 ));     then age="${delta}s"
        elif (( delta < 3600 ));   then age="$(( delta / 60 ))m"
        elif (( delta < 86400 ));  then age="$(( delta / 3600 ))h"
        elif (( delta < 604800 )); then age="$(( delta / 86400 ))d"
        else                            age="$(( delta / 604800 ))w"
        fi
      else
        age="?"
      fi
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$bucket" "$slug" "$title" "$age" "$updated_epoch" "$created_epoch"
    done < <(index_read_bucket "$bucket")
  done
}

# Keep only one bucket's rows from a TSV stream (stdin → stdout).
query_filter_bucket() {
  awk -F'\t' -v b="$1" '$1 == b'
}

# Apply --sort within a set of TSV rows (stdin → stdout).
query_sort() {
  local sort_key="$1" reverse="$2"
  # Newest-first is the default; --reverse clears -r for oldest-first.
  local order_flag="-r"; [[ "$reverse" == "1" ]] && order_flag=""
  case "$sort_key" in
    updated) sort -t$'\t' -k5 -n $order_flag ;;
    created) sort -t$'\t' -k6 -n $order_flag ;;
    slug)    sort -t$'\t' -k2 $order_flag ;;
    title)   sort -t$'\t' -k3 -f $order_flag ;;
    *)       cat ;;
  esac
}

# Read one change's tracking fields into globals (single place for the
# field list — commands/show.sh and pages/detail_page.sh render the
# same record):
#   CHANGE_TITLE / CHANGE_STATUS / CHANGE_CREATED / CHANGE_UPDATED
#   CHANGE_REASON — decline reason, "" unless the change was declined
# shellcheck disable=SC2034  # CHANGE_* are a documented cross-layer protocol
query_change_fields() {
  local dir="$1"
  CHANGE_TITLE=$("$TRACKING_SH" get "$dir" title 2>/dev/null)
  CHANGE_STATUS=$("$TRACKING_SH" get "$dir" status 2>/dev/null)
  CHANGE_CREATED=$("$TRACKING_SH" get "$dir" created_at 2>/dev/null)
  CHANGE_UPDATED=$("$TRACKING_SH" get "$dir" updated_at 2>/dev/null)
  CHANGE_REASON=$("$TRACKING_SH" get "$dir" decline_reason 2>/dev/null || true)
}
