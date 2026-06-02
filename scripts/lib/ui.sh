#!/usr/bin/env bash
# ui.sh — presentation primitives for the foundry CLI.
#
# Two modes:
#   interactive — gum-driven; colored cells, panels, prompts. Default
#                 when stdout is a TTY and FOUNDRY_PLAIN is unset.
#   plain       — ASCII, no colors, no prompts. For Claude Code,
#                 pipelines, dumb terminals.
#
# Design notes (CLI UX practice):
#   - vertical whitespace: a blank line before/after every block
#   - color hierarchy: bright = primary data; default = secondary;
#     dim = labels & metadata
#   - icons are colored consistently with bucket meaning
#   - long strings truncate with ellipsis at fixed widths
#   - empty states give the next action verbatim

# ── mode detection ─────────────────────────────────────────────────────────
if [[ -n "${FOUNDRY_PLAIN:-}" ]]; then
  UI_MODE=plain
elif [[ ! -t 1 ]]; then
  UI_MODE=plain
elif ! command -v gum >/dev/null 2>&1; then
  echo "foundry: gum not found, falling back to plain (brew install gum)" >&2
  UI_MODE=plain
else
  UI_MODE=interactive
fi

# ── colors (ANSI 256) ──────────────────────────────────────────────────────
# Semantic names — readable on light AND dark. macOS bash 3.2 has no
# associative arrays, so this is a case lookup.
ui_color_code() {
  case "$1" in
    primary) echo 255 ;;  # near-white — main data values
    muted|dim) echo 244 ;;# mid-gray — labels, metadata
    subtle)  echo 240 ;;  # dark-gray — separators, dim text
    accent)  echo 212 ;;  # pink — header titles
    ok)      echo 40 ;;   # green — success
    warn)    echo 214 ;;  # amber
    danger)  echo 124 ;;  # red
    # ── foundry brand palette (user-approved) ──
    fd_icon)        echo 153 ;;  # baby blue — status circles + titles
    fd_title)       echo 153 ;;  # alias for clarity
    fd_created)     echo 121 ;;  # softer mint #87FFAF — created date column
    fd_updated)     echo 141 ;;  # electric lavender
    fd_chrome)      echo 117 ;;  # sky blue — action buttons + "+N more" + chrome
    fd_backlog)     echo 105 ;;  # soft indigo
    fd_inprogress)  echo 215 ;;  # warm orange
    fd_done)        echo 121 ;;  # soft mint
    fd_declined)    echo 218 ;;  # pale pink
    # 256-palette codes (not hex) for brand + dates — macOS Terminal.app's
    # truecolor pipeline silently desaturates ~half of `\e[38;2;…m`
    # sequences (a known long-standing rendering bug); its built-in 256
    # palette renders reliably.  Each chosen code below is the nearest
    # palette colour to the original target, so the visual identity
    # holds: vivid violet brand, electric-blue project, coral search,
    # softer mint dates.
    fd_search)      echo 99 ;;   # vivid blue-violet #875fff — matches fd_brand (user-aligned)
    fd_caret)       echo 99 ;;   # vivid blue-violet #875fff — matches fd_brand
    fd_match)       echo 222 ;;  # pale gold #ffd787 — search-match highlight in titles
    fd_brand)       echo 99 ;;   # vivid blue-violet #875fff — star + "Foundry"
    fd_project)     echo 33 ;;   # electric blue #0087ff — project name in header
    fd_more)        echo 103 ;;  # gray with subtle blue lift #8787af — "+N more" rows
    *)       echo 7 ;;
  esac
}

