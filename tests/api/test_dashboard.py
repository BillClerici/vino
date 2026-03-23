import pytest

from tests.factories.factories import PlaceFactory, TripFactory, TripMemberFactory, VisitLogFactory


@pytest.mark.django_db
class TestDashboardAPI:
    def test_dashboard(self, authenticated_drf_client):
        user = authenticated_drf_client.user
        place = PlaceFactory()
        VisitLogFactory(user=user, place=place, rating_overall=5)
        trip = TripFactory(created_by=user, status="completed")
        TripMemberFactory(trip=trip, user=user)

        resp = authenticated_drf_client.get("/api/v1/dashboard/")
        assert resp.status_code == 200
        data = resp.data
        assert data["stats"]["visit_count"] == 1
        assert data["stats"]["trips_completed"] == 1
        assert len(data["recent_visits"]) == 1

    def test_dashboard_unauthenticated(self, drf_client):
        resp = drf_client.get("/api/v1/dashboard/")
        assert resp.status_code == 401
