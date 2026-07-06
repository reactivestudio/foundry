#!/usr/bin/env bash
# picker_widget.sh — custom interactive picker widget.
#
# Source this file; do not execute it directly.
# Needs: primitives.sh (ui_paint, ui_bright, ui_strip_ansi,
# ui_color_code, _ui_fg_seq).  Knows NOTHING about changes/buckets as
# domain objects — callers describe the page through the PICKER_*
# protocol below and get a selection back.
#
# Why custom: gum filter and fzf both visit every row with the cursor —
# no way to skip non-selectables (column headers, summary, padding) in
# the middle of the list.
#
# ── PICKER_* protocol ─────────────────────────────────────────────────────
# Input: 10 parallel arrays, one slot per display line.  Callers reset
# them with picker_reset and fill them with the picker_push_* helpers
# (which keep all arrays in lock-step — never push raw).
#
#   PICKER_ENTRIES[i]    — display line (may contain ANSI escapes)
#   PICKER_SLUGS[i]      — return key for selectables; "" otherwise
#   PICKER_TYPES[i]      — 'row' | 'action' | 'header' | 'padding'
#                          | 'summary' | 'info'
#   PICKER_FILTERABLE[i] — '1' to include line in text-filter; '0' to always show
#
# Per-row metadata (meaningful for type='row'; empty for the rest):
#   PICKER_BUCKET[i]     — bucket tag; powers Tab → jump to next bucket
#   PICKER_TITLE[i]      — raw title text (truncated, unpadded, no ANSI)
#   PICKER_TITLE_W[i]    — target visual width for padding the title cell
#   PICKER_LEFT[i]       — pre-painted "<icon>  <bucket>  " segment
#   PICKER_LEFT_HOVER[i] — same, icon recoloured for cursor-on-row
#   PICKER_RIGHT[i]      — pre-painted "  <created>  <updated>" segment
# When a filter is active and the row's title contains the filter substring
# (case-insensitive), the picker rebuilds the row from LEFT + highlighted
# title + RIGHT so the match appears in fd_match (pale gold) while the rest
# of the title stays in fd_title.
#
# Input: PICKER_HEADER — optional fully-painted multi-line header string
# (embedded "\n"); shifts the search prompt down.
#
# Output (set by picker_run on ↵): PICKER_RESULT_SLUG, PICKER_RESULT_ENTRY.
# picker_run returns 0 on ↵, 1 on ⎋.
#
# Keys:
#   ↑ / ↓     move cursor through selectables (type row/action only)
#   Tab       on 'row'    → jump to first selectable of the NEXT bucket
#             on 'action' → behave like ↓
#   ↵         select (sets PICKER_RESULT_SLUG and returns 0)
#   ⌫         delete one char from filter
#   ⎋         cancel (returns 1)
# Type-to-filter is always on: typed chars build a substring filter against
# filterable entries.  Non-filterable entries always show.

# Reset all protocol arrays — call before building a page.
picker_reset() {
  PICKER_ENTRIES=()
  PICKER_SLUGS=()
  PICKER_TYPES=()
  PICKER_FILTERABLE=()
  PICKER_BUCKET=()
  PICKER_TITLE=()
  PICKER_TITLE_W=()
  PICKER_LEFT=()
  PICKER_LEFT_HOVER=()
  PICKER_RIGHT=()
}

# Append empty placeholders to all per-row metadata arrays.  Keeps them
# parallel with PICKER_ENTRIES so the picker can index any slot safely.
# CRITICAL: every meta array must get a push per entry, including
# PICKER_LEFT_HOVER (which the cursor-hover render path indexes by
# absolute PICKER_ENTRIES index, not by row count).
_picker_meta_empty() {
  PICKER_BUCKET+=("")
  PICKER_TITLE+=("")
  PICKER_TITLE_W+=("0")
  PICKER_LEFT+=("")
  PICKER_LEFT_HOVER+=("")
  PICKER_RIGHT+=("")
}

