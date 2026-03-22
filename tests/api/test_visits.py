import pytest
from django.utils import timezone

from tests.factories.factories import PlaceFactory, VisitLogFactory, VisitWineFactory


@pytest.mark.django_db
class TestVisitAPI:
    def test_list_visits(self, authenticated_drf_client):
        VisitLogFactory.create_batch(3, user=authenticated_drf_client.user)
        resp = authenticated_drf_client.get("/api/v1/visits/")
        assert resp.status_code == 200
        assert len(resp.data["data"]) == 3

    def test_retrieve_visit(self, authenticated_drf_client):
        visit = VisitLogFactory(user=authenticated_drf_client.user)
        VisitWineFactory(visit=visit)
        resp = authenticated_drf_client.get(f"/api/v1/visits/{visit.id}/")
        assert resp.status_code == 200
        assert len(resp.data["data"]["wines_tasted"]) == 1

    def test_checkin(self, authenticated_drf_client):
        place = PlaceFactory()
        resp = authenticated_drf_client.post("/api/v1/visits/", {
            "place": str(place.id),
            "visited_at": timezone.now().isoformat(),
            "rating_overall": 5,
            "notes": "Great visit!",
            "wines": [
                {
                    "wine_name": "House Red",
                    "wine_type": "Red",
                    "serving_type": "glass",
                    "rating": 4,
                },
            ],
        }, format="json")
        assert resp.status_code == 201

    def test_add_wine_to_visit(self, authenticated_drf_client):
        visit = VisitLogFactory(user=authenticated_drf_client.user)
        resp = authenticated_drf_client.post(f"/api/v1/visits/{visit.id}/wines/", {
            "wine_name": "Pinot Noir",
            "wine_type": "Red",
            "serving_type": "tasting",
            "rating": 5,
        }, format="json")
        assert resp.status_code == 201

    def test_filter_by_rating(self, authenticated_drf_client):
        VisitLogFactory(user=authenticated_drf_client.user, rating_overall=5)
        VisitLogFactory(user=authenticated_drf_client.user, rating_overall=2)
        resp = authenticated_drf_client.get("/api/v1/visits/?rating_min=4")
        assert resp.status_code == 200
        assert len(resp.data["data"]) == 1

    def test_soft_delete(self, authenticated_drf_client):
        visit = VisitLogFactory(user=authenticated_drf_client.user)
        resp = authenticated_drf_client.delete(f"/api/v1/visits/{visit.id}/")
        assert resp.status_code == 204
        visit.refresh_from_db()
        assert visit.is_active is False

    def test_other_users_visits_hidden(self, authenticated_drf_client, user_factory):
        other_user = user_factory()
        VisitLogFactory(user=other_user)
        resp = authenticated_drf_client.get("/api/v1/visits/")
        assert len(resp.data["data"]) == 0
