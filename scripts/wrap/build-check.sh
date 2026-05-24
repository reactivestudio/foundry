#!/usr/bin/env bash
# build-check.sh — run gradle build, return compact PASS/FAIL.
#
# 12-FACTOR §7: «Compact errors in context». Don't dump full gradle
# output (~10k lines) into the LLM — return PASS, or FAIL + the last
# N lines that actually mention an error/warning.
#
# Auto-detects:
#   ./gradlew  preferred (project-pinned wrapper)
#   gradle     fallback (system-wide)
#
# Output (stdout):
#   PASS: ./gradlew build (took 12.3s)
# OR
#   FAIL: ./gradlew build (exit 1, took 8.1s)
#   --- last 20 error lines ---
#   <relevant lines>
#
# Exit code = gradle's exit code.

set -euo pipefail
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

MAX_LINES="${BUILD_CHECK_MAX_LINES:-20}"

detect_gradle() {
  if [[ -x "./gradlew" ]]; then
    echo "./gradlew"
  elif command -v gradle >/dev/null 2>&1; then
    echo "gradle"
  else
    echo "no gradle: neither ./gradlew nor system gradle found" >&2
    exit 2
  fi
}

GRADLE=$(detect_gradle)
LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT

start=$(date +%s)
set +e
"$GRADLE" build --console=plain > "$LOG" 2>&1
rc=$?
set -e
end=$(date +%s)
elapsed=$((end - start))

if (( rc == 0 )); then
  echo "PASS: $GRADLE build (took ${elapsed}s)"
  exit 0
fi

echo "FAIL: $GRADLE build (exit $rc, took ${elapsed}s)"
echo "--- last $MAX_LINES error lines ---"
# Match: gradle FAILURE blocks, kotlin compiler e:/w: prefixes,
# exception chains, stack frames, "What went wrong" sections.
grep -nE '^\s*[ew]:|FAILURE:|BUILD FAILED|What went wrong|Execution failed|[Ee]rror|[Ee]xception|^\s+at [A-Za-z]' "$LOG" \
  | tail -n "$MAX_LINES" \
  || tail -n "$MAX_LINES" "$LOG"
exit "$rc"
