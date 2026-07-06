#!/usr/bin/env bash
# detail_page.sh — change-detail page + full-proposal reader.
#
# Source this file; do not execute it directly.
# Needs: query.sh, render/{table,brand_header,markdown,history,picker_widget,primitives}.sh,
# commands/move.sh, TRACKING_SH.
#
# NOTE: 0.33.0's _view_full_with_pager (piping into `less`) was deleted
# in 0.33.12 — users found the pager-driven view confusing.  Replaced by
# proposal_page below: a dedicated picker screen that stays inside the
# picker grammar end-to-end, so the user never sees less.

# Populate PICKER_* arrays for the change-detail page.  Layout mirrors
# the main page's grammar (same indent, same colour roles, same
# header/search) so navigating in/out reads as one continuous surface.
#
#   <padding>
#   <icon>  <bucket>  <change-title-bold>
#   <padding>
#   ꜱᴛᴀᴛᴜꜱ     <status>
#   ᴜᴘᴅᴀᴛᴇᴅ    <relative · full date>
#   ᴄʀᴇᴀᴛᴇᴅ    <full date>
#   [ʀᴇᴀꜱᴏɴ    <decline reason — declined bucket only>]
#   <padding>
#   ᴘʀᴏᴘᴏꜱᴀʟ        ← small caps, no dividers (user spec)
#   <padding>
#     line 1 of proposal.md
#     ... (up to 5 non-blank lines)
#   <padding>
#   ⏿  View...    ← action; only when there's more than the preview
#   <padding>
#   ʜɪꜱᴛᴏʀʏ
#   <padding>
#     <rel>  <actor>  <event>  <details>     (newest first)
#   <padding>
#   ▶  Start / ⏸ Pause / ✓ Finish / ↩ Revive / ×  Decline   (bucket-conditional)
#   ⇠  Back
#
# Section headings use ui_small_caps + fd_title — the same small-caps
# treatment as the main page's column headers, with fd_title (not
# dim) because section headings on a single-record screen organise
# the screen rather than label repeating columns.
_detail_page_entries() {
  local slug="$1" bucket="$2"
  local dir="$CHANGES_DIR/$bucket/$slug"
  query_change_fields "$dir"   # → CHANGE_TITLE/STATUS/CREATED/UPDATED/REASON

  picker_reset

  # ── META ──
  # Compact horizontal layout — small-caps column header row + a
  # single data row underneath, mirroring the main page's
  # STATUS / TITLE / CREATED / UPDATED column grammar.  Vertical
  # 5-row layout in 0.33.12 was tall for a screen with a long
  # proposal below; horizontal squeezes 5 fields into 2 rows.
  # Column widths picked to fit ~96 cells of terminal width:
  #   ɪᴅ      16 (truncate with …)
  #   ᴛɪᴛʟᴇ   24 (truncate with …)
  #   ꜱᴛᴀᴛᴜꜱ  12
  #   ᴜᴘᴅᴀᴛᴇᴅ 12 (relative only — "yesterday" / "2h ago")
  #   ᴄʀᴇᴀᴛᴇᴅ 18 (full date)
  # Full update timestamp dropped from the column — the relative
  # part is the actionable signal ("when did this change last
  # move?"), the absolute timestamp is still in tracking.yaml for
  # anyone who needs it.
  local _id_w=16 _title_w=24 _status_w=12 _updated_w=12
  local _id_trunc;   _id_trunc=$(ui_truncate "$_id_w" "$slug")
  local _title_trunc; _title_trunc=$(ui_truncate "$_title_w" "$CHANGE_TITLE")
  local _updated_str; _updated_str="$(ui_date_relative "$CHANGE_UPDATED")"
  local _created_str; _created_str="$(ui_date_full "$CHANGE_CREATED")"

  picker_push_padding
  # Header row — small caps + dim, padded to column widths.
  picker_push_info "$(printf '   %s  %s  %s  %s  %s' \
    "$(ui_dim "$(ui_pad_visual "$(ui_small_caps ID)"      "$_id_w")")" \
    "$(ui_dim "$(ui_pad_visual "$(ui_small_caps TITLE)"   "$_title_w")")" \
    "$(ui_dim "$(ui_pad_visual "$(ui_small_caps STATUS)"  "$_status_w")")" \
    "$(ui_dim "$(ui_pad_visual "$(ui_small_caps UPDATED)" "$_updated_w")")" \
    "$(ui_dim "$(ui_small_caps CREATED)")")"
  # Data row — per-column colours.  Same padded widths so columns line
  # up under their headers.
  picker_push_info "$(printf '   %s  %s  %s  %s  %s' \
    "$(ui_paint fd_chrome  "$(printf '%-*s' "$_id_w"      "$_id_trunc")")" \
    "$(ui_paint_bold fd_title "$(printf '%-*s' "$_title_w"  "$_title_trunc")")" \
    "$(ui_paint "$(ui_bucket_color "$bucket")" "$(printf '%-*s' "$_status_w" "$CHANGE_STATUS")")" \
    "$(ui_paint fd_updated "$(printf '%-*s' "$_updated_w" "$_updated_str")")" \
    "$(ui_paint fd_created "$_created_str")")"
  if [[ -n "$CHANGE_REASON" ]]; then
    # Decline reason wraps as its own labelled row underneath — too
    # long to fit horizontally on the same line.
    picker_push_info "$(printf '   %s  %s' \
      "$(ui_dim "$(printf '%-8s' 'reason')")" \
      "$(ui_paint "$(ui_bucket_color "$bucket")" "$CHANGE_REASON")")"
  fi

  # ── PROPOSAL ──
  # Heading: small caps + fd_title (ᴘʀᴏᴘᴏꜱᴀʟ).  Content: every source
  # line passes through render_markdown_line which STRIPS markers (#, -,
  # **, ``, [text](url), etc.) and wraps the result in ui_dim.
  # Pushed as filtered-info rows with a PLAIN TITLE so:
  #   1. ⌕ search hides non-matches (FILTERABLE=1)
  #   2. matches get a gold (fd_match 222) highlight on the substring
  #      that fired the filter — same affordance the main page has
  #      for row titles (cf. picker's info-type match-rebuild path).
  # Cursor never lands inside the proposal — type stays "info".
  if [[ -f "$dir/proposal.md" ]]; then
    picker_push_padding  # extra spacer (user asked +1 before heading)
    picker_push_padding
    picker_push_info "$(ui_paint fd_title "⛰  $(ui_small_caps PROPOSAL)")"
    picker_push_padding

    # Preview cap: render at most the first 5 NON-BLANK lines of the
    # proposal here on the detail page.  Blank lines between them
    # are preserved as paragraph breaks (they don't count against the
    # cap).  If the proposal has more than 5 visible lines we tack on
    # a "⏿ View..." action that opens the full document in
    # proposal_page; if everything fits, the View action is
    # suppressed entirely — no reason to expose a "view full" link
    # when the user is already looking at the full thing.
    local _src_lines=() _rendered_lines=() _plain_lines=()
    local _line
    while IFS= read -r _line || [[ -n "$_line" ]]; do
      _src_lines+=("$_line")
    done < "$dir/proposal.md"

    # Pre-render so each source line is processed exactly once: we
    # need rendered (for the entry), plain (for PICKER_TITLE / search
    # highlight), and a total-visible count to decide the View action.
    local _total_visible=0 _idx
    for _idx in "${!_src_lines[@]}"; do
      _rendered_lines[_idx]="$(render_markdown_line "${_src_lines[$_idx]}")"
      _plain_lines[_idx]="$(render_markdown_line "${_src_lines[$_idx]}" plain)"
      [[ -n "${_rendered_lines[$_idx]}" ]] && _total_visible=$((_total_visible + 1))
    done

    local _shown=0 _preview_cap=5
    for _idx in "${!_src_lines[@]}"; do
      (( _shown >= _preview_cap )) && break
      if [[ -z "${_rendered_lines[$_idx]}" ]]; then
        # Blank line → paragraph break, non-filterable info row.
        picker_push_info ''
      else
        picker_push_filtered_info "   ${_rendered_lines[$_idx]}" "${_plain_lines[$_idx]}"
        _shown=$((_shown + 1))
      fi
    done

    # "View..." action — only when there's more to view.  Eye glyph
    # ⏿ (U+23FF OBSERVER EYE SYMBOL) is pure unicode (no Nerd Font
    # cluster).  Opens proposal_page, a dedicated picker screen
    # with the full document + a single ⇠ Back action.
    if (( _total_visible > _preview_cap )); then
      picker_push_padding
      picker_push_action "$(ui_paint fd_chrome '⏿  View...')" "__view_proposal__"
      picker_push_padding  # extra spacer after View (user-asked +1)
    fi
  fi

  # ── HISTORY ──
  # Heading + small-caps column header + data rows all anchor at col 7
  # (3-cell indent + 3-cell picker prefix).
  if [[ -f "$dir/history.log" ]]; then
    picker_push_padding
    picker_push_info "$(ui_paint fd_title "⛙  $(ui_small_caps HISTORY)")"
    picker_push_padding

    picker_push_info "$(printf '   %s  %s  %s  %s' \
      "$(ui_dim "$(ui_pad_visual "$(ui_small_caps WHEN)" 12)")" \
      "$(ui_dim "$(ui_pad_visual "$(ui_small_caps ACTOR)" 14)")" \
      "$(ui_dim "$(ui_pad_visual "$(ui_small_caps EVENT)" 8)")" \
      "$(ui_dim "$(ui_small_caps CHANGE)")")"

    local history_lines=()
    local _line
    while IFS= read -r _line; do
      history_lines+=("$_line")
    done < <(render_history_newest_first "$dir/history.log")

    local history_line actor_color
    for history_line in "${history_lines[@]}"; do
      render_history_fields "$history_line"
      case "$HIST_ACTOR" in
        user)          actor_color=fd_done ;;
        state-machine) actor_color=fd_chrome ;;
        *)             actor_color=muted ;;
      esac
      picker_push_filtered_info "$(printf '   %s  %s  %s  %s' \
        "$(ui_paint fd_updated "$(printf '%-12s' "$HIST_REL")")" \
        "$(ui_paint "$actor_color" "$(printf '%-14s' "$HIST_ACTOR")")" \
        "$(ui_paint fd_title    "$(printf '%-8s'  "$HIST_EVENT")")" \
        "$(ui_paint fd_created  "$HIST_PRETTY")")"
      if [[ -n "$HIST_REASON" ]]; then
        # Reason wrap as a non-filterable info row — aligned under the
        # CHANGE column (3 indent + 12 when + 2 + 14 actor + 2 + 8 event + 2 = 43).
        picker_push_info "$(printf '   %42s%s' '' "$(ui_dim "\"$HIST_REASON\"")")"
      fi
    done
  fi

  # ── ACTION BAR (bottom) ──
  # Per user 0.33.14:
  # - in-progress's "Done" → "Finish" (Done stays exclusive to the
  #   backlog → done skip path; in-progress uses the active verb).
  # - labels stay plain — no parenthetical hints.
  # - ALL icons painted in fd_chrome to match the labels.  The
  #   previous bucket-target colour-coding (▶ orange, ✓ mint, etc.)
  #   was visually noisy next to the chrome labels — single-colour
  #   strip reads more like a tool bar.
  # +1 padding before the bar so it breathes off the HISTORY block.
  picker_push_padding
  picker_push_padding
  case "$bucket" in
    backlog)
      picker_push_action "$(ui_paint fd_chrome '▶  Start')" "__act_start__"
      picker_push_action "$(ui_paint fd_chrome '✓  Done')" "__act_finish__"
      picker_push_action "$(ui_paint fd_chrome '×  Decline')" "__act_decline__"
      ;;
    in-progress)
      picker_push_action "$(ui_paint fd_chrome '✓  Finish')" "__act_finish__"
      picker_push_action "$(ui_paint fd_chrome '⏸  Pause')" "__act_pause__"
      picker_push_action "$(ui_paint fd_chrome '×  Decline')" "__act_decline__"
      ;;
    done)
      : # terminal state — only Back below
      ;;
    declined)
      picker_push_action "$(ui_paint fd_chrome '↩  Revive')" "__act_revive__"
      ;;
  esac
  picker_push_action "$(ui_paint fd_chrome '⇠  Back')" "__act_back__"
}

