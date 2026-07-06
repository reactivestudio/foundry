#!/usr/bin/env bash
# list_page.sh — single-bucket paged view (entered from a "+N more" row).
#
# Source this file; do not execute it directly.
# Needs: query.sh, render/{table,brand_header,picker_widget,primitives}.sh, pages/detail_page.sh,
# PAGE_SORT / PAGE_REVERSE (set by main_page).
# Reuses picker_run with bucket-specific column header, page summary,
# and inline pagination actions.

list_page() {
  local bucket="$1"
  # Page size 5 — matches the user-requested pagination cadence and
  # keeps the screen height predictable.  Was 20 previously (with
  # ◀ Previous page / ▶ Next page footer actions); 0.33.3 moved the
  # pagination controls inline as "+N previous" / "+M next" entries
  # that sit at the top/bottom of the list, so the page has to be
  # smaller to actually surface pagination on realistic data sizes.
  local page=1 per_page=5

  while true; do
    local rows; rows=$(query_rows all | query_filter_bucket "$bucket" \
                      | query_sort "$PAGE_SORT" "$PAGE_REVERSE")
    local total; total=$(ui_count_lines "$rows")
    (( total == 0 )) && return
    local pages=$(( (total + per_page - 1) / per_page ))
    (( pages < 1 )) && pages=1
    (( page > pages )) && page=$pages
    (( page < 1 )) && page=1
    local start=$(( (page - 1) * per_page + 1 ))
    local end=$(( page * per_page ))
    (( end > total )) && end=$total
    local prev_count=$((start - 1))
    local next_count=$((total - end))
    local page_rows; page_rows=$(printf '%s\n' "$rows" | sed -n "${start},${end}p")

    picker_reset

    # Extra blank row before the column header — matches the main
    # view's breathing space between the ⌕ Search caret and the
    # STATUS / TITLE / CREATED / UPDATED strip.
    picker_push_padding

    # Column header.
    picker_push_header "$(render_columns_row)"

    # Blank padding row beneath the column header — matches main view.
    picker_push_padding

    # ── inline pagination: "+N previous" at top when page > 1 ──
    # Reuses render_more_row so the row visually matches the main-
    # screen overflow row (blank icon/bucket cells, label in fd_more
    # across the title cell, blank date cells).  Selecting it pages
    # back; the picker treats it as an action.  Filterable=0 so it
    # stays visible regardless of search text.
    if (( prev_count > 0 )); then
      picker_push_action "$(render_more_row "+${prev_count} previous")" "__bv_prev__"
    fi

    # Bucket rows — same composition as the main page (byte-identical
    # rows), so filter-match title highlighting works here too.
    while IFS=$'\t' read -r row_bucket slug title _ updated_epoch created_epoch; do
      render_push_change_row "$row_bucket" "$slug" "$title" "$updated_epoch" "$created_epoch"
    done <<< "$page_rows"

    # ── inline pagination: "+M next" at bottom when more pages exist ──
    if (( next_count > 0 )); then
      picker_push_action "$(render_more_row "+${next_count} next")" "__bv_next__"
    fi

    # Minimal summary — replaces the verbose
    #   "○ backlog  ·  page X of Y  ·  N total"
    # of pre-0.33.3.  Position is now implied by the in-list pagination
    # entries above, and the bucket badge already sits in the header
    # subtitle, so the only orientation the summary still owes the
    # user is the total count.  Dim so it reads as chrome, not data.
    picker_push_padding
    picker_push_summary "   $(ui_dim "${total} changes total")"
    picker_push_padding

    # Back action.  Pagination is now in-list, so the only chrome
    # action left at the bottom is the back navigation.
    picker_push_action "$(ui_paint fd_chrome "⇠  Back to all changes")" "__bv_back__"

    # Two-line branded header — IDENTICAL to the main view.  The user
    # explicitly wants the list page's header to match main 1:1
    # (same subtitle tagline, same project line).  Bucket context is
    # already conveyed by:
    #   1. how the user got here (drilling in via "+N more...")
    #   2. the uniform bucket icon/colour at the left of every row
    # so the header doesn't owe them a bucket badge.
    # shellcheck disable=SC2034  # read by picker_run
    PICKER_HEADER="$(render_page_header)"
    if picker_run "⌕  Search "; then
      case "$PICKER_RESULT_SLUG" in
        __bv_prev__) page=$((page - 1)) ;;
        __bv_next__) page=$((page + 1)) ;;
        __bv_back__) return ;;
        '') ;;
        *) detail_page "$PICKER_RESULT_SLUG" ;;
      esac
    else
      return
    fi
  done
}
