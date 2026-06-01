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
#   .foundry/aliases.sh    →  `alias foundry=…` and `alias f=…`
#                              both expanding to ./.foundry/cli
#   .gitignore             ← /foundry, /.foundry/cli, /.foundry/aliases.sh
#
# Why a chained symlink instead of two independent symlinks?  So that a
# plugin-path move only requires updating .foundry/cli — ./foundry and
# the aliases automatically follow through the local chain.
#
# Why aliases AND a symlink?  The symlink lets `./foundry list` work
# from the project root and from scripts (no shell sourcing needed).
# The aliases let `foundry list` and `f list` work as bare commands in
# an interactive shell — once the user sources .foundry/aliases.sh.
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

  --install-cli   also create the CLI symlinks (.foundry/cli AND
                  ./foundry at the project root), write the
                  per-project aliases file (.foundry/aliases.sh), and
                  add all three to the project .gitignore.
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

cli_status=""
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

  # Write the per-project aliases file.  Sourcing it makes `foundry`
  # and `f` work as bare commands in the user's interactive shell,
  # without polluting their PATH.  Both alias targets are relative
  # to ./.foundry/cli — the local file, NOT the plugin cache path
  # — so the user's shell config doesn't need to know where the
  # plugin lives.  Rewritten on every setup run to stay in sync.
  aliases_file="$FOUNDRY_ROOT/aliases.sh"
  cat > "$aliases_file" <<'ALIASES'
#!/usr/bin/env bash
# foundry per-project aliases.
#
# Both aliases expand to ./.foundry/cli — a project-local symlink that
# in turn resolves to the plugin's CLI.  Because the path is relative,
# the aliases ONLY work when your shell's cwd is the foundry project
# root.  cd elsewhere and they'll fail with "no such file or directory"
# — which is intentional: foundry state is per-project.
#
# Activate now (current shell):
#   source .foundry/aliases.sh
#
# Activate every shell on entry to a foundry project — one-time addition
# to ~/.zshrc or ~/.bashrc:
#   [[ -f .foundry/aliases.sh ]] && source .foundry/aliases.sh
#
# Or wire it to cd hooks so it follows you between projects:
#   _foundry_chpwd() { [[ -f ./.foundry/aliases.sh ]] && source ./.foundry/aliases.sh; }
#   # zsh:
#   chpwd_functions+=(_foundry_chpwd); _foundry_chpwd
#   # bash:
#   PROMPT_COMMAND="_foundry_chpwd${PROMPT_COMMAND:+; }$PROMPT_COMMAND"
alias foundry='./.foundry/cli'
alias f='./.foundry/cli'
ALIASES

  # All three artifacts are plugin/path/host-specific so they don't
  # belong in version control.
  _ensure_gitignore_line "/foundry"
  _ensure_gitignore_line "/.foundry/cli"
  _ensure_gitignore_line "/.foundry/aliases.sh"

  cli_status="
  cli              — .foundry/cli → $SRC_CLI
                     ./foundry    → .foundry/cli   (relative, chains)
                     run: ./foundry list           — from project root
                     run: ./.foundry/cli list      — anywhere
  aliases.sh       — per-project shell aliases for \`foundry\` and \`f\`
                     activate now: source .foundry/aliases.sh
                     persistent:   add to ~/.zshrc:
                       [[ -f .foundry/aliases.sh ]] && source .foundry/aliases.sh
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
