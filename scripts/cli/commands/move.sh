#!/usr/bin/env bash
# move.sh — `foundry move <slug>`: transition a change between buckets.
#
# Source this file; do not execute it directly.
# Needs: query.sh, render/primitives.sh, CHANGE_SH, require_foundry.
# The transition itself is validated by spec/state-machine.sh via
# store/change.sh — this command only collects the arguments.

cmd_move() {
  require_foundry
  local slug="${1:-}"
  [[ -n "$slug" ]] || { ui_error "move: missing slug"; exit 64; }
  shift

  local to="" reason=""
  for arg in "$@"; do
    case "$arg" in
      --to=*)     to="${arg#--to=}" ;;
      --reason=*) reason="${arg#--reason=}" ;;
      *) ui_error "unknown flag: $arg"; exit 64 ;;
    esac
  done

  local from; from=$(query_bucket_of "$slug") || { ui_error "not found: $slug"; exit 1; }

  if [[ -z "$to" ]]; then
    if [[ "$UI_MODE" == "interactive" ]]; then
      # offer all buckets except current
      local bucket_options=() bucket
      for bucket in "${BUCKETS[@]}"; do
        [[ "$bucket" == "$from" ]] && continue
        bucket_options+=("$(ui_icon "$bucket") $bucket")
      done
      local picked_option
      picked_option=$(ui_choose "Move $slug from $(ui_icon "$from") $from to:" "${bucket_options[@]}") || exit 1
      to="${picked_option#* }"
    else
      ui_error "move: --to=<bucket> required in --plain mode"
      exit 64
    fi
  fi

  if [[ "$to" == "declined" && -z "$reason" ]]; then
    if [[ "$UI_MODE" == "interactive" ]]; then
      reason=$(ui_input "Reason for declining")
      [[ -z "$reason" ]] && { ui_error "decline reason required"; exit 1; }
    else
      ui_error "move to declined: --reason=... required in --plain mode"
      exit 64
    fi
  fi

  local move_output
  if move_output=$("$CHANGE_SH" move "$slug" "$to" ${reason:+"$reason"} 2>&1); then
    printf '\n  %s  %s  %s %s %s\n\n' \
      "$(ui_paint ok '✓')" \
      "$(ui_bright "$slug")" \
      "$(ui_status_icon "$from")" \
      "$(ui_dim '→')" \
      "$(ui_status "$to")"
  else
    printf '%s\n' "$move_output" >&2
    exit 1
  fi
}
