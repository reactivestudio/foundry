#!/usr/bin/env bash
# sync.sh — `foundry sync`: full rebuild of all per-bucket .index.yaml files.
#
# Source this file; do not execute it directly.
# Needs: store/index_cache.sh, render/primitives.sh, CLI_DIR, FOUNDRY_ROOT, require_foundry.
# Backs the Sync action item in the picker and is exposed as a CLI
# subcommand for scripting / cron-style recovery.  In interactive mode a
# gum spinner covers the rebuild; in --plain mode we print a single
# success line.

cmd_sync() {
  require_foundry
  if [[ "$UI_MODE" == "interactive" ]] && command -v gum >/dev/null 2>&1; then
    gum spin --title "Syncing change indexes…" --spinner dot -- \
      bash -c "
        export FOUNDRY_ROOT='$FOUNDRY_ROOT'
        . '$CLI_DIR/config/constants.sh'
        . '$CLI_DIR/store/index_cache.sh'
        index_rebuild_all
      "
  else
    index_rebuild_all
    ui_success "indexes rebuilt"
  fi
}
