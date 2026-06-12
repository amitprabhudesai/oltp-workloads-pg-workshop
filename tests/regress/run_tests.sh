#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# run_tests.sh  — pg_regress-style test runner using psql + normalize.sed
#
# Runs each SQL file in tests/regress/sql/, captures output to out/,
# normalizes both actual and expected via normalize.sed, then diffs.
#
# Usage (from workshop-playground root or tests/regress/):
#   ./tests/regress/run_tests.sh [test_name ...]
#
# If no names are given, all tests are run.
#
# Environment / overrides:
#   PGHOST       default: postgres  (devcontainer service name)
#   PGPORT       default: 5432
#   PGDATABASE   default: workshop
#   REGRESS_USER default: workshop  (superuser; needed for pg_stat_reset_shared)
#   REGRESS_PASS default: workshop
#
# NOTE: PGUSER / PGPASSWORD are intentionally NOT used as the primary knobs.
# The devcontainer sets PGUSER=participant in the environment, which would
# silently override a ${PGUSER:-workshop} default and break pg_stat_reset_shared.
# Use REGRESS_USER / REGRESS_PASS to override the test user explicitly.
#
# Why workshop (superuser)?
#   pg_stat_reset_shared('wal') requires superuser.  The participant role
#   has pg_read_all_stats and pg_checkpoint, but not pg_stat_reset_shared.
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_DIR="$SCRIPT_DIR/sql"
EXPECTED_DIR="$SCRIPT_DIR/expected"
OUT_DIR="$SCRIPT_DIR/out"
NORM="$SCRIPT_DIR/normalize.sed"

PGHOST="${PGHOST:-postgres}"
PGPORT="${PGPORT:-5432}"
PGDATABASE="${PGDATABASE:-workshop}"
PGUSER="${REGRESS_USER:-workshop}"
PGPASSWORD="${REGRESS_PASS:-workshop}"
export PGPASSWORD

mkdir -p "$OUT_DIR/normalized/expected" "$OUT_DIR/normalized/results"

# ── Resolve test list ────────────────────────────────────────────────────────
if [[ $# -gt 0 ]]; then
    TESTS=("$@")
else
    TESTS=()
    for f in "$SQL_DIR"/*.sql; do
        TESTS+=("$(basename "$f" .sql)")
    done
fi

PASS=0
FAIL=0
MISSING=0

# ── psql invocation that matches pg_regress behaviour ───────────────────────
run_psql() {
    local sql_file="$1"
    local out_file="$2"
    PGOPTIONS='-c client_min_messages=warning' \
    psql \
        -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" \
        -X -q \
        -f "$sql_file" \
        > "$out_file" 2>&1
}

# ── Run each test ────────────────────────────────────────────────────────────
for test in "${TESTS[@]}"; do
    sql_file="$SQL_DIR/${test}.sql"
    expected_file="$EXPECTED_DIR/${test}.out"
    out_file="$OUT_DIR/${test}.out"
    norm_expected="$OUT_DIR/normalized/expected/${test}.out"
    norm_actual="$OUT_DIR/normalized/results/${test}.out"

    if [[ ! -f "$sql_file" ]]; then
        echo "ERROR: $sql_file not found" >&2
        ((FAIL++)) || true
        continue
    fi

    if [[ ! -f "$expected_file" ]]; then
        echo "MISSING expected: $expected_file — run 'make generate-expected' first" >&2
        ((MISSING++)) || true
        continue
    fi

    printf "%-40s " "$test"
    run_psql "$sql_file" "$out_file"

    # Normalize both sides before diffing
    sed -Ef "$NORM" "$expected_file" > "$norm_expected"
    sed -Ef "$NORM" "$out_file"      > "$norm_actual"

    if diff -u "$norm_expected" "$norm_actual" > "$OUT_DIR/${test}.diff" 2>&1; then
        echo "ok"
        rm -f "$OUT_DIR/${test}.diff"
        ((PASS++)) || true
    else
        echo "FAILED"
        echo "  diff: $OUT_DIR/${test}.diff"
        ((FAIL++)) || true
    fi
done

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed, $MISSING missing expected"

if [[ $FAIL -gt 0 || $MISSING -gt 0 ]]; then
    exit 1
fi
