#!/usr/bin/env bash
# trajectory-counter.sh — PostToolUse hook recording every tool call.
#
# Trajectory matters (NO-VIBES §4): «pattern "я ошибся → human yelled" →
# next-most-likely token: "do something wrong so the human can yell again"».
# Framework doesn't auto-restart, but it does *make the pattern visible* —
# this log is what Phase 6 implementor will read to decide "≥2 consecutive
# errors → propose new context".
#
# Reads JSON on stdin (Claude Code PostToolUse event), appends one TSV
# line to <project>/.foundry/.trajectory.log:
#
#   <ISO-8601 UTC>\t<tool_name>\t<ok|error>\t<excerpt>
#
# NEVER blocks — always exits 0. Silently no-ops if .foundry/ doesn't
# exist (project not foundry-setup'd) or jq missing.

set -uo pipefail
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
log="$project_dir/.foundry/.trajectory.log"

# silent no-op if not a foundry project
[[ -d "$project_dir/.foundry" ]] || exit 0

# silent no-op if jq missing (don't crash Claude)
command -v jq >/dev/null 2>&1 || exit 0

payload=$(cat)

# Parse once. If jq can't read the payload at all, silently skip —
# don't pollute the log with empty rows.
tool=$(echo "$payload" | jq -r '.tool_name // "unknown"' 2>/dev/null) || exit 0
[[ -z "$tool" ]] && exit 0

is_error=$(echo "$payload" | jq -r '
  if (.tool_response.is_error == true) then "error"
  elif (.tool_response.stderr // "" | length > 0) then "error"
  elif (.tool_response.error // "" | length > 0) then "error"
  else "ok"
  end
' 2>/dev/null) || exit 0

excerpt=""
if [[ "$is_error" == "error" ]]; then
  excerpt=$(echo "$payload" | jq -r '
    .tool_response.stderr //
    .tool_response.error //
    (.tool_response | tostring)
  ' 2>/dev/null | tr '\n\t' '  ' | cut -c1-80)
fi

ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
printf '%s\t%s\t%s\t%s\n' "$ts" "$tool" "$is_error" "$excerpt" >> "$log"

exit 0
