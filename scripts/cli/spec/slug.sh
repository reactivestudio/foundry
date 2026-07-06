#!/usr/bin/env bash
# slug.sh — naming rules for change slugs.
#
# Source this file; do not execute it directly.
# The slug is the change's directory name and its key everywhere
# (tracking, index, history) — these two functions are the single
# definition of what a legal slug is and how one is derived.

# Legal slug: lower-case ASCII alphanumerics with single internal
# hyphens (kebab-case; a single word is also legal), ≤60 chars.
slug_valid() {
  [[ "$1" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] && (( ${#1} <= 60 ))
}

# Derive a slug from a free-text title: ASCII-fold (translit), lowercase,
# kebab-case, capped at 40 chars.  Falls back to change-<epoch> when the
# title yields nothing (e.g. untransliterable input).  Callers may skip
# this entirely via the FOUNDRY_SLUG env override (used by Claude Code
# when it wants to LLM-pick a semantic slug).
slug_from_title() {
  local slug
  slug=$(printf '%s' "$1" \
    | iconv -f utf-8 -t ascii//translit 2>/dev/null \
    | tr '[:upper:]' '[:lower:]' \
    | tr -c 'a-z0-9' '-' \
    | sed -E 's/-+/-/g; s/^-+|-+$//g' \
    | cut -c1-40)
  [[ -z "$slug" ]] && slug="change-$(date +%s)"
  printf '%s' "$slug"
}
