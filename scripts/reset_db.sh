#!/usr/bin/env bash
# =============================================================================
# reset_db.sh
#
# Drops and recreates all workshop tables, then reloads seed data.
# Run this between exercises to start from a clean baseline.
# =============================================================================
set -euo pipefail

PSQL="psql -h postgres -U workshop -d workshop"

echo "==> Resetting workshop database..."

$PSQL <<-SQL
    DROP TABLE IF EXISTS audit_log  CASCADE;
    DROP TABLE IF EXISTS transfers  CASCADE;
    DROP TABLE IF EXISTS accounts   CASCADE;
SQL

$PSQL -f /workspace/modules/00-setup/01_schema.sql
$PSQL -f /workspace/modules/00-setup/02_seed.sql

echo "==> Done. Database is back to baseline."
