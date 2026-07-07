#!/usr/bin/env bash
# brand_header.sh — branded header for picker pages.
#
# Source this file; do not execute it directly.
# Needs: primitives.sh (ui_paint_bold, ui_dim).

# Build the brand header shown above the search prompt.  Two lines:
#
#     ⭑  Foundry  ·  <subtitle>
#        project: <name>
#
# Line 1:
#   ⭑            — brand mark, bold, in fd_brand (#443199 royal purple)
#   Foundry      — app name, bold, same fd_brand colour
#   ·            — dim separator
#   <subtitle>   — caller-supplied per-page description, already painted
#
# Line 2 (caller-supplied, already painted) — typically
# "project: <name>".  No tree-branch glyph: the user explicitly asked
# for that to come off.
#
# Returns a string with embedded "\n" between the two lines.  picker_run
# counts the newlines to figure out where to put the caret.
render_brand_header() {
  local subtitle="${1:-}"      # already-painted text supplied by the caller
  local second_line="${2:-}"   # already-painted text supplied by the caller
  local header
  # ⭑ and "Foundry" rendered bold via ui_paint_bold.  As of 0.32.23 the
  # bold SGR is emitted in its own CSI (see primitives.sh) — Terminal.app was
  # silently dropping the bold attribute when bundled with the
  # extended-foreground SGR in a single CSI in 0.32.22.  Colour comes
  # from fd_brand → 256 palette code 27 (#005fff, electric blue with
  # faint green lift) — picked from a 15-row preview after both
  # palette 57 and truecolor #5800FF mis-rendered in the user's
  # Terminal.app profile.
  header="$(ui_paint_bold fd_brand '⭑')  "
  header+="$(ui_paint_bold fd_brand 'Foundry')"
  if [[ -n "$subtitle" ]]; then
    header+="  $(ui_dim '·')  ${subtitle}"
  fi
  if [[ -n "$second_line" ]]; then
    # 18-space indent so line 2 starts at column 19 — flush under the
    # first character of the subtitle (currently "Code change…"), not
    # under the 'F' of Foundry.  Layout reference: cols 1-3 frame
    # indent, col 4 ⭑, cols 5-6 spaces, cols 7-13 "Foundry", cols
    # 14-15 spaces, col 16 "·", cols 17-18 spaces, col 19 first char
    # of subtitle.
    header+=$'\n                  '"$second_line"
  fi
  printf '%s' "$header"
}

# The standard two-line header every page uses — identical bytes on
# main / bucket / detail / proposal so navigating between them reads as
# one continuous surface.  Callers do:
#   PICKER_HEADER="$(render_page_header)"
render_page_header() {
  local _project _project_line
  _project=$(basename "$PWD")
  _project_line="$(ui_dim 'project:')  $(ui_paint_bold fd_project "[${_project}]")"
  render_brand_header \
    "$(ui_dim 'Code change registry — propose, track, implement, ship')" "$_project_line"
}
