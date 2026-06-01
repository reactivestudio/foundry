#!/usr/bin/env bash
# setup.sh — idempotent scaffold of .foundry/ in the target project (cwd).
#
# Creates:
#   .foundry/changes/{backlog,in-progress,done,declined}/.gitkeep
#   .foundry/changes/.template/{tracking.yaml,proposal.md}
#
# With --install-cli, additionally:
#   .foundry/cli  →  ${CLAUDE_PLUGIN_ROOT}/cli  (symlink)
#   ./foundry     →  ${CLAUDE_PLUGIN_ROOT}/cli  (symlink at project root)
#   .gitignore    ← /foundry and /.foundry/cli appended if missing
#
# The root-level `foundry` symlink lets you type `./foundry` from anywhere
# in the project tree (combined with bash's auto-PATH search for "./" it
# IS your project-local entry point).  Both symlinks point at the same
# plugin binary, so a plugin upgrade lights them up automatically.
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
                  ./foundry at the project root) and add them to
                  the project .gitignore.
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
  # Always refresh both links so a plugin-path move (e.g. version upgrade
  # under ~/.claude/plugins/) lights them up without manual cleanup.
  inner_link="$FOUNDRY_ROOT/cli"
  root_link="$PROJECT_ROOT/foundry"
  ln -sf "$SRC_CLI" "$inner_link"
  ln -sf "$SRC_CLI" "$root_link"
  # Both links are plugin-path-dependent and per-developer, so they
  # don't belong in version control.
  _ensure_gitignore_line "/foundry"
  _ensure_gitignore_line "/.foundry/cli"
  cli_status="
  cli              — symlink → $SRC_CLI (.foundry/cli + ./foundry)
                     run: ./foundry        from project root
                     run: ./.foundry/cli   from inside .foundry/
                     .gitignore: /foundry and /.foundry/cli added"
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
