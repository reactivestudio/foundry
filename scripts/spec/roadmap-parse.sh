#!/usr/bin/env bash
# Usage: roadmap-parse.sh <roadmap-path>
# Extracts all tasks from a roadmap.md as TSV.
# Output (per task, one line):
#   id<TAB>title<TAB>estimate<TAB>blockers<TAB>assignee<TAB>state<TAB>acceptance
#
# Task block format:
#   ## <ID>. <title>
#   - **Estimate:** <value>
#   - **Blockers:** <comma-separated IDs or —>
#   - **Assignee:** <agent name>
#   - **State:** <pending|in-progress|done|blocked|rejected>
#   - **Acceptance:** <criterion>
#
# ID matches: [A-Z]?[0-9]+(\.[0-9]+)* (e.g. 1, 2.1, Q1, Q2.3)
# Missing fields render as empty cells.
# Exit 0 ok; 2 bad args; 3 file missing.

set -eu

roadmap=${1:-}
if [ -z "$roadmap" ]; then
  echo "roadmap-parse: missing arg (need <roadmap-path>)" >&2
  exit 2
fi
if [ ! -f "$roadmap" ]; then
  echo "roadmap-parse: file not found at $roadmap" >&2
  exit 3
fi

awk '
  function flush_task() {
    if (id != "") {
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", id, title, est, blockers, assignee, state, acceptance
    }
    id = ""; title = ""; est = ""; blockers = ""; assignee = ""; state = ""; acceptance = ""
  }
  function trim(s) {
    sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s
  }
  function field_value(line,    pos) {
    # Strip leading "- **Field:** " — find first occurrence of "** ".
    pos = index(line, "** ")
    if (pos == 0) return ""
    return trim(substr(line, pos + 3))
  }
  /^## [A-Za-z]?[0-9]+(\.[0-9]+)*\. / {
    flush_task()
    # Capture ID: text between "## " and the first ". " separator.
    s = substr($0, 4)
    pos = index(s, ". ")
    id = substr(s, 1, pos - 1)
    title = substr(s, pos + 2)
    next
  }
  /^- \*\*Estimate:\*\*/     { est       = field_value($0); next }
  /^- \*\*Blockers:\*\*/     { blockers  = field_value($0); next }
  /^- \*\*Assignee:\*\*/     { assignee  = field_value($0); next }
  /^- \*\*State:\*\*/        { state     = field_value($0); next }
  /^- \*\*Acceptance:\*\*/   { acceptance = field_value($0); next }
  /^## / { flush_task() }       # any other H2 closes current task
  /^# /  { flush_task() }       # H1 closes too
  END { flush_task() }
' "$roadmap"
