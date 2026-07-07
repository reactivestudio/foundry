#!/usr/bin/env bash
# run.sh — run every test suite; the pre-commit hook's single entry.
#
# CI keeps one workflow step per suite instead (better step-level
# visibility in the Actions UI) — keep the suite list here and there
# in sync when adding one.
#
# usage: tests/run.sh
# exit:  0 — all suites passed · 1 — at least one failed

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for suite in smoke picker store pages; do
  echo "── $suite ──"
  /bin/bash "$TESTS_DIR/$suite.sh" | tail -2
  suite_status=${PIPESTATUS[0]}
  if [[ "$suite_status" != "0" ]]; then
    echo "run: $suite FAILED (exit $suite_status)" >&2
    exit 1
  fi
done
echo "run: all suites green"
