#!/usr/bin/env bash
# render.sh — shared helper for rendering .template/ files.
#
# Source this file; do not execute it directly.
#
# Usage:
#   render_template <src> <dst> NAME=value [NAME=value ...]
#
# Reads the template at <src>, substitutes each __NAME__ marker with
# its corresponding value (literal — no regex escaping needed), and
# writes to <dst>.
#
# Substitution uses bash parameter expansion, so values containing
# &, /, |, $, etc. are safe — no sed-replacement hazards.

render_template() {
  local src="$1" dst="$2"
  shift 2

  [[ -f "$src" ]] || { echo "render_template: missing template: $src" >&2; return 2; }

  local content
  content=$(<"$src")

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

  printf '%s\n' "$content" > "$dst"
}
