#!/usr/bin/env bash
# change.sh — operations on change directories (.spec/changes/<bucket>/<name>/).
# Uses tracking.sh for change-level state queries (active stage, scope, roadmap progress).
#
# Usage:
#   change.sh validate-name --name <name>
#   change.sh locate        --name <name>
#   change.sh new           --title <title> --name <slug> [--description <one-line>]
#   change.sh move          --name <name> --to <bucket> [--by <who>]
#   change.sh list          [--bucket backlog|in-progress|done|declined]
#
# Buckets: backlog in-progress done declined
# Reserved names (cannot be used as change name): backlog in-progress done declined .template

set -eu

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
TRACKING="$SELF_DIR/tracking.sh"
ROADMAP="$SELF_DIR/roadmap.sh"

VALID_BUCKETS="backlog in-progress done declined"
RESERVED_NAMES="backlog in-progress done declined .template _template"
NAME_REGEX='^[a-z][a-z0-9]*(-[a-z0-9]+)*$'

# === helpers ===

require_args() {
  local sub=$1; shift
  while [ $# -gt 0 ]; do
    local flag=${1%%|*}
    local val=${1#*|}
    if [ -z "$val" ]; then
      echo "change $sub: missing $flag" >&2
      exit 2
    fi
    shift
  done
}

is_valid_bucket() {
  printf ' %s ' "$VALID_BUCKETS" | grep -q " $1 "
}

now_ts() { date '+%Y-%m-%d %H:%M:%S'; }

read_yaml_field() {
  # Reads a top-level scalar `key: value` (value may be quoted).
  local file=$1 key=$2
  awk -v key="$key" '
    $0 ~ "^"key":[[:space:]]" {
      sub("^"key":[[:space:]]*", "", $0)
      gsub(/^"|"$/, "", $0)
      print
      exit
    }' "$file"
}

# === subcommand: validate-name ===

cmd_validate_name() {
  local name=""
  while [ $# -gt 0 ]; do
    case ${1:-} in
      --name) shift; name=${1:-} ;;
      *) echo "change validate-name: unknown arg '$1'" >&2; exit 2 ;;
    esac
    shift || true
  done
  require_args validate-name "--name|$name"
  if ! printf '%s' "$name" | grep -qE "$NAME_REGEX"; then
    echo "change validate-name: '$name' is not kebab-case (lowercase letters/digits/hyphens; must start with a letter)" >&2
    exit 1
  fi
  local r
  for r in $RESERVED_NAMES; do
    if [ "$name" = "$r" ]; then
      echo "change validate-name: '$name' conflicts with reserved bucket/template name" >&2
      exit 1
    fi
  done
  local b
  for b in $VALID_BUCKETS; do
    if [ -d ".spec/changes/$b/$name" ]; then
      echo "change validate-name: change '$name' already exists in $b bucket (.spec/changes/$b/$name)" >&2
      exit 1
    fi
  done
  echo "valid"
}

# === subcommand: locate ===

cmd_locate() {
  local name=""
  while [ $# -gt 0 ]; do
    case ${1:-} in
      --name) shift; name=${1:-} ;;
      *) echo "change locate: unknown arg '$1'" >&2; exit 2 ;;
    esac
    shift || true
  done
  require_args locate "--name|$name"
  local matches="" b
  for b in $VALID_BUCKETS; do
    local d=".spec/changes/$b/$name"
    if [ -d "$d" ]; then
      matches="${matches}$(cd "$d" && pwd)"$'\n'
    fi
  done
  matches=${matches%$'\n'}
  if [ -z "$matches" ]; then
    echo "change locate: change '$name' not found in any bucket" >&2
    exit 1
  fi
  local count
  count=$(printf '%s\n' "$matches" | wc -l | tr -d ' ')
  if [ "$count" -gt 1 ]; then
    echo "change locate: change '$name' is ambiguous — found in multiple buckets:" >&2
    printf '%s\n' "$matches" >&2
    exit 2
  fi
  printf '%s\n' "$matches"
}

# === subcommand: new ===

