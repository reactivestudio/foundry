#!/usr/bin/env bash
# config_loader.sh — flat-YAML config lookup with defaults.
#
# Source this; do not execute. Reads from $FOUNDRY_ROOT/config.yaml
# (per-project, optional). Each line is "key: value".
#
# Usage:
#   value=$(config_get some_key fallback)
# Known keys go through the typed accessors below — the ONLY place
# their default values live.

config_get() {
  local key="$1" default="${2:-}"
  local config_file="${FOUNDRY_ROOT:-$PWD/.foundry}/config.yaml"
  if [[ -f "$config_file" ]]; then
    local value
    # index()==1 → literal prefix match: the key can't inject regex,
    # and one awk replaces the grep|head|sed pipeline.
    value=$(awk -v key="$key" 'index($0, key ":") == 1 {
              sub(/^[^:]*:[[:space:]]*/, ""); print; exit
            }' "$config_file" 2>/dev/null)
    if [[ -n "$value" ]]; then
      printf '%s' "$value"
      return
    fi
  fi
  printf '%s' "$default"
}

# ── typed accessors (single source of the defaults) ──────────────────────────

# Sort key for lists and pages: updated | created | slug | title.
config_default_sort() { config_get default_sort updated; }

# 1 when config says default_reverse: true, else 0 — arithmetic-ready.
config_default_reverse_flag() {
  [[ "$(config_get default_reverse false)" == "true" ]] && printf 1 || printf 0
}

# Rows shown per bucket before "+N more" folds the rest.
config_list_per_bucket_limit() { config_get list_per_bucket_limit 3; }
