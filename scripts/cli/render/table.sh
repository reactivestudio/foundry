#!/usr/bin/env bash
# table.sh — row/column formatting for lists and picker pages.
#
# Source this file; do not execute it directly.
# Needs: primitives.sh, BUCKETS (constants.sh), query_sort (store/query.sh).
#
# Two column geometries live here on purpose (do NOT unify):
#   render_list_widths   — plain `foundry list`, terminal capped at 100
#   render_picker_widths — picker pages, terminal capped at 140

# ── plain list (foundry list) ─────────────────────────────────────────────

# Resolve column widths from terminal size.
render_list_widths() {
  local terminal_columns; terminal_columns=$(ui_terminal_columns 120)
  local slug_width=28 updated_width=12
  local title_width=$(( terminal_columns - 4 - slug_width - 2 - updated_width - 4 ))
  (( title_width < 20 )) && title_width=20
  printf '%d %d %d' "$slug_width" "$title_width" "$updated_width"
}

# Render a single row of the list (icon + slug + title + age, all
# padded/colored). Used by both the grouped renderer and --bucket flat.
render_list_row() {
  local bucket="$1" slug="$2" title="$3" updated_epoch="$4"
  local slug_width="$5" title_width="$6" updated_width="$7"

  local updated_relative="?"
  if [[ "$updated_epoch" != "0" ]]; then
    local iso_timestamp; iso_timestamp=$(ui_epoch_to_iso "$updated_epoch")
    [[ -n "$iso_timestamp" ]] && updated_relative=$(ui_date_relative "$iso_timestamp")
  fi
  local slug_truncated; slug_truncated=$(ui_truncate "$slug_width" "$slug")
  local title_truncated; title_truncated=$(ui_truncate "$title_width" "$title")
  printf '  %s  %s  %s  %s\n' \
    "$(ui_status_icon "$bucket")" \
    "$(ui_bright "$(printf '%-*s' "$slug_width" "$slug_truncated")")" \
    "$(ui_paint fd_title "$(printf '%-*s' "$title_width" "$title_truncated")")" \
    "$(ui_paint fd_updated "$(printf '%-*s' "$updated_width" "$updated_relative")")"
}

# Render one bucket section: divider with name + count, capped rows,
# "⋯ +N more" footer when truncated. Skips empty buckets.
render_bucket_section() {
  local bucket="$1" all_rows="$2" sort_key="$3" reverse="$4" limit="$5"
  local bucket_rows; bucket_rows=$(printf '%s\n' "$all_rows" | query_filter_bucket "$bucket")
  [[ -z "$bucket_rows" ]] && return

  local row_count; row_count=$(ui_count_lines "$bucket_rows")

  printf '\n'
  ui_divider "$(ui_status "$bucket") · $row_count"

  bucket_rows=$(printf '%s\n' "$bucket_rows" | query_sort "$sort_key" "$reverse")

  local visible_rows="$bucket_rows"
  if (( row_count > limit )); then
    visible_rows=$(printf '%s\n' "$bucket_rows" | head -n "$limit")
  fi

  read -r slug_width title_width updated_width <<< "$(render_list_widths)"
  while IFS=$'\t' read -r row_bucket slug title _ updated_epoch _; do
    render_list_row "$row_bucket" "$slug" "$title" "$updated_epoch" "$slug_width" "$title_width" "$updated_width"
  done <<< "$visible_rows"

  if (( row_count > limit )); then
    local hidden_count=$((row_count - limit))
    printf '  %s  %s\n' \
      "$(ui_dim '⋯')" \
      "$(ui_dim "+$hidden_count more in $bucket — foundry list --bucket=$bucket")"
  fi
}

# ── picker pages ─────────────────────────────────────────────────────────

# Column widths used by picker rows, the column-header row and the
# "+N more" rows so everything aligns.
render_picker_widths() {
  local terminal_columns; terminal_columns=$(ui_terminal_columns 140)
  local bucket_width=12 created_width=18 updated_width=11
  local title_width=$(( terminal_columns - bucket_width - created_width - updated_width - 10 ))
  (( title_width < 20 )) && title_width=20
  printf '%d %d %d %d' "$bucket_width" "$title_width" "$created_width" "$updated_width"
}

# render_row_parts — populate per-row globals consumed by the page
# builders and by picker_run (for filter-match title highlighting).
# Side-effects:
#   ROW_LEFT       — painted "<icon>  <padded bucket>  " (icon in fd_icon)
#   ROW_LEFT_HOVER — same, but icon painted in fd_brand (cursor-on-row)
#   ROW_TITLE       — raw, ANSI-free, truncated title text (unpadded)
#   ROW_TITLE_WIDTH — visual width to pad title to (column alignment)
#   ROW_RIGHT       — painted "  <padded created>  <padded updated>"
# The page builders compose ROW_LEFT + painted(padded(ROW_TITLE)) +
# ROW_RIGHT into the display entry.  picker_run, when a filter is active
# and the title matches, re-paints the title slot with highlight ANSI
# around the match while keeping LEFT/RIGHT unchanged.
render_row_parts() {
  local bucket="$1" title="$2" updated_epoch="$3" created_epoch="$4"

  local bucket_width title_width created_width updated_width
  read -r bucket_width title_width created_width updated_width <<< "$(render_picker_widths)"

  local created_display="?" updated_display="?" iso_timestamp
  if [[ "$created_epoch" != "0" ]]; then
    iso_timestamp=$(ui_epoch_to_iso "$created_epoch")
    [[ -n "$iso_timestamp" ]] && created_display=$(ui_date_full "$iso_timestamp")
  fi
  if [[ "$updated_epoch" != "0" ]]; then
    iso_timestamp=$(ui_epoch_to_iso "$updated_epoch")
    [[ -n "$iso_timestamp" ]] && updated_display=$(ui_date_relative "$iso_timestamp")
  fi

  ROW_TITLE=$(ui_truncate "$title_width" "$title")
  ROW_TITLE_WIDTH=$title_width
  local _padded_bucket; _padded_bucket=$(printf '%-*s' "$bucket_width" "$bucket")
  local _icon_glyph; _icon_glyph=$(ui_icon "$bucket")
  ROW_LEFT=$(printf '%s  %s  ' \
    "$(ui_paint fd_icon "$_icon_glyph")" \
    "$(ui_paint "$(ui_bucket_color "$bucket")" "$_padded_bucket")")
  # ROW_LEFT_HOVER: same structure, but the status icon paints in
  # fd_brand instead of fd_icon — used when the cursor lands on this
  # row, so icon + title (re-painted in fd_brand by picker_run) read
  # as a single selector-coloured pair.  Bucket label keeps its per-
  # bucket colour so the bucket identity stays legible.
  ROW_LEFT_HOVER=$(printf '%s  %s  ' \
    "$(ui_paint fd_brand "$_icon_glyph")" \
    "$(ui_paint "$(ui_bucket_color "$bucket")" "$_padded_bucket")")
  ROW_RIGHT=$(printf '  %s  %s' \
    "$(ui_paint fd_created "$(printf '%-*s' "$created_width" "$created_display")")" \
    "$(ui_paint fd_updated "$(printf '%-*s' "$updated_width" "$updated_display")")")
}

