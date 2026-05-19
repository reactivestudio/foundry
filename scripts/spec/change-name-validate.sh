#!/usr/bin/env bash
# Usage: change-name-validate.sh <name>
# Validates that <name> is kebab-case and not a currently-active change.
# Exit 0 + "valid" on success; exit 1 + diagnostic on stderr on failure.

set -eu

name=${1:-}
if [ -z "$name" ]; then
  echo "change-name-validate: missing name argument" >&2
  exit 2
fi

if ! printf '%s' "$name" | grep -qE '^[a-z][a-z0-9]*(-[a-z0-9]+)*$'; then
  echo "change-name-validate: '$name' is not kebab-case (lowercase letters/digits/hyphens; must start with a letter)" >&2
  exit 1
fi

if [ -d ".spec/changes/$name" ]; then
  echo "change-name-validate: active change '$name' already exists at .spec/changes/$name" >&2
  exit 1
fi

echo "valid"
