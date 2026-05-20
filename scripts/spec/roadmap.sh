#!/usr/bin/env bash
# roadmap.sh — all operations on a change's roadmap.md.
#
# Usage:
#   roadmap.sh parse          --roadmap <path>
#   roadmap.sh status         --roadmap <path>
#   roadmap.sh ready          --roadmap <path>
#   roadmap.sh set-task-state --roadmap <path> --task-id <id> --state <state>
#
# Task block format (in roadmap.md):
#   ## <ID>. <title>
#   - **Estimate:** <value>
#   - **Blockers:** <comma-separated IDs or —>
#   - **Assignee:** <agent name>
#   - **State:** <pending|in-progress|done|blocked|rejected>
#   - **Acceptance:** <criterion>
#
# Task ID pattern: [A-Z]?[0-9]+(\.[0-9]+)*  (e.g. 1, 2.1, Q1, Q2.3)
# Task states (5): pending in-progress done blocked rejected

set -eu

VALID_TASK_STATES="pending in-progress done blocked rejected"

require_args() {
  local sub=$1; shift
  while [ $# -gt 0 ]; do
    local flag=${1%%|*}
    local val=${1#*|}
    if [ -z "$val" ]; then
      echo "roadmap $sub: missing $flag" >&2
      exit 2
    fi
    shift
  done
}

require_file() {
  local f=$1
  if [ ! -f "$f" ]; then
    echo "roadmap: file not found at $f" >&2
    exit 3
  fi
}

# === parse logic ===
# Emits TSV: id\ttitle\test\tblockers\tassignee\tstate\tacceptance
do_parse() {
  local roadmap=$1
  awk '
    function flush_task() {
      if (id != "") {
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", id, title, est, blockers, assignee, state, acceptance
      }
      id=""; title=""; est=""; blockers=""; assignee=""; state=""; acceptance=""
    }
    function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
    function field_value(line,    pos) {
      pos = index(line, "** ")
      if (pos == 0) return ""
      return trim(substr(line, pos + 3))
    }
    /^## [A-Za-z]?[0-9]+(\.[0-9]+)*\. / {
      flush_task()
      s = substr($0, 4)
      pos = index(s, ". ")
      id = substr(s, 1, pos - 1)
      title = substr(s, pos + 2)
      next
    }
    /^- \*\*Estimate:\*\*/     { est = field_value($0); next }
    /^- \*\*Blockers:\*\*/     { blockers = field_value($0); next }
    /^- \*\*Assignee:\*\*/     { assignee = field_value($0); next }
    /^- \*\*State:\*\*/        { state = field_value($0); next }
    /^- \*\*Acceptance:\*\*/   { acceptance = field_value($0); next }
    /^## / { flush_task() }
    /^# /  { flush_task() }
    END { flush_task() }
  ' "$roadmap"
}

# === subcommands ===

cmd_parse() {
  local roadmap=""
  while [ $# -gt 0 ]; do
    case ${1:-} in
      --roadmap) shift; roadmap=${1:-} ;;
      *) echo "roadmap parse: unknown arg '$1'" >&2; exit 2 ;;
    esac
    shift || true
  done
  require_args parse "--roadmap|$roadmap"
  require_file "$roadmap"
  do_parse "$roadmap"
}

cmd_status() {
  local roadmap=""
  while [ $# -gt 0 ]; do
    case ${1:-} in
      --roadmap) shift; roadmap=${1:-} ;;
      *) echo "roadmap status: unknown arg '$1'" >&2; exit 2 ;;
    esac
    shift || true
  done
  require_args status "--roadmap|$roadmap"
  if [ ! -f "$roadmap" ]; then
    echo "pending=0 in-progress=0 done=0 blocked=0 rejected=0 total=0"
    return
  fi
  do_parse "$roadmap" | awk -F '\t' '
    { state = $6; total++; counts[state]++ }
    END {
      printf "pending=%d in-progress=%d done=%d blocked=%d rejected=%d total=%d\n",
        counts["pending"]+0, counts["in-progress"]+0, counts["done"]+0,
        counts["blocked"]+0, counts["rejected"]+0, total+0
    }
  '
}