# Build the column-header line for the custom picker. The picker prefixes
# each rendered row with "▸ " (cursor) or "  " (non-cursor) — 2 cells.
# Row content is then icon(1) + sep(2) + bucket, so bucket text starts at
# column 5. The column-header line has no icon, so 3 leading spaces here +
# 2 cells from the picker = 5 → STATUS aligns with "backlog".
# Small-caps via ui_pad_visual which counts visual cells (wc -m).
render_columns_row() {
  local bucket_width title_width created_width updated_width
  read -r bucket_width title_width created_width updated_width <<< "$(render_picker_widths)"
  printf '   %s  %s  %s  %s' \
    "$(ui_dim "$(ui_pad_visual "$(ui_small_caps STATUS)" "$bucket_width")")" \
    "$(ui_dim "$(ui_pad_visual "$(ui_small_caps TITLE)" "$title_width")")" \
    "$(ui_dim "$(ui_pad_visual "$(ui_small_caps CREATED)" "$created_width")")" \
    "$(ui_dim "$(ui_pad_visual "$(ui_small_caps UPDATED)" "$updated_width")")"
}

# Build a chrome row in the "+N more..." visual style — blank bucket
# cell, caller-supplied label painted in fd_more across the title
# cell, blank date cells.  Column widths come from render_picker_widths
# so alignment with real change rows is preserved.
#
# Used for:
#   - main-page bucket overflow ("+5 more...")
#   - bucket-view pagination       ("+N previous" / "+M next")
#
# fd_more is 256-palette 110 (#87afd7) — same baby-blue family as
# fd_title (153, #afd7ff) dropped roughly 15% in luminance, so these
# rows sit "under" real titles without falling into chrome-gray.
render_more_row() {
  local label="$1"
  local bucket_width title_width created_width updated_width
  read -r bucket_width title_width created_width updated_width <<< "$(render_picker_widths)"
  printf '   %s  %s  %s  %s' \
    "$(printf '%-*s' "$bucket_width" "")" \
    "$(ui_paint fd_more "$(printf '%-*s' "$title_width" "$label")")" \
    "$(printf '%-*s' "$created_width" "")" \
    "$(printf '%-*s' "$updated_width" "")"
}

# Build inline stats string — used both as a header second-line and as
# the (now-removed) bottom summary in earlier versions.  Output shape:
#   "N changes  ·  ○ a  ⊙ b  ● c  ⊗ d"
# Colors:
#   "N changes"       → ui_dim
#   "·" separator     → ui_dim
#   "<icon> <count>"  → per-bucket color (one painted segment so the ANSI
#                       reset doesn't bleed back to dim)
render_change_stats() {
  local total="$1" all_rows="$2"
  local stats_line
  stats_line="$(ui_dim "$total changes")"
  local bucket
  for bucket in "${BUCKETS[@]}"; do
    local bucket_count
    bucket_count=$(ui_count_lines "$(printf '%s\n' "$all_rows" | query_filter_bucket "$bucket")")
    stats_line+="  $(ui_dim '·')  $(ui_paint "$(ui_bucket_color "$bucket")" "$(ui_icon "$bucket") $bucket_count")"
  done
  printf '%s' "$stats_line"
}

# Bottom summary row — picker-formatted (leading indent matches the
# column-header / +N-more / row prefix so everything aligns).  Wraps
# render_change_stats.
render_summary_row() {
  printf '   %s' "$(render_change_stats "$1" "$2")"
}

# Render one change row and push it into the picker — the composition
# every page uses for its data rows (main and list pages must emit
# byte-identical rows).  Args: bucket slug title updated_epoch created_epoch.
render_push_change_row() {
  local bucket="$1" slug="$2" title="$3" updated_epoch="$4" created_epoch="$5"
  render_row_parts "$bucket" "$title" "$updated_epoch" "$created_epoch"
  local padded; padded=$(printf '%-*s' "$ROW_TITLE_WIDTH" "$ROW_TITLE")
  picker_push_row "${ROW_LEFT}$(ui_paint fd_title "$padded")${ROW_RIGHT}" \
    "$slug" "$bucket" "$ROW_TITLE" "$ROW_TITLE_WIDTH" \
    "$ROW_LEFT" "$ROW_LEFT_HOVER" "$ROW_RIGHT"
}