# Blank spacer row — cursor skips it.
picker_push_padding() {
  PICKER_ENTRIES+=("")
  PICKER_SLUGS+=("")
  PICKER_TYPES+=("padding")
  PICKER_FILTERABLE+=("0")
  _picker_meta_empty
}

# Column-header row — display-only chrome above data rows.
picker_push_header() {
  PICKER_ENTRIES+=("$1")
  PICKER_SLUGS+=("")
  PICKER_TYPES+=("header")
  PICKER_FILTERABLE+=("0")
  _picker_meta_empty
}

# Summary/stats row — display-only chrome below data rows.
picker_push_summary() {
  PICKER_ENTRIES+=("$1")
  PICKER_SLUGS+=("")
  PICKER_TYPES+=("summary")
  PICKER_FILTERABLE+=("0")
  _picker_meta_empty
}

# Info row — display-only, cursor skips over it.  Used in detail-view
# for headings (PROPOSAL, HISTORY) and rendered metadata lines.
picker_push_info() {
  PICKER_ENTRIES+=("$1")
  PICKER_SLUGS+=("")
  PICKER_TYPES+=("info")
  PICKER_FILTERABLE+=("0")
  _picker_meta_empty
}

# Action row — cursor lands on it; selecting returns $2 as the slug.
# Optional $3 (filterable, default 0) lets a chrome action hide while
# the user is searching ("+N more").  Optional $4 tags the action with
# a bucket so Tab-navigation treats it as part of that bucket's block.
picker_push_action() {
  PICKER_ENTRIES+=("$1")
  PICKER_SLUGS+=("$2")
  PICKER_TYPES+=("action")
  PICKER_FILTERABLE+=("${3:-0}")
  PICKER_BUCKET+=("${4:-}")
  PICKER_TITLE+=("")
  PICKER_TITLE_W+=("0")
  PICKER_LEFT+=("")
  PICKER_LEFT_HOVER+=("")
  PICKER_RIGHT+=("")
}

# Filterable info row — same as picker_push_info but FILTERABLE=1 so
# the ⌕ search prompt hides non-matching rows.  Cursor still skips
# (type stays "info").
#
# Optional $2 (plain title) drives the picker's filter-match HIGHLIGHT:
# when set, the picker rebuilds the entry on match as dim prefix + gold
# matched substring + dim suffix.  Omit $2 if you want filter to *hide*
# non-matches but preserve the entry's per-column ANSI on matches
# (history rows: column colours stay on matches because we don't ask
# for the dim rebuild).
picker_push_filtered_info() {
  PICKER_ENTRIES+=("$1")
  PICKER_SLUGS+=("")
  PICKER_TYPES+=("info")
  PICKER_FILTERABLE+=("1")
  PICKER_BUCKET+=("")
  PICKER_TITLE+=("${2:-}")
  PICKER_TITLE_W+=("${#2}")
  PICKER_LEFT+=("")
  PICKER_LEFT_HOVER+=("")
  PICKER_RIGHT+=("")
}

# Data row — cursor lands on it; selecting returns $2 (the slug).
# Args: entry slug bucket title title_w left left_hover right
picker_push_row() {
  PICKER_ENTRIES+=("$1")
  PICKER_SLUGS+=("$2")
  PICKER_TYPES+=("row")
  PICKER_FILTERABLE+=("1")
  PICKER_BUCKET+=("$3")
  PICKER_TITLE+=("$4")
  PICKER_TITLE_W+=("$5")
  PICKER_LEFT+=("$6")
  PICKER_LEFT_HOVER+=("$7")
  PICKER_RIGHT+=("$8")
}

# ── picker_run internals ──────────────────────────────────────────────────
# The _picker_* helpers below are NOT standalone: they execute inside
# picker_run and read/write its locals through bash dynamic scoping —
# the only way to split a bash function without leaking real globals.
# Each header lists the caller locals it writes.

