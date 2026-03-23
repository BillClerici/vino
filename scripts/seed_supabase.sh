#!/bin/bash
# Seed the Supabase database with local data.
#
# Usage:
#   bash scripts/seed_supabase.sh
#
# Requires DATABASE_URL_DIRECT set to the Supabase direct connection string.
# You can pass it inline:
#   DATABASE_URL=postgresql://postgres.ref:pw@host:5432/postgres \
#   DATABASE_URL_DIRECT=postgresql://postgres.ref:pw@host:5432/postgres \
#   DJANGO_SETTINGS_MODULE=config.settings.prod \
#   bash scripts/seed_supabase.sh

set -e

if [ -z "$DATABASE_URL" ]; then
    echo "ERROR: DATABASE_URL is not set."
    echo "Set it to your Supabase direct connection string."
    exit 1
fi

echo "==> Running migrations..."
python manage.py migrate --no-input

echo "==> Loading seed data..."
python manage.py load_seed_data --file seed_data.json

echo "==> Done! Seed data loaded into Supabase."
