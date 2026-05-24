#!/usr/bin/env bash
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
  tracking.sh has <dir> <field>                 # exit 0 if present
  tracking.sh history <dir> <actor> <event> [details]
  tracking.sh history-tail <dir> [n]
EOF
  exit 64
}

now_utc() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

# Read field value. Echoes value (without leading space) or empty.
yaml_get() {
  local file="$1" field="$2"
  grep -E "^${field}:( |$)" "$file" 2>/dev/null | head -n1 | sed -E "s/^${field}:[[:space:]]?//"
}

yaml_has() {
  local file="$1" field="$2"
  grep -Eq "^${field}:( |$)" "$file" 2>/dev/null
}

# Set or append field. Uses a temp file to keep BSD/GNU sed compatible.
yaml_set() {
  local file="$1" field="$2" value="$3"
  if yaml_has "$file" "$field"; then
    local tmp; tmp=$(mktemp)
    awk -v f="$field" -v v="$value" '
      BEGIN { done = 0 }
      {
        if (!done && index($0, f ":") == 1) {
          print f ": " v
          done = 1
        } else {
          print
        }
      }
    ' "$file" > "$tmp"
    mv "$tmp" "$file"
  else
    printf '%s: %s\n' "$field" "$value" >> "$file"
  fi
}

cmd_init() {
  local dir="$1" slug="$2" title="$3"
  local tracking="$dir/tracking.yaml"
  local history="$dir/history.log"
  local ts; ts=$(now_utc)
  mkdir -p "$dir"
  cat > "$tracking" <<EOF
slug: $slug
title: $title
status: backlog
created_at: $ts
updated_at: $ts
EOF
  : > "$history"
  printf '%s\t%s\t%s\t%s\n' "$ts" "user" "created" "in backlog" >> "$history"
}

cmd_get() {
  local dir="$1" field="$2"
  yaml_get "$dir/tracking.yaml" "$field"
}

cmd_set() {
  local dir="$1" field="$2" value="$3"
  yaml_set "$dir/tracking.yaml" "$field" "$value"
  if [[ "$field" != "updated_at" ]]; then
    yaml_set "$dir/tracking.yaml" "updated_at" "$(now_utc)"
  fi
}

cmd_has() {
  local dir="$1" field="$2"
  yaml_has "$dir/tracking.yaml" "$field"
}

cmd_history() {
  local dir="$1" actor="$2" event="$3"
  local details="${4:-}"
  printf '%s\t%s\t%s\t%s\n' "$(now_utc)" "$actor" "$event" "$details" >> "$dir/history.log"
}

cmd_history_tail() {
  local dir="$1" n="${2:-20}"
  tail -n "$n" "$dir/history.log" 2>/dev/null || true
}

main() {
  [[ $# -lt 1 ]] && usage
  local sub="$1"; shift
  case "$sub" in
    init)         [[ $# -eq 3 ]] || usage; cmd_init "$@" ;;
    get)          [[ $# -eq 2 ]] || usage; cmd_get "$@" ;;
    set)          [[ $# -eq 3 ]] || usage; cmd_set "$@" ;;
    has)          [[ $# -eq 2 ]] || usage; cmd_has "$@" ;;
    history)      [[ $# -ge 3 && $# -le 4 ]] || usage; cmd_history "$@" ;;
    history-tail) [[ $# -ge 1 && $# -le 2 ]] || usage; cmd_history_tail "$@" ;;
    *)            usage ;;
  esac
}

main "$@"
