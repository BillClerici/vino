import pytest

from tests.factories.factories import FavoritePlaceFactory, MenuItemFactory, PlaceFactory


@pytest.mark.django_db
class TestPlaceAPI:
    def test_list_places(self, authenticated_drf_client):
        PlaceFactory.create_batch(3)
        resp = authenticated_drf_client.get("/api/v1/places/")
        assert resp.status_code == 200
        assert resp.data["success"] is True
        assert len(resp.data["data"]) == 3

    def test_retrieve_place(self, authenticated_drf_client):
        place = PlaceFactory()
        resp = authenticated_drf_client.get(f"/api/v1/places/{place.id}/")
        assert resp.status_code == 200
        assert resp.data["data"]["name"] == place.name

    def test_search_places(self, authenticated_drf_client):
        PlaceFactory(name="Napa Valley Winery", city="Napa")
        PlaceFactory(name="Sonoma Estate", city="Sonoma")
        resp = authenticated_drf_client.get("/api/v1/places/?q=Napa")
        assert resp.status_code == 200
        assert len(resp.data["data"]) == 1

    def test_filter_by_type(self, authenticated_drf_client):
        PlaceFactory(place_type="winery")
        PlaceFactory(place_type="brewery")
        resp = authenticated_drf_client.get("/api/v1/places/?place_type=winery")
        assert resp.status_code == 200
        assert len(resp.data["data"]) == 1

    def test_create_place(self, authenticated_drf_client):
        resp = authenticated_drf_client.post("/api/v1/places/", {
            "name": "New Winery",
            "place_type": "winery",
            "city": "Sonoma",
            "state": "CA",
        }, format="json")
        assert resp.status_code == 201

    def test_toggle_favorite(self, authenticated_drf_client):
        place = PlaceFactory()
        resp = authenticated_drf_client.post(f"/api/v1/places/{place.id}/favorite/")
        assert resp.status_code == 200
        assert resp.data["data"]["is_favorited"] is True

        resp = authenticated_drf_client.post(f"/api/v1/places/{place.id}/favorite/")
        assert resp.data["data"]["is_favorited"] is False

    def test_favorites_list(self, authenticated_drf_client):
        place = PlaceFactory()
        FavoritePlaceFactory(user=authenticated_drf_client.user, place=place)
        resp = authenticated_drf_client.get("/api/v1/places/favorites/")
        assert resp.status_code == 200
        assert len(resp.data["data"]) == 1

    def test_map_endpoint(self, authenticated_drf_client):
        PlaceFactory(latitude=38.5, longitude=-122.5)
        PlaceFactory(latitude=None, longitude=None)
        resp = authenticated_drf_client.get("/api/v1/places/map/")
        assert resp.status_code == 200
        assert len(resp.data["data"]) == 1

    def test_menu_items(self, authenticated_drf_client):
        place = PlaceFactory()
        MenuItemFactory(place=place)
        MenuItemFactory(place=place)
        resp = authenticated_drf_client.get(f"/api/v1/places/{place.id}/menu/")
        assert resp.status_code == 200
        assert len(resp.data["data"]) == 2

    def test_unauthenticated_denied(self, drf_client):
        resp = drf_client.get("/api/v1/places/")
        assert resp.status_code == 401
