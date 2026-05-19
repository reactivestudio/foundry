#!/usr/bin/env bash
# Usage: roadmap-status.sh <roadmap-path>
# Aggregates task counts from a roadmap.md.
# Output (single line):
#   pending=N in-progress=M done=K blocked=L rejected=R total=T
# Exit 0 ok.

set -eu

roadmap=${1:-}
if [ -z "$roadmap" ]; then
  echo "roadmap-status: missing arg (need <roadmap-path>)" >&2
  exit 2
fi
if [ ! -f "$roadmap" ]; then
  echo "pending=0 in-progress=0 done=0 blocked=0 rejected=0 total=0"
  exit 0
fi

self_dir=$(cd "$(dirname "$0")" && pwd)

"$self_dir/roadmap-parse.sh" "$roadmap" | awk -F '\t' '
  { state = $6; total++; counts[state]++ }
  END {
    printf "pending=%d in-progress=%d done=%d blocked=%d rejected=%d total=%d\n",
      counts["pending"]+0, counts["in-progress"]+0, counts["done"]+0,
      counts["blocked"]+0, counts["rejected"]+0, total+0
  }
'
