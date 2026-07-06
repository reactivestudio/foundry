#!/usr/bin/env bash
# constants.sh — single source of truth for framework constants.
#
# Source this file; do not execute it directly. Sourcing makes the
# arrays available in the caller's shell (bash arrays don't survive
# export across subshells).

# Buckets a change can live in. Order is significant for `list` output
# (backlog first, terminal states last).
# shellcheck disable=SC2034  # read by every layer that iterates buckets
BUCKETS=(backlog in-progress 'done' declined)
