#\!/bin/bash
set -e

# Wait for database to be ready
echo "Waiting for database..."
while \! python -c "
import os, django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings.local')
django.setup()
from django.db import connection
connection.ensure_connection()
" 2>/dev/null; do
    sleep 1
done
echo "Database ready."

# Run migrations
python manage.py migrate --no-input

# Collect static files
python manage.py collectstatic --no-input

exec "$@"
