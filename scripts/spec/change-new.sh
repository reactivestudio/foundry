#!/usr/bin/env bash
# Usage: change-new.sh <title> [<name-override>]
# Creates a new change in .spec/changes/backlog/<name>/ from the _template/ scaffold.
# Derives <name> as kebab-case slug from <title> unless an explicit override is provided.
# Substitutes {{id}}, {{title}}, {{now}} placeholders in tracking.yaml + proposal.md.
# Output: absolute path to the new change directory.
# Exit 0 ok; 1 invalid name (delegated to change-name-validate); 2 bad args; 3 already exists / template missing.

set -eu

title=${1:-}
name_override=${2:-}

if [ -z "$title" ]; then
  echo "change-new: missing arg (need <title>)" >&2
  exit 2
fi

# Derive slug from title: lowercase, ws → '-', strip non-[a-z0-9-], collapse repeats, trim hyphens.
derive_slug() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -s '[:space:]' '-' \
    | sed -e 's/[^a-z0-9-]//g' -e 's/--*/-/g' -e 's/^-//' -e 's/-$//'
}

if [ -n "$name_override" ]; then
  name=$name_override
else
  name=$(derive_slug "$title")
fi

if [ -z "$name" ]; then
  echo "change-new: could not derive a valid name from title '$title'; pass an explicit <name-override>" >&2
  exit 2
fi

self_dir=$(cd "$(dirname "$0")" && pwd)

# Validate name (kebab-case + uniqueness across all 4 buckets).
if ! "$self_dir/change-name-validate.sh" "$name" >/dev/null; then
  exit 1
fi

# Locate template scaffold. Order:
#   1) ${CLAUDE_PLUGIN_ROOT}/.claude-template/spec/changes/_template (plugin-installed)
#   2) .spec/changes/_template (project-local copy)
# Either must contain tracking.yaml + proposal.md.
template=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "$CLAUDE_PLUGIN_ROOT/.claude-template/spec/changes/_template" ]; then
  template="$CLAUDE_PLUGIN_ROOT/.claude-template/spec/changes/_template"
elif [ -d ".spec/changes/_template" ]; then
  template=".spec/changes/_template"
else
  echo "change-new: scaffold template not found (looked for \$CLAUDE_PLUGIN_ROOT/.claude-template/spec/changes/_template and .spec/changes/_template)" >&2
  exit 3
fi

# Ensure target backlog exists; build destination path.
mkdir -p ".spec/changes/backlog"
dest=".spec/changes/backlog/$name"
if [ -e "$dest" ]; then
  echo "change-new: destination already exists at $dest" >&2
  exit 3
fi

cp -r "$template" "$dest"

# Substitute placeholders.
now=$(date '+%Y-%m-%d %H:%M')
# Escape characters that sed treats specially in replacement string.
title_escaped=$(printf '%s' "$title" | sed 's/[&/\]/\\&/g')

for f in "$dest"/tracking.yaml "$dest"/proposal.md; do
  [ -f "$f" ] || continue
  tmp=$(mktemp "${TMPDIR:-/tmp}/change-new.XXXXXX")
  sed -e "s/{{id}}/$name/g" -e "s/{{title}}/$title_escaped/g" -e "s/{{now}}/$now/g" "$f" > "$tmp"
  mv "$tmp" "$f"
done

# Echo absolute path to new change directory.
abs=$(cd "$dest" && pwd)
echo "$abs"
