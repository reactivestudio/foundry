#!/usr/bin/env bash
# pages.sh — unit checks for the page builders (no TTY needed).
#
# _main_page_entries and _detail_page_entries only populate the
# PICKER_* protocol arrays — so we stub the store reads, run them, and
# assert the arrays: row composition, "+N more" folding, the sentinels,
# and the action bar derived from the state machine.  picker_run itself
# (the event loop) still needs a real terminal and stays manual.
#
# usage: scripts/test/pages.sh
# exit:  0 — all checks passed · 1 — at least one failed

# shellcheck source-path=SCRIPTDIR/../cli
# shellcheck disable=SC2034  # PAGE_* / CHANGE_* feed the sourced builders
# shellcheck disable=SC2317,SC2329  # the stubs ARE invoked — indirectly, by the
#                              sourced page builders they override
set -uo pipefail   # no -e: assertions inspect non-zero exit codes

export FOUNDRY_PLAIN=1
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLI_DIR="$PLUGIN_ROOT/scripts/cli"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

FOUNDRY_ROOT="$SANDBOX/.foundry"
CHANGES_DIR="$FOUNDRY_ROOT/changes"
STATE_MACHINE_SH="$CLI_DIR/spec/state-machine.sh"
TRACKING_SH="$CLI_DIR/store/tracking.sh"

# shellcheck source=config/constants.sh
. "$CLI_DIR/config/constants.sh"
# shellcheck source=config/config_loader.sh
. "$CLI_DIR/config/config_loader.sh"
# shellcheck source=render/primitives.sh
. "$CLI_DIR/render/primitives.sh"
# shellcheck source=store/index_cache.sh
. "$CLI_DIR/store/index_cache.sh"
# shellcheck source=store/query.sh
. "$CLI_DIR/store/query.sh"
# shellcheck source=render/table.sh
. "$CLI_DIR/render/table.sh"
# shellcheck source=render/brand_header.sh
. "$CLI_DIR/render/brand_header.sh"
# shellcheck source=render/markdown.sh
. "$CLI_DIR/render/markdown.sh"
# shellcheck source=render/history.sh
. "$CLI_DIR/render/history.sh"
# shellcheck source=render/picker_widget.sh
. "$CLI_DIR/render/picker_widget.sh"
# shellcheck source=pages/main_page.sh
. "$CLI_DIR/pages/main_page.sh"
# shellcheck source=pages/detail_page.sh
. "$CLI_DIR/pages/detail_page.sh"

pass_count=0
fail_count=0
pass() { printf 'ok - %s\n' "$1"; pass_count=$((pass_count + 1)); }
fail() { printf 'NOT OK - %s\n' "$1" >&2; fail_count=$((fail_count + 1)); }

