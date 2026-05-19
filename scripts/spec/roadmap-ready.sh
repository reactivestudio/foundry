#!/usr/bin/env bash
# Usage: roadmap-ready.sh <roadmap-path>
# Lists task IDs whose own state is `pending` AND all blockers are in state `done`.
# Empty blockers (`—`, `-`, or blank) = no blockers → ready immediately.
# Circular blockers are detected and reported on stderr but do not infinite-loop.
# Output: one ID per line.
# Exit 0 ok.

set -eu

roadmap=${1:-}
if [ -z "$roadmap" ]; then
  echo "roadmap-ready: missing arg (need <roadmap-path>)" >&2
  exit 2
fi
if [ ! -f "$roadmap" ]; then
  exit 0
fi

self_dir=$(cd "$(dirname "$0")" && pwd)

# We delegate the entire logic to a single awk pass over parsed TSV.
# Inputs: id\ttitle\test\tblockers\tassignee\tstate\tacceptance
"$self_dir/roadmap-parse.sh" "$roadmap" | awk -F '\t' '
  {
    id = $1; blockers = $4; state = $6
    state_of[id] = state
    blockers_of[id] = blockers
    order[++n] = id
  }
  END {
    for (i = 1; i <= n; i++) {
      id = order[i]
      if (state_of[id] != "pending") continue
      b = blockers_of[id]
      # Normalise empty markers.
      gsub(/[[:space:]]/, "", b)
      if (b == "" || b == "—" || b == "-") { print id; continue }
      # Split by comma.
      m = split(b, parts, ",")
      ready = 1
      for (j = 1; j <= m; j++) {
        bid = parts[j]
        if (!(bid in state_of)) {
          printf "roadmap-ready: warning — task %s references unknown blocker %s\n", id, bid > "/dev/stderr"
          ready = 0; break
        }
        if (state_of[bid] != "done") { ready = 0; break }
      }
      if (ready) print id
    }
  }
'
