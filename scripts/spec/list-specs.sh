#!/usr/bin/env bash
# Usage: list-specs.sh
# Lists every capability spec with its requirement count.
# Output: TSV — capability<TAB>requirement_count<TAB>path
# Exit 0 on success.

set -eu

if [ ! -d ".spec/specs" ]; then
  exit 0
fi

for spec in .spec/specs/*/spec.md; do
  [ -f "$spec" ] || continue
  cap=$(basename "$(dirname "$spec")")
  count=$(grep -cE '^### Requirement: ' "$spec" || true)
  printf '%s\t%s\t%s\n' "$cap" "${count:-0}" "$spec"
done | sort
