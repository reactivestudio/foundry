#!/usr/bin/env bash
# setup.sh — idempotent scaffold of .foundry/ in the target project (cwd).
#
# Creates:
#   .foundry/changes/{backlog,in-progress,done,declined}/.gitkeep
#   .foundry/changes/.template/{tracking.yaml,proposal.md}
#
# With --install-cli, additionally:
#   .foundry/cli   →  ${CLAUDE_PLUGIN_ROOT}/cli   (symlink to plugin)
#   ./foundry      →  .foundry/cli                (relative, chains)
#   ./f            →  .foundry/cli                (relative, chains —
#                                                  short-name twin)
#   .gitignore     ← /foundry, /f, /.foundry/cli
#
# Invocation:
#   ./foundry list        — runs from the project root
#   ./f list              — same thing, short
#   ./.foundry/cli list   — works from .foundry/ too
#
# A bare `foundry` (no `./`) needs `.` in PATH or a shell alias — neither
# is set up here.  Type the `./`.
#
# Cleanup on every --install-cli run (artifacts from 0.32.10–0.32.11
# experiments that the user asked to remove):
#   - .foundry/aliases.sh                          (deleted)
#   - /.foundry/aliases.sh line in .gitignore      (removed)
#   - shell-hook block in ~/.zshrc or ~/.bashrc    (removed, by markers)
#
# Templates are copied from ${CLAUDE_PLUGIN_ROOT}/.template/. Target
# copies are preserved on re-run so users can customize per-project.

set -euo pipefail

INSTALL_CLI=0
for arg in "$@"; do
  case "$arg" in
    --install-cli) INSTALL_CLI=1 ;;
    -h|--help)
      cat <<'EOF'
usage: setup.sh [--install-cli]

  --install-cli   also create the CLI symlinks (.foundry/cli, ./foundry,
                  ./f) and add the root-level ones to .gitignore.

                  This run will ALSO clean up any per-project aliases.sh
                  or rc-file shell hook left by older setup versions.
EOF
      exit 0 ;;
    *) echo "setup.sh: unknown arg: $arg" >&2; exit 64 ;;
  esac
done

FOUNDRY_ROOT="${FOUNDRY_ROOT:-$PWD/.foundry}"
PROJECT_ROOT="${PROJECT_ROOT:-$PWD}"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
SRC_TEMPLATE="$PLUGIN_ROOT/.template"
SRC_CLI="$PLUGIN_ROOT/cli"

# shellcheck source=../config/constants.sh
. "$(dirname "${BASH_SOURCE[0]}")/../config/constants.sh"

if [[ ! -d "$SRC_TEMPLATE" ]]; then
  echo "no template source at $SRC_TEMPLATE" >&2
  echo "(set CLAUDE_PLUGIN_ROOT or run from inside the plugin)" >&2
  exit 2
fi

# bucket dirs with .gitkeep
for b in "${BUCKETS[@]}"; do
  mkdir -p "$FOUNDRY_ROOT/changes/$b"
  [[ -f "$FOUNDRY_ROOT/changes/$b/.gitkeep" ]] || : > "$FOUNDRY_ROOT/changes/$b/.gitkeep"
done

# Mirror plugin's .template/ into .foundry/, preserving structure;
# never overwrites existing files (idempotent + user-editable).
while IFS= read -r rel; do
  rel="${rel#./}"
  dst="$FOUNDRY_ROOT/$rel"
  if [[ ! -f "$dst" ]]; then
    mkdir -p "$(dirname "$dst")"
    cp "$SRC_TEMPLATE/$rel" "$dst"
  fi
done < <(cd "$SRC_TEMPLATE" && find . -type f)

# Clean up the pre-0.21.3 layout (.foundry/bin/foundry) if present
if [[ -L "$FOUNDRY_ROOT/bin/foundry" ]]; then
  rm "$FOUNDRY_ROOT/bin/foundry"
  rmdir "$FOUNDRY_ROOT/bin" 2>/dev/null || true
fi

# Idempotently append a literal line to the project .gitignore.  Creates
# the file if it doesn't exist.  Matches exact whole lines so we don't
# stomp on entries the user already has.
_ensure_gitignore_line() {
  local entry="$1"
  local gi="$PROJECT_ROOT/.gitignore"
  if [[ ! -f "$gi" ]]; then
    : > "$gi"
  fi
  if ! grep -qxF -- "$entry" "$gi"; then
    if [[ -s "$gi" ]] && [[ $(tail -c1 "$gi" | wc -l | tr -d ' ') == "0" ]]; then
      printf '\n' >> "$gi"
    fi
    printf '%s\n' "$entry" >> "$gi"
  fi
}

