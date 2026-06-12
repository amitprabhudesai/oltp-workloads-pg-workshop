#!/usr/bin/env bash
# search-tests.sh — search test SQL and expected output for a keyword
#
# Usage: agent/scripts/search-tests.sh <keyword>
#
# Searches tests/regress/sql/*.sql and tests/regress/expected/*.out.
# Returns file:line matches with 2 lines of context so you can read
# the assertion and the surrounding setup in one pass.
#
# Run from workshop-playground/ root.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <keyword>" >&2
  exit 1
fi

KEYWORD="$1"
TEST_ROOT="tests/regress"

if [[ ! -d "$TEST_ROOT" ]]; then
  echo "Error: $TEST_ROOT not found. Run from workshop-playground/ root." >&2
  exit 1
fi

echo "=== Test SQL (specifications) ==="
grep -rn --include="*.sql" -i -C 2 "$KEYWORD" "$TEST_ROOT/sql/" 2>/dev/null \
  || echo "  (no matches)"

echo ""
echo "=== Expected output (canonical results) ==="
grep -rn --include="*.out" -i -C 2 "$KEYWORD" "$TEST_ROOT/expected/" 2>/dev/null \
  || echo "  (no matches)"
