#!/usr/bin/env bash
# Usage: change-locate.sh <name>
# Finds which bucket directory holds a change of <name>.
# Scans .spec/changes/{backlog,sprint,done,declined}/<name>.
# Output: absolute path to the matched directory.
# Exit 0 ok; 1 not found; 2 ambiguous (multiple buckets contain <name>).

set -eu

name=${1:-}
if [ -z "$name" ]; then
  echo "change-locate: missing arg (need <name>)" >&2
  exit 2
fi

matches=""
for bucket in backlog sprint done declined; do
  d=".spec/changes/$bucket/$name"
  if [ -d "$d" ]; then
    abs=$(cd "$d" && pwd)
    matches="${matches}${abs}"$'\n'
  fi
done

# Strip trailing newline and count.
matches=${matches%$'\n'}
if [ -z "$matches" ]; then
  echo "change-locate: change '$name' not found in any bucket" >&2
  exit 1
fi

count=$(printf '%s\n' "$matches" | wc -l | tr -d ' ')
if [ "$count" -gt 1 ]; then
  echo "change-locate: change '$name' is ambiguous — found in multiple buckets:" >&2
  printf '%s\n' "$matches" >&2
  exit 2
fi

printf '%s\n' "$matches"
