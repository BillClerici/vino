import json

from django.conf import settings
from django.contrib import messages
from django.contrib.auth.mixins import LoginRequiredMixin, UserPassesTestMixin
from django.db.models import Avg, Count, Max, Q
from django.http import JsonResponse
from django.shortcuts import get_object_or_404, redirect, render
from django.urls import reverse, reverse_lazy
from django.views import View
from django.views.generic import CreateView, ListView, UpdateView

from apps.visits.models import VisitLog
from apps.wineries.forms import MenuItemForm, PlaceAdminForm, PlaceForm
from apps.wineries.models import FavoritePlace, Place


class PlaceListView(LoginRequiredMixin, ListView):
    model = Place
    template_name = "wineries/list.html"
    context_object_name = "wineries"
    paginate_by = 12

    def get_queryset(self):
        qs = Place.objects.annotate(
            visit_count=Count("visits", filter=Q(visits__is_active=True)),
            avg_rating=Avg("visits__rating_overall", filter=Q(visits__is_active=True)),
            wine_count=Count("menu_items", filter=Q(menu_items__is_active=True)),
        )
        q = self.request.GET.get("q", "").strip()
        if q:
            qs = qs.filter(Q(name__icontains=q) | Q(city__icontains=q) | Q(state__icontains=q))
        return qs.order_by("name")

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        user = self.request.user
        ctx["search_query"] = self.request.GET.get("q", "")
        ctx["total_places"] = Place.objects.count()
        ctx["google_maps_api_key"] = settings.GOOGLE_MAPS_API_KEY

        # Trip mode: when adding stops from the trip detail page
        trip_id = self.request.GET.get("trip", "")
        if trip_id:
            from apps.trips.models import Trip
            try:
                trip = Trip.objects.prefetch_related("trip_stops__place").get(pk=trip_id)
                ctx["adding_to_trip"] = trip
                ctx["trip_id"] = str(trip.pk)
                ctx["trip_stops"] = trip.trip_stops.select_related("place").order_by("order")
            except Trip.DoesNotExist:
                pass

        # DB places with coordinates for map
        full_qs = self.get_queryset()
        map_places = full_qs.filter(
            latitude__isnull=False, longitude__isnull=False
        ).values("id", "name", "city", "state", "address", "website", "latitude", "longitude")
        ctx["map_places_json"] = json.dumps([
            {
                "id": str(w["id"]),
                "name": w["name"],
                "city": w["city"] or "",
                "state": w["state"] or "",
                "address": w["address"] or "",
                "website": w["website"] or "",
                "lat": float(w["latitude"]),
                "lng": float(w["longitude"]),
            }
            for w in map_places
        ])

        # User's favorites (set of place IDs)
        favorite_ids = set(
            FavoritePlace.objects.filter(user=user, is_active=True)
            .values_list("place_id", flat=True)
        )
        ctx["favorite_ids"] = favorite_ids
        ctx["favorite_ids_json"] = json.dumps([str(pk) for pk in favorite_ids])

        # User's visited places with last visit date
        visited_data = (
            VisitLog.objects.filter(user=user, is_active=True)
            .values("place_id")
            .annotate(last_visited=Max("visited_at"), visit_count=Count("id"))
        )
        visited_map = {str(v["place_id"]): v for v in visited_data}
        ctx["visited_ids_json"] = json.dumps(list(visited_map.keys()))

        # Favorites table data
        fav_places = (
            Place.objects.filter(pk__in=favorite_ids)
            .annotate(
                last_visited=Max(
                    "visits__visited_at",
                    filter=Q(visits__user=user, visits__is_active=True),
                ),
                user_visit_count=Count(
                    "visits",
                    filter=Q(visits__user=user, visits__is_active=True),
                ),
                avg_rating=Avg("visits__rating_overall", filter=Q(visits__is_active=True)),
            )
            .order_by("name")
        )
        ctx["favorites_list"] = fav_places

        # Visited table data
        visited_place_ids = [v["place_id"] for v in visited_data]
        visited_places = (
            Place.objects.filter(pk__in=visited_place_ids)
            .annotate(
                last_visited=Max(
                    "visits__visited_at",
                    filter=Q(visits__user=user, visits__is_active=True),
                ),
                user_visit_count=Count(
                    "visits",
                    filter=Q(visits__user=user, visits__is_active=True),
                ),
                avg_rating=Avg("visits__rating_overall", filter=Q(visits__is_active=True)),
            )
            .order_by("-last_visited")
        )
        ctx["visited_list"] = visited_places

        return ctx


