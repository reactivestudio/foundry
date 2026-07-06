#!/usr/bin/env bash
# opinion-words.sh — research artifact must contain facts, not opinions.
#
# CRISPY §3: «If you tell the model what you're building, then you get
# opinions.» Research stage must return facts (file:line, what's there),
# not recommendations. This script greps for opinion-words and fails the
# artifact if any are found OUTSIDE code blocks.
#
# Code blocks (```...```) are skipped — opinion words inside quoted
# code/output are fine (a snippet might literally contain "should").
#
# Banned words (case-insensitive, word-boundary):
#   English:  recommend, suggest, should, ought, better, prefer, propose,
#             advise, ideally, preferable
#   Russian:  следует, рекомендую, рекомендуется, лучше, предлагаю,
#             предпочтительно, желательно
#
# Exit codes:
#   0  — clean
#   1  — opinion words found (prints file:line:match to stderr)
#   64 — usage error

set -euo pipefail

# Force UTF-8 locale so grep/awk treat Cyrillic and other multibyte
# input correctly. Required because child shells inherit LC_CTYPE=C
# from the env, which makes BSD grep silently skip non-ASCII matches.
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

usage() {
  echo "usage: opinion-words.sh <file>" >&2
  exit 64
}

[[ $# -eq 1 ]] || usage
file="$1"
[[ -f "$file" ]] || { echo "no such file: $file" >&2; exit 64; }

EN='recommend|recommends|recommended|suggest|suggests|suggested|should|ought|better|prefer|prefers|propose|proposes|advise|advises|ideally|preferable'
RU='следует|рекомендую|рекомендуется|рекомендуем|лучше|предлагаю|предпочтительно|желательно'
PATTERN="\\b(${EN})\\b|(${RU})"

# Strip fenced code blocks before scanning. Preserve line numbers by
# replacing in-block lines with empty strings (awk).
stripped=$(awk '
  /^[[:space:]]*```/ { in_block = !in_block; print ""; next }
  in_block          { print ""; next }
                    { print }
' "$file")

hits=$(echo "$stripped" | grep -niE "$PATTERN" || true)

if [[ -n "$hits" ]]; then
  echo "opinion-words FAIL: $file" >&2
  while IFS= read -r line; do
    echo "  $file:$line" >&2
  done <<< "$hits"
  exit 1
fi

echo "opinion-words PASS: $file"