cmd_ready() {
  local roadmap=""
  while [ $# -gt 0 ]; do
    case ${1:-} in
      --roadmap) shift; roadmap=${1:-} ;;
      *) echo "roadmap ready: unknown arg '$1'" >&2; exit 2 ;;
    esac
    shift || true
  done
  require_args ready "--roadmap|$roadmap"
  [ -f "$roadmap" ] || return 0
  do_parse "$roadmap" | awk -F '\t' '
    {
      id = $1; blockers = $4; state = $6
      state_of[id] = state
      blockers_of[id] = blockers
      order[++n] = id
    }
    END {
      for (i = 1; i <= n; i++) {
        id = order[i]
        if (state_of[id] != "pending") continue
        b = blockers_of[id]
        gsub(/[[:space:]]/, "", b)
        if (b == "" || b == "—" || b == "-") { print id; continue }
        m = split(b, parts, ",")
        ready = 1
        for (j = 1; j <= m; j++) {
          bid = parts[j]
          if (!(bid in state_of)) {
            printf "roadmap ready: warning — task %s references unknown blocker %s\n", id, bid > "/dev/stderr"
            ready = 0; break
          }
          if (state_of[bid] != "done") { ready = 0; break }
        }
        if (ready) print id
      }
    }
  '
}

cmd_set_task_state() {
  local roadmap="" task_id="" new_state=""
  while [ $# -gt 0 ]; do
    case ${1:-} in
      --roadmap) shift; roadmap=${1:-} ;;
      --task-id) shift; task_id=${1:-} ;;
      --state)   shift; new_state=${1:-} ;;
      *) echo "roadmap set-task-state: unknown arg '$1'" >&2; exit 2 ;;
    esac
    shift || true
  done
  require_args set-task-state "--roadmap|$roadmap" "--task-id|$task_id" "--state|$new_state"
  require_file "$roadmap"
  if ! printf ' %s ' "$VALID_TASK_STATES" | grep -q " $new_state "; then
    echo "roadmap set-task-state: '$new_state' is not a valid task state (one of: $VALID_TASK_STATES)" >&2
    exit 3
  fi
  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/roadmap-set-task.XXXXXX")
  awk -v want="$task_id" -v val="$new_state" '
    BEGIN { in_task = 0; replaced = 0 }
    /^## [A-Za-z]?[0-9]+(\.[0-9]+)*\. / {
      s = substr($0, 4)
      pos = index(s, ". ")
      cur_id = substr(s, 1, pos - 1)
      in_task = (cur_id == want) ? 1 : 0
      print; next
    }
    /^## / { in_task = 0; print; next }
    /^# /  { in_task = 0; print; next }
    in_task && /^- \*\*State:\*\*/ {
      print "- **State:** " val
      replaced = 1
      next
    }
    { print }
    END { if (!replaced) exit 1 }
  ' "$roadmap" > "$tmp" || {
    rm -f "$tmp"
    echo "roadmap set-task-state: task '$task_id' not found in $roadmap" >&2
    exit 1
  }
  mv "$tmp" "$roadmap"
  echo "$new_state"
}

usage() {
  cat >&2 <<EOF
Usage: roadmap.sh <subcommand> [options]

Subcommands:
  parse          --roadmap <path>            TSV: id<TAB>title<TAB>est<TAB>blockers<TAB>assignee<TAB>state<TAB>acceptance
  status         --roadmap <path>            counts string
  ready          --roadmap <path>            task IDs ready to run (own state pending + blockers all done)
  set-task-state --roadmap <path> --task-id <id> --state <state>   atomic single-task state rewrite

Task states: $VALID_TASK_STATES
EOF
}

sub=${1:-}
shift || true
case "$sub" in
  parse)          cmd_parse "$@" ;;
  status)         cmd_status "$@" ;;
  ready)          cmd_ready "$@" ;;
  set-task-state) cmd_set_task_state "$@" ;;
  -h|--help|"")   usage; [ -z "$sub" ] && exit 2 || exit 0 ;;
  *) echo "roadmap: unknown subcommand '$sub'" >&2; usage; exit 2 ;;
esac
