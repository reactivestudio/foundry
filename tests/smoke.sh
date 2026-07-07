#!/usr/bin/env bash
# smoke.sh — end-to-end test suite for the foundry CLI (plain mode).
#
# Runs every subcommand against a throwaway sandbox project and checks
# output and exit codes, including the domain guards (serial invariant,
# terminal bucket, decline reason) and all three invocation paths.
# Needs only what the CLI itself needs: bash 3.2+, coreutils, awk, sed.
#
# usage: tests/smoke.sh
# exit:  0 — all checks passed · 1 — at least one failed

# shellcheck source-path=SCRIPTDIR
set -uo pipefail   # no -e: assertions inspect non-zero exit codes

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=harness.sh
. "$PLUGIN_ROOT/tests/harness.sh"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
cd "$SANDBOX" || exit 1

# shellcheck disable=SC2317,SC2329  # invoked indirectly through assert_* "$@"
run_cli() { CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$PLUGIN_ROOT/cli" --plain "$@"; }

# ── setup ──────────────────────────────────────────────────────────────────
assert_exit 0 "setup scaffolds"            run_cli setup --install-cli
assert_file .foundry/changes/backlog/.gitkeep       "setup: bucket dirs"
assert_file .foundry/changes/.template/tracking.yaml "setup: templates copied"
assert_file .foundry/cli                   "setup: cli symlink"
assert_file ./foundry                      "setup: ./foundry symlink"
assert_file ./f                            "setup: ./f symlink"
assert_contains "/foundry" "setup: gitignore entries" cat .gitignore
assert_exit 0  "setup is idempotent"       run_cli setup --install-cli
assert_exit 64 "setup rejects unknown arg" run_cli setup --bogus

# ── new ────────────────────────────────────────────────────────────────────
assert_exit 0 "new: auto slug from title"  run_cli new "Fix flaky login test"
assert_file .foundry/changes/backlog/fix-flaky-login-test/proposal.md \
  "new: proposal created"
assert_exit 0 "new: FOUNDRY_SLUG override" \
  env FOUNDRY_SLUG=custom-slug CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
  "$PLUGIN_ROOT/cli" --plain new "Custom titled change"
assert_exit 2  "new: duplicate slug rejected" \
  env FOUNDRY_SLUG=custom-slug CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
  "$PLUGIN_ROOT/cli" --plain new "Duplicate"
assert_exit 64 "new: title required in plain mode" run_cli new

# ── list ───────────────────────────────────────────────────────────────────
assert_contains "fix-flaky-login-test" "list: grouped shows slug" run_cli list
assert_contains "custom-slug" "list: --bucket=backlog shows slug" \
  run_cli list --bucket=backlog
assert_exit 64 "list: bad --sort rejected"   run_cli list --sort=bogus
assert_exit 64 "list: unknown flag rejected" run_cli list --bogus

# ── show ───────────────────────────────────────────────────────────────────
assert_contains "Custom titled change" "show: prints title" run_cli show custom-slug
assert_exit 1 "show: unknown slug exits 1"  run_cli show no-such-slug
assert_contains "did you mean" "show: near-miss suggests" run_cli show fix-flaky
assert_exit 64 "show: missing slug is usage" run_cli show

# ── move: full lifecycle + guards ──────────────────────────────────────────
assert_exit 0 "move: backlog -> in-progress" \
  run_cli move fix-flaky-login-test --to=in-progress
assert_exit 1 "move: serial invariant blocks a second start" \
  run_cli move custom-slug --to=in-progress
assert_exit 64 "move: decline without reason is usage (plain)" \
  run_cli move custom-slug --to=declined
assert_exit 0 "move: decline with reason" \
  run_cli move custom-slug --to=declined --reason="duplicate"
assert_contains "duplicate" "show: decline reason recorded" run_cli show custom-slug
assert_exit 0 "move: in-progress -> done" \
  run_cli move fix-flaky-login-test --to=done
assert_exit 1 "move: done is terminal" \
  run_cli move fix-flaky-login-test --to=backlog
assert_exit 0 "move: declined -> backlog (revive)" \
  run_cli move custom-slug --to=backlog
assert_exit 1  "move: unknown slug exits 1"  run_cli move no-such-slug --to=done
assert_exit 64 "move: missing slug is usage" run_cli move
assert_exit 64 "move: unknown flag rejected" run_cli move custom-slug --bogus

# ── state machine: transitions table ───────────────────────────────────────
# shellcheck disable=SC2317,SC2329  # invoked indirectly through assert_* "$@"
state_machine() { "$PLUGIN_ROOT/scripts/cli/spec/state-machine.sh" "$@"; }
assert_contains "in-progress	start" "transitions-from backlog lists start" \
  state_machine transitions-from backlog
assert_exit 0 "transitions-from done is empty but ok" \
  state_machine transitions-from 'done'
if [[ -z "$(state_machine transitions-from 'done')" ]]; then
  pass "transitions-from done prints nothing"
else
  fail "transitions-from done prints nothing"
fi
assert_exit 2 "transitions-from rejects unknown bucket" \
  state_machine transitions-from bogus
assert_exit 1 "validate-bucket rejects declined -> done" \
  state_machine validate-bucket declined 'done'

# ── sync / help / dispatch ─────────────────────────────────────────────────
rm -f .foundry/changes/backlog/.index.yaml
assert_exit 0 "sync rebuilds indexes" run_cli sync
assert_file .foundry/changes/backlog/.index.yaml "sync: index file written"
assert_exit 0  "help exits 0"               run_cli help
assert_exit 64 "unknown subcommand exits 64" run_cli bogus
manifest_version=$(awk -F'"' '/"version":/ { print $4; exit }' \
  "$PLUGIN_ROOT/.claude-plugin/plugin.json")
assert_contains "foundry $manifest_version" "version matches plugin.json" \
  run_cli version
assert_exit 64 "list: unknown bucket rejected" run_cli list --bucket=bogus

# ── invocation paths ───────────────────────────────────────────────────────
assert_exit 0 "invocation: ./foundry" \
  env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" ./foundry --plain list
assert_exit 0 "invocation: ./f" \
  env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" ./f --plain list
assert_exit 0 "invocation: .foundry/cli" \
  env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" ./.foundry/cli --plain list
assert_exit 0 "invocation: scripts/cli/app directly" \
  env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$PLUGIN_ROOT/scripts/cli/app" --plain list

# ── config defaults ────────────────────────────────────────────────────────
printf 'default_sort: slug\n' > .foundry/config.yaml
assert_contains "sort: slug" "config: default_sort honoured" run_cli list
rm -f .foundry/config.yaml

# ── sanitization: hostile free text can't corrupt the schema ──────────────
assert_exit 0 "new: title with tab and newline accepted" \
  run_cli new "$(printf 'Hostile\ttitle with\nnewline')"
hostile_dir=.foundry/changes/backlog/hostile-title-with-newline
assert_equals 1 "$(grep -c '^title:' "$hostile_dir/tracking.yaml")" \
  "sanitize: hostile title is one YAML line"
assert_exit 0 "move: reason with newline accepted" \
  run_cli move hostile-title-with-newline --to=declined \
    --reason="$(printf 'multi\nline\treason')"
hostile_dir=.foundry/changes/declined/hostile-title-with-newline
assert_equals 2 "$(wc -l < "$hostile_dir/history.log" | tr -d ' ')" \
  "sanitize: history stays one TSV line per event"
assert_contains "multi line reason" "sanitize: reason readable in show" \
  run_cli show hostile-title-with-newline

# ── lint gates ─────────────────────────────────────────────────────────────
# shellcheck disable=SC2317,SC2329  # invoked indirectly through assert_* "$@"
line_count() { "$PLUGIN_ROOT/scripts/cli/spec/lint/line-count.sh" "$@"; }
# shellcheck disable=SC2317,SC2329  # invoked indirectly through assert_* "$@"
opinion_words() { "$PLUGIN_ROOT/scripts/cli/spec/lint/opinion-words.sh" "$@"; }
printf '# title\n\ncontent one\ncontent two\n---\n' > artifact.md
assert_exit 0  "line-count: within limit"      line_count artifact.md 5
assert_exit 1  "line-count: over limit fails"  line_count artifact.md 2
assert_exit 0  "line-count: --raw counts all"  line_count --raw artifact.md 5
assert_exit 64 "line-count: bad max is usage"  line_count artifact.md abc
assert_exit 64 "line-count: missing file"      line_count no-such.md 5
printf 'The parser lives in src/parse.c:42.\n' > research.md
assert_exit 0 "opinion-words: facts pass" opinion_words research.md
printf 'You should refactor this.\n' > opinionated.md
assert_exit 1 "opinion-words: 'should' fails" opinion_words opinionated.md
# shellcheck disable=SC2016  # backticks are literal markdown fence
printf '```\nthis should stay quoted\n```\n' > quoted.md
assert_exit 0 "opinion-words: code blocks skipped" opinion_words quoted.md

# ── verdict ────────────────────────────────────────────────────────────────
test_verdict
