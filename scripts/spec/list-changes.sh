#!/usr/bin/env bash
# Usage: list-changes.sh [--backlog | --sprint | --done | --declined]
# Lists changes from one bucket (flag) or from all 4 buckets (default).
# Output TSV (one row per change):
#   bucket<TAB>name<TAB>active_stage<TAB>active_stage_state<TAB>scope<TAB>roadmap<TAB>last_event_at<TAB>path
# When the active stage is "" (all done/skipped), active_stage and active_stage_state render as "—".
# When roadmap.md absent, roadmap column is "—".
# Exit 0 on success; 2 on bad usage.

set -eu

bucket_filter=""
while [ $# -gt 0 ]; do
  case ${1:-} in
    --backlog)  bucket_filter=backlog  ;;
    --sprint)   bucket_filter=sprint   ;;
    --done)     bucket_filter=done     ;;
    --declined) bucket_filter=declined ;;
    -h|--help)
      echo "Usage: $0 [--backlog | --sprint | --done | --declined]"
      exit 0
      ;;
    *) echo "list-changes: unknown arg '$1'" >&2; exit 2 ;;
  esac
  shift || true
done

self_dir=$(cd "$(dirname "$0")" && pwd)

if [ ! -d ".spec/changes" ]; then
  exit 0
fi

if [ -n "$bucket_filter" ]; then
  buckets="$bucket_filter"
else
  buckets="backlog sprint done declined"
fi

read_scope() {
  # Top-level `scope: <value>` (one line). Empty quoted string renders as "—".
  awk '/^scope:[[:space:]]*/ {
    sub(/^scope:[[:space:]]*/, "", $0)
    gsub(/"/, "", $0)
    print
    exit
  }' "$1"
}

read_last_event_at() {
  # Last history line: `  - { at: "YYYY-MM-DD HH:MM", ... }`. Capture the at value.
  awk '/^[[:space:]]+-[[:space:]]*\{[[:space:]]*at:[[:space:]]*"/ {
    line = $0
    # Extract the quoted at value.
    sub(/^.*at:[[:space:]]*"/, "", line)
    sub(/".*$/, "", line)
    last = line
  }
  END { if (last != "") print last }' "$1"
}

for bucket in $buckets; do
  bdir=".spec/changes/$bucket"
  [ -d "$bdir" ] || continue
  for d in "$bdir"/*/; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    [ "$name" = "_template" ] && continue
    tracking="$d/tracking.yaml"
    if [ ! -f "$tracking" ]; then
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$bucket" "$name" "—" "—" "—" "—" "—" "$d"
      continue
    fi
    abs=$(cd "$d" && pwd)
    active=$("$self_dir/tracking-active-stage.sh" "$abs" 2>/dev/null || echo "")
    if [ -n "$active" ]; then
      active_state=$("$self_dir/tracking-get-stage.sh" "$abs" "$active" 2>/dev/null || echo "—")
    else
      active="—"
      active_state="—"
    fi
    scope=$(read_scope "$tracking")
    [ -z "$scope" ] && scope="—"
    roadmap_md="$d/roadmap.md"
    if [ -f "$roadmap_md" ]; then
      roadmap_progress=$("$self_dir/roadmap-status.sh" "$roadmap_md")
    else
      roadmap_progress="—"
    fi
    last_event=$(read_last_event_at "$tracking")
    [ -z "$last_event" ] && last_event="—"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$bucket" "$name" "$active" "$active_state" "$scope" "$roadmap_progress" "$last_event" "$abs"
  done
done
