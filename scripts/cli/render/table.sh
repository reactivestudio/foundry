#!/usr/bin/env bash
# table.sh — row/column formatting for lists and picker pages.
#
# Source this file; do not execute it directly.
# Needs: primitives.sh, BUCKETS (constants.sh), query_sort (spec/query.sh).
#
# Two column geometries live here on purpose (do NOT unify):
#   render_list_widths   — plain `foundry list`, terminal capped at 100
#   render_picker_widths — picker pages, terminal capped at 140

# ── plain list (foundry list) ─────────────────────────────────────────────

# Resolve column widths from terminal size.
render_list_widths() {
  local cols; cols=$(ui_term_cols 120)
  local slug_w=28 upd_w=12
  local title_w=$(( cols - 4 - slug_w - 2 - upd_w - 4 ))
  (( title_w < 20 )) && title_w=20
  printf '%d %d %d' "$slug_w" "$title_w" "$upd_w"
}

# Render a single row of the list (icon + slug + title + age, all
# padded/colored). Used by both the grouped renderer and --bucket flat.
render_list_row() {
  local bucket="$1" slug="$2" title="$3" epoch="$4"
  local slug_w="$5" title_w="$6" upd_w="$7"

  local rel="?"
  if [[ "$epoch" != "0" ]]; then
    local iso; iso=$(ui_epoch_to_iso "$epoch")
    [[ -n "$iso" ]] && rel=$(ui_date_relative "$iso")
  fi
  local s_t; s_t=$(ui_truncate "$slug_w" "$slug")
  local t_t; t_t=$(ui_truncate "$title_w" "$title")
  printf '  %s  %s  %s  %s\n' \
    "$(ui_status_icon "$bucket")" \
    "$(ui_bright "$(printf '%-*s' "$slug_w" "$s_t")")" \
    "$(ui_paint fd_title "$(printf '%-*s' "$title_w" "$t_t")")" \
    "$(ui_paint fd_updated "$(printf '%-*s' "$upd_w" "$rel")")"
}

# Render one bucket section: divider with name + count, capped rows,
# "⋯ +N more" footer when truncated. Skips empty buckets.
render_bucket_section() {
  local bucket="$1" all_rows="$2" sort_key="$3" reverse="$4" limit="$5"
  local bucket_rows; bucket_rows=$(printf '%s\n' "$all_rows" | query_filter_bucket "$bucket")
  [[ -z "$bucket_rows" ]] && return

  local n; n=$(ui_count_lines "$bucket_rows")

  printf '\n'
  ui_divider "$(ui_status "$bucket") · $n"

  bucket_rows=$(printf '%s\n' "$bucket_rows" | query_sort "$sort_key" "$reverse")

  local show="$bucket_rows"
  if (( n > limit )); then
    show=$(printf '%s\n' "$bucket_rows" | head -n "$limit")
  fi

  read -r slug_w title_w upd_w <<< "$(render_list_widths)"
  while IFS=$'\t' read -r row_bucket slug title _ updated_epoch _; do
    render_list_row "$row_bucket" "$slug" "$title" "$updated_epoch" "$slug_w" "$title_w" "$upd_w"
  done <<< "$show"

  if (( n > limit )); then
    local more=$((n - limit))
    printf '  %s  %s\n' \
      "$(ui_dim '⋯')" \
      "$(ui_dim "+$more more in $bucket — foundry list --bucket=$bucket")"
  fi
}

# ── picker pages ─────────────────────────────────────────────────────────

# Column widths used by picker rows, the column-header row and the
# "+N more" rows so everything aligns.
render_picker_widths() {
  local cols; cols=$(ui_term_cols 140)
  local bucket_w=12 created_w=18 updated_w=11
  local title_w=$(( cols - bucket_w - created_w - updated_w - 10 ))
  (( title_w < 20 )) && title_w=20
  printf '%d %d %d %d' "$bucket_w" "$title_w" "$created_w" "$updated_w"
}

