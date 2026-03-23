from config.settings.base import *  # noqa: F401,F403

DEBUG = False

# Railway provides RAILWAY_PUBLIC_DOMAIN
RAILWAY_DOMAIN = env('RAILWAY_PUBLIC_DOMAIN', default='')
ALLOWED_HOSTS = env.list('ALLOWED_HOSTS', default=['localhost'])
if RAILWAY_DOMAIN:
    ALLOWED_HOSTS.append(RAILWAY_DOMAIN)
    ALLOWED_HOSTS.append(f'.{RAILWAY_DOMAIN}')

# CORS — allow mobile app and Railway domain
CORS_ALLOW_ALL_ORIGINS = False
CORS_ALLOWED_ORIGINS = env.list('CORS_ALLOWED_ORIGINS', default=[])
if RAILWAY_DOMAIN:
    CORS_ALLOWED_ORIGINS.append(f'https://{RAILWAY_DOMAIN}')
# Allow all origins for mobile API calls (no browser CORS applies to native apps,
# but web testing still needs it)
CORS_ALLOW_ALL_ORIGINS = env.bool('CORS_ALLOW_ALL', default=True)

# CSRF trusted origins
CSRF_TRUSTED_ORIGINS = env.list('CSRF_TRUSTED_ORIGINS', default=[])
if RAILWAY_DOMAIN:
    CSRF_TRUSTED_ORIGINS.append(f'https://{RAILWAY_DOMAIN}')

# Security — HTTPS
SECURE_SSL_REDIRECT = env.bool('SECURE_SSL_REDIRECT', default=True)
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
SECURE_HSTS_SECONDS = 31536000
SECURE_HSTS_INCLUDE_SUBDOMAINS = True
SECURE_HSTS_PRELOAD = True

# Railway uses a reverse proxy — trust the forwarded headers
SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')

# Override DATABASES for Supabase PgBouncer compatibility
DATABASES = {
    'default': {
        **env.db('DATABASE_URL'),
        'OPTIONS': {
            'sslmode': 'require',
        },
        'DISABLE_SERVER_SIDE_CURSORS': True,
        'CONN_MAX_AGE': 0,
    }
}

# Static files — whitenoise for Railway (no S3 needed)
MIDDLEWARE.insert(1, 'whitenoise.middleware.WhiteNoiseMiddleware')
STATICFILES_STORAGE = 'whitenoise.storage.CompressedManifestStaticFilesStorage'
