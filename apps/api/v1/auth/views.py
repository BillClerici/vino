import logging

from django.conf import settings
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework_simplejwt.tokens import RefreshToken

from apps.users.models import SocialAccount, User

from .serializers import MobileMicrosoftAuthSerializer

logger = logging.getLogger(__name__)


def _exchange_google_code(auth_code):
    """Exchange a Google auth code for user info."""
    import requests

    # For mobile (Android/iOS) server auth codes, redirect_uri is not needed
    # Some Google configurations require it to be omitted entirely
    payload = {
        "code": auth_code,
        "client_id": settings.SOCIAL_AUTH_GOOGLE_OAUTH2_KEY,
        "client_secret": settings.SOCIAL_AUTH_GOOGLE_OAUTH2_SECRET,
        "grant_type": "authorization_code",
    }
    token_resp = requests.post("https://oauth2.googleapis.com/token", data=payload, timeout=10)
    if not token_resp.ok:
        logger.error("Google token exchange failed: %s %s", token_resp.status_code, token_resp.text)
    token_resp.raise_for_status()
    tokens = token_resp.json()

    userinfo_resp = requests.get(
        "https://www.googleapis.com/oauth2/v3/userinfo",
        headers={"Authorization": f"Bearer {tokens['access_token']}"},
        timeout=10,
    )
    userinfo_resp.raise_for_status()
    return tokens, userinfo_resp.json()


def _exchange_microsoft_code(auth_code):
    """Exchange a Microsoft auth code for user info."""
    import requests

    tenant = getattr(settings, "SOCIAL_AUTH_MICROSOFT_OAUTH2_TENANT_ID", "common")
    token_resp = requests.post(
        f"https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token",
        data={
            "code": auth_code,
            "client_id": settings.SOCIAL_AUTH_MICROSOFT_OAUTH2_KEY,
            "client_secret": settings.SOCIAL_AUTH_MICROSOFT_OAUTH2_SECRET,
            "redirect_uri": "",
            "grant_type": "authorization_code",
            "scope": "openid profile email",
        },
        timeout=10,
    )
    token_resp.raise_for_status()
    tokens = token_resp.json()

    userinfo_resp = requests.get(
        "https://graph.microsoft.com/v1.0/me",
        headers={"Authorization": f"Bearer {tokens['access_token']}"},
        timeout=10,
    )
    userinfo_resp.raise_for_status()
    return tokens, userinfo_resp.json()


def _get_or_create_user(email, first_name="", last_name="", provider="", provider_uid="", access_token="", raw_data=None):
    """Find or create user and update social account."""
    try:
        user = User.objects.get(email=email)
    except User.DoesNotExist:
        user = User.objects.create_user(
            email=email,
            first_name=first_name,
            last_name=last_name,
        )

    # Update names if blank
    changed = []
    if not user.first_name and first_name:
        user.first_name = first_name
        changed.append("first_name")
    if not user.last_name and last_name:
        user.last_name = last_name
        changed.append("last_name")
    if provider:
        user.last_login_provider = provider
        changed.append("last_login_provider")
    if changed:
        changed.append("updated_at")
        user.save(update_fields=changed)

    # Update social account
    if provider and provider_uid:
        SocialAccount.objects.update_or_create(
            provider=provider,
            provider_uid=provider_uid,
            defaults={
                "user": user,
                "access_token": access_token or "",
                "raw_data": raw_data or {},
            },
        )

    return user


def _issue_tokens(user):
    """Generate JWT pair for user."""
    refresh = RefreshToken.for_user(user)
    return {
        "access_token": str(refresh.access_token),
        "refresh_token": str(refresh),
    }