# Pre-derive everything that doesn't depend on the filter or cursor so
# the per-frame loop stays in pure bash — no sed/tr forks during render.
# Writes (caller's): entries_lc[], entries_brand[], title_lc[].
#   entries_lc[i]     — ANSI-stripped lowercase for substring filtering
#   entries_brand[i]  — entry recoloured in fd_brand (used when the
#                       cursor lands on an action item)
#   title_lc[i]       — lowercase raw title for filter-match highlighting
_picker_init_caches() {
  local i stripped
  for (( i = 0; i < n_total; i++ )); do
    stripped=""
    if [[ "${PICKER_FILTERABLE[$i]}" == "1" || "${PICKER_TYPES[$i]}" == "action" ]]; then
      stripped=$(printf '%s' "${PICKER_ENTRIES[$i]}" | ui_strip_ansi)
    fi
    if [[ "${PICKER_FILTERABLE[$i]}" == "1" ]]; then
      entries_lc[i]=$(printf '%s' "$stripped" | tr '[:upper:]' '[:lower:]')
    else
      entries_lc[i]=""
    fi
    if [[ "${PICKER_TYPES[$i]}" == "action" ]]; then
      entries_brand[i]=$(ui_paint fd_brand "$stripped")
    else
      entries_brand[i]=""
    fi
    # title_lc populates for any row whose caller set PICKER_TITLE —
    # both row (data picks) and info (filterable-info content, e.g.
    # proposal lines on the detail page).  The frame renderer uses
    # title_lc + PICKER_TITLE to splice in the filter-match highlight
    # on either type.
    if [[ -n "${PICKER_TITLE[$i]:-}" ]]; then
      title_lc[i]=$(printf '%s' "${PICKER_TITLE[$i]}" | tr '[:upper:]' '[:lower:]')
    else
      title_lc[i]=""
    fi
  done
}

