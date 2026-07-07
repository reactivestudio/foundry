#!/usr/bin/env bash
# store.sh — unit checks for the store layer and slug rules.
#
# Exercises the pieces the smoke suite only touches indirectly:
# yaml_get/yaml_set edge values, history sanitization, the index-cache
# entry operations, render_template substitution safety and
# slug_from_title derivation.
#
# usage: tests/store.sh
# exit:  0 — all checks passed · 1 — at least one failed

# shellcheck source-path=SCRIPTDIR/../scripts/cli
# shellcheck source-path=SCRIPTDIR
set -uo pipefail   # no -e: assertions inspect non-zero exit codes

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI_DIR="$PLUGIN_ROOT/scripts/cli"
# shellcheck source=harness.sh
. "$PLUGIN_ROOT/tests/harness.sh"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
cd "$SANDBOX" || exit 1

export FOUNDRY_ROOT="$SANDBOX/.foundry"
TRACKING_SH="$CLI_DIR/store/tracking.sh"

# shellcheck source=config/constants.sh
. "$CLI_DIR/config/constants.sh"
# shellcheck source=store/template.sh
. "$CLI_DIR/store/template.sh"
# shellcheck source=store/index_cache.sh
. "$CLI_DIR/store/index_cache.sh"
# shellcheck source=spec/slug.sh
. "$CLI_DIR/spec/slug.sh"


# ── tracking.sh: yaml round-trips with hostile values ──────────────────────
change_dir="$FOUNDRY_ROOT/changes/backlog/unit-test"
mkdir -p "$FOUNDRY_ROOT/changes/.template"
{
  printf 'slug: __SLUG__\ntitle: __TITLE__\nstatus: backlog\n'
  printf 'created_at: __TIMESTAMP__\nupdated_at: __TIMESTAMP__\n'
} > "$FOUNDRY_ROOT/changes/.template/tracking.yaml"
"$TRACKING_SH" init "$change_dir" unit-test "Unit test change"

assert_equals "Unit test change" "$("$TRACKING_SH" get "$change_dir" title)" \
  "tracking: get returns the written title"

# shellcheck disable=SC2016  # literal $D is the point: no expansion may happen
"$TRACKING_SH" set "$change_dir" title 'A & B / C | $D: "quoted"'
# shellcheck disable=SC2016  # literal $D is the point: no expansion may happen
assert_equals 'A & B / C | $D: "quoted"' "$("$TRACKING_SH" get "$change_dir" title)" \
  "tracking: sed-hazard characters survive set/get"

"$TRACKING_SH" set "$change_dir" title "$(printf 'multi\nline\ttitle')"
assert_equals "multi line title" "$("$TRACKING_SH" get "$change_dir" title)" \
  "tracking: newlines and tabs collapse to spaces"
assert_equals "1" "$(grep -c '^title:' "$change_dir/tracking.yaml")" \
  "tracking: hostile title stays a single YAML line"

"$TRACKING_SH" set "$change_dir" brand_new_field "appended"
assert_equals "appended" "$("$TRACKING_SH" get "$change_dir" brand_new_field)" \
  "tracking: set appends fields that don't exist yet"

"$TRACKING_SH" history "$change_dir" user tested "$(printf 'de\ttails\nsplit')"
assert_equals "1" "$(grep -c 'tested' "$change_dir/history.log")" \
  "tracking: history event with tabs/newlines is one TSV line"

# ── index_cache: entry operations ──────────────────────────────────────────
# Drop the tracking-section change dir first: rebuild scans slug
# folders, and a leftover one would duplicate the entry added below.
rm -rf "$change_dir"
mkdir -p "$FOUNDRY_ROOT/changes/backlog"
index_rebuild_bucket backlog
index_add_entry backlog unit-test "Indexed title" \
  "2026-07-01T00:00:00Z" "2026-07-02T00:00:00Z"
assert_equals "unit-test" "$(index_read_bucket backlog | cut -f1)" \
  "index: added entry is readable"
assert_equals "Indexed title" "$(index_read_bucket backlog | cut -f2)" \
  "index: title column round-trips"

index_update_entry backlog unit-test title "Renamed title" \
  updated_at "2026-07-03T00:00:00Z"
assert_equals "Renamed title" "$(index_read_bucket backlog | cut -f2)" \
  "index: update rewrites the title in place"
assert_equals "2026-07-03T00:00:00Z" "$(index_read_bucket backlog | cut -f4)" \
  "index: updated_at refresh lands"
updated_epoch="$(index_read_bucket backlog | cut -f6)"
if [[ "$updated_epoch" != "0" && -n "$updated_epoch" ]]; then
  pass "index: updated_epoch derived automatically"
else
  fail "index: updated_epoch derived automatically (got '$updated_epoch')"
fi

index_remove_entry backlog unit-test
assert_equals "" "$(index_read_bucket backlog)" \
  "index: removed entry is gone"

# ── render_template: literal substitution, no sed hazards ──────────────────
printf 'title: __TITLE__\n' > template-source.txt
# shellcheck disable=SC2016  # literal $D is the point: no expansion may happen
render_template template-source.txt rendered.txt TITLE='A & B / C | $D'
# shellcheck disable=SC2016  # literal $D is the point: no expansion may happen
assert_equals 'title: A & B / C | $D' "$(cat rendered.txt)" \
  "template: &, /, | and \$ substitute literally"

# ── slug_from_title: derivation rules ──────────────────────────────────────
assert_equals "fix-flaky-login-test" "$(slug_from_title 'Fix Flaky  Login Test!')" \
  "slug: lowercase kebab, punctuation folded"
long_title="This title is long enough to overflow the forty character cap easily"
derived_slug="$(slug_from_title "$long_title")"
if (( ${#derived_slug} <= 40 )); then
  pass "slug: capped at 40 chars"
else
  fail "slug: capped at 40 chars (got ${#derived_slug})"
fi
if slug_valid "$derived_slug"; then
  pass "slug: derived slug passes slug_valid"
else
  fail "slug: derived slug passes slug_valid ('$derived_slug')"
fi
case "$(slug_from_title '!!!')" in
  change-*) pass "slug: untransliterable title falls back to change-<epoch>" ;;
  *)        fail "slug: untransliterable title falls back to change-<epoch>" ;;
esac

# ── verdict ────────────────────────────────────────────────────────────────
test_verdict
