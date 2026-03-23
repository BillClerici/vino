from django.db.models import Avg, Count, Exists, OuterRef, Q
from rest_framework import status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.viewsets import ModelViewSet

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
        menu_items_qs = place.menu_items.filter(is_active=True)[:30]
        menu_items = [
            {"id": str(m.id), "name": m.name, "varietal": m.varietal,
             "vintage": m.vintage, "description": m.description,
             "price": float(m.price) if m.price else None}
            for m in menu_items_qs
        ]

        if not menu_items:
            return Response({"recommendations": [], "detail": "No menu items available."})

        # Get user palate
        from apps.palate.models import PalateProfile
        profile = PalateProfile.objects.filter(user=request.user).first()
        palate = json.dumps(profile.preferences, indent=2) if profile and profile.preferences else "No palate profile yet"

        # Get user's past wines at this place
        from apps.visits.models import VisitWine
        past_wines = list(
            VisitWine.objects.filter(
                visit__user=request.user, visit__place=place, is_active=True
            ).values_list("wine_name", flat=True)[:10]
        )

        prompt = f"""Based on this user's palate profile and the menu below, recommend the top 3 items they should try. Return ONLY valid JSON array.

Palate: {palate}

Past wines here: {json.dumps(past_wines) if past_wines else 'First visit'}

Menu at {place.name}:
{json.dumps(menu_items)}

Return ONLY a JSON array of exactly 3 objects with these exact keys:
[{{"name": "Wine name from menu", "why": "1 sentence why this matches their palate"}}]"""

        try:
            from langchain_core.messages import HumanMessage

            from apps.api.ai_utils import get_claude

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
        menu_items_qs = place.menu_items.filter(is_active=True)[:30]
        menu_items = [
            {"name": m.name, "varietal": m.varietal, "vintage": m.vintage,
             "description": m.description, "price": float(m.price) if m.price else None}
            for m in menu_items_qs
        ]

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
            from langchain_core.messages import HumanMessage

            from apps.api.ai_utils import get_claude

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

    @action(detail=True, methods=["post"])
    def pairings(self, request, pk=None):
        """Get AI-powered wine & food pairing suggestions for this place."""
        import json
        import logging

        logger = logging.getLogger(__name__)
        place = self.get_object()
        menu_items = list(
            place.menu_items.filter(is_active=True).values(
                "name", "varietal", "vintage", "description", "price"
            )[:20]
        )

        # What the user is eating/drinking (optional context)
        context = request.data.get("context", "")
        place_type = place.place_type

        if place_type in ("winery", "brewery"):
            direction = "food"
            prompt_intro = f"The user is at {place.name}, a {place_type}. Suggest food pairings for their drinks."
        else:
            direction = "wine"
            prompt_intro = f"The user is at {place.name}, a restaurant. Suggest wine/beer pairings for their food."

        from apps.palate.models import PalateProfile
        profile = PalateProfile.objects.filter(user=request.user).first()
        palate = json.dumps(profile.preferences, indent=2) if profile and profile.preferences else "No palate profile"

        prompt = f"""{prompt_intro}

User's palate: {palate}
{f'User context: {context}' if context else ''}

Menu at {place.name}:
{json.dumps(menu_items, default=str) if menu_items else 'No menu available — suggest general pairings based on the place type.'}

Return ONLY valid JSON with EXACTLY these keys (do not rename them):
{{
  "pairings": [
    {{
      "item": "The wine or beer name from the menu",
      "pairs_with": "The food that goes well with it",
      "why": "1 sentence explanation",
      "tip": "Optional tasting or serving tip"
    }}
  ],
  "general_tip": "1 sentence general pairing advice"
}}

IMPORTANT: Use exactly "item" and "pairs_with" as the key names. Provide 3-5 pairings."""

        try:
            from langchain_core.messages import HumanMessage

            from apps.api.ai_utils import get_claude

            llm = get_claude()
            response = llm.invoke([HumanMessage(content=prompt)])
            raw = response.content.strip()
            if raw.startswith("```"):
                raw = raw.split("\n", 1)[1] if "\n" in raw else raw[3:]
                if raw.endswith("```"):
                    raw = raw[:-3]
                raw = raw.strip()

            result = json.loads(raw)

            # Normalize keys — Claude sometimes uses different names
            if "pairings" in result:
                normalized = []
                for p in result["pairings"]:
                    normalized.append({
                        "item": p.get("item") or p.get("wine") or p.get("drink") or p.get("name") or "",
                        "pairs_with": p.get("pairs_with") or p.get("food_pairings") or p.get("food") or p.get("pairing") or "",
                        "why": p.get("why") or p.get("reason") or p.get("explanation") or "",
                        "tip": p.get("tip") or p.get("tasting_tip") or p.get("serving_tip") or "",
                    })
                    # Handle case where pairs_with is a list
                    if isinstance(normalized[-1]["pairs_with"], list):
                        normalized[-1]["pairs_with"] = ", ".join(normalized[-1]["pairs_with"])
                result["pairings"] = normalized

            result["direction"] = direction
            return Response(result)
        except Exception:
            logger.exception("Pairing generation failed")
            return Response({
                "pairings": [],
                "direction": direction,
                "detail": "Could not generate pairings.",
            })

    @action(detail=False, methods=["get"])
    def nearby(self, request):
        """Search for nearby wineries and breweries via Google Places API."""
        import logging

        import httpx

        logger = logging.getLogger(__name__)

        lat = request.query_params.get("lat")
        lng = request.query_params.get("lng")
        radius = int(request.query_params.get("radius", 40000))  # 25 miles ≈ 40km

        if not lat or not lng:
            return Response(
                {"detail": "lat and lng are required."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        from django.conf import settings

        api_key = getattr(settings, "GOOGLE_MAPS_API_KEY", "")
        if not api_key:
            return Response({"detail": "No Google Maps API key."}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

        results = []

        # Search for wineries and breweries
        for place_type in ["winery", "brewery"]:
            try:
                with httpx.Client(timeout=15) as client:
                    resp = client.post(
                        "https://places.googleapis.com/v1/places:searchNearby",
                        headers={
                            "Content-Type": "application/json",
                            "X-Goog-Api-Key": api_key,
                            "X-Goog-FieldMask": (
                                "places.id,places.displayName,places.formattedAddress,"
                                "places.location,places.rating,places.userRatingCount,"
                                "places.websiteUri,places.nationalPhoneNumber,"
                                "places.currentOpeningHours,places.regularOpeningHours,"
                                "places.photos,places.editorialSummary,"
                                "places.priceLevel,places.googleMapsUri"
                            ),
                        },
                        json={
                            "includedTypes": [place_type],
                            "locationRestriction": {
                                "circle": {
                                    "center": {"latitude": float(lat), "longitude": float(lng)},
                                    "radius": float(radius),
                                }
                            },
                            "maxResultCount": 15,
                            "languageCode": "en",
                        },
                    )
                    resp.raise_for_status()
                    data = resp.json()

                for gp in data.get("places", []):
                    name = gp.get("displayName", {}).get("text", "")
                    location = gp.get("location", {})

                    # Photo URL
                    image_url = ""
                    photos = gp.get("photos", [])
                    if photos:
                        photo_name = photos[0].get("name", "")
                        if photo_name:
                            image_url = f"https://places.googleapis.com/v1/{photo_name}/media?maxWidthPx=600&key={api_key}"

                    # Opening hours
                    hours = []
                    reg_hours = gp.get("regularOpeningHours", {})
                    for period_text in reg_hours.get("weekdayDescriptions", []):
                        hours.append(period_text)

                    current_hours = gp.get("currentOpeningHours", {})
                    is_open = current_hours.get("openNow") if current_hours else None

                    results.append({
                        "google_place_id": gp.get("id", ""),
                        "name": name,
                        "place_type": place_type,
                        "address": gp.get("formattedAddress", ""),
                        "latitude": location.get("latitude"),
                        "longitude": location.get("longitude"),
                        "rating": gp.get("rating"),
                        "rating_count": gp.get("userRatingCount"),
                        "website": gp.get("websiteUri", ""),
                        "phone": gp.get("nationalPhoneNumber", ""),
                        "image_url": image_url,
                        "description": gp.get("editorialSummary", {}).get("text", "") if gp.get("editorialSummary") else "",
                        "hours": hours,
                        "is_open_now": is_open,
                        "price_level": gp.get("priceLevel", ""),
                        "google_maps_url": gp.get("googleMapsUri", ""),
                    })

            except Exception:
                logger.exception("Nearby search failed for %s", place_type)

        # Sort by rating descending
        results.sort(key=lambda x: x.get("rating") or 0, reverse=True)

        return Response({
            "places": results[:25],
            "total": len(results),
        })

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
