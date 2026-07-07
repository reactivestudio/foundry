#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# tracking.sh — read/write flat tracking.yaml + append history.log
#
# Schema (flat YAML, one key:value per line, no nesting):
#   slug: <kebab-case>
#   title: <free text>
#   status: backlog|in-progress|done|declined
#   created_at: <ISO-8601 UTC>
#   updated_at: <ISO-8601 UTC>
#   decline_reason: <free text>   (only when status=declined)
#
# history.log alongside tracking.yaml — TSV append-only:
#   <ISO-8601>\t<actor>\t<event>\t<details>

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage:
  tracking.sh init <dir> <slug> <title>
  tracking.sh get <dir> <field>
  tracking.sh set <dir> <field> <value>
  tracking.sh history <dir> <actor> <event> [details]
  tracking.sh history-tail <dir> [lines]
EOF
  exit 64
}

now_utc() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

# Collapse newlines, carriage returns and tabs into single spaces.
# tracking.yaml is flat "key: value" one-per-line and history.log is
# line-per-event TSV — a value carrying either delimiter would corrupt
# the schema for every awk/grep parser downstream.  Applied to every
# free-text write (title on init, set values, history fields).
sanitize_single_line() {
  printf '%s' "$1" | tr '\n\r\t' '   '
}

# Read field value. Echoes value (without leading space) or empty.
# index()==1 → literal prefix match: the field name can't inject regex,
# and one awk replaces the grep|head|sed pipeline.
yaml_get() {
  local file="$1" field="$2"
  awk -v field="$field" 'index($0, field ":") == 1 {
    sub(/^[^:]*:[[:space:]]?/, ""); print; exit
  }' "$file" 2>/dev/null
}

yaml_has() {
  local file="$1" field="$2"
  grep -Eq "^${field}:( |$)" "$file" 2>/dev/null
}

# Set or append field. Uses a temp file to keep BSD/GNU sed compatible.
yaml_set() {
  local file="$1" field="$2" value="$3"
  if yaml_has "$file" "$field"; then
    local temp_file; temp_file=$(mktemp)
    awk -v field="$field" -v value="$value" '
      BEGIN { replaced = 0 }
      {
        if (!replaced && index($0, field ":") == 1) {
          print field ": " value
          replaced = 1
        } else {
          print
        }
      }
    ' "$file" > "$temp_file"
    mv "$temp_file" "$file"
  else
    printf '%s: %s\n' "$field" "$value" >> "$file"
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=template.sh
. "$SCRIPT_DIR/template.sh"

cmd_init() {
  local dir="$1" slug="$2" title
  title=$(sanitize_single_line "$3")
  local tracking_file="$dir/tracking.yaml"
  local history_file="$dir/history.log"
  local timestamp; timestamp=$(now_utc)

  # find .template/ by stripping last two path components from $dir
  # (e.g. .foundry/changes/backlog/<slug> → .foundry/changes/)
  local changes_dir="${FOUNDRY_CHANGES_DIR:-${dir%/*/*}}"
  local template_file="$changes_dir/.template/tracking.yaml"

  mkdir -p "$dir"
  render_template "$template_file" "$tracking_file" \
    SLUG="$slug" TITLE="$title" TIMESTAMP="$timestamp"
  : > "$history_file"
  printf '%s\t%s\t%s\t%s\n' "$timestamp" "user" "created" "in backlog" >> "$history_file"
}

cmd_get() {
  local dir="$1" field="$2"
  yaml_get "$dir/tracking.yaml" "$field"
}

cmd_set() {
  local dir="$1" field="$2" value
  value=$(sanitize_single_line "$3")
  yaml_set "$dir/tracking.yaml" "$field" "$value"
  if [[ "$field" != "updated_at" ]]; then
    yaml_set "$dir/tracking.yaml" "updated_at" "$(now_utc)"
  fi
}

cmd_history() {
  local dir="$1" actor="$2" event="$3"
  local details
  details=$(sanitize_single_line "${4:-}")
  printf '%s\t%s\t%s\t%s\n' "$(now_utc)" "$actor" "$event" "$details" >> "$dir/history.log"
}

cmd_history_tail() {
  local dir="$1" line_count="${2:-20}"
  tail -n "$line_count" "$dir/history.log" 2>/dev/null || true
}

main() {
  [[ $# -lt 1 ]] && usage
  local subcommand="$1"; shift
  case "$subcommand" in
    init)         [[ $# -eq 3 ]] || usage; cmd_init "$@" ;;
    get)          [[ $# -eq 2 ]] || usage; cmd_get "$@" ;;
    set)          [[ $# -eq 3 ]] || usage; cmd_set "$@" ;;
    history)      [[ $# -ge 3 && $# -le 4 ]] || usage; cmd_history "$@" ;;
    history-tail) [[ $# -ge 1 && $# -le 2 ]] || usage; cmd_history_tail "$@" ;;
    *)            usage ;;
  esac
}

main "$@"
