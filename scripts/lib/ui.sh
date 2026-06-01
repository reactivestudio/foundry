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
    ok)      echo 40 ;;   # green — success, done bucket
    warn)    echo 214 ;;  # amber — in-progress
    danger)  echo 124 ;;  # red — error, declined
    *)       echo 7 ;;    # default
  esac
}

# ui_paint <color-name> <text...>
ui_paint() {
  local color; color=$(ui_color_code "$1"); shift
  if [[ "$UI_MODE" == "interactive" ]]; then
    printf '\033[38;5;%sm%s\033[0m' "$color" "$*"
  else
    printf '%s' "$*"
  fi
}

ui_dim()     { ui_paint dim     "$@"; }
ui_bright()  { ui_paint primary "$@"; }
ui_accent()  { ui_paint accent  "$@"; }

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
# Same-family glyphs render at consistent widths in monospace fonts.
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
    backlog)     echo muted ;;
    in-progress) echo warn ;;
    done)        echo ok ;;
    declined)    echo danger ;;
    *)           echo dim ;;
  esac
}

# Echo "<icon> <bucket>" colored.
ui_status() {
  local b="$1"
  ui_paint "$(ui_bucket_color "$b")" "$(ui_icon "$b") $b"
}

# Just the icon, colored.
ui_status_icon() {
  local b="$1"
  ui_paint "$(ui_bucket_color "$b")" "$(ui_icon "$b")"
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

