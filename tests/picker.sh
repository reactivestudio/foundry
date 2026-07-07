#!/usr/bin/env bash
# picker.sh — non-TTY unit checks for the picker widget internals.
#
# picker_run itself needs a terminal, but its _picker_* helpers run on
# plain dynamic scoping — so we fabricate the caller's locals here and
# drive the helpers directly: filter pass, cursor placement, Tab bucket
# jump, and the filter-match highlight splice.
#
# usage: tests/picker.sh
# exit:  0 — all checks passed · 1 — at least one failed

# shellcheck source-path=SCRIPTDIR/../scripts/cli
# shellcheck disable=SC2034  # the emulated locals are read by the
#                              _picker_* helpers via dynamic scoping
set -euo pipefail
export FOUNDRY_PLAIN=1

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI_DIR="$PLUGIN_ROOT/scripts/cli"
# shellcheck source=render/primitives.sh
. "$CLI_DIR/render/primitives.sh"
# shellcheck source=render/picker_widget.sh
. "$CLI_DIR/render/picker_widget.sh"

# Deliberately NOT on tests/harness.sh: every check here builds on the
# state the previous one produced, so the first failure must stop the
# suite — counters would only cascade noise after it.
fail() { echo "NOT OK - $*" >&2; exit 1; }

# Build a page: padding, header, 2 backlog rows, 1 done row, action.
picker_reset
picker_push_padding
picker_push_header "STATUS TITLE"
picker_push_row "entry-alpha" "alpha" "backlog" "Alpha change" 20 "L" "LH" "R"
picker_push_row "entry-beta"  "beta"  "backlog" "Beta change"  20 "L" "LH" "R"
picker_push_row "entry-gamma" "gamma" "done"    "Gamma change" 20 "L" "LH" "R"
picker_push_action "Add" "__act_add__"

# Emulate picker_run's local context (dynamic-scope substrate).
entry_count=${#PICKER_ENTRIES[@]}
declare -a entries_lowercase=() entries_brand=() titles_lowercase=()
declare -a visible_indices=() selectable_indices=()
filter="" filter_lowercase="" cursor=0
selectable_count=0 cursor_visible_index=-1
_first_render=1 _filter_changed=0

_picker_init_caches

# 1. No filter: 4 selectables (3 rows + action), cursor on first row.
_picker_filter_pass
[[ "$selectable_count" == 4 ]] \
  || fail "selectable_count=$selectable_count, want 4"
[[ "${visible_indices[$cursor_visible_index]}" == 2 ]] \
  || fail "initial cursor not on first data row"
echo "ok - filter pass counts selectables, cursor on first row"

# 2. Filter 'beta': only the beta row survives among filterables.
filter_lowercase="beta"; _filter_changed=1
_picker_filter_pass
[[ "$selectable_count" == 2 ]] \
  || fail "filtered selectable_count=$selectable_count, want 2 (beta + action)"
entry_index="${visible_indices[$cursor_visible_index]}"
[[ "${PICKER_SLUGS[$entry_index]}" == "beta" ]] \
  || fail "cursor on '${PICKER_SLUGS[$entry_index]}', want beta"
echo "ok - typing a filter narrows rows and snaps cursor to the match"

# 3. Tab from a backlog row jumps to the next bucket (gamma in done).
filter_lowercase=""; _first_render=1
_picker_filter_pass
_picker_jump_next_bucket
entry_index="${visible_indices[${selectable_indices[$cursor]}]}"
[[ "${PICKER_SLUGS[$entry_index]}" == "gamma" ]] \
  || fail "Tab landed on '${PICKER_SLUGS[$entry_index]}', want gamma"
echo "ok - Tab jumps to the first selectable of the next bucket"

# 4. Highlight splice keeps the title text intact and paints the match.
_match_format=$'\033[38;5;222m'
filter_lowercase="eta"
_highlighted_title=""
_picker_highlight_match "Beta change" "beta change" $'\033[38;5;153m'
plain_title=$(printf '%s' "$_highlighted_title" | sed -E $'s/\033\\[[0-9;]*m//g')
[[ "$plain_title" == "Beta change" ]] \
  || fail "highlight mangled the title: '$plain_title'"
case "$_highlighted_title" in
  *$'\033[38;5;222m'eta*) : ;;
  *) fail "matched substring not painted in fd_match" ;;
esac
echo "ok - highlight splice preserves text and paints the match"

echo
echo "picker: all 4 checks passed"
