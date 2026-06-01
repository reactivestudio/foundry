#!/usr/bin/env bash
# setup.sh — idempotent scaffold of .foundry/ in the target project (cwd).
#
# Creates:
#   .foundry/changes/{backlog,in-progress,done,declined}/.gitkeep
#   .foundry/changes/.template/{tracking.yaml,proposal.md}
#
# With --install-cli, additionally:
#   .foundry/cli  →  ${CLAUDE_PLUGIN_ROOT}/cli  (symlink)
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

  --install-cli   also create .foundry/cli symlink to the plugin's
                  CLI, so you can run `./.foundry/cli` in this
                  project's terminal.
EOF
      exit 0 ;;
    *) echo "setup.sh: unknown arg: $arg" >&2; exit 64 ;;
  esac
done

FOUNDRY_ROOT="${FOUNDRY_ROOT:-$PWD/.foundry}"
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

# .template dir — copy each file only if missing (idempotent, user-editable)
mkdir -p "$FOUNDRY_ROOT/changes/.template"
for src in "$SRC_TEMPLATE"/*; do
  name=$(basename "$src")
  dst="$FOUNDRY_ROOT/changes/.template/$name"
  [[ -f "$dst" ]] || cp "$src" "$dst"
done

# Clean up the pre-0.21.3 layout (.foundry/bin/foundry) if present
if [[ -L "$FOUNDRY_ROOT/bin/foundry" ]]; then
  rm "$FOUNDRY_ROOT/bin/foundry"
  rmdir "$FOUNDRY_ROOT/bin" 2>/dev/null || true
fi

cli_status=""
if (( INSTALL_CLI )); then
  if [[ ! -x "$SRC_CLI" ]]; then
    echo "setup.sh: CLI not found at $SRC_CLI (CLAUDE_PLUGIN_ROOT wrong?)" >&2
    exit 2
  fi
  link="$FOUNDRY_ROOT/cli"
  # always refresh: ensures upgrade if plugin path changed
  ln -sf "$SRC_CLI" "$link"
  cli_status="
  cli              — symlink → $SRC_CLI
                     run: ./.foundry/cli  (or add .foundry to PATH)"
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
