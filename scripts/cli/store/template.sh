#!/usr/bin/env bash
# template.sh — shared helper for rendering .template/ files.
#
# Source this file; do not execute it directly.
#
# Usage:
#   render_template <source> <destination> NAME=value [NAME=value ...]
#
# Reads the template at <source>, substitutes each __NAME__ marker with
# its corresponding value (literal — no regex escaping needed), and
# writes to <destination>.
#
# Substitution uses bash parameter expansion, so values containing
# &, /, |, $, etc. are safe — no sed-replacement hazards.

# ...except that bash 5.2 (GNU/Linux) gave `&` a sed-style special
# meaning inside ${var//pattern/replacement} — it expands to the match,
# which would corrupt values containing '&' (caught by CI on ubuntu;
# macOS bash 3.2 has no such feature).  Turn it off for the whole
# sourcing process: the CLI targets 3.2 semantics everywhere.  The
# shopt doesn't exist before 5.2 — hence the silent fallback.
shopt -u patsub_replacement 2>/dev/null || true

render_template() {
  local source_file="$1" destination_file="$2"
  shift 2

  [[ -f "$source_file" ]] \
    || { echo "render_template: missing template: $source_file" >&2; return 2; }

  local content
  content=$(<"$source_file")

  local pair name value
  for pair in "$@"; do
    name="${pair%%=*}"
    value="${pair#*=}"
    if [[ "$name" == "$pair" ]]; then
      echo "render_template: bad pair '$pair' (expected NAME=value)" >&2
      return 2
    fi
    content="${content//__${name}__/$value}"
  done

  printf '%s\n' "$content" > "$destination_file"
}
