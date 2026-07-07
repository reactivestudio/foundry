#!/usr/bin/env bash
# markdown.sh — strip-render markdown lines for terminal display.
#
# Source this file; do not execute it directly.
# Needs: primitives.sh (ui_dim).

# Render one source line of markdown to display-ready text.  Per the
# user's 0.33.12 spec ("просто чтобы не было элементов разметки MD"):
# this is a *strip* — markers come out, everything wraps in ui_dim,
# no per-element styling (no bold headings, no bullet glyphs, no
# fence rules, no inline bold/italic spans).  The proposal reads as
# one plain paragraph stream; the user said full MD rendering was
# overkill.
#
#   "# h1" / "## h2" / ...   → "h1" / "h2" (marker dropped)
#   "- item" / "* " / "+ "    → "item"
#   "1. item"                 → "item"
#   "> quote"                 → "quote"
#   "```..."                  → empty
#   "**bold**"                → "bold"
#   "*italic*"                → "italic"
#   "`code`"                  → "code"
#   "[text](url)"             → "text"
#   blank                     → blank
#
# Mode arg $2:
#   (empty)  — painted: result wraps in ui_dim, ready to display
#   plain    — unpainted: the *visible* text only, for PICKER_TITLE
#              (the picker substring-slices it on filter match to
#              splice in the gold-on-match highlight)
#
# Caller still wraps the painted result in `   ` indent + push_info.
render_markdown_line() {
  local line="$1" mode="${2:-}"
  case "$line" in
    '###### '*) line="${line#'###### '}" ;;
    '##### '*)  line="${line#'##### '}" ;;
    '#### '*)   line="${line#'#### '}" ;;
    '### '*)    line="${line#'### '}" ;;
    '## '*)     line="${line#'## '}" ;;
    '# '*)      line="${line#'# '}" ;;
    '- '*|'* '*|'+ '*)  line="${line:2}" ;;
    '> '*)      line="${line#'> '}" ;;
    '```'*)     line='' ;;
  esac
  # ordered list — strip "N. " prefix
  if [[ "$line" =~ ^[0-9]+\.\ (.*)$ ]]; then
    line="${BASH_REMATCH[1]}"
  fi
  # inline marker strip (order matters: ** before *); single quotes are
  # deliberate — the backticks are sed literals, nothing should expand
  # shellcheck disable=SC2016
  line=$(printf '%s' "$line" | sed -E \
    's/\*\*([^*]+)\*\*/\1/g; s/`([^`]+)`/\1/g; s/\[([^]]+)\]\([^)]+\)/\1/g; s/\*([^*]+)\*/\1/g')
  if [[ -z "$line" ]]; then
    printf ''
  elif [[ "$mode" == "plain" ]]; then
    printf '%s' "$line"
  else
    printf '%s' "$(ui_dim "$line")"
  fi
}
