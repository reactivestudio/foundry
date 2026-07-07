#!/usr/bin/env bash
# list_changes.sh — `foundry list`: grouped or single-bucket change listing.
#
# Source this file; do not execute it directly.
# Needs: store/query.sh, render/table.sh, render/primitives.sh,
# config_loader.sh, require_foundry.
#
# The _list_changes_* helpers execute inside cmd_list_changes and read
# its locals (rows, total, bucket_filter, sort_key, reverse, sort_arrow)
# through bash dynamic scoping — same pattern as _show_change_*.

# Single-bucket flat listing — no grouping, no per-bucket cap.
_list_changes_single_bucket() {
  local bucket_rows
  bucket_rows=$(printf '%s\n' "$rows" | query_filter_bucket "$bucket_filter")
  local bucket_count; bucket_count=$(ui_count_lines "$bucket_rows")
  if (( bucket_count == 0 )); then
    ui_header "Foundry" "$(ui_status "$bucket_filter") · empty"
    echo
    return 0
  fi
  ui_header "Foundry" \
    "$(ui_status "$bucket_filter") · $bucket_count · sort: $sort_key $sort_arrow"
  local slug_width title_width updated_width
  read -r slug_width title_width updated_width <<< "$(render_list_widths)"
  local row_bucket slug title updated_epoch
  while IFS=$'\t' read -r row_bucket slug title _ updated_epoch _; do
    render_list_row "$row_bucket" "$slug" "$title" "$updated_epoch" \
      "$slug_width" "$title_width" "$updated_width"
  done < <(printf '%s\n' "$bucket_rows" | query_sort "$sort_key" "$reverse")
  echo
}

# Grouped view: summary line + section per non-empty bucket.
_list_changes_grouped() {
  local breakdown="" bucket bucket_count
  for bucket in "${BUCKETS[@]}"; do
    bucket_count=$(ui_count_lines "$(printf '%s\n' "$rows" | query_filter_bucket "$bucket")")
    breakdown+="$(ui_status_icon "$bucket") $bucket_count  "
  done
  ui_header "Foundry" "$total · ${breakdown% } · sort: $sort_key $sort_arrow"
  local limit; limit="$(config_list_per_bucket_limit)"
  for bucket in "${BUCKETS[@]}"; do
    render_bucket_section "$bucket" "$rows" "$sort_key" "$reverse" "$limit"
  done
  echo
}

# Next-action hints under the grouped view — interactive only.
_list_changes_footer_hints() {
  printf '  %s  %s\n' \
    "$(ui_dim 'open      :')" "$(ui_dim 'foundry show <slug>')"
  printf '  %s  %s\n' \
    "$(ui_dim 'add       :')" "$(ui_dim 'foundry new "your idea"')"
  printf '  %s  %s\n' \
    "$(ui_dim 'one bucket:')" "$(ui_dim 'foundry list --bucket=<status>')"
  printf '  %s  %s\n' \
    "$(ui_dim 'configure :')" "$(ui_dim '.foundry/config.yaml')"
  echo
}

cmd_list_changes() {
  require_foundry
  local bucket_filter="all" sort_key reverse
  sort_key="$(config_default_sort)"
  reverse="$(config_default_reverse_flag)"

  local arg
  for arg in "$@"; do
    case "$arg" in
      --bucket=*) bucket_filter="${arg#--bucket=}" ;;
      --sort=*)   sort_key="${arg#--sort=}" ;;
      --reverse)  reverse=1 ;;
      *) ui_error "list: unknown flag: $arg"; exit 64 ;;
    esac
  done

  case "$sort_key" in
    updated|created|slug|title) ;;
    *) ui_error "list: --sort must be one of: updated, created, slug, title"; exit 64 ;;
  esac
  if [[ "$bucket_filter" != "all" ]] && ! bucket_valid "$bucket_filter"; then
    ui_error "list: unknown bucket: $bucket_filter (valid: ${BUCKETS[*]})"
    exit 64
  fi

  local rows; rows=$(query_change_rows all)
  if [[ -z "$rows" ]]; then
    ui_header "Foundry" "empty"
    ui_info "get started: foundry new \"your idea\""
    echo
    return 0
  fi

  local total; total=$(ui_count_lines "$rows")
  local sort_arrow; (( reverse )) && sort_arrow='↑' || sort_arrow='↓'

  if [[ "$bucket_filter" != "all" ]]; then
    _list_changes_single_bucket
    return 0
  fi
  _list_changes_grouped
  [[ "$UI_MODE" == "interactive" ]] && _list_changes_footer_hints
  return 0
}
