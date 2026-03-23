import pytest


@pytest.mark.django_db
class TestUserProfileAPI:
    def test_get_profile(self, authenticated_drf_client):
        resp = authenticated_drf_client.get("/api/v1/me/")
        assert resp.status_code == 200
        assert resp.data["email"] == authenticated_drf_client.user.email

    def test_update_profile(self, authenticated_drf_client):
        resp = authenticated_drf_client.patch("/api/v1/me/", {
            "first_name": "Updated",
            "timezone": "America/Chicago",
        }, format="json")
        assert resp.status_code == 200
        assert resp.data["first_name"] == "Updated"

    def test_get_stats(self, authenticated_drf_client):
        resp = authenticated_drf_client.get("/api/v1/me/stats/")
        assert resp.status_code == 200
        assert "visit_count" in resp.data
