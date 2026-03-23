from config.settings.base import *  # noqa: F401,F403

DEBUG = False
CORS_ALLOW_ALL_ORIGINS = False

# Enforce HTTPS
SECURE_SSL_REDIRECT = True
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
SECURE_HSTS_SECONDS = 31536000
SECURE_HSTS_INCLUDE_SUBDOMAINS = True
SECURE_HSTS_PRELOAD = True

# Override DATABASES for Supabase PgBouncer compatibility
DATABASES = {
    'default': {
        **env.db('DATABASE_URL'),
        'OPTIONS': {
            'sslmode': 'require',
        },
        # PgBouncer transaction mode does not support server-side cursors
        'DISABLE_SERVER_SIDE_CURSORS': True,
        # Let PgBouncer manage the pool — don't hold connections in Django
        'CONN_MAX_AGE': 0,
    }
}