# Resolve every SGR fragment / painted chrome string exactly once.
# Writes (caller's): _brand_fmt, _title_dim_fmt, _dim_fmt, _match_fmt,
# prompt_painted, _caret_seq, cursor_arrow.  Reads: prompt_label.
#
# CRITICAL: fragments are built via `printf -v` (not single-quote
# literals) so the `\033` in the format string is interpreted as the
# real ESC byte — otherwise printf %s in the title format would emit
# it as 4 literal characters (`\`, `0`, `3`, `3`), which the user
# reported in 0.33.2 as "\033[38;5;27mSome change 4" showing up
# verbatim in the title cell.  All colours resolve through the palette
# (primitives.sh) so a change there propagates without a second edit.
_picker_init_styles() {
  # Brand colour for cursor hover (row-title + action-label and the
  # row's status icon via PICKER_LEFT_HOVER).
  local _brand_code; _brand_code=$(ui_color_code fd_brand)
  if [[ "$_brand_code" == \#* ]]; then
    printf -v _brand_fmt '\033[%sm' "$(_ui_fg_seq "$_brand_code")"
  else
    printf -v _brand_fmt '\033[38;5;%sm' "$_brand_code"
  fi
  printf -v _title_dim_fmt '\033[38;5;%sm' "$(ui_color_code fd_title)"
  printf -v _dim_fmt '\033[38;5;%sm' "$(ui_color_code muted)"
  printf -v _match_fmt '\033[38;5;%sm' "$(ui_color_code fd_match)"

  # ⌕ + "Search" share the brand colour (fd_search); the caret a few
  # columns to the right is painted in the matching fd_caret slot.
  prompt_painted=$(ui_paint fd_search "$prompt_label")
  local _caret_code; _caret_code=$(ui_color_code fd_caret)
  _caret_seq=$(_ui_fg_seq "$_caret_code")
  # Selector arrow on the cursor row.  ➤ (U+27A4 BLACK RIGHTWARDS
  # ARROWHEAD) — solid filled, heavier than the previous ▸ small
  # triangle so the user can see "this is the selected row" at a
  # glance.  Painted in fd_brand so the selector reads as part of the
  # Foundry brand identity (matches ⭑ + "Foundry" + ⌕ + caret).
  cursor_arrow=$(ui_paint fd_brand '➤')
}

# Fork the caret blink sidecar.  A background process drives the caret
# animation while the main loop blocks on read() — a thin ▏ in
# fd_search for 1 s, then a blank space for 1 s, ≈ 0.5 Hz blink.
# Writes (caller's): anim_col_file, anim_pid.  Reads: caret_row, _caret_seq.
#
# Coordination: before drawing a full frame the main loop SIGSTOPs the
# animator so its writes can't interleave with the frame's bytes, then
# SIGCONTs after the frame and the new cursor column have been written.
# Cleanup on exit: rm the col file (animator loop sees missing file and
# exits), then SIGTERM, then wait.
_picker_spawn_caret() {
  anim_col_file=$(mktemp -t fdcaret 2>/dev/null || mktemp)
  printf '%d' 14 > "$anim_col_file"

  # Capture caret_row in a child-safe variable.  The subshell forks
  # with `set +eu` so an unbound `caret_row` shouldn't abort, but
  # explicit shadow keeps the printf format from receiving an empty
  # string if anything weird happens with scope across the `&`.
  local _ar="$caret_row"
  local _cs="$_caret_seq"
  (
    # The subshell inherits set -euo pipefail from the parent; disable so
    # transient failures (kill races on parent shutdown, tmp-file read
    # blips) can't tear down the animator prematurely.
    set +euo pipefail
    trap 'exit 0' TERM INT
    _row="${_ar:-2}"
    _seq="${_cs:-38;5;99}"
    phase=0
    while [[ -f "$anim_col_file" ]]; do
      col=$(<"$anim_col_file" 2>/dev/null) || break
      # If the read landed mid-update (file truncated to 0 bytes before
      # the new column was written) OR yielded a non-integer, skip this
      # tick rather than painting at a stale fallback column.  The old
      # `[[ -z "$col" ]] && col=14` line was the cause of "caret stuck
      # at column 14 covering the first typed char" — when the race
      # fired the caret got nailed to position 14 regardless of filter
      # length.
      if [[ -z "$col" || ! "$col" =~ ^[0-9]+$ ]]; then
        sleep 1
        continue
      fi
      # Slow 2-phase blink — 1 s bright, 1 s blank = 2 s total = 0.5 Hz.
      # Each printf goes directly to /dev/tty per call (bypasses libc's
      # line-buffered subshell stdout, which was stranding bytes between
      # sleeps).  Colour comes from fd_caret — matches the brand strip
      # so the caret reads as "Foundry's" cursor, not a generic one.
      case "$phase" in
        0) printf '\033[%s;%sH\033[%sm▏\033[0m' "$_row" "$col" "$_seq" >/dev/tty ;;
        1) printf '\033[%s;%sH \033[0m'         "$_row" "$col"         >/dev/tty ;;
      esac
      phase=$(( (phase + 1) % 2 ))
      sleep 1
    done
  ) </dev/null >/dev/null 2>/dev/null &
  anim_pid=$!
}

