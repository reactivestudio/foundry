#!/usr/bin/env bash
# main_page.sh — the main interactive screen: all changes grouped by bucket.
#
# Source this file; do not execute it directly.
# Needs: store/query.sh, render/{table,brand_header,picker_widget,primitives}.sh,
# config_loader.sh, commands/{new_change,sync_indexes}.sh,
# pages/{list_page,detail_page}.sh, require_foundry.
#
# Shared page state (set here, read by pages/list_page.sh too):
#   PAGE_SORT / PAGE_REVERSE — sort key + direction from config.

# Populate PICKER_* arrays for the main page.
# Layout: padding → column header → padding → rows (per bucket, capped
# + "+N more") → summary → padding → action items.
_main_page_entries() {
  picker_reset

  # Action labels (icons are plain Unicode, no Nerd Font: ⛖ U+26D6).
  # Display values get painted in fd_chrome at the push below.
  local add_label='+  Add new change'
  local sync_label='⛖  Sync'
  local reload_label='⟳  Reload'
  local exit_label='⏻  Exit'

  local rows; rows=$(query_change_rows all)

  # Extra blank row before the column header — user wanted one more
  # line of breathing space between the ⌕ Search caret and the
  # STATUS / TITLE / CREATED / UPDATED strip.
  picker_push_padding

  # Column headers.
  picker_push_header "$(render_columns_row)"

  # Blank padding row beneath the column header — the user wanted the
  # STATUS / TITLE / CREATED / UPDATED strip to breathe before the data
  # rows start.  Type=padding so the cursor skips it.
  picker_push_padding

  local limit; limit="$(config_list_per_bucket_limit)"
  local bucket
  for bucket in "${BUCKETS[@]}"; do
    local bucket_rows; bucket_rows=$(printf '%s\n' "$rows" \
      | query_filter_bucket "$bucket" \
      | query_sort "$PAGE_SORT" "$PAGE_REVERSE")
    [[ -z "$bucket_rows" ]] && continue
    local bucket_count; bucket_count=$(ui_count_lines "$bucket_rows")
    local visible_rows="$bucket_rows"
    (( bucket_count > limit )) && visible_rows=$(printf '%s\n' "$bucket_rows" | head -n "$limit")
    while IFS=$'\t' read -r row_bucket slug title _ updated_epoch created_epoch; do
      render_push_change_row "$row_bucket" "$slug" "$title" "$updated_epoch" "$created_epoch"
    done <<< "$visible_rows"
    if (( bucket_count > limit )); then
      # Filterable=1 so "+N more" hides when the user is searching by
      # text (its label "+N more..." rarely matches a query).  Tagged
      # with the bucket it belongs to — Tab on the last row of bucket X
      # then lands on the next bucket (not on +N more which still
      # belongs to bucket X).
      picker_push_action "$(render_more_row "+$((bucket_count - limit)) more...")" \
        "__more__$bucket" 1 "$bucket"
      # Empty padding row after +N more.  Note: the user has asked
      # multiple times for "half a row" of gap here.  In a cell-based
      # terminal that's physically not possible — rows are atomic units
      # of the grid, so the available choices are 0 rows or 1 row of
      # gap.  0.32.7's ▁-glyph approximation drew a visible line
      # instead of empty space, which the user rejected; restoring a
      # plain empty pad here is the only "non-zero, non-glyph" option.
      picker_push_padding
    fi
  done

  # Bottom summary block — restored in 0.32.9.  In 0.33.0 the user
  # asked to lift the summary one line up: drop the pre-summary
  # padding (the bucket-rows loop's trailing "+N more" padding
  # already leaves a natural gap), keep two padding rows after so
  # the summary doesn't crash into Add/Reload/Exit below.
  local total_count; total_count=$(ui_count_lines "$rows")
  picker_push_summary "$(render_summary_row "$total_count" "$rows")"

  picker_push_padding
  picker_push_padding

  # Action items at bottom (always selectable, never filtered).
  picker_push_action "$(ui_paint fd_chrome "$add_label")" "__act_add__"
  picker_push_action "$(ui_paint fd_chrome "$sync_label")" "__act_sync__"
  picker_push_action "$(ui_paint fd_chrome "$reload_label")" "__act_reload__"
  picker_push_action "$(ui_paint fd_chrome "$exit_label")" "__act_exit__"
}

# Confirm-and-quit gate shared by the ESC path and the ⏻ Exit action.
_exit_confirm_dialog() {
  if ui_confirm "Exit foundry?"; then clear; exit 0; fi
}

# Prompt for a title → create → return (caller redraws).
_new_change_dialog() {
  clear
  ui_header "Foundry" "new change"
  local title
  title=$(ui_input "Change title (free text)" --width 60) || return
  [[ -z "$title" ]] && return
  # Subshell: a refusal (e.g. duplicate slug) exits non-zero — the TUI
  # must show the message and return to the picker, not die with it.
  (cmd_new_change "$title") || true
  ui_pause
}

# Interactive REPL — single screen via picker_run:
#   ⌕ Search prompt → column headers → list rows → padding →
#   summary → padding → action items.
# Cursor skips header/padding/summary; only row/action types are selectable.
main_page() {
  require_foundry
  if [[ "$UI_MODE" != "interactive" ]]; then
    ui_error "no args: pass a subcommand (list/show/new/move/setup) in --plain mode"
    exit 64
  fi

  PAGE_SORT="$(config_default_sort)"
  PAGE_REVERSE="$(config_default_reverse_flag)"

  trap 'clear; exit 0' INT

  while true; do
    local rows; rows=$(query_change_rows all)

    if [[ -z "$rows" ]]; then
      clear
      ui_header "Foundry" "empty"
      echo
      if ui_confirm "Add your first change now?"; then
        _new_change_dialog
      else
        clear; exit 0
      fi
      continue
    fi

    _main_page_entries
    # Two-line branded header (⭑ Foundry · tagline / project: [name]) —
    # identical bytes on every page, built by render_page_header.
    # shellcheck disable=SC2034  # read by picker_run
    PICKER_HEADER="$(render_page_header)"
    if picker_run "⌕  Search "; then
      local slug="$PICKER_RESULT_SLUG"
      case "$slug" in
        __more__*)
          list_page "${slug#__more__}" ;;
        __act_add__)
          _new_change_dialog ;;
        __act_sync__)
          (cmd_sync_indexes) || true ;;  # rebuild indexes; refusal must not kill the TUI
        __act_reload__)
          : ;;   # loop back, rebuild entries
        __act_exit__)
          _exit_confirm_dialog ;;
        '')
          : ;;   # non-selectable somehow — re-render
        *)
          detail_page "$slug" ;;
      esac
    else
      # esc — confirm exit
      _exit_confirm_dialog
    fi
  done
}