cmd_new() {
  local title="" name="" description=""
  while [ $# -gt 0 ]; do
    case ${1:-} in
      --title)       shift; title=${1:-} ;;
      --name)        shift; name=${1:-} ;;
      --description) shift; description=${1:-} ;;
      *) echo "change new: unknown arg '$1'" >&2; exit 2 ;;
    esac
    shift || true
  done
  require_args new "--title|$title" "--name|$name"
  # Validate (self-call).
  if ! "$0" validate-name --name "$name" >/dev/null; then
    exit 1
  fi
  # Locate template.
  local template=""
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "$CLAUDE_PLUGIN_ROOT/.claude-template/spec/changes/.template" ]; then
    template="$CLAUDE_PLUGIN_ROOT/.claude-template/spec/changes/.template"
  elif [ -d ".spec/changes/.template" ]; then
    template=".spec/changes/.template"
  else
    echo "change new: scaffold template not found (looked for \$CLAUDE_PLUGIN_ROOT/.claude-template/spec/changes/.template and .spec/changes/.template)" >&2
    exit 3
  fi
  mkdir -p ".spec/changes/backlog"
  local dest=".spec/changes/backlog/$name"
  if [ -e "$dest" ]; then
    echo "change new: destination already exists at $dest" >&2
    exit 3
  fi
  cp -r "$template" "$dest"
  local now description_indented tmp
  now=$(now_ts)
  # Description: indent each line by 2 spaces (YAML | block body). If empty,
  # use a single literal-empty placeholder line; agent should always supply
  # non-empty description, but we tolerate empty for safety.
  if [ -z "$description" ]; then
    description_indented="  "
  else
    description_indented=$(printf '%s' "$description" | awk '{ print "  " $0 }')
  fi
  # tracking.yaml — awk-based, multi-line description-aware.
  # Pass description via ENVIRON (awk's -v does not support newlines).
  tmp=$(mktemp "${TMPDIR:-/tmp}/change-new.XXXXXX")
  CHANGE_DESC="$description_indented" \
  CHANGE_ID="$name" \
  CHANGE_TITLE="$title" \
  CHANGE_NOW="$now" \
  awk '
    /\{\{description\}\}/ {
      # Whole line is the placeholder — emit the multi-line description body.
      # The leading indentation in the template (e.g. "  ") is discarded; the
      # body itself is pre-indented to 2 spaces by the caller.
      print ENVIRON["CHANGE_DESC"]
      next
    }
    {
      gsub(/\{\{id\}\}/,    ENVIRON["CHANGE_ID"])
      gsub(/\{\{title\}\}/, ENVIRON["CHANGE_TITLE"])
      gsub(/\{\{now\}\}/,   ENVIRON["CHANGE_NOW"])
      print
    }
  ' "$dest/tracking.yaml" > "$tmp"
  mv "$tmp" "$dest/tracking.yaml"
  # propose.md — single-line title substitution only.
  if [ -f "$dest/propose.md" ]; then
    tmp=$(mktemp "${TMPDIR:-/tmp}/change-new.XXXXXX")
    awk -v title="$title" '
      { gsub(/\{\{title\}\}/, title); print }
    ' "$dest/propose.md" > "$tmp"
    mv "$tmp" "$dest/propose.md"
  fi
  (cd "$dest" && pwd)
}

# === subcommand: move ===