class ToggleFavoriteView(LoginRequiredMixin, View):
    """AJAX endpoint to toggle a place as favorite."""

    def post(self, request, pk):
        place = get_object_or_404(Place, pk=pk)
        fav, created = FavoritePlace.all_objects.get_or_create(
            user=request.user, place=place,
            defaults={"is_active": True},
        )
        if not created:
            fav.is_active = not fav.is_active
            fav.save(update_fields=["is_active", "updated_at"])

        return JsonResponse({
            "favorited": fav.is_active,
            "place_id": str(pk),
            "name": place.name,
            "city": place.city,
            "state": place.state,
        })


class FavoritePlaceView(LoginRequiredMixin, View):
    """AJAX endpoint: find-or-create a place from Google Places data, then toggle favorite."""

    def post(self, request):
        import json as _json
        try:
            body = _json.loads(request.body)
        except (ValueError, TypeError):
            return JsonResponse({"error": "Invalid JSON"}, status=400)

        name = body.get("name", "").strip()
        if not name:
            return JsonResponse({"error": "Name is required"}, status=400)

        addr = body.get("address", "")
        lat = body.get("lat")
        lng = body.get("lng")
        website = body.get("website", "")
        photo_url = body.get("photo_url", "")

        # Try to find existing place by name + coordinates (within ~100m)
        place = None
        if lat and lng:
            from decimal import Decimal
            lat_d, lng_d = Decimal(str(lat)), Decimal(str(lng))
            place = (
                Place.objects.filter(
                    name__iexact=name,
                    latitude__range=(lat_d - Decimal("0.001"), lat_d + Decimal("0.001")),
                    longitude__range=(lng_d - Decimal("0.001"), lng_d + Decimal("0.001")),
                )
                .first()
            )

        if not place:
            from apps.core.utils import parse_google_address
            parsed = parse_google_address(addr)

            place_type = body.get("place_type", "winery")
            if place_type not in dict(Place.PlaceType.choices):
                place_type = "winery"
            place = Place.objects.create(
                name=name,
                address=parsed["address"],
                city=parsed["city"],
                state=parsed["state"],
                zip_code=parsed["zip_code"],
                latitude=lat,
                longitude=lng,
                website=website,
                image_url=photo_url,
                place_type=place_type,
                phone=body.get("phone", ""),
                description=body.get("description", ""),
            )
        else:
            # Update existing place with any missing data
            changed = []
            if photo_url and not place.image_url:
                place.image_url = photo_url
                changed.append("image_url")
            if body.get("phone") and not place.phone:
                place.phone = body["phone"]
                changed.append("phone")
            if body.get("description") and not place.description:
                place.description = body["description"]
                changed.append("description")
            if changed:
                place.save(update_fields=changed + ["updated_at"])

        # Toggle favorite
        fav, created = FavoritePlace.all_objects.get_or_create(
            user=request.user, place=place,
            defaults={"is_active": True},
        )
        if not created:
            fav.is_active = not fav.is_active
            fav.save(update_fields=["is_active", "updated_at"])

        return JsonResponse({
            "favorited": fav.is_active,
            "place_id": str(place.pk),
            "name": place.name,
            "city": place.city,
            "state": place.state,
        })


class FindOrCreatePlaceView(LoginRequiredMixin, View):
    """AJAX endpoint: find-or-create a place from Google Places data (no favorite toggle)."""

    def post(self, request):
        import json as _json
        try:
            body = _json.loads(request.body)
        except (ValueError, TypeError):
            return JsonResponse({"error": "Invalid JSON"}, status=400)

        name = body.get("name", "").strip()
        if not name:
            return JsonResponse({"error": "Name is required"}, status=400)

        addr = body.get("address", "")
        lat = body.get("lat")
        lng = body.get("lng")
        website = body.get("website", "")
        photo_url = body.get("photo_url", "")

        # Try to find existing place by name + coordinates (within ~100m)
        place = None
        if lat and lng:
            from decimal import Decimal
            lat_d, lng_d = Decimal(str(lat)), Decimal(str(lng))
            place = (
                Place.objects.filter(
                    name__iexact=name,
                    latitude__range=(lat_d - Decimal("0.001"), lat_d + Decimal("0.001")),
                    longitude__range=(lng_d - Decimal("0.001"), lng_d + Decimal("0.001")),
                )
                .first()
            )

        if not place:
            from apps.core.utils import parse_google_address
            parsed = parse_google_address(addr)

            place_type = body.get("place_type", "winery")
            if place_type not in dict(Place.PlaceType.choices):
                place_type = "winery"
            place = Place.objects.create(
                name=name,
                address=parsed["address"],
                city=parsed["city"],
                state=parsed["state"],
                zip_code=parsed["zip_code"],
                latitude=lat,
                longitude=lng,
                website=website,
                image_url=photo_url,
                place_type=place_type,
                phone=body.get("phone", ""),
                description=body.get("description", ""),
            )
        else:
            changed = []
            if photo_url and not place.image_url:
                place.image_url = photo_url
                changed.append("image_url")
            if body.get("phone") and not place.phone:
                place.phone = body["phone"]
                changed.append("phone")
            if body.get("description") and not place.description:
                place.description = body["description"]
                changed.append("description")
            if changed:
                place.save(update_fields=changed + ["updated_at"])

        return JsonResponse({
            "place_id": str(place.pk),
            "name": place.name,
            "city": place.city,
            "state": place.state,
        })


