#!/bin/bash
set -x

echo "=== Starting Railway ==="
echo "PORT=$PORT"
echo "DJANGO_SETTINGS_MODULE=$DJANGO_SETTINGS_MODULE"

# Auto-set BUILD_NUMBER from Railway deployment ID if not set
if [ -z "$BUILD_NUMBER" ] || [ "$BUILD_NUMBER" = "0" ]; then
    export BUILD_NUMBER="${RAILWAY_GIT_COMMIT_SHA:0:7}"
fi
echo "BUILD_NUMBER=$BUILD_NUMBER"

echo "=== Running migrations ==="
python manage.py migrate --no-input

echo "=== Collecting static files ==="
python manage.py collectstatic --no-input || echo "collectstatic failed, continuing..."

echo "=== Starting gunicorn on port ${PORT:-8000} ==="
exec gunicorn config.wsgi:application \
    --bind "0.0.0.0:${PORT:-8000}" \
    --workers 2 \
    --threads 2 \
    --timeout 120 \
    --access-logfile - \
    --error-logfile - \
    --log-level info