# Expand a colour code into the SGR fragment that selects it.  Codes
# beginning with '#' are 6-digit hex truecolor (24-bit) and expand to
# "38;2;R;G;B"; plain numerics expand to "38;5;N" (256-colour palette).
# Used by ui_paint / ui_paint_bold so callers can request exact hex
# values for a few brand-critical slots without giving up the palette
# names everywhere else.
_ui_fg_seq() {
  local c="$1"
  if [[ "$c" == \#* ]]; then
    local hex="${c#\#}"
    printf '38;2;%d;%d;%d' \
      "$((16#${hex:0:2}))" "$((16#${hex:2:2}))" "$((16#${hex:4:2}))"
  else
    printf '38;5;%s' "$c"
  fi
}

# ui_paint <color-name> <text...>
ui_paint() {
  local color; color=$(ui_color_code "$1"); shift
  if [[ "$UI_MODE" == "interactive" ]]; then
    printf '\033[%sm%s\033[0m' "$(_ui_fg_seq "$color")" "$*"
  else
    printf '%s' "$*"
  fi
}

ui_dim()     { ui_paint dim     "$@"; }
ui_bright()  { ui_paint primary "$@"; }
ui_accent()  { ui_paint accent  "$@"; }

# Same as ui_paint but prepends SGR 1 (bold) before the colour.  Plain
# mode passes through as-is.
ui_paint_bold() {
  local color; color=$(ui_color_code "$1"); shift
  if [[ "$UI_MODE" == "interactive" ]]; then
    printf '\033[1;%sm%s\033[0m' "$(_ui_fg_seq "$color")" "$*"
  else
    printf '%s' "$*"
  fi
}

# Wrap text with SGR 5 (blink). Modern macOS Terminal, iTerm2, Alacritty and
# WezTerm honor it; on terminals that ignore SGR 5 the text just stays
# static (graceful degradation).
ui_blink() {
  if [[ "$UI_MODE" == "interactive" ]]; then
    printf '\033[5m%s\033[25m' "$*"
  else
    printf '%s' "$*"
  fi
}

# Strip ISO-8601 noise: "2026-06-01T11:39:32Z" → "2026-06-01 11:39:32"
ui_format_ts() {
  local t="$1"
  t="${t/T/ }"
  echo "${t%Z}"
}

# Format ISO-8601 with strftime — handles macOS BSD date and GNU date.
# Falls back to original string when both fail.
ui_date_format() {
  local ts="$1" fmt="$2"
  date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$ts" "$fmt" 2>/dev/null \
    || date -u -d "$ts" "$fmt" 2>/dev/null \
    || echo "$ts"
}

# ISO-8601 → epoch (UTC). Echoes 0 on parse failure.
ui_ts_to_epoch() {
  local ts="$1"
  date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null \
    || date -u -d "$ts" +%s 2>/dev/null \
    || echo 0
}

# Human-readable age: "just now", "5m ago", "3h ago", "yesterday",
# "3d ago", "Mon Jun 1".
ui_date_relative() {
  local ts="$1"
  local then; then=$(ui_ts_to_epoch "$ts")
  if [[ "$then" == "0" ]]; then echo "$ts"; return; fi
  local now; now=$(date -u +%s)
  local d=$((now - then))
  if   (( d < 0 ));       then echo "in future"
  elif (( d < 60 ));      then echo "just now"
  elif (( d < 3600 ));    then echo "$((d/60))m ago"
  elif (( d < 86400 ));   then echo "$((d/3600))h ago"
  elif (( d < 172800 ));  then echo "yesterday"
  elif (( d < 604800 ));  then echo "$((d/86400))d ago"
  else ui_date_format "$ts" "+%a %b %-d"
  fi
}

# Compact absolute: "Mon Jun 1, 11:40"
ui_date_short() { ui_date_format "$1" "+%a %b %-d, %H:%M"; }

# Full format for the list view: "Mon, May 27, 23:30"
ui_date_full() { ui_date_format "$1" "+%a, %b %-d, %H:%M"; }

# Replace letters with their Unicode small-caps equivalents. Used for
# column headers and date strings to give a visually-smaller "font"
# look (the closest CLI can do without actual font sizing). Plain
# mode passes through unchanged so Claude / pipelines stay greppable.
ui_small_caps() {
  local text="$1"
  if [[ "$UI_MODE" != "interactive" ]]; then
    printf '%s' "$text"; return
  fi
  text=$(printf '%s' "$text" | tr 'A-Z' 'a-z')
  text="${text//a/ᴀ}"
  text="${text//b/ʙ}"
  text="${text//c/ᴄ}"
  text="${text//d/ᴅ}"
  text="${text//e/ᴇ}"
  text="${text//f/ꜰ}"
  text="${text//g/ɢ}"
  text="${text//h/ʜ}"
  text="${text//i/ɪ}"
  text="${text//j/ᴊ}"
  text="${text//k/ᴋ}"
  text="${text//l/ʟ}"
  text="${text//m/ᴍ}"
  text="${text//n/ɴ}"
  text="${text//o/ᴏ}"
  text="${text//p/ᴘ}"
  text="${text//q/ǫ}"
  text="${text//r/ʀ}"
  text="${text//s/ꜱ}"
  text="${text//t/ᴛ}"
  text="${text//u/ᴜ}"
  text="${text//v/ᴠ}"
  text="${text//w/ᴡ}"
  text="${text//y/ʏ}"
  text="${text//z/ᴢ}"
  printf '%s' "$text"
}

# Section divider — "─── title ──────────────────────" or just dashes.
ui_divider() {
  local title="${1:-}"
  local width; width=${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}
  (( width > 100 )) && width=100
  local dash_count
  if [[ -n "$title" ]]; then
    dash_count=$(( width - ${#title} - 6 ))
    (( dash_count < 4 )) && dash_count=4
    local dashes; printf -v dashes '%*s' "$dash_count" ''
    dashes="${dashes// /─}"
    printf '  %s %s %s\n' \
      "$(ui_dim '───')" \
      "$(ui_paint primary "$title")" \
      "$(ui_dim "$dashes")"
  else
    local dashes; printf -v dashes '%*s' "$((width - 2))" ''
    printf '  %s\n' "$(ui_dim "${dashes// /─}")"
  fi
}

# ── status icons + per-bucket color ────────────────────────────────────────
# Small consistent-width glyphs — all 1 cell in monospace, accept the
# smaller visual size in exchange for guaranteed alignment.
ui_icon() {
  case "$1" in
    backlog)     printf '○' ;;  # U+25CB WHITE CIRCLE
    in-progress) printf '⊙' ;;  # U+2299 CIRCLED DOT OPERATOR
    done)        printf '●' ;;  # U+25CF BLACK CIRCLE
    declined)    printf '⊗' ;;  # U+2297 CIRCLED TIMES
    *)           printf '?' ;;
  esac
}

# Strip ANSI color codes — used to parse a colored picker row.
ui_strip_ansi() {
  sed -E $'s/\033\\[[0-9;]*[a-zA-Z]//g'
}

ui_bucket_color() {
  case "$1" in
    backlog)     echo fd_backlog ;;
    in-progress) echo fd_inprogress ;;
    done)        echo fd_done ;;
    declined)    echo fd_declined ;;
    *)           echo dim ;;
  esac
}

