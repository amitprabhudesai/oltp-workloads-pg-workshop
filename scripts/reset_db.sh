#!/usr/bin/env bash
# =============================================================================
# reset_db.sh
#
# Drops and recreates the rootconf schema and all objects within it,
# then re-applies privileges and reloads seed data.
#
# Roles (rcf_owner, rcf_contributor, rcf_reviewer, amit, participant) are
# preserved across resets — only schema objects are dropped and recreated.
# =============================================================================
set -euo pipefail

PSQL="psql -h postgres -U workshop -d workshop"

echo "==> Dropping rootconf schema..."
$PSQL -c "DROP SCHEMA IF EXISTS rootconf CASCADE;"

echo "==> Recreating schema and tables..."
$PSQL -f /workspace/modules/00-setup/01_schema.sql

echo "==> Re-applying ownership and privileges..."
# Roles already exist; skip CREATE ROLE statements, only apply grants/ownership.
# The full 02_roles.sql uses IF NOT EXISTS so it's safe to re-run entirely.
$PSQL -f /workspace/modules/00-setup/02_roles.sql

echo "==> Reloading seed data..."
$PSQL -f /workspace/modules/00-setup/03_seed.sql

echo "==> Done. Database is back to baseline."