# Remove a literal whole-line entry from .gitignore if it's present.
# No-op if the file or the line doesn't exist.
_remove_gitignore_line() {
  local entry="$1"
  local gi="$PROJECT_ROOT/.gitignore"
  [[ -f "$gi" ]] || return 0
  if grep -qxF -- "$entry" "$gi"; then
    local tmp; tmp=$(mktemp)
    grep -vxF -- "$entry" "$gi" > "$tmp" || true
    mv "$tmp" "$gi"
  fi
}

# Strip the foundry shell-hook block (added by 0.32.11 setup) from the
# user's rc file if present.  Identified by the start/end markers.
# No-op if the rc file doesn't exist or the block isn't there.  Sets
# CLEANUP_NOTE so the user sees what we removed.
_remove_shell_hook() {
  local rc
  case "${SHELL:-}" in
    */zsh)  rc="$HOME/.zshrc"  ;;
    */bash) rc="$HOME/.bashrc" ;;
    *)      rc="$HOME/.zshrc"  ;;
  esac
  [[ -f "$rc" ]] || return 0

  local marker_start='# >>> foundry shell hook (managed by /foundry:setup) >>>'
  if ! grep -qF -- "$marker_start" "$rc"; then
    return 0
  fi

  local tmp; tmp=$(mktemp)
  awk '
    /^# >>> foundry shell hook \(managed by \/foundry:setup\) >>>$/ { in_block = 1; next }
    /^# <<< foundry shell hook <<<$/                                { in_block = 0; next }
    in_block { next }
    { print }
  ' "$rc" > "$tmp"
  mv "$tmp" "$rc"
  CLEANUP_NOTE+=" removed foundry shell hook from ${rc/#$HOME/~};"
}

cli_status=""
CLEANUP_NOTE=""
if (( INSTALL_CLI )); then
  if [[ ! -x "$SRC_CLI" ]]; then
    echo "setup.sh: CLI not found at $SRC_CLI (CLAUDE_PLUGIN_ROOT wrong?)" >&2
    exit 2
  fi
  # .foundry/cli is the canonical local pointer to the plugin's CLI.
  # ./foundry and ./f are RELATIVE symlinks that chain through it, so
  # the plugin path appears in exactly one place — re-running setup
  # after a plugin version bump updates the chain without touching
  # the root-level symlinks.
  inner_link="$FOUNDRY_ROOT/cli"
  foundry_link="$PROJECT_ROOT/foundry"
  f_link="$PROJECT_ROOT/f"
  ln -sf "$SRC_CLI" "$inner_link"
  ln -sf ".foundry/cli" "$foundry_link"
  ln -sf ".foundry/cli" "$f_link"

  # .gitignore for the root-level symlinks — they're host-specific.
  _ensure_gitignore_line "/foundry"
  _ensure_gitignore_line "/f"
  _ensure_gitignore_line "/.foundry/cli"

  # ── cleanup of 0.32.10–0.32.11 experiments ─────────────────────────
  # Per-project aliases.sh and the rc-file shell hook were the user's
  # explicit "no global aliases" rejection — undo them on every setup.
  if [[ -f "$FOUNDRY_ROOT/aliases.sh" ]]; then
    rm -f "$FOUNDRY_ROOT/aliases.sh"
    CLEANUP_NOTE+=" removed obsolete .foundry/aliases.sh;"
  fi
  _remove_gitignore_line "/.foundry/aliases.sh"
  _remove_shell_hook

  cli_status="
  cli              — .foundry/cli → $SRC_CLI
                     ./foundry    → .foundry/cli   (relative)
                     ./f          → .foundry/cli   (relative)
                     run from project root:
                       ./foundry list      ./f list
                       ./foundry show <slug>   etc.
  .gitignore       — /foundry, /f, /.foundry/cli added"
  if [[ -n "$CLEANUP_NOTE" ]]; then
    cli_status+="
  cleanup          —${CLEANUP_NOTE}"
  fi
fi

cat <<EOF
foundry scaffold ready: $FOUNDRY_ROOT

  changes/
    backlog/      — proposed but not started
    in-progress/  — active work (one at a time)
    done/         — completed (terminal)
    declined/     — abandoned (with reason)
    .template/    — tracking.yaml + proposal.md (edit to customize)$cli_status

next: /foundry:change "your first idea"
EOF
