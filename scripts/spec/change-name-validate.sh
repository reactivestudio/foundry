#!/usr/bin/env bash
# Usage: change-name-validate.sh <name>
# Validates that <name> is kebab-case and not already used in ANY bucket.
# Scans .spec/changes/{backlog,sprint,done,declined}/<name>.
# Also reject names that conflict with bucket prefixes themselves.
# Exit 0 + "valid" on success; exit 1 + diagnostic on stderr on failure.
# Exit 2 on missing argument.

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

# Bucket prefix conflict (cannot name a change after the bucket it would sit in).
for reserved in backlog sprint done declined _template; do
  if [ "$name" = "$reserved" ]; then
    echo "change-name-validate: '$name' conflicts with reserved bucket/template name" >&2
    exit 1
  fi
done

# Uniqueness scan across all 4 buckets.
for bucket in backlog sprint done declined; do
  if [ -d ".spec/changes/$bucket/$name" ]; then
    echo "change-name-validate: change '$name' already exists in $bucket bucket (.spec/changes/$bucket/$name)" >&2
    exit 1
  fi
done

echo "valid"
