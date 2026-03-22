import pytest
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken
from tests.factories.factories import UserFactory


@pytest.mark.django_db
class TestSubscriptionPermission:
    def test_expired_subscription_denied(self):
        user = UserFactory(subscription_status="canceled", trial_end=None)
        client = APIClient()
        refresh = RefreshToken.for_user(user)
        client.credentials(HTTP_AUTHORIZATION=f"Bearer {refresh.access_token}")
        resp = client.get("/api/v1/places/")
        assert resp.status_code == 403

    def test_active_subscription_allowed(self):
        user = UserFactory(subscription_status="active")
        client = APIClient()
        refresh = RefreshToken.for_user(user)
        client.credentials(HTTP_AUTHORIZATION=f"Bearer {refresh.access_token}")
        resp = client.get("/api/v1/places/")
        assert resp.status_code == 200

    def test_trial_user_allowed(self):
        from django.utils import timezone
        from datetime import timedelta
        user = UserFactory(
            subscription_status="trialing",
            trial_end=timezone.now() + timedelta(days=7),
        )
        client = APIClient()
        refresh = RefreshToken.for_user(user)
        client.credentials(HTTP_AUTHORIZATION=f"Bearer {refresh.access_token}")
        resp = client.get("/api/v1/places/")
        assert resp.status_code == 200
