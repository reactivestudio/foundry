#!/usr/bin/env bash
# history.sh — shared parsing/prettifying of history.log lines.
#
# Source this file; do not execute it directly.
# Needs: primitives.sh (ui_date_relative).
#
# history.log is append-only TSV: ts \t actor \t event \t details.
# Both consumers (commands/show.sh plain view, pages/detail_page.sh picker
# view) render the same fields with different palettes — the shared
# piece is the parse + prettify, extracted here so the "->" arrow and
# "(reason)" split never drift between the two.

# Parse one raw history.log line into globals:
#   HIST_REL    — relative timestamp ("2h ago")
#   HIST_ACTOR  — actor column
#   HIST_EVENT  — event column
#   HIST_PRETTY — details with "->" prettified to " → ", "(reason)" removed
#   HIST_REASON — the parenthesised reason, "" when absent
# shellcheck disable=SC2034  # HIST_* are a documented cross-layer protocol
render_history_fields() {
  local ts actor event details
  IFS=$'\t' read -r ts actor event details <<< "$1"
  HIST_REL=$(ui_date_relative "$ts")
  HIST_ACTOR="$actor"
  HIST_EVENT="$event"
  # Pretty details: "backlog->declined (reason)" → "backlog → declined"
  # with the reason split out for the caller to render as its own line.
  HIST_PRETTY="${details//->/ → }"
  HIST_REASON=""
  if [[ "$HIST_PRETTY" =~ ^(.+)\ \((.+)\)$ ]]; then
    HIST_PRETTY="${BASH_REMATCH[1]}"
    HIST_REASON="${BASH_REMATCH[2]}"
  fi
}

# Emit history.log newest-first.  tac is GNU; macOS ships tail -r —
# both consumers (show, detail page) need the same fallback chain.
render_history_newest_first() {
  tac "$1" 2>/dev/null || tail -r "$1"
}