# Drill into one change — picker-based detail page.  Same branded
# header (⭑ Foundry · subtitle / project: [name]) and ⌕  Search prompt
# as the main page, with the change's metadata, proposal preview,
# history preview, and an action bar inline as picker entries.  Loops
# until the user picks Back (or ESC) so an action that doesn't leave
# the screen (view full, decline-then-cancel) keeps the same cursor
# position re-rendered fresh.
detail_page() {
  local slug="$1"
  while true; do
    local bucket
    if ! bucket=$(query_bucket_of "$slug"); then
      # The change got moved out from under us (e.g. concurrent edit).
      # Bail back to the main page rather than rendering empty.
      return
    fi
    local dir="$CHANGES_DIR/$bucket/$slug"

    _detail_page_entries "$slug" "$bucket"

    # Branded header — identical bytes to the main page by
    # construction (same render_page_header call).
    # shellcheck disable=SC2034  # read by picker_run
    PICKER_HEADER="$(render_page_header)"

    if picker_run "⌕  Search "; then
      case "$PICKER_RESULT_SLUG" in
        __view_proposal__)
          # Dedicated picker screen — same header + ⌕ search, just the
          # proposal content rendered (markers stripped) and a single
          # ⇠ Back action.  Stays inside the picker grammar; no
          # external pager, no terminal-mode handoff.
          proposal_page "$slug" "$bucket"
          ;;
        __act_start__)
          cmd_move "$slug" --to=in-progress
          ui_pause
          ;;
        __act_finish__)
          cmd_move "$slug" --to=done
          ui_pause
          ;;
        __act_pause__)
          cmd_move "$slug" --to=backlog
          ui_pause
          ;;
        __act_revive__)
          cmd_move "$slug" --to=backlog
          ui_pause
          ;;
        __act_decline__)
          local reason
          reason=$(ui_input "Reason for declining" --header "Decline $slug") || reason=""
          if [[ -n "$reason" ]]; then
            cmd_move "$slug" --to=declined --reason="$reason"
            ui_pause
          fi
          ;;
        __act_back__)
          return
          ;;
        *)
          # Empty slug (Enter on a proposal/history info row) or an
          # unexpected sentinel — no-op: loop back, rebuild, re-render.
          ;;
      esac
    else
      # ESC from picker → back to main page.
      return
    fi
  done
}

