import os
from datetime import timedelta
from pathlib import Path

import environ

env = environ.Env()

BASE_DIR = Path(__file__).resolve().parent.parent.parent

# Read .env file
environ.Env.read_env(os.path.join(BASE_DIR, '.env'), overwrite=False)

# App version — BUILD_NUMBER set by CI or Railway
BUILD_NUMBER = env('BUILD_NUMBER', default='dev')
APP_VERSION_FULL = f'v1.0.{BUILD_NUMBER}'

SECRET_KEY = env('DJANGO_SECRET_KEY')
DEBUG = env.bool('DEBUG', default=False)
ALLOWED_HOSTS = env.list('ALLOWED_HOSTS', default=['localhost', '127.0.0.1'])

INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    # Third party (from selected modules)
    'django_celery_results',
    'social_django',
    'rest_framework',
    'corsheaders',
    'django_filters',
    'drf_spectacular',
    # GSD apps
    'apps.core',
    'apps.lookup',
    'apps.users',
    'apps.api',
    'apps.rbac',
    # Vino Trip apps
    'apps.wineries',
    'apps.visits',
    'apps.trips',
    'apps.palate',
    'apps.partners',
]

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'whitenoise.middleware.WhiteNoiseMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'corsheaders.middleware.CorsMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
    'apps.users.middleware.SubscriptionRequiredMiddleware',
    'apps.core.middleware.UserTimezoneMiddleware',
]

ROOT_URLCONF = 'config.urls'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [BASE_DIR / 'templates'],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.debug',
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
                'apps.core.context_processors.app_version_context',
                'apps.core.context_processors.partner_context',
            ],
        },
    },
]

WSGI_APPLICATION = 'config.wsgi.application'

DATABASES = {
    'default': env.db('DATABASE_URL')
}

# Raw connection strings for LangGraph checkpointer (psycopg3 format)
DATABASE_URL = env('DATABASE_URL')
# Direct connection (bypasses PgBouncer) — used for migrations and LangGraph
DATABASE_URL_DIRECT = env('DATABASE_URL_DIRECT', default=DATABASE_URL)

AUTH_USER_MODEL = 'users.User'

# Authentication backends
AUTHENTICATION_BACKENDS = [
    'social_core.backends.google.GoogleOAuth2',
    'social_core.backends.microsoft.MicrosoftOAuth2',
    'django.contrib.auth.backends.ModelBackend',
]

# Encrypted model fields
FIELD_ENCRYPTION_KEY = env('FIELD_ENCRYPTION_KEY')

# Social Auth
SOCIAL_AUTH_JSONFIELD_ENABLED = True
SOCIAL_AUTH_USER_MODEL = 'users.User'
SOCIAL_AUTH_USERNAME_IS_FULL_EMAIL = True
SOCIAL_AUTH_LOGIN_REDIRECT_URL = '/'
SOCIAL_AUTH_NEW_USER_REDIRECT_URL = '/'

LOGIN_URL = '/login/'
LOGIN_REDIRECT_URL = '/'
LOGOUT_REDIRECT_URL = '/'

SOCIAL_AUTH_GOOGLE_OAUTH2_KEY = env('GOOGLE_CLIENT_ID', default='')
SOCIAL_AUTH_GOOGLE_OAUTH2_SECRET = env('GOOGLE_CLIENT_SECRET', default='')
SOCIAL_AUTH_GOOGLE_OAUTH2_SCOPE = [
    'openid',
    'https://www.googleapis.com/auth/userinfo.email',
    'https://www.googleapis.com/auth/userinfo.profile',
]

SOCIAL_AUTH_MICROSOFT_OAUTH2_KEY = env('MICROSOFT_CLIENT_ID', default='')
SOCIAL_AUTH_MICROSOFT_OAUTH2_SECRET = env('MICROSOFT_CLIENT_SECRET', default='')
SOCIAL_AUTH_MICROSOFT_OAUTH2_SCOPE = ['openid', 'profile', 'email', 'offline_access']
SOCIAL_AUTH_MICROSOFT_OAUTH2_TENANT_ID = env('MICROSOFT_TENANT_ID', default='common')