class PlaceDetailView(LoginRequiredMixin, View):
    def get(self, request, pk):
        place = get_object_or_404(Place, pk=pk)
        user = request.user
        menu_items = place.menu_items.filter(is_active=True).order_by("name")
        visits = (
            VisitLog.objects.filter(place=place, is_active=True)
            .select_related("user")
            .order_by("-visited_at")[:10]
        )
        my_visits = VisitLog.objects.filter(place=place, user=user, is_active=True).order_by("-visited_at")
        avg_ratings = VisitLog.objects.filter(place=place, is_active=True).aggregate(
            staff=Avg("rating_staff"),
            ambience=Avg("rating_ambience"),
            food=Avg("rating_food"),
            overall=Avg("rating_overall"),
        )
        is_favorite = FavoritePlace.objects.filter(
            user=user, place=place, is_active=True
        ).exists()

        # Stats
        from apps.visits.models import VisitWine
        total_community_visits = VisitLog.objects.filter(place=place, is_active=True).count()
        my_visit_count = my_visits.count()
        my_wines_here = (
            VisitWine.objects.filter(
                visit__user=user, visit__place=place, is_active=True,
            )
            .select_related("menu_item")
            .order_by("-rating", "wine_name")
        )

        return render(request, "wineries/detail.html", {
            "place": place,
            "winery": place,
            "wines": menu_items,
            "visits": visits,
            "my_visits": my_visits,
            "avg_ratings": avg_ratings,
            "is_favorite": is_favorite,
            "total_community_visits": total_community_visits,
            "my_visit_count": my_visit_count,
            "my_wines_here": my_wines_here,
            "google_maps_api_key": settings.GOOGLE_MAPS_API_KEY,
        })


class PlaceCreateView(LoginRequiredMixin, View):
    def get(self, request):
        return render(request, "wineries/form.html", {
            "form": PlaceForm(),
            "page_title": "Add Place",
            "icon": "add_business",
        })

    def post(self, request):
        form = PlaceForm(request.POST)
        if form.is_valid():
            place = form.save()
            messages.success(request, f"{place.name} added!")
            return redirect("place_detail", pk=place.pk)
        return render(request, "wineries/form.html", {
            "form": form,
            "page_title": "Add Place",
            "icon": "add_business",
        })


class PlaceEditView(LoginRequiredMixin, View):
    def get(self, request, pk):
        place = get_object_or_404(Place, pk=pk)
        return render(request, "wineries/form.html", {
            "form": PlaceForm(instance=place),
            "page_title": f"Edit {place.name}",
            "icon": "edit",
        })

    def post(self, request, pk):
        place = get_object_or_404(Place, pk=pk)
        form = PlaceForm(request.POST, instance=place)
        if form.is_valid():
            form.save()
            messages.success(request, f"{place.name} updated.")
            return redirect("place_detail", pk=place.pk)
        return render(request, "wineries/form.html", {
            "form": form,
            "page_title": f"Edit {place.name}",
            "icon": "edit",
        })


class MenuItemCreateView(LoginRequiredMixin, View):
    def get(self, request, place_pk):
        place = get_object_or_404(Place, pk=place_pk)
        return render(request, "wineries/wine_form.html", {
            "form": MenuItemForm(),
            "winery": place,
        })

    def post(self, request, place_pk):
        place = get_object_or_404(Place, pk=place_pk)
        form = MenuItemForm(request.POST)
        if form.is_valid():
            menu_item = form.save(commit=False)
            menu_item.place = place
            menu_item.save()
            messages.success(request, f"{menu_item.name} added to {place.name}!")
            return redirect("place_detail", pk=place.pk)
        return render(request, "wineries/wine_form.html", {
            "form": form,
            "winery": place,
        })


