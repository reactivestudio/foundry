#!/usr/bin/env bash
# constants.sh — single source of truth for framework constants:
# the bucket registry (order, icon, colour slot).
#
# Source this file; do not execute it directly. Sourcing makes the
# arrays available in the caller's shell (bash arrays don't survive
# export across subshells).
#
# Adding a bucket = edit THIS file (array + both lookups), the
# transition table in spec/state-machine.sh, and — only if it needs a
# brand-new colour — a palette slot in render/primitives.sh.

# Buckets a change can live in. Order is significant for `list` output
# (backlog first, terminal states last).
# shellcheck disable=SC2034  # read by every layer that iterates buckets
BUCKETS=(backlog in-progress 'done' declined)

# Status glyph per bucket — small consistent-width glyphs, all 1 cell
# in monospace; the smaller visual size buys guaranteed alignment.
bucket_icon() {
  case "$1" in
    backlog)     printf '○' ;;  # U+25CB WHITE CIRCLE
    in-progress) printf '⊙' ;;  # U+2299 CIRCLED DOT OPERATOR
    done)        printf '●' ;;  # U+25CF BLACK CIRCLE
    declined)    printf '⊗' ;;  # U+2297 CIRCLED TIMES
    *)           printf '?' ;;
  esac
}

# True iff $1 is a registered bucket.
bucket_valid() {
  local bucket="$1" known_bucket
  for known_bucket in "${BUCKETS[@]}"; do
    [[ "$bucket" == "$known_bucket" ]] && return 0
  done
  return 1
}

# Palette-slot name per bucket — resolved to an actual colour by
# ui_color_code in render/primitives.sh.
bucket_color() {
  case "$1" in
    backlog)     echo fd_backlog ;;
    in-progress) echo fd_inprogress ;;
    done)        echo fd_done ;;
    declined)    echo fd_declined ;;
    *)           echo dim ;;
  esac
}
