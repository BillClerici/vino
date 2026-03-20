from django.urls import path

from apps.wineries.views import (
    FavoritePlaceView,
    FindOrCreatePlaceView,
    MenuItemCreateView,
    PlaceAdminFetchGoogleView,
    PlaceAdminMenuView,
    PlaceCreateView,
    PlaceDetailView,
    PlaceEditView,
    PlaceListView,
    ToggleFavoriteView,
)

urlpatterns = [
    path("", PlaceListView.as_view(), name="place_list"),
    path("add/", PlaceCreateView.as_view(), name="place_create"),
    path("favorite-place/", FavoritePlaceView.as_view(), name="place_favorite_place"),
    path("find-or-create/", FindOrCreatePlaceView.as_view(), name="place_find_or_create"),
    path("<uuid:pk>/", PlaceDetailView.as_view(), name="place_detail"),
    path("<uuid:pk>/edit/", PlaceEditView.as_view(), name="place_edit"),
    path("<uuid:pk>/favorite/", ToggleFavoriteView.as_view(), name="place_toggle_favorite"),
    path("<uuid:pk>/admin-menu/", PlaceAdminMenuView.as_view(), name="place_admin_menu"),
    path("<uuid:pk>/fetch-google/", PlaceAdminFetchGoogleView.as_view(), name="place_fetch_google"),
    path("<uuid:place_pk>/wines/add/", MenuItemCreateView.as_view(), name="menuitem_create"),
]
