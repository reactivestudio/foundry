#!/usr/bin/env bash
# ui.sh — presentation primitives for bin/foundry.
#
# Source this; do not execute. Two modes:
#
#   interactive — gum-driven, colors, choose/input prompts. Default
#                 when stdout is a TTY and FOUNDRY_PLAIN is unset.
#   plain       — ASCII tables, no prompts, deterministic output for
#                 Claude Code / pipelines.
#
# Detection:
#   - FOUNDRY_PLAIN=1                → plain
#   - stdout not a TTY               → plain
#   - gum not on PATH                → plain (with one-time stderr note)
#   - else                           → interactive

if [[ -n "${FOUNDRY_PLAIN:-}" ]]; then
  UI_MODE=plain
elif [[ ! -t 1 ]]; then
  UI_MODE=plain
elif ! command -v gum >/dev/null 2>&1; then
  echo "foundry: gum not found, falling back to plain output (brew install gum)" >&2
  UI_MODE=plain
else
  UI_MODE=interactive
fi

# ─── status icons (UTF-8, rendered in both modes) ──────────────────────────
ui_icon() {
  case "$1" in
    backlog)     printf '○' ;;
    in-progress) printf '⊙' ;;
    done)        printf '●' ;;
    declined)    printf '⊗' ;;
    *)           printf '?' ;;
  esac
}

# ─── gum color for a bucket ────────────────────────────────────────────────
# Values are ANSI 256 color codes, picked to be readable on light/dark terms.
ui_color() {
  case "$1" in
    backlog)     printf '244' ;;  # dim gray
    in-progress) printf '214' ;;  # amber
    done)        printf '40'  ;;  # green
    declined)    printf '124' ;;  # red
    *)           printf '7'   ;;
  esac
}

# Echo "<icon> <bucket>" colored. Plain mode = no color codes.
ui_status() {
  local bucket="$1"
  local icon; icon=$(ui_icon "$bucket")
  if [[ "$UI_MODE" == "interactive" ]]; then
    gum style --foreground "$(ui_color "$bucket")" "$icon $bucket"
  else
    printf '%s %s' "$icon" "$bucket"
  fi
}

# Just the icon, colored (for compact use in tables).
ui_status_icon() {
  local bucket="$1"
  local icon; icon=$(ui_icon "$bucket")
  if [[ "$UI_MODE" == "interactive" ]]; then
    gum style --foreground "$(ui_color "$bucket")" "$icon"
  else
    printf '%s' "$icon"
  fi
}

# ─── section header ────────────────────────────────────────────────────────
ui_header() {
  local text="$*"
  if [[ "$UI_MODE" == "interactive" ]]; then
    gum style --bold --foreground 212 --border-foreground 240 \
      --border normal --padding "0 1" "$text"
  else
    printf '=== %s ===\n' "$text"
  fi
}

# ─── single info line ──────────────────────────────────────────────────────
ui_info() {
  if [[ "$UI_MODE" == "interactive" ]]; then
    gum style --foreground 244 "$*"
  else
    printf '%s\n' "$*"
  fi
}

# ─── error to stderr ───────────────────────────────────────────────────────
ui_error() {
  if [[ "$UI_MODE" == "interactive" ]]; then
    gum style --foreground 196 --bold "✗ $*" >&2
  else
    printf 'ERROR: %s\n' "$*" >&2
  fi
}

# ─── success ───────────────────────────────────────────────────────────────
ui_success() {
  if [[ "$UI_MODE" == "interactive" ]]; then
    gum style --foreground 40 "✓ $*"
  else
    printf '%s\n' "$*"
  fi
}

# ─── interactive prompts (no-op in plain mode — caller checks UI_MODE) ────

# ui_choose <header> <opt1> <opt2> ...
# Prints selected option to stdout. Returns 1 if user cancels.
ui_choose() {
  local header="$1"; shift
  if [[ "$UI_MODE" == "interactive" ]]; then
    gum choose --header "$header" "$@"
  else
    ui_error "ui_choose: interactive only; pass --to or use --plain with explicit arg"
    return 2
  fi
}

# ui_input <placeholder>
ui_input() {
  local placeholder="${1:-}"
  if [[ "$UI_MODE" == "interactive" ]]; then
    gum input --placeholder "$placeholder"
  else
    ui_error "ui_input: interactive only; pass the value as argument"
    return 2
  fi
}

# ui_confirm <question>
# Exit 0 = yes, 1 = no.
ui_confirm() {
  local question="$1"
  if [[ "$UI_MODE" == "interactive" ]]; then
    gum confirm "$question"
  else
    ui_error "ui_confirm: interactive only"
    return 2
  fi
}

# ─── table renderer ────────────────────────────────────────────────────────
# Input on stdin: TSV rows. First row = headers.
# In interactive: gum table with selection (echoes chosen row's first column).
# In plain: aligned columns, no selection.
#
# Usage:
#   printf 'BUCKET\tSLUG\tTITLE\n%s\t%s\t%s\n' ... | ui_table
ui_table() {
  if [[ "$UI_MODE" == "interactive" ]]; then
    # gum table reads CSV; convert TSV → CSV (best-effort: escape quotes)
    awk -F'\t' 'BEGIN{OFS=","} {
      for (i=1; i<=NF; i++) {
        gsub(/"/, "\"\"", $i)
        $i = "\"" $i "\""
      }
      print
    }' | gum table --print
  else
    column -t -s $'\t'
  fi
}
