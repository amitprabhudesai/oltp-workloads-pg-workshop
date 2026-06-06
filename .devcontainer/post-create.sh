#!/usr/bin/env bash
set -euo pipefail

echo "==> Waiting for PostgreSQL to be ready..."
until pg_isready -h postgres -U workshop -d workshop; do
  sleep 1
done

echo "==> Loading schema..."
psql -h postgres -U workshop -d workshop -f /workspace/modules/00-setup/01_schema.sql

echo "==> Loading seed data..."
psql -h postgres -U workshop -d workshop -f /workspace/modules/00-setup/02_seed.sql

echo ""
echo "Workshop database is ready."
echo "Connect with: psql -h postgres -U workshop -d workshop"
echo "Or just: psql  (env vars are set)"
