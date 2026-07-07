#!/usr/bin/env bash
# help.sh — `foundry help` / usage text.
#
# Source this file; do not execute it directly.
# Prints usage and returns 0 — the exit code is the dispatcher's call:
# explicit `foundry help` succeeds, unknown subcommand exits 64.

cmd_help() {
  cat <<'EOF'
usage:
  foundry                          interactive: pick a change and act
  foundry list [--bucket=X]        list changes (all or filtered)
  foundry show <slug>              show a change's tracking + history
  foundry new ["title"]            create a change (asks for title if omitted)
  foundry move <slug> [--to=X] [--reason=R]
                                   move a change between buckets
  foundry sync                     rebuild per-bucket index caches (run after
                                   manual edits inside .foundry/changes/)
  foundry setup                    scaffold .foundry/ in the current project
  foundry version                  print the installed plugin version

global flags:
  --plain                          ASCII output, no prompts
EOF
}
