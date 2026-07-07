#!/usr/bin/env bash
# list_changes.sh — `foundry list`: grouped or single-bucket change listing.
#
# Source this file; do not execute it directly.
# Needs: store/query.sh, render/table.sh, render/primitives.sh, config_loader.sh, require_foundry.

cmd_list_changes() {
  require_foundry
  local bucket_filter="all" sort_key reverse
  sort_key="$(config_default_sort)"
  reverse="$(config_default_reverse_flag)"

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
    # single-list page — no grouping, no cap.
    local bucket_rows; bucket_rows=$(printf '%s\n' "$rows" | query_filter_bucket "$bucket_filter")
    local bucket_count; bucket_count=$(ui_count_lines "$bucket_rows")
    if (( bucket_count == 0 )); then
      ui_header "Foundry" "$(ui_status "$bucket_filter") · empty"
      echo
      return 0
    fi
    ui_header "Foundry" \
      "$(ui_status "$bucket_filter") · $bucket_count · sort: $sort_key $sort_arrow"
    read -r slug_width title_width updated_width <<< "$(render_list_widths)"
    while IFS=$'\t' read -r row_bucket slug title _ updated_epoch _; do
      render_list_row "$row_bucket" "$slug" "$title" "$updated_epoch" \
        "$slug_width" "$title_width" "$updated_width"
    done < <(printf '%s\n' "$bucket_rows" | query_sort "$sort_key" "$reverse")
    echo
    return 0
  fi

  # Grouped view: summary line + section per non-empty bucket.
  local breakdown=""
  for bucket in "${BUCKETS[@]}"; do
    local bucket_count
    bucket_count=$(ui_count_lines "$(printf '%s\n' "$rows" | query_filter_bucket "$bucket")")
    breakdown+="$(ui_status_icon "$bucket") $bucket_count  "
  done
  ui_header "Foundry" "$total · ${breakdown% } · sort: $sort_key $sort_arrow"
  local limit; limit="$(config_list_per_bucket_limit)"
  for bucket in "${BUCKETS[@]}"; do
    render_bucket_section "$bucket" "$rows" "$sort_key" "$reverse" "$limit"
  done
  echo

  if [[ "$UI_MODE" == "interactive" ]]; then
    printf '  %s  %s\n' \
      "$(ui_dim 'open      :')" "$(ui_dim 'foundry show <slug>')"
    printf '  %s  %s\n' \
      "$(ui_dim 'add       :')" "$(ui_dim 'foundry new "your idea"')"
    printf '  %s  %s\n' \
      "$(ui_dim 'one bucket:')" "$(ui_dim 'foundry list --bucket=<status>')"
    printf '  %s  %s\n' \
      "$(ui_dim 'configure :')" "$(ui_dim '.foundry/config.yaml')"
    echo
  fi
}
