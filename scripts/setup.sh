#!/usr/bin/env bash
# setup.sh — idempotent scaffold of .foundry/ in the target project (cwd).
#
# Creates:
#   .foundry/changes/{backlog,in-progress,done,declined}/.gitkeep
#   .foundry/changes/.template/{tracking.yaml,proposal.md}
#
# With --install-cli, additionally:
#   .foundry/cli           →  ${CLAUDE_PLUGIN_ROOT}/cli   (symlink to plugin)
#   ./foundry              →  .foundry/cli                (RELATIVE symlink —
#                                                          chains through the
#                                                          local file so the
#                                                          plugin path lives in
#                                                          exactly one place)
#   .foundry/aliases.sh    →  `foundry()` and `f()` shell functions that
#                              walk up from cwd to find .foundry/cli
#                              and exec it — so they work from any subdir
#                              of the project, not just the root
#   ~/.zshrc or ~/.bashrc  ← a one-time, idempotent, marker-delimited
#                              cd hook that sources .foundry/aliases.sh
#                              whenever cwd is inside a foundry project
#                              (skipped with --no-shell-hook)
#   .gitignore             ← /foundry, /.foundry/cli, /.foundry/aliases.sh
#
# Net effect: after a single `setup --install-cli`, the user can type
# `foundry list` or `f list` from anywhere inside any foundry project
# in any new shell.  Nothing pollutes their PATH, nothing references
# the plugin cache by absolute path in their rc file.
#
# Templates are copied from ${CLAUDE_PLUGIN_ROOT}/.template/. Target
# copies are preserved on re-run so users can customize per-project.

set -euo pipefail

INSTALL_CLI=0
INSTALL_SHELL_HOOK=1
for arg in "$@"; do
  case "$arg" in
    --install-cli) INSTALL_CLI=1 ;;
    --no-shell-hook) INSTALL_SHELL_HOOK=0 ;;
    -h|--help)
      cat <<'EOF'
usage: setup.sh [--install-cli] [--no-shell-hook]

  --install-cli     also create the CLI symlinks (.foundry/cli AND
                    ./foundry at the project root), write the
                    per-project shell-function file (.foundry/aliases.sh),
                    install a one-time shell hook in ~/.zshrc or
                    ~/.bashrc, and add the local artifacts to .gitignore.
  --no-shell-hook   skip the ~/.zshrc / ~/.bashrc modification (the
                    user can source .foundry/aliases.sh manually).
EOF
      exit 0 ;;
    *) echo "setup.sh: unknown arg: $arg" >&2; exit 64 ;;
  esac
done

FOUNDRY_ROOT="${FOUNDRY_ROOT:-$PWD/.foundry}"
PROJECT_ROOT="${PROJECT_ROOT:-$PWD}"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SRC_TEMPLATE="$PLUGIN_ROOT/.template"
SRC_CLI="$PLUGIN_ROOT/cli"

# shellcheck source=lib/constants.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/constants.sh"

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
  # Whole-line match — skip if already present.
  if ! grep -qxF -- "$entry" "$gi"; then
    # Ensure the file ends with a newline before appending.
    if [[ -s "$gi" ]] && [[ $(tail -c1 "$gi" | wc -l | tr -d ' ') == "0" ]]; then
      printf '\n' >> "$gi"
    fi
    printf '%s\n' "$entry" >> "$gi"
  fi
}

# Append a marker-delimited block to the user's interactive shell rc
# file (~/.zshrc for zsh, ~/.bashrc for bash, ~/.zshrc as default
# fallback) so that on every shell start AND every `cd`, the shell
# walks up from cwd looking for .foundry/aliases.sh and sources it.
# The result: `foundry` and `f` work as bare commands from any depth
# inside any foundry project, with no PATH pollution.  Sets the global
# SHELL_HOOK_STATUS so the final summary can print what happened.
_install_shell_hook() {
  local rc
  case "${SHELL:-}" in
    */zsh)  rc="$HOME/.zshrc"  ;;
    */bash) rc="$HOME/.bashrc" ;;
    *)      rc="$HOME/.zshrc"  ;;  # modern default on macOS
  esac
  [[ -f "$rc" ]] || : > "$rc"

  # Stable marker — grep on this exact line to detect a prior install.
  local marker='# >>> foundry shell hook (managed by /foundry:setup) >>>'
  if grep -qF -- "$marker" "$rc"; then
    SHELL_HOOK_STATUS="already present in ${rc/#$HOME/~}"
    return 0
  fi

  # Single-quoted heredoc so every $ stays literal until the user's
  # shell sees it at runtime.
  {
    printf '\n'
    cat <<'HOOK'
# >>> foundry shell hook (managed by /foundry:setup) >>>
# Walks up from cwd looking for .foundry/aliases.sh and sources it,
# giving you `foundry` and `f` as commands inside any foundry project
# tree (works from subdirs too).  Remove this entire block to disable.
_foundry_last_pwd=""
_foundry_auto_source() {
  [[ "$PWD" == "$_foundry_last_pwd" ]] && return
  _foundry_last_pwd="$PWD"
  local d="$PWD"
  while [[ "$d" != "/" ]]; do
    if [[ -f "$d/.foundry/aliases.sh" ]]; then
      source "$d/.foundry/aliases.sh"
      return
    fi
    d="${d%/*}"
    [[ -z "$d" ]] && d="/"
  done
}
if [[ -n "${ZSH_VERSION:-}" ]]; then
  typeset -ga chpwd_functions
  chpwd_functions+=(_foundry_auto_source)
elif [[ -n "${BASH_VERSION:-}" ]]; then
  PROMPT_COMMAND="_foundry_auto_source${PROMPT_COMMAND:+; }${PROMPT_COMMAND:-}"
fi
_foundry_auto_source
# <<< foundry shell hook <<<
HOOK
  } >> "$rc"

  SHELL_HOOK_STATUS="installed in ${rc/#$HOME/~}"
}