@api_view(["POST"])
@permission_classes([AllowAny])
def dev_login(request):
    """DEV ONLY: Issue JWT for a test user without OAuth. Gated by DEBUG=True."""
    if not settings.DEBUG:
        return Response(
            {"detail": "Not available in production."},
            status=status.HTTP_404_NOT_FOUND,
        )

    email = request.data.get("email", "")
    # Try to find the requested user, or fall back to first superuser, or create one
    user = None
    if email:
        user = User.objects.filter(email=email).first()
    if user is None:
        user = User.objects.filter(is_superuser=True, is_active=True).first()
    if user is None:
        user = User.objects.create_user(
            email="dev@vino.local",
            first_name="Dev",
            last_name="User",
        )
        user.subscription_status = "active"
        user.save(update_fields=["subscription_status", "updated_at"])

    return Response(_issue_tokens(user))


def _verify_google_id_token(id_token):
    """Verify a Google ID token and return user info."""
    import requests

    # Use Google's tokeninfo endpoint to verify
    resp = requests.get(
        f"https://oauth2.googleapis.com/tokeninfo?id_token={id_token}",
        timeout=10,
    )
    resp.raise_for_status()
    payload = resp.json()

    # Verify the audience matches our client ID
    if payload.get("aud") != settings.SOCIAL_AUTH_GOOGLE_OAUTH2_KEY:
        raise ValueError("Token audience mismatch")

    return {}, {
        "email": payload.get("email"),
        "given_name": payload.get("given_name", ""),
        "family_name": payload.get("family_name", ""),
        "sub": payload.get("sub", ""),
    }


@api_view(["POST"])
@permission_classes([AllowAny])
def mobile_google_auth(request):
    """Exchange Google auth code or ID token from mobile app for JWT tokens."""
    auth_code = request.data.get("auth_code")
    id_token = request.data.get("id_token")

    if not auth_code and not id_token:
        return Response(
            {"detail": "auth_code or id_token is required."},
            status=status.HTTP_400_BAD_REQUEST,
        )

    try:
        if auth_code:
            tokens, userinfo = _exchange_google_code(auth_code)
        else:
            tokens, userinfo = _verify_google_id_token(id_token)
    except Exception as exc:
        logger.exception("Google auth failed")
        detail = "Failed to authenticate with Google."
        if hasattr(exc, 'response') and exc.response is not None:
            try:
                detail += f" Google says: {exc.response.json()}"
            except Exception:
                detail += f" Status: {exc.response.status_code}"
        return Response(
            {"detail": detail},
            status=status.HTTP_401_UNAUTHORIZED,
        )

    email = userinfo.get("email")
    if not email:
        return Response(
            {"detail": "No email returned from Google."},
            status=status.HTTP_400_BAD_REQUEST,
        )

    user = _get_or_create_user(
        email=email,
        first_name=userinfo.get("given_name", ""),
        last_name=userinfo.get("family_name", ""),
        provider="google-oauth2",
        provider_uid=userinfo.get("sub", ""),
        access_token=tokens.get("access_token", ""),
        raw_data=userinfo,
    )

    return Response(_issue_tokens(user))


@api_view(["POST"])
@permission_classes([AllowAny])
def mobile_microsoft_auth(request):
    """Exchange Microsoft auth code from mobile app for JWT tokens."""
    serializer = MobileMicrosoftAuthSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)

    try:
        tokens, userinfo = _exchange_microsoft_code(serializer.validated_data["auth_code"])
    except Exception:
        logger.exception("Microsoft auth code exchange failed")
        return Response(
            {"detail": "Failed to authenticate with Microsoft."},
            status=status.HTTP_401_UNAUTHORIZED,
        )

    email = userinfo.get("mail") or userinfo.get("userPrincipalName")
    if not email:
        return Response(
            {"detail": "No email returned from Microsoft."},
            status=status.HTTP_400_BAD_REQUEST,
        )

    user = _get_or_create_user(
        email=email,
        first_name=userinfo.get("givenName", ""),
        last_name=userinfo.get("surname", ""),
        provider="microsoft-graph",
        provider_uid=userinfo.get("id", ""),
        access_token=tokens.get("access_token", ""),
        raw_data=userinfo,
    )

    return Response(_issue_tokens(user))