cmd_move() {
  local name="" to="" by=auto
  while [ $# -gt 0 ]; do
    case ${1:-} in
      --name) shift; name=${1:-} ;;
      --to)   shift; to=${1:-} ;;
      --by)   shift; by=${1:-} ;;
      *) echo "change move: unknown arg '$1'" >&2; exit 2 ;;
    esac
    shift || true
  done
  require_args move "--name|$name" "--to|$to"
  if ! is_valid_bucket "$to"; then
    echo "change move: '$to' is not a valid bucket (one of: $VALID_BUCKETS)" >&2
    exit 2
  fi
  local src
  if ! src=$("$0" locate --name "$name"); then
    exit 3
  fi
  # No-op if already at target.
  case "$src" in
    */.spec/changes/$to/$name) echo "$src"; return ;;
  esac
  local proj
  proj=${src%/.spec/changes/*/$name}
  if [ "$proj" = "$src" ]; then
    echo "change move: cannot derive project root from '$src'" >&2
    exit 3
  fi
  mkdir -p "$proj/.spec/changes/$to"
  local dest="$proj/.spec/changes/$to/$name"
  if [ -e "$dest" ]; then
    echo "change move: destination already exists at $dest (name collision)" >&2
    exit 1
  fi
  mv "$src" "$dest"
  if [ -f "$dest/tracking.yaml" ]; then
    "$TRACKING" sync --change "$dest" >/dev/null
  fi
  echo "$dest"
}

# === subcommand: list ===

cmd_list() {
  local bucket_filter=""
  while [ $# -gt 0 ]; do
    case ${1:-} in
      --bucket) shift; bucket_filter=${1:-} ;;
      *) echo "change list: unknown arg '$1'" >&2; exit 2 ;;
    esac
    shift || true
  done
  if [ -n "$bucket_filter" ] && ! is_valid_bucket "$bucket_filter"; then
    echo "change list: '$bucket_filter' is not a valid bucket (one of: $VALID_BUCKETS)" >&2
    exit 2
  fi
  [ -d ".spec/changes" ] || return 0
  local buckets
  if [ -n "$bucket_filter" ]; then
    buckets="$bucket_filter"
  else
    buckets="$VALID_BUCKETS"
  fi

  read_last_event_at() {
    awk '/^[[:space:]]+-[[:space:]]*\{[[:space:]]*at:[[:space:]]*"/ {
      line = $0
      sub(/^.*at:[[:space:]]*"/, "", line)
      sub(/".*$/, "", line)
      last = line
    }
    END { if (last != "") print last }' "$1"
  }

  # Format an ISO timestamp ("YYYY-MM-DD HH:MM:SS") as
  # "[<day>, HH:MM] [DD mon]" in lowercase.
  # BSD date(1) is tried first (macOS), GNU date(1) second (Linux).
  # Empty input → empty output.
  format_pretty_date() {
    local iso=$1 out
    if [ -z "$iso" ] || [ "$iso" = "—" ]; then
      return
    fi
    if out=$(date -j -f "%Y-%m-%d %H:%M:%S" "$iso" "+[%A, %H:%M] [%d %b]" 2>/dev/null); then
      printf '%s' "$out" | tr '[:upper:]' '[:lower:]'
      return
    fi
    if out=$(date -d "$iso" "+[%A, %H:%M] [%d %b]" 2>/dev/null); then
      printf '%s' "$out" | tr '[:upper:]' '[:lower:]'
      return
    fi
    printf '%s' "$iso"
  }

  # Output columns (TSV):
  # bucket  name  title  status  stage  stage_state  scope  roadmap  last_event_at  last_event_pretty  path

  local b d name tracking abs title status stage stage_state scope roadmap_md roadmap_progress last_event last_event_pretty
  for b in $buckets; do
    local bdir=".spec/changes/$b"
    [ -d "$bdir" ] || continue
    for d in "$bdir"/*/; do
      [ -d "$d" ] || continue
      name=$(basename "$d")
      [ "$name" = ".template" ] && continue
      tracking="$d/tracking.yaml"
      if [ ! -f "$tracking" ]; then
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
          "$b" "$name" "—" "—" "—" "—" "—" "—" "—" "—" "$d"
        continue
      fi
      abs=$(cd "$d" && pwd)
      title=$(read_yaml_field "$tracking" title)
      [ -z "$title" ] && title="—"
      status=$(read_yaml_field "$tracking" status)
      [ -z "$status" ] && status="—"
      stage=$(read_yaml_field "$tracking" stage)
      [ -z "$stage" ] && stage="none"
      if [ "$stage" != "none" ] && [ "$stage" != "—" ]; then
        stage_state=$("$TRACKING" get-stage --change "$abs" --stage "$stage" 2>/dev/null || echo "—")
      else
        stage_state="—"
      fi
      scope=$("$TRACKING" get-scope --change "$abs" 2>/dev/null || echo "")
      [ -z "$scope" ] && scope="—"
      roadmap_md="$d/roadmap.md"
      if [ -f "$roadmap_md" ]; then
        roadmap_progress=$("$ROADMAP" status --roadmap "$roadmap_md")
      else
        roadmap_progress="—"
      fi
      last_event=$(read_last_event_at "$tracking")
      [ -z "$last_event" ] && last_event="—"
      last_event_pretty=$(format_pretty_date "$last_event")
      [ -z "$last_event_pretty" ] && last_event_pretty="—"
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$b" "$name" "$title" "$status" "$stage" "$stage_state" "$scope" "$roadmap_progress" "$last_event" "$last_event_pretty" "$abs"
    done
  done
}

usage() {
  cat >&2 <<EOF
Usage: change.sh <subcommand> [options]

Subcommands:
  validate-name --name <name>
  locate        --name <name>
  new           --title <title> --name <slug> [--description <one-line>]
  move          --name <name> --to <bucket> [--by <who>]
  list          [--bucket backlog|in-progress|done|declined]

List output columns (TSV):
  bucket  name  title  status  stage  stage_state  scope  roadmap  last_event_at  last_event_pretty  path

Buckets:        $VALID_BUCKETS
Reserved names: $RESERVED_NAMES
EOF
}

sub=${1:-}
shift || true
case "$sub" in
  validate-name) cmd_validate_name "$@" ;;
  locate)        cmd_locate "$@" ;;
  new)           cmd_new "$@" ;;
  move)          cmd_move "$@" ;;
  list)          cmd_list "$@" ;;
  -h|--help|"")  usage; [ -z "$sub" ] && exit 2 || exit 0 ;;
  *) echo "change: unknown subcommand '$sub'" >&2; usage; exit 2 ;;
esac