cli_status=""
SHELL_HOOK_STATUS=""
if (( INSTALL_CLI )); then
  if [[ ! -x "$SRC_CLI" ]]; then
    echo "setup.sh: CLI not found at $SRC_CLI (CLAUDE_PLUGIN_ROOT wrong?)" >&2
    exit 2
  fi
  # .foundry/cli is the canonical local pointer to the plugin's CLI.
  # ./foundry is a RELATIVE symlink that chains through it, so the
  # plugin path only appears once — re-running setup after a plugin
  # version bump updates the chain without manual cleanup.
  inner_link="$FOUNDRY_ROOT/cli"
  root_link="$PROJECT_ROOT/foundry"
  ln -sf "$SRC_CLI" "$inner_link"
  ln -sf ".foundry/cli" "$root_link"

  # Write the per-project shell integration.  These are FUNCTIONS, not
  # aliases — they walk up from cwd to find the foundry project root,
  # then exec the local .foundry/cli with the user's args.  Net result:
  # `foundry list` works from any subdir of the project, not just root.
  # Rewritten on every setup run to stay in sync with this template.
  aliases_file="$FOUNDRY_ROOT/aliases.sh"
  cat > "$aliases_file" <<'ALIASES'
#!/usr/bin/env bash
# foundry per-project shell integration.
#
# Defines `foundry` and `f` as shell functions that walk up from your
# cwd until they find .foundry/cli, then exec that.  Works from any
# subdir of a foundry project — not just the root — because the
# search is anchored to .foundry/cli, not to ./.foundry/cli.
#
# Activate now (current shell):
#   source .foundry/aliases.sh
#
# Activate every shell automatically, with cwd-aware loading — add
# the block /foundry:setup wrote to your ~/.zshrc (or ~/.bashrc).
# That block is marked between
#   # >>> foundry shell hook ... >>>
#   # <<< foundry shell hook <<<
# delete it to disable.
_foundry_find_root() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/.foundry/cli" ]]; then
      printf '%s' "$dir"
      return 0
    fi
    dir="${dir%/*}"
    [[ -z "$dir" ]] && dir="/"
  done
  return 1
}

foundry() {
  local root
  root=$(_foundry_find_root) || {
    printf 'foundry: not in a foundry project (no .foundry/cli in any parent of %s)\n' "$PWD" >&2
    return 1
  }
  # Export FOUNDRY_ROOT so the cli (which by default reads $PWD/.foundry)
  # finds the project's scaffold even when we're invoked from a subdir.
  FOUNDRY_ROOT="$root/.foundry" "$root/.foundry/cli" "$@"
}

f() { foundry "$@"; }
ALIASES

  # All three artifacts are plugin/path/host-specific so they don't
  # belong in version control.
  _ensure_gitignore_line "/foundry"
  _ensure_gitignore_line "/.foundry/cli"
  _ensure_gitignore_line "/.foundry/aliases.sh"

  # Auto-install the cd-hook in the user's interactive shell rc unless
  # they opted out with --no-shell-hook.
  if (( INSTALL_SHELL_HOOK )); then
    _install_shell_hook
  else
    SHELL_HOOK_STATUS='skipped (--no-shell-hook)'
  fi

  cli_status="
  cli              — .foundry/cli → $SRC_CLI
                     ./foundry    → .foundry/cli   (relative, chains)
                     run: ./foundry list           — from project root
                     run: ./.foundry/cli list      — anywhere
  aliases.sh       — defines \`foundry\` and \`f\` as shell functions
                     (walk up to find .foundry/cli — work from any subdir)
                     activate now in this shell:  source .foundry/aliases.sh
  shell hook       — ${SHELL_HOOK_STATUS}
                     start a NEW terminal — \`foundry\` and \`f\` then work
                     anywhere inside any foundry project
  .gitignore       — /foundry, /.foundry/cli, /.foundry/aliases.sh added"
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