# ── App Admin: Places CRUD ──

class AppAdminRequiredMixin(LoginRequiredMixin, UserPassesTestMixin):
    def test_func(self):
        return self.request.user.is_superuser


class PlaceAdminListView(AppAdminRequiredMixin, ListView):
    model = Place
    template_name = "admin/list.html"

    def get_queryset(self):
        return Place.all_objects.all().order_by("name")

    def get_context_data(self, **kwargs):
        from django.utils.safestring import mark_safe

        ctx = super().get_context_data(**kwargs)
        ctx["page_title"] = "Places"
        ctx["icon"] = "place"
        ctx["create_url"] = reverse("admin_places_create")
        ctx["columns"] = ["", "Name", "Type", "City", "State", "Website", "Active"]
        ctx["rows"] = [
            {
                "values": [
                    mark_safe(
                        f'<img src="{w.image_url}" style="width:36px;height:36px;border-radius:6px;object-fit:cover;">'
                        if w.image_url else
                        '<div style="width:36px;height:36px;border-radius:6px;background:#ede7f6;display:flex;align-items:center;justify-content:center;">'
                        '<i class="material-icons" style="color:#7e57c2;font-size:1.1rem;">place</i></div>'
                    ),
                    w.name,
                    w.get_place_type_display(),
                    w.city or "—",
                    w.state or "—",
                    w.website[:40] + "..." if len(w.website) > 40 else (w.website or "—"),
                    "Yes" if w.is_active else "No",
                ],
                "edit_url": reverse("admin_places_edit", args=[w.pk]),
                "delete_url": reverse("admin_places_delete", args=[w.pk]),
            }
            for w in ctx["object_list"]
        ]
        return ctx


class PlaceAdminCreateView(AppAdminRequiredMixin, CreateView):
    model = Place
    form_class = PlaceAdminForm
    template_name = "admin/form.html"
    success_url = reverse_lazy("admin_places_list")

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        ctx["page_title"] = "Create Place"
        ctx["icon"] = "add_business"
        ctx["cancel_url"] = reverse("admin_places_list")
        return ctx

    def form_valid(self, form):
        place = form.save()
        messages.success(self.request, f'Place "{place.name}" created.')
        return redirect(self.success_url)


class PlaceAdminEditView(AppAdminRequiredMixin, UpdateView):
    model = Place
    form_class = PlaceAdminForm
    template_name = "admin/place_edit.html"
    success_url = reverse_lazy("admin_places_list")

    def get_queryset(self):
        return Place.all_objects.all()

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        place = self.object
        ctx["page_title"] = f"Edit Place: {place.name}"
        ctx["icon"] = "edit"
        ctx["cancel_url"] = reverse("admin_places_list")

        # Stats
        from django.db.models import Avg, Count
        ctx["trip_count"] = place.trip_stops.filter(is_active=True).values("trip").distinct().count()
        ctx["favorite_count"] = place.favorited_by.filter(is_active=True).count()
        ctx["visit_count"] = place.visits.filter(is_active=True).count()
        avg = place.visits.filter(is_active=True).aggregate(avg=Avg("rating_overall"))["avg"]
        ctx["avg_rating"] = round(avg, 1) if avg else None
        ctx["wine_count"] = place.menu_items.count()
        ctx["has_menu"] = place.place_type in ("winery", "brewery")

        return ctx

    def form_valid(self, form):
        place = form.save()
        messages.success(self.request, f'Place "{place.name}" updated.')
        return redirect(self.success_url)


