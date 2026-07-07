#!/usr/bin/env bash
# version.sh — `foundry version`: print the installed plugin version.
#
# Source this file; do not execute it directly.
# Needs: PLUGIN_ROOT.
#
# The version lives in .claude-plugin/plugin.json only — this reads it
# from there so there is exactly one place to bump.

cmd_version() {
  local manifest="$PLUGIN_ROOT/.claude-plugin/plugin.json"
  local version
  version=$(awk -F'"' '/"version":/ { print $4; exit }' "$manifest" 2>/dev/null)
  if [[ -z "$version" ]]; then
    ui_error "version: cannot read $manifest"
    exit 2
  fi
  printf 'foundry %s\n' "$version"
}
