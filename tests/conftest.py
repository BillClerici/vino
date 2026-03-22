import pytest
from django.test import Client
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken


@pytest.fixture
def api_client():
    """Unauthenticated Django test client."""
    return Client()


@pytest.fixture
def drf_client():
    """Unauthenticated DRF API client."""
    return APIClient()


@pytest.fixture
def user_factory():
    """Shortcut to the User factory."""
    from tests.factories.factories import UserFactory
    return UserFactory


@pytest.fixture
def authenticated_client(api_client, user_factory):
    """Test client with a logged-in user."""
    user = user_factory()
    api_client.force_login(user)
    return api_client


@pytest.fixture
def authenticated_drf_client(drf_client, user_factory):
    """DRF API client with JWT authentication."""
    user = user_factory(subscription_status="active")
    refresh = RefreshToken.for_user(user)
    drf_client.credentials(HTTP_AUTHORIZATION=f"Bearer {refresh.access_token}")
    drf_client.user = user
    return drf_client


@pytest.fixture
def lookup_factory():
    """Shortcut to the LookupValue factory."""
    from tests.factories.factories import LookupValueFactory
    return LookupValueFactory


@pytest.fixture
def place_factory():
    from tests.factories.factories import PlaceFactory
    return PlaceFactory


@pytest.fixture
def visit_factory():
    from tests.factories.factories import VisitLogFactory
    return VisitLogFactory


@pytest.fixture
def trip_factory():
    from tests.factories.factories import TripFactory
    return TripFactory


@pytest.fixture
def trip_member_factory():
    from tests.factories.factories import TripMemberFactory
    return TripMemberFactory


@pytest.fixture
def trip_stop_factory():
    from tests.factories.factories import TripStopFactory
    return TripStopFactory