# Echo "<icon> <bucket>" — icon in baby blue, label in per-bucket color.
ui_status() {
  local b="$1"
  printf '%s %s' \
    "$(ui_paint fd_icon "$(ui_icon "$b")")" \
    "$(ui_paint "$(ui_bucket_color "$b")" "$b")"
}

# Just the icon, in the shared baby-blue.
ui_status_icon() {
  local b="$1"
  ui_paint fd_icon "$(ui_icon "$b")"
}

# ── header (used at top of every command output) ───────────────────────────
# ui_header <title> [subtitle]
ui_header() {
  local title="$1" sub="${2:-}"
  if [[ "$UI_MODE" == "interactive" ]]; then
    if [[ -n "$sub" ]]; then
      printf '\n%s  %s\n\n' "$(ui_accent "$title")" "$(ui_dim "$sub")"
    else
      printf '\n%s\n\n' "$(ui_accent "$title")"
    fi
  else
    if [[ -n "$sub" ]]; then
      printf '\n%s  %s\n\n' "$title" "$sub"
    else
      printf '\n%s\n\n' "$title"
    fi
  fi
}

# ── key-value lines (sectioned show output) ────────────────────────────────
# Usage: ui_kv <label-width> <key> <value>
ui_kv() {
  local w="$1" key="$2" value="$3"
  printf '  %s  %s\n' \
    "$(printf '%-*s' "$w" "$(ui_dim "$key")")" \
    "$(ui_bright "$value")"
}

# ── single info / success / error lines ────────────────────────────────────
ui_info()    { printf '  %s\n' "$(ui_dim "$*")"; }
ui_success() { printf '  %s %s\n' "$(ui_paint ok '✓')" "$*"; }
ui_warn()    { printf '  %s %s\n' "$(ui_paint warn '!')" "$*" >&2; }
ui_error()   { printf '  %s %s\n' "$(ui_paint danger '✗')" "$*" >&2; }

# ── truncation with ellipsis ───────────────────────────────────────────────
# ui_truncate <max> <text>
ui_truncate() {
  local max="$1" text="$2"
  if (( ${#text} > max )); then
    printf '%s…' "${text:0:max-1}"
  else
    printf '%s' "$text"
  fi
}

# Pad a string to visual width $2 (counting multi-byte UTF-8 chars as 1 cell).
# Plain bash `%-*s` pads by byte count, which breaks alignment for small-caps
# headers (each glyph is 3 bytes but 1 cell).
ui_pad_visual() {
  local s="$1" n="$2"
  local vlen
  vlen=$(printf '%s' "$s" | LC_ALL=en_US.UTF-8 wc -m | tr -d ' ')
  local pad=$((n - vlen))
  (( pad < 0 )) && pad=0
  printf '%s%*s' "$s" "$pad" ""
}

# ── interactive prompts (caller should branch on UI_MODE before use) ──────

ui_choose() {
  local header="$1"; shift
  if [[ "$UI_MODE" == "interactive" ]]; then
    gum choose --header "$header" "$@"
  else
    ui_error "ui_choose: interactive only"
    return 2
  fi
}

ui_input() {
  local placeholder="${1:-}"
  if [[ "$UI_MODE" == "interactive" ]]; then
    gum input --placeholder "$placeholder"
  else
    ui_error "ui_input: interactive only"
    return 2
  fi
}

ui_confirm() {
  local question="$1"
  if [[ "$UI_MODE" == "interactive" ]]; then
    gum confirm "$question"
  else
    ui_error "ui_confirm: interactive only"
    return 2
  fi
}

