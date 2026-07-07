#!/usr/bin/env bash
# show_change.sh — `foundry show <slug>`: tracking metadata + history for one change.
#
# Source this file; do not execute it directly.
# Needs: store/query.sh, render/{primitives,history}.sh, TRACKING_SH,
# STATE_MACHINE_SH, require_foundry.
#
# The _show_change_* helpers execute inside cmd_show_change and read its
# locals (slug, bucket, dir) through bash dynamic scoping — same pattern
# as the _picker_* internals in render/picker_widget.sh.

# "did you mean" — slug/title substring matches for a slug that wasn't
# found.  Prints nothing when there are no near matches.
_show_change_suggestions() {
  local hits
  hits=$(query_change_rows all 2>/dev/null | awk -F'\t' -v query="$slug" '
    BEGIN { query_lowercase = tolower(query) }
    index(tolower($2), query_lowercase) > 0 || \
    index(tolower($3), query_lowercase) > 0 { print $0 }
  ' | head -5)
  [[ -n "$hits" ]] || return 0

  echo
  ui_info "did you mean:"
  local hit_bucket hit_slug hit_title
  while IFS=$'\t' read -r hit_bucket hit_slug hit_title _ _; do
    printf '    %s  %s  %s\n' \
      "$(ui_status_icon "$hit_bucket")" \
      "$(ui_bright "$hit_slug")" \
      "$(ui_dim "$hit_title")"
  done <<< "$hits"
  echo
}

# Icon + slug, title, then the labelled metadata block.
_show_change_meta() {
  query_change_fields "$dir"   # → CHANGE_TITLE/STATUS/CREATED/UPDATED/REASON

  echo
  printf '  %s  %s\n' "$(ui_status_icon "$bucket")" "$(ui_paint fd_title "$slug")"
  printf '  %s\n' "$(ui_paint fd_title "$CHANGE_TITLE")"
  echo
  printf '  %s  %s\n' \
    "$(printf '%-10s' "$(ui_dim "status")")" \
    "$(ui_paint "$(bucket_color "$bucket")" "$CHANGE_STATUS")"
  printf '  %s  %s\n' \
    "$(printf '%-10s' "$(ui_dim "updated")")" \
    "$(ui_paint fd_updated \
       "$(ui_date_relative "$CHANGE_UPDATED") · $(ui_date_full "$CHANGE_UPDATED")")"
  printf '  %s  %s\n' \
    "$(printf '%-10s' "$(ui_dim "created")")" \
    "$(ui_paint fd_created "$(ui_date_full "$CHANGE_CREATED")")"
  [[ -n "$CHANGE_REASON" ]] && printf '  %s  %s\n' \
    "$(printf '%-10s' "$(ui_dim "reason")")" \
    "$(ui_paint "$(bucket_color "$bucket")" "$CHANGE_REASON")"
  echo
}

# First N content lines of proposal.md, dim, blanks collapsed.
_show_change_proposal_preview() {
  [[ -f "$dir/proposal.md" ]] || return 0

  ui_divider "proposal"
  local preview_cap=12 total_content line
  total_content=$(grep -cE '[^[:space:]]' "$dir/proposal.md" || echo 0)
  grep -E '[^[:space:]]' "$dir/proposal.md" | head -n "$preview_cap" \
    | while IFS= read -r line; do
        printf '  %s\n' "$(ui_dim "$line")"
      done
  if (( total_content > preview_cap )); then
    printf '  %s\n' \
      "$(ui_dim "  … $((total_content - preview_cap)) more lines in proposal.md")"
  fi
  echo
}

# Last 10 history events, newest first, log-style columns.
_show_change_history() {
  [[ -f "$dir/history.log" ]] || return 0

  ui_divider "history"
  local history_line actor_color
  render_history_newest_first "$dir/history.log" | head -10 \
    | while IFS= read -r history_line; do
        render_history_fields "$history_line"
        case "$HIST_ACTOR" in
          user)          actor_color=ok ;;
          state-machine) actor_color=accent ;;
          *)             actor_color=muted ;;
        esac
        printf '  %s  %s  %s  %s\n' \
          "$(ui_dim "$(printf '%-12s' "$HIST_RELATIVE")")" \
          "$(ui_paint "$actor_color" "$(printf '%-14s' "$HIST_ACTOR")")" \
          "$(ui_bright "$(printf '%-8s' "$HIST_EVENT")")" \
          "$HIST_PRETTY"
        if [[ -n "$HIST_REASON" ]]; then
          printf '  %s  %s  %s  %s\n' \
            "            " "              " "        " \
            "$(ui_dim "\"$HIST_REASON\"")"
        fi
      done
  echo
}

# Copy-pasteable `foundry move` lines for every transition the state
# machine allows out of this bucket — read live from transitions-from,
# so a matrix change shows up here without a second edit.
_show_change_next_hints() {
  ui_divider "next"
  local to verb printed_any=0
  while IFS=$'\t' read -r to verb; do
    [[ -z "$to" ]] && continue
    local flags="--to=$to"
    [[ "$to" == "declined" ]] && flags="--to=declined --reason=\"…\""
    printf '  %s  %s\n' \
      "$(ui_dim "foundry move $slug $flags")" "$(ui_dim "— $verb")"
    printed_any=1
  done < <("$STATE_MACHINE_SH" transitions-from "$bucket")
  (( printed_any )) || printf '  %s\n' "$(ui_dim '(terminal — no transitions out)')"
  echo
}

cmd_show_change() {
  require_foundry
  local slug="${1:-}"
  [[ -n "$slug" ]] || { ui_error "show: missing slug"; exit 64; }

  local bucket
  if ! bucket=$(query_bucket_of "$slug" 2>/dev/null); then
    ui_error "show: not found: $slug"
    _show_change_suggestions
    exit 1
  fi
  local dir="$CHANGES_DIR/$bucket/$slug"

  _show_change_meta
  _show_change_proposal_preview
  _show_change_history
  [[ "$UI_MODE" == "interactive" ]] && _show_change_next_hints
  return 0
}
