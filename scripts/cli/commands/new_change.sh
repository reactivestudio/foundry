#!/usr/bin/env bash
# new_change.sh — `foundry new ["title"]`: create a change in backlog.
#
# Source this file; do not execute it directly.
# Needs: spec/slug.sh, render/primitives.sh, CHANGE_SH, require_foundry.

cmd_new_change() {
  local title="${1:-}"
  if [[ -z "$title" ]]; then
    if [[ "$UI_MODE" == "interactive" ]]; then
      title=$(ui_input "Change title (free text)")
      [[ -z "$title" ]] && { ui_error "title required"; exit 1; }
    else
      ui_error "new: title required as argument in --plain mode"
      exit 64
    fi
  fi

  # Slug: FOUNDRY_SLUG env overrides (used by Claude Code when it wants
  # to LLM-pick a semantic slug); otherwise derived from the title by
  # the naming rules in spec/slug.sh.
  local slug="${FOUNDRY_SLUG:-}"
  [[ -z "$slug" ]] && slug=$(slug_from_title "$title")

  require_foundry
  "$CHANGE_SH" new "$slug" "$title" >/dev/null
  ui_header "$(ui_status_icon backlog) $slug" "created in backlog"
  ui_info "edit: .foundry/changes/backlog/$slug/proposal.md"
  echo
}
