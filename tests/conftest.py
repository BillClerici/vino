import pytest
from django.test import Client


@pytest.fixture
def api_client():
    """Unauthenticated Django test client."""
    return Client()


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
def lookup_factory():
    """Shortcut to the LookupValue factory."""
    from tests.factories.factories import LookupValueFactory
    return LookupValueFactory
