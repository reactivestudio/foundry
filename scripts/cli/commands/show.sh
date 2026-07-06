#!/usr/bin/env bash
# show.sh — `foundry show <slug>`: tracking metadata + history for one change.
#
# Source this file; do not execute it directly.
# Needs: query.sh, render/{primitives,history}.sh, TRACKING_SH, require_foundry.

cmd_show() {
  require_foundry
  local slug="${1:-}"
  [[ -n "$slug" ]] || { ui_error "show: missing slug"; exit 64; }
  local bucket
  if ! bucket=$(query_bucket_of "$slug" 2>/dev/null); then
    ui_error "not found: $slug"
    # offer near matches
    local hits
    hits=$(query_rows all 2>/dev/null | awk -F'\t' -v query="$slug" '
      BEGIN { query_lowercase = tolower(query) }
      index(tolower($2), query_lowercase) > 0 || \
      index(tolower($3), query_lowercase) > 0 { print $0 }
    ' | head -5)
    if [[ -n "$hits" ]]; then
      echo
      ui_info "did you mean:"
      while IFS=$'\t' read -r hit_bucket hit_slug hit_title _ _; do
        printf '    %s  %s  %s\n' \
          "$(ui_status_icon "$hit_bucket")" \
          "$(ui_bright "$hit_slug")" \
          "$(ui_dim "$hit_title")"
      done <<< "$hits"
      echo
    fi
    exit 1
  fi
  local dir="$CHANGES_DIR/$bucket/$slug"

  query_change_fields "$dir"   # → CHANGE_TITLE/STATUS/CREATED/UPDATED/REASON

  # ── header: icon + slug, then title as h1, then metadata ──
  echo
  printf '  %s  %s\n' "$(ui_status_icon "$bucket")" "$(ui_paint fd_title "$slug")"
  printf '  %s\n' "$(ui_paint fd_title "$CHANGE_TITLE")"
  echo
  printf '  %s  %s\n' \
    "$(printf '%-10s' "$(ui_dim "status")")" \
    "$(ui_paint "$(ui_bucket_color "$bucket")" "$CHANGE_STATUS")"
  printf '  %s  %s\n' \
    "$(printf '%-10s' "$(ui_dim "updated")")" \
    "$(ui_paint fd_updated "$(ui_date_relative "$CHANGE_UPDATED") · $(ui_date_full "$CHANGE_UPDATED")")"
  printf '  %s  %s\n' \
    "$(printf '%-10s' "$(ui_dim "created")")" \
    "$(ui_paint fd_created "$(ui_date_full "$CHANGE_CREATED")")"
  [[ -n "$CHANGE_REASON" ]] && printf '  %s  %s\n' \
    "$(printf '%-10s' "$(ui_dim "reason")")" \
    "$(ui_paint "$(ui_bucket_color "$bucket")" "$CHANGE_REASON")"
  echo

  # ── proposal preview: first N content lines, dim, blanks collapsed ──
  if [[ -f "$dir/proposal.md" ]]; then
    ui_divider "proposal"
    local preview_cap=12 total_content
    total_content=$(grep -cE '[^[:space:]]' "$dir/proposal.md" || echo 0)
    grep -E '[^[:space:]]' "$dir/proposal.md" | head -n "$preview_cap" | while IFS= read -r line; do
      printf '  %s\n' "$(ui_dim "$line")"
    done
    if (( total_content > preview_cap )); then
      printf '  %s\n' "$(ui_dim "  … $((total_content - preview_cap)) more lines in proposal.md")"
    fi
    echo
  fi

  # ── history: log-style, newest first ──
  if [[ -f "$dir/history.log" ]]; then
    ui_divider "history"
    render_history_newest_first "$dir/history.log" | head -10 | while IFS= read -r history_line; do
      render_history_fields "$history_line"
      local actor_color
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
  fi

  # ── next actions ──
  if [[ "$UI_MODE" == "interactive" ]]; then
    ui_divider "next"
    case "$bucket" in
      backlog)
        printf '  %s  %s\n' "$(ui_dim "foundry move $slug --to=in-progress")" "$(ui_dim '— start')"
        printf '  %s  %s\n' "$(ui_dim "foundry move $slug --to=declined --reason=\"…\"")" "$(ui_dim '— decline')"
        ;;
      in-progress)
        printf '  %s  %s\n' "$(ui_dim "foundry move $slug --to=done")" "$(ui_dim '— finish')"
        printf '  %s  %s\n' "$(ui_dim "foundry move $slug --to=backlog")" "$(ui_dim '— pause')"
        printf '  %s  %s\n' "$(ui_dim "foundry move $slug --to=declined --reason=\"…\"")" "$(ui_dim '— decline')"
        ;;
      done)
        printf '  %s\n' "$(ui_dim '(terminal — no transitions out)')"
        ;;
      declined)
        printf '  %s  %s\n' "$(ui_dim "foundry move $slug --to=backlog")" "$(ui_dim '— revive')"
        ;;
    esac
    echo
  fi
}
