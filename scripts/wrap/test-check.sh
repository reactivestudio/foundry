#!/usr/bin/env bash
# test-check.sh — run gradle test, return compact PASS/FAIL.
#
# 12-FACTOR §7: same compaction principle as build-check.sh. Gradle test
# output can be many thousands of lines (each test prints stdout); only
# the failed-test summary matters for the agent.
#
# Output (stdout):
#   PASS: ./gradlew test (took 23.4s)
# OR
#   FAIL: ./gradlew test (exit 1, took 19.0s)
#   --- failing tests ---
#   <gradle's failed-test report lines, capped>
#
# Exit code = gradle's exit code.

set -euo pipefail
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

MAX_LINES="${TEST_CHECK_MAX_LINES:-30}"

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
"$GRADLE" test --console=plain > "$LOG" 2>&1
rc=$?
set -e
end=$(date +%s)
elapsed=$((end - start))

if (( rc == 0 )); then
  echo "PASS: $GRADLE test (took ${elapsed}s)"
  exit 0
fi

echo "FAIL: $GRADLE test (exit $rc, took ${elapsed}s)"
echo "--- failing tests ---"
# Gradle's failed-test summary section starts after "FAILED" markers.
# Fallback: grep for FAILED + test method names + first stack frame.
grep -iE 'FAILED|^Tests run|^Caused by|^\s+at |^\s+> Task' "$LOG" \
  | tail -n "$MAX_LINES" \
  || tail -n "$MAX_LINES" "$LOG"
exit "$rc"
