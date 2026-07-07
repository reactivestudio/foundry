#!/usr/bin/env bash
# harness.sh — shared assertions for the test suites.
#
# Source this file; do not execute it directly.  Provides the pass/fail
# counters, the assert_* helpers and the final verdict so each suite
# writes checks, not plumbing.
#
# Usage in a suite:
#   . "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
#   assert_exit 0 "label" some_command --flag
#   ...
#   test_verdict   # prints the tally, exits 1 if anything failed

pass_count=0
fail_count=0

pass() { printf 'ok - %s\n' "$1"; pass_count=$((pass_count + 1)); }
fail() { printf 'NOT OK - %s\n' "$1" >&2; fail_count=$((fail_count + 1)); }

# assert_exit <expected-code> <label> <command...>
assert_exit() {
  local expected="$1" label="$2"; shift 2
  local actual=0
  "$@" >/dev/null 2>&1 || actual=$?
  if [[ "$actual" == "$expected" ]]; then
    pass "$label"
  else
    fail "$label (exit $actual, want $expected)"
  fi
}

# assert_contains <needle> <label> <command...>
assert_contains() {
  local needle="$1" label="$2"; shift 2
  local output
  output=$("$@" 2>&1)
  if [[ "$output" == *"$needle"* ]]; then
    pass "$label"
  else
    fail "$label (output lacks '$needle')"
  fi
}

# assert_equals <expected> <actual> <label>
assert_equals() {
  if [[ "$1" == "$2" ]]; then pass "$3"; else fail "$3 (got '$2', want '$1')"; fi
}

# assert_file <path> <label>
assert_file() {
  if [[ -e "$1" ]]; then pass "$2"; else fail "$2 (missing $1)"; fi
}

# Print the tally; exit code is the suite's result.
test_verdict() {
  echo
  echo "passed: $pass_count · failed: $fail_count"
  (( fail_count == 0 )) || exit 1
  exit 0
}
