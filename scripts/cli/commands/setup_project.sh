#!/usr/bin/env bash
# setup_project.sh — `foundry setup`: idempotent scaffold of .foundry/ in the
# target project (cwd).
#
# Source this file; do not execute it directly.
# Needs: BUCKETS (constants.sh), FOUNDRY_ROOT, PLUGIN_ROOT.
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

# Idempotently append a literal line to the project .gitignore.  Creates
# the file if it doesn't exist.  Matches exact whole lines so we don't
# stomp on entries the user already has.
_setup_ensure_gitignore_line() {
  local entry="$1"
  local gitignore_file="$PROJECT_ROOT/.gitignore"
  if [[ ! -f "$gitignore_file" ]]; then
    : > "$gitignore_file"
  fi
  if ! grep -qxF -- "$entry" "$gitignore_file"; then
    if [[ -s "$gitignore_file" ]] \
       && [[ $(tail -c1 "$gitignore_file" | wc -l | tr -d ' ') == "0" ]]; then
      printf '\n' >> "$gitignore_file"
    fi
    printf '%s\n' "$entry" >> "$gitignore_file"
  fi
}

# Remove a literal whole-line entry from .gitignore if it's present.
# No-op if the file or the line doesn't exist.
_setup_remove_gitignore_line() {
  local entry="$1"
  local gitignore_file="$PROJECT_ROOT/.gitignore"
  [[ -f "$gitignore_file" ]] || return 0
  if grep -qxF -- "$entry" "$gitignore_file"; then
    local temp_file; temp_file=$(mktemp)
    grep -vxF -- "$entry" "$gitignore_file" > "$temp_file" || true
    mv "$temp_file" "$gitignore_file"
  fi
}

# Strip the foundry shell-hook block (added by 0.32.11 setup) from the
# user's rc file if present.  Identified by the start/end markers.
# No-op if the rc file doesn't exist or the block isn't there.  Appends
# to CLEANUP_NOTE (caller's local) so the user sees what we removed.
_setup_remove_shell_hook() {
  local rc_file
  case "${SHELL:-}" in
    */zsh)  rc_file="$HOME/.zshrc"  ;;
    */bash) rc_file="$HOME/.bashrc" ;;
    *)      rc_file="$HOME/.zshrc"  ;;
  esac
  [[ -f "$rc_file" ]] || return 0

  local marker_start='# >>> foundry shell hook (managed by /foundry:setup) >>>'
  if ! grep -qF -- "$marker_start" "$rc_file"; then
    return 0
  fi

  local temp_file; temp_file=$(mktemp)
  awk '
    /^# >>> foundry shell hook \(managed by \/foundry:setup\) >>>$/ { in_block = 1; next }
    /^# <<< foundry shell hook <<<$/                                { in_block = 0; next }
    in_block { next }
    { print }
  ' "$rc_file" > "$temp_file"
  mv "$temp_file" "$rc_file"
  CLEANUP_NOTE+=" removed foundry shell hook from ${rc_file/#$HOME/~};"
}

cmd_setup_project() {
  local install_cli=0
  for arg in "$@"; do
    case "$arg" in
      --install-cli) install_cli=1 ;;
      -h|--help)
        cat <<'EOF'
usage: foundry setup [--install-cli]

  --install-cli   also create the CLI symlinks (.foundry/cli, ./foundry,
                  ./f) and add the root-level ones to .gitignore.

                  This run will ALSO clean up any per-project aliases.sh
                  or rc-file shell hook left by older setup versions.
EOF
        return 0 ;;
      *) ui_error "setup: unknown flag: $arg"; exit 64 ;;
    esac
  done

  local PROJECT_ROOT="${PROJECT_ROOT:-$PWD}"
  local template_source="$PLUGIN_ROOT/.template"
  local cli_source="$PLUGIN_ROOT/cli"

  if [[ ! -d "$template_source" ]]; then
    ui_error "no template source at $template_source"
    ui_error "(set CLAUDE_PLUGIN_ROOT or run from inside the plugin)"
    exit 2
  fi

  # bucket dirs with .gitkeep
  local bucket
  for bucket in "${BUCKETS[@]}"; do
    mkdir -p "$FOUNDRY_ROOT/changes/$bucket"
    [[ -f "$FOUNDRY_ROOT/changes/$bucket/.gitkeep" ]] \
      || : > "$FOUNDRY_ROOT/changes/$bucket/.gitkeep"
  done

  # Mirror plugin's .template/ into .foundry/, preserving structure;
  # never overwrites existing files (idempotent + user-editable).
  local relative_path destination
  while IFS= read -r relative_path; do
    relative_path="${relative_path#./}"
    destination="$FOUNDRY_ROOT/$relative_path"
    if [[ ! -f "$destination" ]]; then
      mkdir -p "$(dirname "$destination")"
      cp "$template_source/$relative_path" "$destination"
    fi
  done < <(cd "$template_source" && find . -type f)

  # Clean up the pre-0.21.3 layout (.foundry/bin/foundry) if present
  if [[ -L "$FOUNDRY_ROOT/bin/foundry" ]]; then
    rm "$FOUNDRY_ROOT/bin/foundry"
    rmdir "$FOUNDRY_ROOT/bin" 2>/dev/null || true
  fi

  local cli_status=""
  local CLEANUP_NOTE=""
  if (( install_cli )); then
    if [[ ! -x "$cli_source" ]]; then
      ui_error "setup: CLI not found at $cli_source (CLAUDE_PLUGIN_ROOT wrong?)"
      exit 2
    fi
    # .foundry/cli is the canonical local pointer to the plugin's CLI.
    # ./foundry and ./f are RELATIVE symlinks that chain through it, so
    # the plugin path appears in exactly one place — re-running setup
    # after a plugin version bump updates the chain without touching
    # the root-level symlinks.
    ln -sf "$cli_source" "$FOUNDRY_ROOT/cli"
    ln -sf ".foundry/cli" "$PROJECT_ROOT/foundry"
    ln -sf ".foundry/cli" "$PROJECT_ROOT/f"

    # .gitignore for the root-level symlinks — they're host-specific.
    _setup_ensure_gitignore_line "/foundry"
    _setup_ensure_gitignore_line "/f"
    _setup_ensure_gitignore_line "/.foundry/cli"

    # ── cleanup of 0.32.10–0.32.11 experiments ─────────────────────────
    # Per-project aliases.sh and the rc-file shell hook were the user's
    # explicit "no global aliases" rejection — undo them on every setup.
    if [[ -f "$FOUNDRY_ROOT/aliases.sh" ]]; then
      rm -f "$FOUNDRY_ROOT/aliases.sh"
      CLEANUP_NOTE+=" removed obsolete .foundry/aliases.sh;"
    fi
    _setup_remove_gitignore_line "/.foundry/aliases.sh"
    _setup_remove_shell_hook

    cli_status="
  cli              — .foundry/cli → $cli_source
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
}