SOCIAL_AUTH_PIPELINE = (
    'social_core.pipeline.social_auth.social_details',
    'social_core.pipeline.social_auth.social_uid',
    'social_core.pipeline.social_auth.auth_allowed',
    'social_core.pipeline.social_auth.social_user',
    'social_core.pipeline.social_auth.associate_by_email',
    'social_core.pipeline.user.get_username',
    'social_core.pipeline.user.create_user',
    'social_core.pipeline.social_auth.associate_user',
    'social_core.pipeline.social_auth.load_extra_data',
    'social_core.pipeline.user.user_details',
    'apps.users.pipeline.save_social_account',
    'apps.users.pipeline.issue_jwt',
)

# JWT
SIMPLE_JWT = {
    'ACCESS_TOKEN_LIFETIME': timedelta(minutes=60),
    'REFRESH_TOKEN_LIFETIME': timedelta(days=14),
    'ROTATE_REFRESH_TOKENS': True,
    'BLACKLIST_AFTER_ROTATION': True,
    'ALGORITHM': 'HS256',
    'AUTH_HEADER_TYPES': ('Bearer',),
}

# REST Framework
REST_FRAMEWORK = {
    'DEFAULT_AUTHENTICATION_CLASSES': [
        'rest_framework_simplejwt.authentication.JWTAuthentication',
    ],
    'DEFAULT_PERMISSION_CLASSES': [
        'rest_framework.permissions.IsAuthenticated',
    ],
    'DEFAULT_RENDERER_CLASSES': [
        'apps.api.v1.renderers.VinoJSONRenderer',
    ],
    'DEFAULT_PAGINATION_CLASS': 'apps.api.v1.pagination.VinoPagination',
    'DEFAULT_FILTER_BACKENDS': [
        'django_filters.rest_framework.DjangoFilterBackend',
        'rest_framework.filters.SearchFilter',
        'rest_framework.filters.OrderingFilter',
    ],
    'PAGE_SIZE': 25,
    'DEFAULT_SCHEMA_CLASS': 'drf_spectacular.openapi.AutoSchema',
}

# OpenAPI / Swagger
SPECTACULAR_SETTINGS = {
    'TITLE': 'Vino API',
    'DESCRIPTION': 'REST API for the Vino wine tracking mobile and web application.',
    'VERSION': '1.0.0',
    'SERVE_INCLUDE_SCHEMA': False,
    'COMPONENT_SPLIT_REQUEST': True,
}

# Static files
STATIC_URL = '/static/'
STATICFILES_DIRS = [BASE_DIR / 'static']
STATIC_ROOT = BASE_DIR / 'staticfiles'
STORAGES = {
    'staticfiles': {
        'BACKEND': 'whitenoise.storage.CompressedManifestStaticFilesStorage',
    },
}

# Media files (user uploads)
MEDIA_URL = '/media/'
MEDIA_ROOT = BASE_DIR / 'media'
FILE_UPLOAD_MAX_MEMORY_SIZE = 10 * 1024 * 1024  # 10 MB
DATA_UPLOAD_MAX_MEMORY_SIZE = 10 * 1024 * 1024

# AWS S3 (for production media storage)
AWS_S3_BUCKET = env('AWS_S3_BUCKET', default='')
AWS_S3_REGION = env('AWS_REGION', default='us-east-1')

# Internationalization
LANGUAGE_CODE = 'en-us'
TIME_ZONE = 'UTC'
USE_I18N = True
USE_TZ = True

DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'

# Redis / Caching
CACHES = {
    'default': {
        'BACKEND': 'django.core.cache.backends.redis.RedisCache',
        'LOCATION': env('REDIS_URL', default='redis://localhost:6379/0'),
    }
}

