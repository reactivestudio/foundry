#!/usr/bin/env bash
# config.sh — flat-YAML config lookup with defaults.
#
# Source this; do not execute. Reads from $FOUNDRY_ROOT/config.yaml
# (per-project, optional). Each line is "key: value".
#
# Usage:
#   value=$(config_get list_per_bucket_limit 3)

config_get() {
  local key="$1" default="${2:-}"
  local cfg="${FOUNDRY_ROOT:-$PWD/.foundry}/config.yaml"
  if [[ -f "$cfg" ]]; then
    local value
    value=$(grep -E "^${key}:" "$cfg" 2>/dev/null | head -1 \
            | sed -E "s/^${key}:[[:space:]]*//")
    if [[ -n "$value" ]]; then
      printf '%s' "$value"
      return
    fi
  fi
  printf '%s' "$default"
}
