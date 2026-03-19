import pytest


pytestmark = pytest.mark.django_db


class TestHealthEndpoint:
    def test_health_returns_200(self, api_client):
        response = api_client.get("/health/")
        assert response.status_code == 200

    def test_health_response_shape(self, api_client):
        response = api_client.get("/health/")
        data = response.json()
        assert "status" in data
        assert "db" in data
        assert data["status"] == "ok"
        assert data["db"] == "ok"


class TestLandingPage:
    def test_landing_returns_200(self, api_client):
        response = api_client.get("/")
        assert response.status_code == 200