# Celery / Redis (default broker — overridden if RabbitMQ selected)
CELERY_BROKER_URL = env('REDIS_URL', default='redis://localhost:6379/0')
CELERY_RESULT_BACKEND = env('REDIS_URL', default='redis://localhost:6379/0')
CELERY_ACCEPT_CONTENT = ['json']
CELERY_TASK_SERIALIZER = 'json'
CELERY_RESULT_SERIALIZER = 'json'
CELERY_TIMEZONE = 'UTC'
CELERY_TASK_TRACK_STARTED = True

# Email
EMAIL_BACKEND = env('EMAIL_BACKEND', default='django.core.mail.backends.console.EmailBackend')
EMAIL_HOST = env('EMAIL_HOST', default='localhost')
EMAIL_PORT = env.int('EMAIL_PORT', default=587)
EMAIL_HOST_USER = env('EMAIL_HOST_USER', default='')
EMAIL_HOST_PASSWORD = env('EMAIL_HOST_PASSWORD', default='')
EMAIL_USE_TLS = env.bool('EMAIL_USE_TLS', default=True)
DEFAULT_FROM_EMAIL = env('DEFAULT_FROM_EMAIL', default='Trip Me <noreply@tripme.app>')

# Stripe
STRIPE_PUBLISHABLE_KEY = env('STRIPE_PUBLISHABLE_KEY', default='')
STRIPE_SECRET_KEY = env('STRIPE_SECRET_KEY', default='')
STRIPE_WEBHOOK_SECRET = env('STRIPE_WEBHOOK_SECRET', default='')
STRIPE_MONTHLY_PRICE_ID = env('STRIPE_MONTHLY_PRICE_ID', default='')
STRIPE_YEARLY_PRICE_ID = env('STRIPE_YEARLY_PRICE_ID', default='')
STRIPE_TRIAL_DAYS = 14

# Partner subscription price IDs (create these as separate Products in Stripe Dashboard)
STRIPE_PARTNER_SILVER_MONTHLY_PRICE_ID = env('STRIPE_PARTNER_SILVER_MONTHLY_PRICE_ID', default='')
STRIPE_PARTNER_SILVER_YEARLY_PRICE_ID = env('STRIPE_PARTNER_SILVER_YEARLY_PRICE_ID', default='')
STRIPE_PARTNER_GOLD_MONTHLY_PRICE_ID = env('STRIPE_PARTNER_GOLD_MONTHLY_PRICE_ID', default='')
STRIPE_PARTNER_GOLD_YEARLY_PRICE_ID = env('STRIPE_PARTNER_GOLD_YEARLY_PRICE_ID', default='')
STRIPE_PARTNER_PLATINUM_MONTHLY_PRICE_ID = env('STRIPE_PARTNER_PLATINUM_MONTHLY_PRICE_ID', default='')
STRIPE_PARTNER_PLATINUM_YEARLY_PRICE_ID = env('STRIPE_PARTNER_PLATINUM_YEARLY_PRICE_ID', default='')

# Google Maps
GOOGLE_MAPS_API_KEY = env('GOOGLE_MAPS_API_KEY', default='')

# AI / LLM
ANTHROPIC_API_KEY = env('ANTHROPIC_API_KEY', default='')
GOOGLE_API_KEY = env('GOOGLE_API_KEY', default='')
PINECONE_API_KEY = env('PINECONE_API_KEY', default='')
PINECONE_INDEX_NAME = env('PINECONE_INDEX_NAME', default='vinovoyage')

# Sentry
import sentry_sdk
from sentry_sdk.integrations.django import DjangoIntegration

if env('SENTRY_DSN', default=''):
    sentry_sdk.init(
        dsn=env('SENTRY_DSN'),
        integrations=[DjangoIntegration()],
        traces_sample_rate=0.1,
        send_default_pii=False,
    )

# Structured Logging
LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'formatters': {
        'json': {
            '()': 'django.utils.log.ServerFormatter',
            'format': '{levelname} {asctime} {module} {message}',
            'style': '{',
        },
    },
    'handlers': {
        'console': {
            'class': 'logging.StreamHandler',
            'formatter': 'json',
        },
    },
    'root': {
        'handlers': ['console'],
        'level': 'INFO',
    },
}
