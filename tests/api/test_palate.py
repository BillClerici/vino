import pytest


@pytest.mark.django_db
class TestPalateAPI:
    def test_get_palate(self, authenticated_drf_client):
        resp = authenticated_drf_client.get("/api/v1/palate/")
        assert resp.status_code == 200
        data = resp.data["data"]
        assert "profile" in data
        assert "visit_stats" in data
        assert "top_varietals" in data
