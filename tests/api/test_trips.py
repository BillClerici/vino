import pytest

from tests.factories.factories import (
    PlaceFactory,
    TripFactory,
    TripMemberFactory,
    TripStopFactory,
)


@pytest.mark.django_db
class TestTripAPI:
    def _make_trip(self, user):
        trip = TripFactory(created_by=user)
        TripMemberFactory(trip=trip, user=user, role="organizer")
        return trip

    def test_list_trips(self, authenticated_drf_client):
        self._make_trip(authenticated_drf_client.user)
        resp = authenticated_drf_client.get("/api/v1/trips/")
        assert resp.status_code == 200
        assert len(resp.data["data"]) == 1

    def test_create_trip(self, authenticated_drf_client):
        resp = authenticated_drf_client.post("/api/v1/trips/", {
            "name": "Napa Trip",
            "scheduled_date": "2026-04-15",
        }, format="json")
        assert resp.status_code == 201

    def test_retrieve_trip(self, authenticated_drf_client):
        trip = self._make_trip(authenticated_drf_client.user)
        resp = authenticated_drf_client.get(f"/api/v1/trips/{trip.id}/")
        assert resp.status_code == 200
        assert resp.data["data"]["name"] == trip.name

    def test_add_stop(self, authenticated_drf_client):
        trip = self._make_trip(authenticated_drf_client.user)
        place = PlaceFactory()
        resp = authenticated_drf_client.post(f"/api/v1/trips/{trip.id}/stops/", {
            "place": str(place.id),
            "duration_minutes": 60,
        }, format="json")
        assert resp.status_code == 201

    def test_reorder_stops(self, authenticated_drf_client):
        trip = self._make_trip(authenticated_drf_client.user)
        s1 = TripStopFactory(trip=trip, order=0)
        s2 = TripStopFactory(trip=trip, order=1)
        resp = authenticated_drf_client.post(
            f"/api/v1/trips/{trip.id}/stops/reorder/",
            {"stops": [{"id": str(s2.id), "order": "0"}, {"id": str(s1.id), "order": "1"}]},
            format="json",
        )
        assert resp.status_code == 200

    def test_invite_member(self, authenticated_drf_client):
        trip = self._make_trip(authenticated_drf_client.user)
        resp = authenticated_drf_client.post(
            f"/api/v1/trips/{trip.id}/members/invite/",
            {"email": "friend@example.com", "message": "Join my trip!"},
            format="json",
        )
        assert resp.status_code == 201

    def test_start_trip(self, authenticated_drf_client):
        trip = self._make_trip(authenticated_drf_client.user)
        trip.status = "confirmed"
        trip.save()
        resp = authenticated_drf_client.post(f"/api/v1/trips/{trip.id}/start/")
        assert resp.status_code == 200
        assert resp.data["data"]["status"] == "in_progress"

    def test_complete_trip(self, authenticated_drf_client):
        trip = self._make_trip(authenticated_drf_client.user)
        trip.status = "in_progress"
        trip.save()
        resp = authenticated_drf_client.post(f"/api/v1/trips/{trip.id}/complete/")
        assert resp.status_code == 200
        assert resp.data["data"]["status"] == "completed"

    def test_live_checkin(self, authenticated_drf_client):
        trip = self._make_trip(authenticated_drf_client.user)
        trip.status = "in_progress"
        trip.save()
        stop = TripStopFactory(trip=trip)
        resp = authenticated_drf_client.post(
            f"/api/v1/trips/{trip.id}/live/checkin/{stop.id}/"
        )
        assert resp.status_code == 201
        assert "visit_id" in resp.data["data"]