# count_slots <needle> — how many PICKER_SLUGS slots equal the needle.
count_slots() {
  local needle="$1" i count=0
  for (( i = 0; i < ${#PICKER_SLUGS[@]}; i++ )); do
    [[ "${PICKER_SLUGS[$i]}" == "$needle" ]] && count=$((count + 1))
  done
  printf '%d' "$count"
}

# count_types <type> — how many PICKER_TYPES slots equal the type.
count_types() {
  local needle="$1" i count=0
  for (( i = 0; i < ${#PICKER_TYPES[@]}; i++ )); do
    [[ "${PICKER_TYPES[$i]}" == "$needle" ]] && count=$((count + 1))
  done
  printf '%d' "$count"
}

# ── main page ──────────────────────────────────────────────────────────────
# Stub the store read and the per-bucket cap: 2 backlog rows + 1 done
# row, limit 1 → each bucket shows 1 row, backlog folds into "+1 more".
query_change_rows() {
  printf 'backlog\talpha\tAlpha change\t1h\t100\t50\n'
  printf 'backlog\tbeta\tBeta change\t2h\t90\t40\n'
  printf 'done\tgamma\tGamma change\t3h\t80\t30\n'
}
config_list_per_bucket_limit() { printf '1'; }
PAGE_SORT=updated
PAGE_REVERSE=0

_main_page_entries

if [[ "$(count_types header)" == "1" ]]; then
  pass "main: exactly one column-header row"
else
  fail "main: exactly one column-header row"
fi
if [[ "$(count_types row)" == "2" ]]; then
  pass "main: limit 1 shows one row per bucket"
else
  fail "main: limit 1 shows one row per bucket (got $(count_types row))"
fi
if [[ "$(count_slots __more__backlog)" == "1" ]]; then
  pass "main: backlog overflow folds into __more__backlog"
else
  fail "main: backlog overflow folds into __more__backlog"
fi
if [[ "$(count_slots __more__done)" == "0" ]]; then
  pass "main: done bucket fits, no __more__ action"
else
  fail "main: done bucket fits, no __more__ action"
fi
for sentinel in __act_add__ __act_sync__ __act_reload__ __act_exit__; do
  if [[ "$(count_slots "$sentinel")" == "1" ]]; then
    pass "main: action $sentinel present once"
  else
    fail "main: action $sentinel present once"
  fi
done
if [[ "$(count_types summary)" == "1" ]]; then
  pass "main: summary row present"
else
  fail "main: summary row present"
fi

# ── detail page ────────────────────────────────────────────────────────────
# Real files on disk, stubbed tracking fields.  Proposal has 8 content
# lines → preview caps at 5 and offers the View action.
detail_dir="$CHANGES_DIR/backlog/alpha"
mkdir -p "$detail_dir"
for i in 1 2 3 4 5 6 7 8; do
  printf 'Proposal line %d\n\n' "$i"
done > "$detail_dir/proposal.md"
printf '2026-07-01T00:00:00Z\tuser\tcreated\tin backlog\n' > "$detail_dir/history.log"
printf '2026-07-02T00:00:00Z\tstate-machine\tmoved\tbacklog->in-progress\n' \
  >> "$detail_dir/history.log"

query_change_fields() {
  CHANGE_TITLE="Alpha change"
  CHANGE_STATUS="backlog"
  CHANGE_CREATED="2026-07-01T00:00:00Z"
  CHANGE_UPDATED="2026-07-02T00:00:00Z"
  CHANGE_REASON=""
}

_detail_page_entries alpha backlog

if [[ "$(count_types info)" -ge 8 ]]; then
  pass "detail: meta + proposal preview + history rendered as info rows"
else
  fail "detail: meta + proposal preview + history rendered as info rows"
fi
if [[ "$(count_slots __view_proposal__)" == "1" ]]; then
  pass "detail: 8 proposal lines > cap 5 → View action offered"
else
  fail "detail: 8 proposal lines > cap 5 → View action offered"
fi
for sentinel in __move__in-progress __move__done __move__declined; do
  if [[ "$(count_slots "$sentinel")" == "1" ]]; then
    pass "detail: backlog action bar offers $sentinel"
  else
    fail "detail: backlog action bar offers $sentinel"
  fi
done
if [[ "$(count_slots __act_back__)" == "1" ]]; then
  pass "detail: Back action present"
else
  fail "detail: Back action present"
fi

# Terminal bucket: the machine allows nothing out of done → bar is Back only.
done_dir="$CHANGES_DIR/done/gamma"
mkdir -p "$done_dir"
query_change_fields() {
  CHANGE_TITLE="Gamma change"
  CHANGE_STATUS="done"
  CHANGE_CREATED="2026-07-01T00:00:00Z"
  CHANGE_UPDATED="2026-07-02T00:00:00Z"
  CHANGE_REASON=""
}
_detail_page_entries gamma 'done'

move_action_count=0
for (( i = 0; i < ${#PICKER_SLUGS[@]}; i++ )); do
  case "${PICKER_SLUGS[$i]}" in __move__*) move_action_count=$((move_action_count + 1)) ;; esac
done
if [[ "$move_action_count" == "0" ]]; then
  pass "detail: done is terminal → no __move__ actions at all"
else
  fail "detail: done is terminal → no __move__ actions at all (got $move_action_count)"
fi
if [[ "$(count_slots __act_back__)" == "1" ]]; then
  pass "detail: terminal bucket still offers Back"
else
  fail "detail: terminal bucket still offers Back"
fi

# ── verdict ────────────────────────────────────────────────────────────────
echo
echo "passed: $pass_count · failed: $fail_count"
(( fail_count == 0 )) || exit 1
exit 0