# Recompute the visible set under the current filter and place the
# cursor.  Writes (caller's): vis_idx[], sel_idx[], n_sel, cursor,
# current; clears _first_render / _filter_changed.
_picker_filter_pass() {
  local i
  vis_idx=(); sel_idx=()
  for (( i = 0; i < n_total; i++ )); do
    if [[ "${PICKER_FILTERABLE[$i]}" == "1" && -n "$filter_lc" ]]; then
      [[ "${entries_lc[$i]}" != *"$filter_lc"* ]] && continue
    fi
    vis_idx+=("$i")
    if [[ "${PICKER_TYPES[$i]}" == "row" || "${PICKER_TYPES[$i]}" == "action" ]]; then
      sel_idx+=("$((${#vis_idx[@]} - 1))")
    fi
  done

  n_sel=${#sel_idx[@]}
  if (( n_sel == 0 )); then
    cursor=0
  else
    if (( _first_render )) || (( _filter_changed )); then
      # Two conditions, same jump:
      #   _first_render   — initial cursor placement: skip action
      #                     items, land on first data row.
      #   _filter_changed — user typed into / backspaced the search
      #                     prompt; jump to the first content row
      #                     that survived the filter so the user
      #                     immediately sees the match they're
      #                     looking for highlighted.
      # Falls through to cursor=0 if no row-type selectables exist
      # in the filtered set (e.g. all proposal lines hidden by an
      # unmatched query — cursor lands on the first action, which
      # for the detail view is "← Back").
      local _k _vi _ei
      for (( _k = 0; _k < n_sel; _k++ )); do
        _vi="${sel_idx[$_k]}"
        _ei="${vis_idx[$_vi]}"
        if [[ "${PICKER_TYPES[$_ei]}" == "row" ]]; then
          cursor=$_k
          break
        fi
      done
    fi
    (( cursor >= n_sel )) && cursor=$((n_sel - 1))
    (( cursor < 0 )) && cursor=0
  fi
  _first_render=0
  _filter_changed=0
  current=-1
  (( n_sel > 0 )) && current="${sel_idx[$cursor]}"
}

# Compose one frame in one printf and hand the animator its new caret
# column.  Reads the caches + style fragments; writes nothing the
# caller keeps between frames.
#
# \033[H\033[2J replaces the external `clear`.  3 leading spaces
# (was 4 pre-0.32.9) so ⬢ on the brand strip and ⌕ on the prompt
# both anchor at col 4, while "foundry" / "Search" / "STATUS" all
# share col 7.  A bright caret is painted once here; the sidecar
# animator overwrites it on its next tick to continue the pulse.
# When PICKER_HEADER is set, the header sits on rows 2..2+n with
# a blank buffer row, pushing the prompt down by (1 + n_lines).
_picker_render_frame() {
  local frame=$'\033[H\033[2J\n'
  if [[ -n "$picker_header" ]]; then
    frame+=$'   '"${picker_header}"$'\n\n'
  fi
  # NB: explicit ' ' before the caret SGR.  Without it the caret ▏
  # glues onto either the trailing space of "Search " (when filter
  # is empty) or the last typed character (when not).  The extra
  # space lives outside `ui_bright "$filter"` so the caret column
  # math (prompt_cols = 14) stays in step.
  frame+=$'   '"${prompt_painted}$(ui_bright "$filter") "$'\033['"${_caret_seq}m"$'▏\033[0m\n\n\n'
  local j idx row_render is_cursor
  for (( j = 0; j < ${#vis_idx[@]}; j++ )); do
    idx="${vis_idx[$j]}"
    is_cursor=0
    (( j == current )) && is_cursor=1
    # Title colour on rows:
    #   default (no cursor, no filter match) → ${PICKER_ENTRIES[i]} verbatim
    #   filter match, no cursor              → fd_title + fd_match splice
    #   cursor on row                        → _brand_fmt (fd_brand) for
    #                                          the title AND the status
    #                                          icon (via PICKER_LEFT_HOVER)
    # action items get the entire label re-painted in fd_brand via
    # entries_brand[idx] so the action label matches the brand-coloured
    # selector arrow on its left.
    if [[ "${PICKER_TYPES[$idx]}" == "row" ]]; then
      local _has_match=0 _use_left
      # `:-` defaults guard against any builder path that pushes
      # to PICKER_ENTRIES but skips the parallel hover array.
      # Without the default, set -u would abort on an unbound
      # array element when the cursor lands on such a row.
      _use_left="${PICKER_LEFT[$idx]:-}"
      (( is_cursor )) && _use_left="${PICKER_LEFT_HOVER[$idx]:-$_use_left}"
      if [[ -n "$filter_lc" && -n "${title_lc[$idx]}" \
            && "${title_lc[$idx]}" == *"$filter_lc"* ]]; then
        _has_match=1
      fi
      if (( _has_match || is_cursor )); then
        local _t _tw _title_fmt
        _t="${PICKER_TITLE[$idx]}"
        _tw="${PICKER_TITLE_W[$idx]}"
        if (( is_cursor )); then
          _title_fmt="$_brand_fmt"
        else
          _title_fmt="$_title_dim_fmt"
        fi
        # NB: split assignments — bash 3.2 evaluates `local a=… b=$((…a…))`
        # right-to-left through the outer scope, which trips set -u when
        # `a` doesn't exist there yet.
        local _vlen _pad _padding
        _vlen=${#_t}
        _pad=$((_tw - _vlen))
        (( _pad < 0 )) && _pad=0
        printf -v _padding '%*s' "$_pad" ''
        if (( _has_match )); then
          local _lc _before_lc _pos _mlen _pre _mat _suf _hl
          _lc="${title_lc[$idx]}"
          _before_lc="${_lc%%"$filter_lc"*}"
          _pos=${#_before_lc}
          _mlen=${#filter_lc}
          _pre="${_t:0:_pos}"
          _mat="${_t:_pos:_mlen}"
          _suf="${_t:_pos+_mlen}"
          # title-fmt prefix → fd_match → title-fmt suffix → pad, reset
          printf -v _hl '%s%s%s%s%s%s%s\033[0m' \
            "$_title_fmt" "$_pre" "$_match_fmt" "$_mat" "$_title_fmt" "$_suf" "$_padding"
          row_render="${_use_left}${_hl}${PICKER_RIGHT[$idx]}"
        else
          # Cursor on row, no filter match — recolour title via title-fmt.
          local _ti
          printf -v _ti '%s%s%s\033[0m' "$_title_fmt" "$_t" "$_padding"
          row_render="${_use_left}${_ti}${PICKER_RIGHT[$idx]}"
        fi
      else
        row_render="${PICKER_ENTRIES[$idx]}"
      fi
    elif [[ "${PICKER_TYPES[$idx]}" == "info" \
            && -n "$filter_lc" \
            && -n "${title_lc[$idx]:-}" \
            && "${title_lc[$idx]:-}" == *"$filter_lc"* ]]; then
      # Info row with caller-supplied plain title that matched the
      # filter — rebuild the visible line as 3-cell indent + dim
      # prefix + fd_match match + dim suffix + reset.
      # PICKER_ENTRIES gets discarded for this frame; info rows
      # don't carry the LEFT/RIGHT split that row-type uses, so
      # the rebuild is the full line, not a splice.
      local _it _ilc _ibefore _ipos _imlen _ipre _imat _isuf _ihl
      _it="${PICKER_TITLE[$idx]:-}"
      _ilc="${title_lc[$idx]:-}"
      _ibefore="${_ilc%%"$filter_lc"*}"
      _ipos=${#_ibefore}
      _imlen=${#filter_lc}
      _ipre="${_it:0:_ipos}"
      _imat="${_it:_ipos:_imlen}"
      _isuf="${_it:_ipos+_imlen}"
      printf -v _ihl '   %s%s%s%s%s%s\033[0m' \
        "$_dim_fmt" "$_ipre" "$_match_fmt" "$_imat" "$_dim_fmt" "$_isuf"
      row_render="$_ihl"
    else
      row_render="${PICKER_ENTRIES[$idx]}"
    fi
    if (( is_cursor )); then
      if [[ "${PICKER_TYPES[$idx]}" == "action" ]]; then
        # :- default for action entries that didn't get a
        # pre-derived entries_brand[] slot (any builder path that
        # bypassed the standard init loop).  Falls back to the
        # already-coloured PICKER_ENTRIES.
        frame+=" ${cursor_arrow} ${entries_brand[$idx]:-${PICKER_ENTRIES[$idx]}}"$'\n'
      else
        frame+=" ${cursor_arrow} ${row_render}"$'\n'
      fi
    else
      frame+="   ${row_render}"$'\n'
    fi
  done
  printf '%s' "$frame"

  # Tell the animator the new caret column.  Atomic write via tmp + mv
  # — a bare `> "$anim_col_file"` truncates the file to 0 bytes BEFORE
  # the new content is written, opening a tiny race window where the
  # animator's read sees an empty string.  The previous fallback to
  # col=14 hid the race as "caret stuck at column 14".  mv is atomic
  # on the same filesystem so the animator only ever sees a fully-
  # written old or fully-written new value.
  local cur_col=$((prompt_cols + 1 + ${#filter}))
  printf '%d' "$cur_col" > "${anim_col_file}.tmp"
  mv -f "${anim_col_file}.tmp" "$anim_col_file"
}

# Tab semantics: on a row jump to the first selectable of the NEXT
# bucket; on an action item (or anywhere with no bucket) behave like ↓.
# Writes (caller's): cursor.
_picker_jump_next_bucket() {
  (( n_sel > 0 )) || return 0
  local _cv="${sel_idx[$cursor]}" _co
  _co="${vis_idx[$_cv]}"
  local _ctype="${PICKER_TYPES[$_co]}" _cbuck="${PICKER_BUCKET[$_co]:-}"
  if [[ "$_ctype" == "action" || -z "$_cbuck" ]]; then
    cursor=$(( (cursor + 1) % n_sel ))
    return 0
  fi
  local _target="$cursor" _k _kv _ko _kb
  for (( _k = 1; _k <= n_sel; _k++ )); do
    local _cand=$(( (cursor + _k) % n_sel ))
    _kv="${sel_idx[$_cand]}"
    _ko="${vis_idx[$_kv]}"
    _kb="${PICKER_BUCKET[$_ko]:-}"
    # First selectable with a different bucket (or no bucket,
    # i.e. an action) — land there.
    if [[ "$_kb" != "$_cbuck" ]]; then
      _target="$_cand"; break
    fi
  done
  cursor="$_target"
}

# ── picker_run — the event loop ───────────────────────────────────────────
# Orchestration only: set up terminal state, delegate to the _picker_*
# helpers above, run read-key → update-state → redraw until ↵ or ⎋.
# shellcheck disable=SC2034  # PICKER_RESULT_* are the widget's output contract
picker_run() {
  local prompt_label="${1:-⌕ Search }"

  local filter="" filter_lc="" cursor=0
  # First-render flag — used once by the filter pass to snap the
  # initial cursor onto the first 'row' selectable instead of the
  # first 'action'.  Matters for the list page's "+N previous"
  # pagination entry which sits ABOVE the data rows when page > 1;
  # without this nudge the cursor would land on the prev-page button
  # and Enter would accidentally page backwards.
  local _first_render=1
  # Filter-changed flag — set when the user types into or backspaces
  # the search box.  Triggers the same "jump cursor to first 'row'
  # selectable" logic as _first_render, so typing in search snaps the
  # cursor onto the first matching content row (proposal line /
  # history entry in the detail view).  Cleared after the rebuild.
  local _filter_changed=0
  local stty_save; stty_save=$(stty -g)
  stty -echo -icanon
  # Hide the hardware cursor — we draw our own ▏ thin bar so we control
  # its color (fd_search neon purple) and blink rate.  Terminals can't
  # repaint their native caret with a custom colour, so faking it is
  # the only way.
  printf '\033[?25l'

  PICKER_RESULT_SLUG=""
  PICKER_RESULT_ENTRY=""
  local rc=0
  local n_total=${#PICKER_ENTRIES[@]}

  # Per-picker caches + style fragments (helpers fill these locals).
  local -a entries_lc=() entries_brand=() title_lc=()
  local _brand_fmt _title_dim_fmt _dim_fmt _match_fmt
  local prompt_painted _caret_seq cursor_arrow
  _picker_init_caches
  _picker_init_styles

  # Optional N-line header above the search prompt.  Callers set
  # PICKER_HEADER (a fully-painted, ANSI-styled string with embedded
  # "\n" between lines) to brand the page.  When set, the prompt row
  # shifts down by (1 + n_lines): header occupies rows 2..(1+n_lines),
  # then a blank, then the prompt on (3 + n_lines).
  #   no header  → caret_row = 2
  #   1-line     → caret_row = 4
  #   2-line     → caret_row = 5
  local picker_header="${PICKER_HEADER:-}"
  local caret_row=2
  if [[ -n "$picker_header" ]]; then
    local _nl_only="${picker_header//[^$'\n']}"
    local _n_header_lines=$((${#_nl_only} + 1))
    caret_row=$((3 + _n_header_lines))
  fi

  local anim_col_file anim_pid
  _picker_spawn_caret

  # Prompt cell layout (0.32.23 — extra gap before the caret):
  #   col 1-3 : leading indent (3 spaces)
  #   col 4   : ⌕            (search icon)
  #   col 5-6 : 2 gap spaces
  #   col 7-12: "Search"    (anchor — aligns with STATUS / foundry)
  #   col 13  : trailing space   ← from prompt_label "⌕ Search "
  #   col 14  : breathing space  ← new in 0.32.23 (the explicit ' ' in
  #             the frame renderer)
  #   col 15  : caret  (when filter is empty)
  # When the user types, the caret slides right by ${#filter} chars,
  # always with one breathing space between the typed text and ▏ — no
  # more "Search [foo]▏" gluing.  prompt_cols = 14 so that
  #   caret_col = prompt_cols + 1 + ${#filter} = 15 (empty),
  # which matches the static frame's column index.
  local prompt_cols=14

  local needs_full_redraw=1
  local n_sel=0 current=-1
  local -a vis_idx=() sel_idx=()

  while true; do
    if (( needs_full_redraw )); then
      # Freeze the animator so its mid-tick write can't tear the frame,
      # resume once the frame and the new caret column are out.
      # `|| true` because under set -e a missing pid would abort the
      # loop; if the animator already died, we keep going pulseless.
      kill -STOP "$anim_pid" 2>/dev/null || true
      _picker_filter_pass
      _picker_render_frame
      kill -CONT "$anim_pid" 2>/dev/null || true
      needs_full_redraw=0
    fi

    # Block on read — sidecar handles caret pulse in background.  The
    # `|| true` masks read's non-zero return on EOF / signal interrupt so
    # set -e doesn't unwind the picker; an empty key is then treated as
    # Enter, which is what would normally happen anyway.
    local key=""
    IFS= read -rsn1 key || true

    if [[ -z "$key" ]]; then
      # `read -n1` returns rc=0 with empty $key when the line terminator
      # (Enter) arrives — the delimiter is consumed but not stored.
      if (( n_sel > 0 )); then
        local orig_idx="${vis_idx[$current]}"
        PICKER_RESULT_SLUG="${PICKER_SLUGS[$orig_idx]}"
        PICKER_RESULT_ENTRY="${PICKER_ENTRIES[$orig_idx]}"
      fi
      break
    fi

    case "$key" in
      $'\e')
        # Arrow key (ESC [ A/B) or bare ESC.  Bash 3.2 has no fractional
        # `read -t`; stty min/time peeks the rest of the sequence.
        stty -icanon min 0 time 1
        local seq="" dir=""
        IFS= read -rsn1 seq
        if [[ "$seq" == '[' ]]; then
          IFS= read -rsn1 dir
        fi
        stty -icanon min 1 time 0
        if [[ "$seq" == '[' ]]; then
          case "$dir" in
            A) (( n_sel > 0 )) && cursor=$(( (cursor - 1 + n_sel) % n_sel )) ;;
            B) (( n_sel > 0 )) && cursor=$(( (cursor + 1) % n_sel )) ;;
          esac
        else
          rc=1; break
        fi ;;
      $'\t')
        _picker_jump_next_bucket ;;
      $'\x7f'|$'\b')
        filter="${filter%?}"
        filter_lc="${filter_lc%?}"
        cursor=0
        _filter_changed=1 ;;
      [[:print:]])
        filter+="$key"
        # tr fork happens once per keypress (human-paced), not per frame.
        filter_lc+=$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')
        cursor=0
        _filter_changed=1 ;;
    esac
    needs_full_redraw=1
  done

  # Stop the animator before restoring terminal state.  All three calls
  # tolerate failure — the animator may have died on its own already.
  rm -f "$anim_col_file" 2>/dev/null || true
  kill "$anim_pid" 2>/dev/null || true
  wait "$anim_pid" 2>/dev/null || true

  stty "$stty_save" 2>/dev/null || true
  printf '\033[?25h'  # show hardware cursor again
  return $rc
}
