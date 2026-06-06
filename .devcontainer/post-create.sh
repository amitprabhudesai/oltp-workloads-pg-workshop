#!/usr/bin/env bash
set -euo pipefail

# All setup runs as the 'workshop' superuser. Participants connect as 'participant'.
export PGPASSWORD=workshop
PSQL="psql -h postgres -U workshop -d workshop"

echo "==> Waiting for PostgreSQL to be ready..."
until pg_isready -h postgres -U workshop -d workshop; do
  sleep 1
done

echo "==> Loading schema..."
$PSQL -f /workspace/modules/00-setup/01_schema.sql

echo "==> Setting up roles and privileges..."
$PSQL -f /workspace/modules/00-setup/02_roles.sql

echo "==> Loading seed data..."
$PSQL -f /workspace/modules/00-setup/03_seed.sql

echo ""
cp /workspace/.devcontainer/psqlrc ~/.psqlrc

echo "Workshop database is ready."
echo ""
echo "  Default session (participant):  psql"
echo "  Owner session   (amit):         psql -U amit -W"
echo "  Superuser       (workshop):     psql -U workshop"
