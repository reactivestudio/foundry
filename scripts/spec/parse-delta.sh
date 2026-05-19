#!/usr/bin/env bash
# Usage: parse-delta.sh <file>
# Extracts delta entries from a change's delta spec.
# Output: TSV — section<TAB>name<TAB>line_number
#   section: ADDED | MODIFIED | REMOVED | RENAMED_FROM | RENAMED_TO
# Exit 0 on success; 2 on bad usage / missing file.

set -eu

file=${1:-}
if [ -z "$file" ] || [ ! -f "$file" ]; then
  echo "parse-delta: file not found: ${file:-<missing>}" >&2
  exit 2
fi

awk '
  /^## ADDED Requirements/    { section = "ADDED";    next }
  /^## MODIFIED Requirements/ { section = "MODIFIED"; next }
  /^## REMOVED Requirements/  { section = "REMOVED";  next }
  /^## RENAMED Requirements/  { section = "RENAMED";  next }
  /^## /                      { section = ""; next }
  section == "ADDED" || section == "MODIFIED" {
    if ($0 ~ /^### Requirement: /) {
      name = $0; sub(/^### Requirement: */, "", name)
      printf "%s\t%s\t%d\n", section, name, NR
    }
  }
  section == "REMOVED" {
    if ($0 ~ /^- ### Requirement: /) {
      name = $0; sub(/^- ### Requirement: */, "", name)
      printf "REMOVED\t%s\t%d\n", name, NR
    }
  }
  section == "RENAMED" {
    if ($0 ~ /^- FROM: `### Requirement: /) {
      name = $0
      sub(/^- FROM: `### Requirement: */, "", name)
      sub(/` *$/, "", name)
      printf "RENAMED_FROM\t%s\t%d\n", name, NR
    } else if ($0 ~ /^- TO: `### Requirement: /) {
      name = $0
      sub(/^- TO: `### Requirement: */, "", name)
      sub(/` *$/, "", name)
      printf "RENAMED_TO\t%s\t%d\n", name, NR
    }
  }
' "$file"