# render_row_parts — populate per-row globals consumed by the page
# builders and by picker_run (for filter-match title highlighting).
# Side-effects:
#   ROW_LEFT       — painted "<icon>  <padded bucket>  " (icon in fd_icon)
#   ROW_LEFT_HOVER — same, but icon painted in fd_brand (cursor-on-row)
#   ROW_TITLE      — raw, ANSI-free, truncated title text (unpadded)
#   ROW_TITLE_W    — visual width to pad title to (column alignment)
#   ROW_RIGHT      — painted "  <padded created>  <padded updated>"
# The page builders compose ROW_LEFT + painted(padded(ROW_TITLE)) +
# ROW_RIGHT into the display entry.  picker_run, when a filter is active
# and the title matches, re-paints the title slot with highlight ANSI
# around the match while keeping LEFT/RIGHT unchanged.
render_row_parts() {
  local bucket="$1" title="$2" upd_epoch="$3" crt_epoch="$4"

  local bucket_w title_w created_w updated_w
  read -r bucket_w title_w created_w updated_w <<< "$(render_picker_widths)"

  local created_str="?" updated_str="?" iso
  if [[ "$crt_epoch" != "0" ]]; then
    iso=$(ui_epoch_to_iso "$crt_epoch")
    [[ -n "$iso" ]] && created_str=$(ui_date_full "$iso")
  fi
  if [[ "$upd_epoch" != "0" ]]; then
    iso=$(ui_epoch_to_iso "$upd_epoch")
    [[ -n "$iso" ]] && updated_str=$(ui_date_relative "$iso")
  fi

  ROW_TITLE=$(ui_truncate "$title_w" "$title")
  ROW_TITLE_W=$title_w
  local _padded_b; _padded_b=$(printf '%-*s' "$bucket_w" "$bucket")
  local _icon_glyph; _icon_glyph=$(ui_icon "$bucket")
  ROW_LEFT=$(printf '%s  %s  ' \
    "$(ui_paint fd_icon "$_icon_glyph")" \
    "$(ui_paint "$(ui_bucket_color "$bucket")" "$_padded_b")")
  # ROW_LEFT_HOVER: same structure, but the status icon paints in
  # fd_brand instead of fd_icon — used when the cursor lands on this
  # row, so icon + title (re-painted in fd_brand by picker_run) read
  # as a single selector-coloured pair.  Bucket label keeps its per-
  # bucket colour so the bucket identity stays legible.
  ROW_LEFT_HOVER=$(printf '%s  %s  ' \
    "$(ui_paint fd_brand "$_icon_glyph")" \
    "$(ui_paint "$(ui_bucket_color "$bucket")" "$_padded_b")")
  ROW_RIGHT=$(printf '  %s  %s' \
    "$(ui_paint fd_created "$(printf '%-*s' "$created_w" "$created_str")")" \
    "$(ui_paint fd_updated "$(printf '%-*s' "$updated_w" "$updated_str")")")
}

# Build the column-header line for the custom picker. The picker prefixes
# each rendered row with "▸ " (cursor) or "  " (non-cursor) — 2 cells.
# Row content is then icon(1) + sep(2) + bucket, so bucket text starts at
# column 5. The column-header line has no icon, so 3 leading spaces here +
# 2 cells from the picker = 5 → STATUS aligns with "backlog".
# Small-caps via ui_pad_visual which counts visual cells (wc -m).
render_columns_row() {
  local bucket_w title_w created_w updated_w
  read -r bucket_w title_w created_w updated_w <<< "$(render_picker_widths)"
  printf '   %s  %s  %s  %s' \
    "$(ui_dim "$(ui_pad_visual "$(ui_small_caps STATUS)" "$bucket_w")")" \
    "$(ui_dim "$(ui_pad_visual "$(ui_small_caps TITLE)" "$title_w")")" \
    "$(ui_dim "$(ui_pad_visual "$(ui_small_caps CREATED)" "$created_w")")" \
    "$(ui_dim "$(ui_pad_visual "$(ui_small_caps UPDATED)" "$updated_w")")"
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
  local bucket_w title_w created_w updated_w
  read -r bucket_w title_w created_w updated_w <<< "$(render_picker_widths)"
  printf '   %s  %s  %s  %s' \
    "$(printf '%-*s' "$bucket_w" "")" \
    "$(ui_paint fd_more "$(printf '%-*s' "$title_w" "$label")")" \
    "$(printf '%-*s' "$created_w" "")" \
    "$(printf '%-*s' "$updated_w" "")"
}

# Build inline stats string — used both as a header second-line and as
# the (now-removed) bottom summary in earlier versions.  Output shape:
#   "N changes  ·  ○ a  ⊙ b  ● c  ⊗ d"
# Colors:
#   "N changes"       → ui_dim
#   "·" separator     → ui_dim
#   "<icon> <count>"  → per-bucket color (one painted segment so the ANSI
#                       reset doesn't bleed back to dim)
render_stats() {
  local total="$1" all_rows="$2"
  local s
  s="$(ui_dim "$total changes")"
  local bucket
  for bucket in "${BUCKETS[@]}"; do
    local cnt; cnt=$(ui_count_lines "$(printf '%s\n' "$all_rows" | query_filter_bucket "$bucket")")
    s+="  $(ui_dim '·')  $(ui_paint "$(ui_bucket_color "$bucket")" "$(ui_icon "$bucket") $cnt")"
  done
  printf '%s' "$s"
}

# Bottom summary row — picker-formatted (leading indent matches the
# column-header / +N-more / row prefix so everything aligns).  Wraps
# render_stats.
render_summary_row() {
  printf '   %s' "$(render_stats "$1" "$2")"
}

# Render one change row and push it into the picker — the composition
# every page uses for its data rows (main and list pages must emit
# byte-identical rows).  Args: bucket slug title updated_epoch created_epoch.
render_push_change_row() {
  local bucket="$1" slug="$2" title="$3" upd_epoch="$4" crt_epoch="$5"
  render_row_parts "$bucket" "$title" "$upd_epoch" "$crt_epoch"
  local padded; padded=$(printf '%-*s' "$ROW_TITLE_W" "$ROW_TITLE")
  picker_push_row "${ROW_LEFT}$(ui_paint fd_title "$padded")${ROW_RIGHT}" \
    "$slug" "$bucket" "$ROW_TITLE" "$ROW_TITLE_W" \
    "$ROW_LEFT" "$ROW_LEFT_HOVER" "$ROW_RIGHT"
}