# Dedicated full-proposal screen invoked when the user picks
# "⏿ View..." on the detail page.  Same header + ⌕ search as
# everywhere else, the proposal rendered inline (markers stripped),
# and a single ⇠ Back action.  Stays inside the picker grammar end-
# to-end — no pager, no less, no "press q" prompt.
proposal_page() {
  local slug="$1" bucket="$2"
  local dir="$CHANGES_DIR/$bucket/$slug"
  [[ -f "$dir/proposal.md" ]] || return

  while true; do
    picker_reset

    picker_push_padding
    picker_push_info "$(ui_paint fd_title "⛰  $(ui_small_caps PROPOSAL)")"
    picker_push_padding

    local _line _rendered _plain
    while IFS= read -r _line || [[ -n "$_line" ]]; do
      _rendered="$(render_markdown_line "$_line")"
      _plain="$(render_markdown_line "$_line" plain)"
      if [[ -z "$_rendered" ]]; then
        picker_push_info ''
      else
        # Pass the plain title so the ⌕ search match lights up gold
        # (fd_match 222) on this screen too — view-proposal had the
        # plain-title arg missing through 0.33.15, so its highlight
        # path never fired.  Detail page always passed it; this
        # closes the parity.
        picker_push_filtered_info "   $_rendered" "$_plain"
      fi
    done < "$dir/proposal.md"

    picker_push_padding
    picker_push_action "$(ui_paint fd_chrome '⇠  Back')" "__view_back__"

    # shellcheck disable=SC2034  # read by picker_run
    PICKER_HEADER="$(render_page_header)"

    if picker_run "⌕  Search "; then
      case "$PICKER_RESULT_SLUG" in
        __view_back__|'') return ;;
        *) ;;
      esac
    else
      return
    fi
  done
}
