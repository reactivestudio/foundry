#!/usr/bin/env bash
# Usage: validate-structural.sh <file> [--strict] [--kind spec|delta]
# Runs cheap deterministic checks on a spec or delta file.
# Findings -> stderr as TSV: severity<TAB>line<TAB>code<TAB>message
# Summary  -> stdout: "PASS: 0 error(s), N warning(s)" or "FAIL: ..."
# Exit 0 = pass; 1 = errors (or warnings under --strict); 2 = bad usage.

set -eu

file=
strict=0
kind=auto

while [ $# -gt 0 ]; do
  case ${1:-} in
    --strict) strict=1 ;;
    --kind)   shift; kind=${1:-auto} ;;
    -h|--help)
      echo "Usage: $0 <file> [--strict] [--kind spec|delta]"
      exit 0
      ;;
    *) file=$1 ;;
  esac
  shift || true
done

if [ -z "$file" ] || [ ! -f "$file" ]; then
  echo "validate-structural: file not found: ${file:-<missing>}" >&2
  exit 2
fi

if [ "$kind" = "auto" ]; then
  case "$file" in
    */changes/*/specs/*) kind=delta ;;
    *)                   kind=spec  ;;
  esac
fi

errors=0
warnings=0

emit() {
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >&2
  case $1 in
    ERROR)   errors=$((errors + 1)) ;;
    WARNING) warnings=$((warnings + 1)) ;;
  esac
}

if [ "$kind" = "spec" ]; then
  grep -q '^## Purpose'      "$file" || emit ERROR 0 SPEC_MISSING_PURPOSE      "missing '## Purpose' section"
  grep -q '^## Requirements' "$file" || emit ERROR 0 SPEC_MISSING_REQUIREMENTS "missing '## Requirements' section"

  # Purpose length: count non-whitespace chars in body between '## Purpose' and next H2.
  purpose_len=$(awk '
    /^## Purpose/ { flag = 1; next }
    /^## /        { flag = 0 }
    flag          { body = body $0 }
    END {
      gsub(/[[:space:]]/, "", body)
      print length(body)
    }
  ' "$file")
  if [ "${purpose_len:-0}" -gt 0 ] && [ "${purpose_len:-0}" -lt 50 ]; then
    emit WARNING 0 SPEC_PURPOSE_TOO_SHORT "Purpose body has $purpose_len non-whitespace chars (< 50)"
  fi

  # Duplicate requirement names.
  while IFS= read -r d; do
    [ -z "$d" ] || emit ERROR 0 SPEC_DUPLICATE_REQUIREMENT "duplicate requirement name: $d"
  done < <(grep -nE '^### Requirement: ' "$file" 2>/dev/null \
    | sed -E 's/^[0-9]+:### Requirement: //' \
    | sort | uniq -d || true)

  # Scenario header must have exactly 4 '#'.
  while IFS=: read -r ln rest; do
    [ -z "$ln" ] && continue
    hashes=$(printf '%s' "$rest" | sed -E 's/^(#+).*/\1/' | tr -d '\n')
    h_count=${#hashes}
    if [ "$h_count" != "4" ]; then
      emit ERROR "$ln" SPEC_SCENARIO_HASH_COUNT "scenario header has $h_count '#' (must be exactly 4)"
    fi
  done < <(grep -nE '^#+ Scenario: ' "$file" 2>/dev/null || true)

  # Requirements without scenarios (advisory).
  while IFS=$'\t' read -r name ln; do
    [ -z "$name" ] || emit WARNING "$ln" SPEC_NO_SCENARIO "requirement '$name' has no scenarios"
  done < <(awk '
    /^### Requirement: / {
      if (req != "" && !scen) print req "\t" req_line
      req = $0; sub(/^### Requirement: */, "", req); req_line = NR; scen = 0; next
    }
    /^#### Scenario: / { if (req != "") scen = 1; next }
    /^## /              { if (req != "" && !scen) print req "\t" req_line; req = ""; scen = 0 }
    END                 { if (req != "" && !scen) print req "\t" req_line }
  ' "$file")

elif [ "$kind" = "delta" ]; then
  if ! grep -qE '^## (ADDED|MODIFIED|REMOVED|RENAMED) Requirements' "$file"; then
    emit ERROR 0 DELTA_NO_SECTION "delta spec must contain at least one of: ADDED/MODIFIED/REMOVED/RENAMED Requirements"
  fi

  # Empty delta sections.
  while IFS=$'\t' read -r sec ln; do
    [ -z "$sec" ] || emit WARNING "$ln" DELTA_EMPTY_SECTION "'## $sec Requirements' section has no entries"
  done < <(awk '
    function flush() { if (sec != "" && entries == 0) print sec "\t" sec_line }
    /^## (ADDED|MODIFIED|REMOVED|RENAMED) Requirements/ {
      flush()
      sec = $2; sec_line = NR; entries = 0; next
    }
    /^## / { flush(); sec = "" }
    sec == "ADDED"    || sec == "MODIFIED" { if ($0 ~ /^### Requirement: /)         entries++ }
    sec == "REMOVED"                        { if ($0 ~ /^- ### Requirement: /)       entries++ }
    sec == "RENAMED"                        { if ($0 ~ /^- FROM: /)                  entries++ }
    END { flush() }
  ' "$file")

  # ADDED / MODIFIED requirement bodies must include RFC 2119 keyword.
  while IFS=$'\t' read -r name ln; do
    [ -z "$name" ] || emit ERROR "$ln" DELTA_MISSING_NORMATIVE "requirement '$name' missing RFC 2119 keyword (SHALL/MUST/SHOULD/MAY)"
  done < <(awk '
    function flush() {
      if (curr != "" && !norm) print curr "\t" curr_line
    }
    /^## (ADDED|MODIFIED) Requirements/ { sec = $2; next }
    /^## /                               { flush(); curr = ""; sec = "" }
    sec == "" { next }
    /^### Requirement: / {
      flush()
      curr = $0; sub(/^### Requirement: */, "", curr); curr_line = NR; norm = 0; next
    }
    /SHALL|MUST|SHOULD|MAY/ { if (curr != "") norm = 1 }
    END { flush() }
  ' "$file")

  # RENAMED entries must follow exact FROM:/TO: format.
  while IFS=$'\t' read -r ln rest; do
    [ -z "$ln" ] || emit ERROR "$ln" DELTA_RENAMED_FORMAT "RENAMED entry must be \`- FROM: \`### Requirement: <name>\`\` or \`- TO: \`### Requirement: <name>\`\`"
  done < <(awk '
    /^## RENAMED Requirements/ { sec = 1; next }
    /^## /                      { sec = 0 }
    sec && /^- / {
      if ($0 !~ /^- FROM: `### Requirement: .+`$/ && $0 !~ /^- TO: `### Requirement: .+`$/) {
        printf "%d\t%s\n", NR, $0
      }
    }
  ' "$file")

  # Cross-section name conflicts.
  tmpfile=$(mktemp -t spec-validate.XXXXXX 2>/dev/null || echo "/tmp/spec-validate.$$")
  trap 'rm -f "$tmpfile"' EXIT
  : > "$tmpfile"
  awk '/^## ADDED Requirements/{f=1;next} /^## /{f=0} f && /^### Requirement: /{n=$0; sub(/^### Requirement: */,"",n); print n}' "$file" >> "$tmpfile"
  awk '/^## MODIFIED Requirements/{f=1;next} /^## /{f=0} f && /^### Requirement: /{n=$0; sub(/^### Requirement: */,"",n); print n}' "$file" >> "$tmpfile"
  awk '/^## REMOVED Requirements/{f=1;next} /^## /{f=0} f && /^- ### Requirement: /{n=$0; sub(/^- ### Requirement: */,"",n); print n}' "$file" >> "$tmpfile"
  awk '/^## RENAMED Requirements/{f=1;next} /^## /{f=0} f && /^- FROM: `### Requirement: /{n=$0; sub(/^- FROM: `### Requirement: */,"",n); sub(/` *$/,"",n); print n}' "$file" >> "$tmpfile"
  awk '/^## RENAMED Requirements/{f=1;next} /^## /{f=0} f && /^- TO: `### Requirement: /{n=$0; sub(/^- TO: `### Requirement: */,"",n); sub(/` *$/,"",n); print n}' "$file" >> "$tmpfile"
  while IFS= read -r d; do
    [ -z "$d" ] || emit ERROR 0 DELTA_CROSS_SECTION "requirement name '$d' appears in multiple delta sections"
  done < <(grep -v '^$' "$tmpfile" | sort | uniq -d || true)

else
  echo "validate-structural: unknown --kind '$kind' (expected spec|delta)" >&2
  exit 2
fi

if [ "$strict" = "1" ] && [ "$warnings" -gt 0 ]; then
  errors=$((errors + warnings))
fi

if [ "$errors" -gt 0 ]; then
  echo "FAIL: $errors error(s), $warnings warning(s)"
  exit 1
fi
echo "PASS: 0 error(s), $warnings warning(s)"
