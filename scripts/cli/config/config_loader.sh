#!/usr/bin/env bash
# config_loader.sh — flat-YAML config lookup with defaults.
#
# Source this; do not execute. Reads from $FOUNDRY_ROOT/config.yaml
# (per-project, optional). Each line is "key: value".
#
# Usage:
#   value=$(config_get list_per_bucket_limit 3)

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
