#!/usr/bin/env bash
# Usage: change-move.sh <name> <to-bucket>
# Moves a change from its current bucket to <to-bucket>.
# Valid buckets: backlog | sprint | done | declined.
# Locates the source via change-locate.sh; destination collision = error.
# Output: absolute path to the new location.
# Exit 0 ok; 1 collision (destination exists); 2 bad args; 3 source not found.

set -eu

name=${1:-}
to=${2:-}
if [ -z "$name" ] || [ -z "$to" ]; then
  echo "change-move: missing args (need <name> <to-bucket>)" >&2
  exit 2
fi

case "$to" in
  backlog|sprint|done|declined) : ;;
  *) echo "change-move: '$to' is not a valid bucket (one of: backlog sprint done declined)" >&2; exit 2 ;;
esac

self_dir=$(cd "$(dirname "$0")" && pwd)

if ! src=$("$self_dir/change-locate.sh" "$name"); then
  exit 3
fi

# If already in target bucket — no-op (echo current path).
case "$src" in
  */.spec/changes/$to/$name) echo "$src"; exit 0 ;;
esac

# Compute destination.
project_root=$(pwd)
# change-locate returns absolute path; we want destination under project root.
# Use the parent of `.spec` from src.
# Source pattern: <project>/.spec/changes/<from>/<name>
# Strip .spec/changes/<from>/<name> from end to get project root.
proj=${src%/.spec/changes/*/$name}
if [ "$proj" = "$src" ]; then
  echo "change-move: cannot derive project root from '$src'" >&2
  exit 3
fi

mkdir -p "$proj/.spec/changes/$to"
dest="$proj/.spec/changes/$to/$name"

if [ -e "$dest" ]; then
  echo "change-move: destination already exists at $dest (name collision)" >&2
  exit 1
fi

mv "$src" "$dest"
echo "$dest"
