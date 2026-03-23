from rest_framework_simplejwt.tokens import RefreshToken

from apps.users.models import SocialAccount


def save_social_account(backend, user, response, *args, **kwargs):
    """Persist or update the SocialAccount record for this login."""
    provider = backend.name
    uid = kwargs.get('uid', '')
    SocialAccount.objects.update_or_create(
        provider=provider,
        provider_uid=uid,
        defaults={
            'user': user,
            'raw_data': response,
            'access_token': kwargs.get('access_token', ''),
        }
    )
    user.last_login_provider = provider
    user.save(update_fields=['last_login_provider', 'updated_at'])


def issue_jwt(strategy, backend, user, *args, **kwargs):
    """Issue JWT tokens and store them in the session for the callback view to pick up."""
    refresh = RefreshToken.for_user(user)
    access_token = str(refresh.access_token)
    refresh_token = str(refresh)
    # Store tokens in session — the auth_callback view (or template context) will use them
    strategy.request.session['jwt_access'] = access_token
    strategy.request.session['jwt_refresh'] = refresh_token
