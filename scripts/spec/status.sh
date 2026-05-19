#!/usr/bin/env bash
# Usage: status.sh <change-name>
# Reports artifact state for a change.
# Output: TSV — artifact<TAB>state<TAB>path
#   state: [x] (exists), [ ] (deps met, file missing), [-] (blocked)
# Exit 0 on success; 2 on bad usage / missing change.

set -eu

name=${1:-}
if [ -z "$name" ]; then
  echo "status: missing change-name argument" >&2
  exit 2
fi

dir=".spec/changes/$name"
if [ ! -d "$dir" ]; then
  echo "status: change '$name' not found at $dir" >&2
  exit 2
fi

has() { [ -f "$1" ]; }

prop="$dir/proposal.md"
specs_dir="$dir/specs"
design="$dir/design.md"
tasks="$dir/tasks.md"

# proposal — no dependencies.
if has "$prop"; then echo -e "proposal\t[x]\t$prop"
else                  echo -e "proposal\t[ ]\t$prop"
fi

# specs — depends on proposal.
have_specs=0
if [ -d "$specs_dir" ] && [ -n "$(find "$specs_dir" -mindepth 2 -maxdepth 2 -name 'spec.md' -print 2>/dev/null | head -1)" ]; then
  have_specs=1
fi
if [ "$have_specs" = "1" ]; then echo -e "specs\t[x]\t$specs_dir/*/spec.md"
elif has "$prop";        then echo -e "specs\t[ ]\t$specs_dir/<capability>/spec.md"
else                          echo -e "specs\t[-]\t$specs_dir/<capability>/spec.md"
fi

# design — depends on specs.
if has "$design";          then echo -e "design\t[x]\t$design"
elif [ "$have_specs" = "1" ]; then echo -e "design\t[ ]\t$design"
else                            echo -e "design\t[-]\t$design"
fi

# tasks — depends on design.
if has "$tasks";    then echo -e "tasks\t[x]\t$tasks"
elif has "$design"; then echo -e "tasks\t[ ]\t$tasks"
else                     echo -e "tasks\t[-]\t$tasks"
fi
