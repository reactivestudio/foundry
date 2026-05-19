#!/usr/bin/env bash
# Usage: parse-spec.sh <file>
# Extracts requirements and scenarios from a canonical spec.
# Output: TSV — kind<TAB>name<TAB>line_number
#   kind: requirement | scenario
# Exit 0 on success; 2 on bad usage / missing file.

set -eu

file=${1:-}
if [ -z "$file" ] || [ ! -f "$file" ]; then
  echo "parse-spec: file not found: ${file:-<missing>}" >&2
  exit 2
fi

awk '
  /^### Requirement: / {
    name = $0
    sub(/^### Requirement: */, "", name)
    printf "requirement\t%s\t%d\n", name, NR
    next
  }
  /^#### Scenario: / {
    name = $0
    sub(/^#### Scenario: */, "", name)
    printf "scenario\t%s\t%d\n", name, NR
  }
' "$file"
