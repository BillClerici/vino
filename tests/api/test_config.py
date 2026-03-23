import pytest
from rest_framework.test import APIClient


@pytest.mark.django_db
class TestConfigAPI:
    def test_config_unauthenticated(self):
        client = APIClient()
        resp = client.get("/api/v1/config/")
        assert resp.status_code == 200
        data = resp.data
        assert "minimum_app_version" in data
        assert "features" in data

    def test_health_check(self):
        client = APIClient()
        resp = client.get("/health/")
        assert resp.status_code == 200
