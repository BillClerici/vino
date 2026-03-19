from django.urls import path

from apps.wineries.views import (
    FavoritePlaceView,
    ToggleFavoriteView,
    WineCreateView,
    WineryCreateView,
    WineryDetailView,
    WineryEditView,
    WineryListView,
)

urlpatterns = [
    path("", WineryListView.as_view(), name="winery_list"),
    path("add/", WineryCreateView.as_view(), name="winery_create"),
    path("favorite-place/", FavoritePlaceView.as_view(), name="winery_favorite_place"),
    path("<uuid:pk>/", WineryDetailView.as_view(), name="winery_detail"),
    path("<uuid:pk>/edit/", WineryEditView.as_view(), name="winery_edit"),
    path("<uuid:pk>/favorite/", ToggleFavoriteView.as_view(), name="winery_toggle_favorite"),
    path("<uuid:winery_pk>/wines/add/", WineCreateView.as_view(), name="wine_create"),
]
