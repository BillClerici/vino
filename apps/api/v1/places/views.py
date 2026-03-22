from django.db.models import Avg, Count, Exists, OuterRef
from rest_framework import status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.viewsets import ModelViewSet, ReadOnlyModelViewSet

from apps.wineries.models import FavoritePlace, MenuItem, Place
from ..permissions import HasActiveSubscription
from .filters import PlaceFilter
from .serializers import (
    FavoritePlaceSerializer,
    MenuItemSerializer,
    MenuItemWriteSerializer,
    PlaceDetailSerializer,
    PlaceListSerializer,
    PlaceMapSerializer,
    PlaceWriteSerializer,
)


class PlaceViewSet(ModelViewSet):
    permission_classes = [HasActiveSubscription]
    filterset_class = PlaceFilter
    search_fields = ["name", "city", "state"]
    ordering_fields = ["name", "city", "avg_rating", "visit_count", "created_at"]
    ordering = ["name"]

    def get_queryset(self):
        qs = Place.objects.filter(is_active=True)
        user = self.request.user

        qs = qs.annotate(
            visit_count=Count("visits", distinct=True),
            avg_rating=Avg("visits__rating_overall"),
        )

        if user.is_authenticated:
            qs = qs.annotate(
                is_favorited=Exists(
                    FavoritePlace.objects.filter(
                        user=user, place=OuterRef("pk"), is_active=True
                    )
                )
            )
        return qs

    def get_serializer_class(self):
        if self.action == "retrieve":
            return PlaceDetailSerializer
        if self.action in ("create", "update", "partial_update"):
            return PlaceWriteSerializer
        return PlaceListSerializer

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        name = data.get("name", "").strip()

        # Find existing place by name (case-insensitive) to avoid duplicates
        existing = Place.objects.filter(
            name__iexact=name, is_active=True
        ).first()

        if existing:
            # Update fields that were empty
            changed = []
            for field in ("address", "city", "state", "zip_code", "website",
                          "phone", "latitude", "longitude", "image_url"):
                new_val = data.get(field)
                if new_val and not getattr(existing, field):
                    setattr(existing, field, new_val)
                    changed.append(field)
            if data.get("place_type") and existing.place_type == "other":
                existing.place_type = data["place_type"]
                changed.append("place_type")
            if changed:
                changed.append("updated_at")
                existing.save(update_fields=changed)
            place = existing
        else:
            place = serializer.save()

        return Response(
            PlaceListSerializer(place).data,
            status=status.HTTP_201_CREATED if not existing else status.HTTP_200_OK,
        )

    @action(detail=True, methods=["post"])
    def favorite(self, request, pk=None):
        """Toggle favorite status for a place."""
        place = self.get_object()
        fav, created = FavoritePlace.all_objects.get_or_create(
            user=request.user, place=place,
        )
        if created or not fav.is_active:
            fav.is_active = True
            fav.save(update_fields=["is_active", "updated_at"])
            return Response({"is_favorited": True}, status=status.HTTP_200_OK)
        else:
            fav.is_active = False
            fav.save(update_fields=["is_active", "updated_at"])
            return Response({"is_favorited": False}, status=status.HTTP_200_OK)

    @action(detail=True, methods=["post"], url_path="fetch-menu")
    def fetch_menu(self, request, pk=None):
        """Scrape the place's website for menu items using Claude AI."""
        place = self.get_object()
        if not place.website:
            return Response(
                {"detail": "No website URL for this place."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        from apps.wineries.scraper import scrape_and_cache_menu_items
        force = request.data.get("force", False)
        if force:
            place.wine_menu_last_scraped = None
            place.save(update_fields=["wine_menu_last_scraped", "updated_at"])

        menu_items = scrape_and_cache_menu_items(place)
        return Response({
            "count": len(menu_items),
            "menu_items": MenuItemSerializer(menu_items, many=True).data,
        })

    @action(detail=False, methods=["get"])
    def favorites(self, request):
        """List user's favorite places."""
        favs = FavoritePlace.objects.filter(
            user=request.user, is_active=True
        ).select_related("place")
        page = self.paginate_queryset(favs)
        if page is not None:
            serializer = FavoritePlaceSerializer(page, many=True)
            return self.get_paginated_response(serializer.data)
        serializer = FavoritePlaceSerializer(favs, many=True)
        return Response(serializer.data)

    @action(detail=False, methods=["get"])
    def map(self, request):
        """Lightweight endpoint for map markers."""
        qs = Place.objects.filter(
            is_active=True,
            latitude__isnull=False,
            longitude__isnull=False,
        )
        serializer = PlaceMapSerializer(qs, many=True)
        return Response(serializer.data)


class MenuItemViewSet(ModelViewSet):
    permission_classes = [HasActiveSubscription]
    ordering = ["name"]

    def get_queryset(self):
        return MenuItem.objects.filter(
            is_active=True,
            place_id=self.kwargs.get("place_pk"),
            place__is_active=True,
        )

    def get_serializer_class(self):
        if self.action in ("create", "update", "partial_update"):
            return MenuItemWriteSerializer
        return MenuItemSerializer

    def perform_create(self, serializer):
        serializer.save(place_id=self.kwargs["place_pk"])
