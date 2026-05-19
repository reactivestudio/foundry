#!/usr/bin/env bash
# Usage: archive-relocate.sh <change-name> [YYYY-MM-DD]
# Moves .spec/changes/<name>/ -> .spec/changes/archive/<date>-<name>/.
# On same-day collision appends -2, -3, … .
# If date is omitted, uses today's local date.
# Output: the target directory on stdout.
# Exit 0 on success; 1 on collision overflow; 2 on bad usage.

set -eu

name=${1:-}
date_str=${2:-}
if [ -z "$name" ]; then
  echo "archive-relocate: missing change-name argument" >&2
  exit 2
fi
src=".spec/changes/$name"
if [ ! -d "$src" ]; then
  echo "archive-relocate: source not found: $src" >&2
  exit 2
fi

if [ -z "$date_str" ]; then
  date_str=$(date +%Y-%m-%d)
fi

archive_dir=".spec/changes/archive"
mkdir -p "$archive_dir"

target="$archive_dir/${date_str}-${name}"
if [ ! -e "$target" ]; then
  mv "$src" "$target"
  echo "$target"
  exit 0
fi

# Collision: try -2, -3, …, up to -999.
i=2
while [ $i -le 999 ]; do
  candidate="$archive_dir/${date_str}-${name}-${i}"
  if [ ! -e "$candidate" ]; then
    mv "$src" "$candidate"
    echo "$candidate"
    exit 0
  fi
  i=$((i + 1))
done

echo "archive-relocate: collision overflow (> 999) for ${date_str}-${name}" >&2
exit 1
