#!/usr/bin/env bash
# Usage: list-changes.sh [--sort recent|name] [--archive]
# Lists active changes (default) or archived changes (--archive).
# Output: TSV — name<TAB>tasks_progress<TAB>last_modified_iso<TAB>path
# Exit 0 on success; 2 on bad usage.

set -eu

sort_by=recent
which_dir=".spec/changes"

while [ $# -gt 0 ]; do
  case ${1:-} in
    --sort) shift; sort_by=${1:-recent} ;;
    --archive) which_dir=".spec/changes/archive" ;;
    -h|--help) echo "Usage: $0 [--sort recent|name] [--archive]"; exit 0 ;;
    *) echo "list-changes: unknown arg '$1'" >&2; exit 2 ;;
  esac
  shift || true
done

if [ ! -d "$which_dir" ]; then
  exit 0
fi

here=$(pwd)
self_dir=$(cd "$(dirname "$0")" && pwd)
progress="$self_dir/tasks-progress.sh"

for d in "$which_dir"/*/; do
  [ -d "$d" ] || continue
  base=$(basename "$d")
  # Skip the archive/ folder when listing active.
  if [ "$which_dir" = ".spec/changes" ] && [ "$base" = "archive" ]; then
    continue
  fi
  tasks_md="$d/tasks.md"
  prog=$("$progress" "$tasks_md" 2>/dev/null || echo "0/0")
  # mtime in seconds since epoch (BSD stat on macOS; GNU stat fallback).
  if mtime=$(stat -f '%m' "$d" 2>/dev/null); then :
  else mtime=$(stat -c '%Y' "$d" 2>/dev/null || echo 0); fi
  printf '%s\t%s\t%s\t%s\n' "$base" "$prog" "$mtime" "$d"
done | (
  case $sort_by in
    recent) sort -t $'\t' -k3,3nr ;;
    name)   sort -t $'\t' -k1,1   ;;
    *)      echo "list-changes: invalid --sort '$sort_by' (expected recent|name)" >&2; exit 2 ;;
  esac
)
