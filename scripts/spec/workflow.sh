#!/usr/bin/env bash
# workflow.sh — orchestration lookup helpers for /workflow command.
# Pure lookup: maps stage → producer agent + output artifact(s) + next-action hint.
# Knows nothing about file mutation; that's tracking.sh / roadmap.sh / change.sh.
#
# Usage:
#   workflow.sh producer --stage <stage>
#   workflow.sh artifact --stage <stage>
#   workflow.sh next-action --change <change-path>
#   workflow.sh stages
#   workflow.sh --help
#
# Exit codes:
#   0 — ok
#   2 — bad args / unknown stage
#   3 — change path invalid (missing tracking.yaml)

set -eu

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"

VALID_STAGES="refinement design decomposition implementation verification termination"

# === stage → producer agent ===
producer_for_stage() {
  case "$1" in
    refinement)     echo "system-analyst" ;;
    design)         echo "architect" ;;
    decomposition)  echo "teamlead" ;;
    implementation) echo "code-implementor" ;;
    verification)   echo "qa-engineer" ;;
    termination)    echo "termination-handler" ;;
    *) return 1 ;;
  esac
}

# === stage → artifact basename(s) ===
# Multiple basenames separated by TAB. Orchestrator parses on TAB.
artifact_for_stage() {
  case "$1" in
    refinement)     printf 'requirements.md\n' ;;
    design)         printf 'system-design.md\tapplication-design.md\n' ;;
    decomposition)  printf 'roadmap.md\n' ;;
    implementation) printf 'roadmap.md\n' ;;  # task-loop reads/writes roadmap states
    verification)   printf 'verification-report.md\n' ;;
    termination)    printf 'termination.md\n' ;;
    *) return 1 ;;
  esac
}

# === next-action hint based on tracking.yaml ===
# Output: one of  start | resume | review | approve | advance | done | blocked | declined
next_action_for_change() {
  local cp="$1"
  if [ ! -f "$cp/tracking.yaml" ]; then
    return 3
  fi
  local status stage state
  status=$("$SELF_DIR/tracking.sh" derive-status --change "$cp")
  if [ "$status" = "declined" ]; then
    echo "declined"; return 0
  fi
  if [ "$status" = "done" ]; then
    echo "done"; return 0
  fi
  stage=$("$SELF_DIR/tracking.sh" derive-stage --change "$cp")
  if [ "$stage" = "none" ]; then
    echo "done"; return 0
  fi
  state=$("$SELF_DIR/tracking.sh" get-stage --change "$cp" --stage "$stage")
  case "$state" in
    estimation|required) echo "start" ;;
    pending)             echo "blocked" ;;
    in-progress)         echo "resume" ;;
    review)              echo "approve" ;;
    completed|skipped)   echo "advance" ;;
    rejected)            echo "blocked" ;;
    *) echo "unknown"; return 2 ;;
  esac
}

# === arg parsing helpers ===
require_value() {
  if [ -z "${2-}" ]; then
    echo "error: $1 requires a value" >&2
    exit 2
  fi
}

cmd_producer() {
  local stage=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --stage) require_value "--stage" "${2-}"; stage="$2"; shift 2 ;;
      *) echo "error: unknown arg $1" >&2; exit 2 ;;
    esac
  done
  if [ -z "$stage" ]; then echo "error: --stage required" >&2; exit 2; fi
  producer_for_stage "$stage" || { echo "error: unknown stage $stage" >&2; exit 2; }
}

cmd_artifact() {
  local stage=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --stage) require_value "--stage" "${2-}"; stage="$2"; shift 2 ;;
      *) echo "error: unknown arg $1" >&2; exit 2 ;;
    esac
  done
  if [ -z "$stage" ]; then echo "error: --stage required" >&2; exit 2; fi
  artifact_for_stage "$stage" || { echo "error: unknown stage $stage" >&2; exit 2; }
}

cmd_next_action() {
  local cp=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --change) require_value "--change" "${2-}"; cp="$2"; shift 2 ;;
      *) echo "error: unknown arg $1" >&2; exit 2 ;;
    esac
  done
  if [ -z "$cp" ]; then echo "error: --change required" >&2; exit 2; fi
  next_action_for_change "$cp"
}

cmd_stages() {
  for s in $VALID_STAGES; do echo "$s"; done
}

usage() {
  cat >&2 <<'USAGE'
workflow.sh — orchestration lookup helpers

Subcommands:
  producer    --stage <stage>           # echo producer agent name
  artifact    --stage <stage>           # echo output artifact basename(s) (tab-separated if multiple)
  next-action --change <change-path>    # echo one-word hint: start|resume|review|approve|advance|done|blocked|declined
  stages                                # list all 6 valid stages
  --help                                # this message

Valid stages: refinement | design | decomposition | implementation | verification | termination
USAGE
}

main() {
  if [ $# -eq 0 ]; then usage; exit 2; fi
  local sub="$1"; shift
  case "$sub" in
    producer)    cmd_producer "$@" ;;
    artifact)    cmd_artifact "$@" ;;
    next-action) cmd_next_action "$@" ;;
    stages)      cmd_stages ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "error: unknown subcommand $sub" >&2; usage; exit 2 ;;
  esac
}

main "$@"