class PlaceAdminFetchGoogleView(AppAdminRequiredMixin, View):
    """AJAX: fetch place details from Google Places API."""

    def post(self, request, pk):
        import httpx
        from django.conf import settings as django_settings

        place = get_object_or_404(Place.all_objects, pk=pk)
        api_key = django_settings.GOOGLE_MAPS_API_KEY
        if not api_key:
            return JsonResponse({"error": "Google Maps API key not configured"}, status=400)

        # Build search query
        search_query = place.name
        if place.city:
            search_query += f" {place.city}"
        if place.state:
            search_query += f" {place.state}"

        try:
            # Use Places API (New) — Text Search
            with httpx.Client(timeout=10) as client:
                resp = client.post(
                    "https://places.googleapis.com/v1/places:searchText",
                    headers={
                        "Content-Type": "application/json",
                        "X-Goog-Api-Key": api_key,
                        "X-Goog-FieldMask": "places.displayName,places.formattedAddress,places.nationalPhoneNumber,places.websiteUri,places.editorialSummary,places.photos,places.location",
                    },
                    json={"textQuery": search_query, "maxResultCount": 1},
                )
                resp.raise_for_status()
                data = resp.json()

            places = data.get("places", [])
            if not places:
                return JsonResponse({"error": "Place not found on Google"}, status=404)

            from apps.core.utils import parse_google_address

            google_place = places[0]
            raw_address = google_place.get("formattedAddress", "")
            parsed = parse_google_address(raw_address)
            result = {
                "ok": True,
                "name": google_place.get("displayName", {}).get("text", ""),
                "address": parsed["address"],
                "city": parsed["city"],
                "state": parsed["state"],
                "zip_code": parsed["zip_code"],
                "full_address": raw_address,
                "phone": google_place.get("nationalPhoneNumber", ""),
                "website": google_place.get("websiteUri", ""),
                "description": google_place.get("editorialSummary", {}).get("text", "") if google_place.get("editorialSummary") else "",
                "image_url": "",
            }

            # Get photo URL if available
            photos = google_place.get("photos", [])
            if photos and api_key:
                photo_name = photos[0].get("name", "")
                if photo_name:
                    result["image_url"] = f"https://places.googleapis.com/v1/{photo_name}/media?maxWidthPx=400&key={api_key}"

            # Get lat/lng
            location = google_place.get("location", {})
            result["latitude"] = location.get("latitude")
            result["longitude"] = location.get("longitude")

            return JsonResponse(result)

        except Exception as e:
            return JsonResponse({"error": str(e)}, status=500)


class PlaceAdminMenuView(AppAdminRequiredMixin, View):
    """AJAX: fetch/scrape menu items for a place (admin)."""

    def get(self, request, pk):
        from apps.wineries.scraper import scrape_and_cache_menu_items

        place = get_object_or_404(Place.all_objects, pk=pk)

        if request.GET.get("refresh"):
            place.wine_menu_last_scraped = None
            place.save(update_fields=["wine_menu_last_scraped", "updated_at"])

        menu_items = scrape_and_cache_menu_items(place)

        from django.http import JsonResponse
        return JsonResponse({
            "ok": True,
            "wines": [
                {
                    "wine_id": str(w.pk),
                    "name": w.name,
                    "varietal": w.varietal,
                    "vintage": w.vintage,
                    "description": w.description or "",
                    "wine_type": (w.metadata or {}).get("wine_type", ""),
                    "price": float(w.price) if w.price else None,
                    "image_url": w.image_url or "",
                }
                for w in menu_items
            ],
        })


class PlaceAdminDeleteView(AppAdminRequiredMixin, View):
    def _can_hard_delete(self, place):
        """Check if place has no trips or visits referencing it."""
        from apps.trips.models import TripStop
        has_trips = TripStop.all_objects.filter(place=place).exists()
        has_visits = VisitLog.all_objects.filter(place=place).exists()
        if has_trips:
            return False, "This place is referenced by trip stops."
        if has_visits:
            return False, "This place has visit records."
        return True, ""

    def get(self, request, pk):
        place = get_object_or_404(Place.all_objects, pk=pk)
        can_hard, reason = self._can_hard_delete(place)
        return render(request, "admin/delete.html", {
            "object_name": place.name,
            "cancel_url": reverse("admin_places_list"),
            "can_hard_delete": can_hard,
            "hard_delete_reason": reason,
        })

    def post(self, request, pk):
        place = get_object_or_404(Place.all_objects, pk=pk)
        delete_type = request.POST.get("delete_type", "soft")

        if delete_type == "hard":
            can_hard, reason = self._can_hard_delete(place)
            if not can_hard:
                messages.error(request, f'Cannot permanently delete: {reason}')
                return redirect("admin_places_list")
            name = place.name
            place.menu_items.all().delete()
            place.favorited_by.all().delete()
            from apps.partners.models import PlaceClaim, Promotion
            PlaceClaim.all_objects.filter(place=place).delete()
            Promotion.all_objects.filter(place=place).delete()
            place.delete()
            messages.success(request, f'Place "{name}" permanently deleted.')
        else:
            place.is_active = False
            place.save(update_fields=["is_active", "updated_at"])
            messages.success(request, f'Place "{place.name}" deactivated.')

        return redirect("admin_places_list")
