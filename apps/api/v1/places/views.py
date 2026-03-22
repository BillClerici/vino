from django.db.models import Avg, Count, Exists, OuterRef, Q
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

        if user.is_authenticated:
            qs = qs.annotate(
                visit_count=Count(
                    "visits",
                    filter=Q(visits__user=user, visits__is_active=True),
                    distinct=True,
                ),
                avg_rating=Avg(
                    "visits__rating_overall",
                    filter=Q(visits__user=user, visits__is_active=True),
                ),
            )
        else:
            qs = qs.annotate(
                visit_count=Count(
                    "visits",
                    filter=Q(visits__is_active=True),
                    distinct=True,
                ),
                avg_rating=Avg(
                    "visits__rating_overall",
                    filter=Q(visits__is_active=True),
                ),
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

    @action(detail=True, methods=["post"])
    def recommend(self, request, pk=None):
        """Get AI-powered wine/beer recommendations for this place based on user's palate."""
        import json
        import logging

        logger = logging.getLogger(__name__)
        place = self.get_object()
        menu_items = list(
            place.menu_items.filter(is_active=True).values(
                "id", "name", "varietal", "vintage", "description", "price"
            )[:30]
        )

        if not menu_items:
            return Response({"recommendations": [], "detail": "No menu items available."})

        # Get user palate
        from apps.palate.models import PalateProfile
        profile = PalateProfile.objects.filter(user=request.user).first()
        palate = json.dumps(profile.preferences, indent=2) if profile and profile.preferences else "No palate profile yet"

        # Get user's past wines at this place
        from apps.visits.models import VisitWine
        from django.db.models import F
        past_wines = list(
            VisitWine.objects.filter(
                visit__user=request.user, visit__place=place, is_active=True
            ).values(varietal=F("wine_type"), rating=F("rating"), name=F("wine_name"))[:10]
        )

        prompt = f"""Based on this user's palate profile and the menu below, recommend the top 3 items they should try. Return ONLY valid JSON array.

Palate: {palate}

Past wines here: {json.dumps(past_wines) if past_wines else 'First visit'}

Menu at {place.name}:
{json.dumps(menu_items, default=str)}

Return JSON array of exactly 3 objects:
[{{"menu_item_id": "uuid", "name": "...", "why": "1 sentence why this matches their palate"}}]"""

        try:
            from apps.api.ai_utils import get_claude
            from langchain_core.messages import HumanMessage

            llm = get_claude()
            response = llm.invoke([HumanMessage(content=prompt)])
            raw = response.content.strip()
            if raw.startswith("```"):
                raw = raw.split("\n", 1)[1] if "\n" in raw else raw[3:]
                if raw.endswith("```"):
                    raw = raw[:-3]
                raw = raw.strip()

            recommendations = json.loads(raw)
            return Response({"recommendations": recommendations})
        except Exception:
            logger.exception("Recommendation failed")
            return Response({"recommendations": [], "detail": "Could not generate recommendations."})

    @action(detail=True, methods=["post"])
    def flight(self, request, pk=None):
        """Build an AI-powered tasting flight from this place's menu."""
        import json
        import logging

        logger = logging.getLogger(__name__)
        place = self.get_object()
        menu_items = list(
            place.menu_items.filter(is_active=True).values(
                "id", "name", "varietal", "vintage", "description", "price"
            )[:30]
        )

        if len(menu_items) < 3:
            return Response({"flight": [], "detail": "Not enough menu items for a flight."})

        from apps.palate.models import PalateProfile
        profile = PalateProfile.objects.filter(user=request.user).first()
        palate = json.dumps(profile.preferences, indent=2) if profile and profile.preferences else "No palate profile yet"

        flight_size = int(request.data.get("size", 4))

        prompt = f"""You are a sommelier building a tasting flight of {flight_size} wines/beers from this menu for a customer.

Customer's palate: {palate}

Menu at {place.name}:
{json.dumps(menu_items, default=str)}

Build a flight that:
1. Starts with something light/approachable (their comfort zone)
2. Progresses in intensity
3. Includes one "stretch" pick to expand their horizons
4. Ends with something bold/memorable

Return ONLY valid JSON:
{{"flight_name": "Creative name for this flight", "description": "1 sentence theme", "items": [{{"menu_item_id": "uuid", "name": "...", "order": 1, "role": "opener|comfort|stretch|finisher", "tasting_tip": "1 sentence tasting guidance"}}]}}"""

        try:
            from apps.api.ai_utils import get_claude
            from langchain_core.messages import HumanMessage

            llm = get_claude()
            response = llm.invoke([HumanMessage(content=prompt)])
            raw = response.content.strip()
            if raw.startswith("```"):
                raw = raw.split("\n", 1)[1] if "\n" in raw else raw[3:]
                if raw.endswith("```"):
                    raw = raw[:-3]
                raw = raw.strip()

            flight = json.loads(raw)
            return Response(flight)
        except Exception:
            logger.exception("Flight builder failed")
            return Response({"flight": [], "detail": "Could not build a flight."})

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
