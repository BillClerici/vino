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
from apps.wineries.forms import PlaceAdminForm, WineForm, WineryForm
from apps.wineries.models import FavoriteWinery, Winery


class WineryListView(LoginRequiredMixin, ListView):
    model = Winery
    template_name = "wineries/list.html"
    context_object_name = "wineries"
    paginate_by = 12

    def get_queryset(self):
        qs = Winery.objects.annotate(
            visit_count=Count("visits", filter=Q(visits__is_active=True)),
            avg_rating=Avg("visits__rating_overall", filter=Q(visits__is_active=True)),
            wine_count=Count("wines", filter=Q(wines__is_active=True)),
        )
        q = self.request.GET.get("q", "").strip()
        if q:
            qs = qs.filter(Q(name__icontains=q) | Q(city__icontains=q) | Q(state__icontains=q))
        return qs.order_by("name")

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        user = self.request.user
        ctx["search_query"] = self.request.GET.get("q", "")
        ctx["total_wineries"] = Winery.objects.count()
        ctx["google_maps_api_key"] = settings.GOOGLE_MAPS_API_KEY

        # Trip mode: when adding stops from the trip detail page
        trip_id = self.request.GET.get("trip", "")
        if trip_id:
            from apps.trips.models import Trip
            try:
                trip = Trip.objects.prefetch_related("trip_wineries__winery").get(pk=trip_id)
                ctx["adding_to_trip"] = trip
                ctx["trip_id"] = str(trip.pk)
                ctx["trip_stops"] = trip.trip_wineries.select_related("winery").order_by("order")
            except Trip.DoesNotExist:
                pass

        # DB wineries with coordinates for map
        full_qs = self.get_queryset()
        map_wineries = full_qs.filter(
            latitude__isnull=False, longitude__isnull=False
        ).values("id", "name", "city", "state", "address", "website", "latitude", "longitude")
        ctx["map_wineries_json"] = json.dumps([
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
            for w in map_wineries
        ])

        # User's favorites (set of winery IDs)
        favorite_ids = set(
            FavoriteWinery.objects.filter(user=user, is_active=True)
            .values_list("winery_id", flat=True)
        )
        ctx["favorite_ids"] = favorite_ids
        ctx["favorite_ids_json"] = json.dumps([str(pk) for pk in favorite_ids])

        # User's visited wineries with last visit date
        visited_data = (
            VisitLog.objects.filter(user=user, is_active=True)
            .values("winery_id")
            .annotate(last_visited=Max("visited_at"), visit_count=Count("id"))
        )
        visited_map = {str(v["winery_id"]): v for v in visited_data}
        ctx["visited_ids_json"] = json.dumps(list(visited_map.keys()))

        # Favorites table data
        fav_wineries = (
            Winery.objects.filter(pk__in=favorite_ids)
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
        ctx["favorites_list"] = fav_wineries

        # Visited table data
        visited_winery_ids = [v["winery_id"] for v in visited_data]
        visited_wineries = (
            Winery.objects.filter(pk__in=visited_winery_ids)
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
        ctx["visited_list"] = visited_wineries

        return ctx


class ToggleFavoriteView(LoginRequiredMixin, View):
    """AJAX endpoint to toggle a winery as favorite."""

    def post(self, request, pk):
        winery = get_object_or_404(Winery, pk=pk)
        fav, created = FavoriteWinery.all_objects.get_or_create(
            user=request.user, winery=winery,
            defaults={"is_active": True},
        )
        if not created:
            fav.is_active = not fav.is_active
            fav.save(update_fields=["is_active", "updated_at"])

        return JsonResponse({
            "favorited": fav.is_active,
            "winery_id": str(pk),
            "name": winery.name,
            "city": winery.city,
            "state": winery.state,
        })


class FavoritePlaceView(LoginRequiredMixin, View):
    """AJAX endpoint: find-or-create a winery from Google Places data, then toggle favorite."""

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

        # Try to find existing winery by name + coordinates (within ~100m)
        winery = None
        if lat and lng:
            from decimal import Decimal
            lat_d, lng_d = Decimal(str(lat)), Decimal(str(lng))
            winery = (
                Winery.objects.filter(
                    name__iexact=name,
                    latitude__range=(lat_d - Decimal("0.001"), lat_d + Decimal("0.001")),
                    longitude__range=(lng_d - Decimal("0.001"), lng_d + Decimal("0.001")),
                )
                .first()
            )

        if not winery:
            # Parse city/state from address (last parts before zip)
            city, state = "", ""
            if addr:
                parts = [p.strip() for p in addr.split(",")]
                if len(parts) >= 3:
                    city = parts[-3]
                    state_zip = parts[-2].strip().split(" ")
                    state = state_zip[0] if state_zip else ""
                elif len(parts) == 2:
                    city = parts[0]

            place_type = body.get("place_type", "winery")
            if place_type not in dict(Winery.PlaceType.choices):
                place_type = "winery"
            winery = Winery.objects.create(
                name=name,
                address=addr,
                city=city,
                state=state,
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
            if photo_url and not winery.image_url:
                winery.image_url = photo_url
                changed.append("image_url")
            if body.get("phone") and not winery.phone:
                winery.phone = body["phone"]
                changed.append("phone")
            if body.get("description") and not winery.description:
                winery.description = body["description"]
                changed.append("description")
            if changed:
                winery.save(update_fields=changed + ["updated_at"])

        # Toggle favorite
        fav, created = FavoriteWinery.all_objects.get_or_create(
            user=request.user, winery=winery,
            defaults={"is_active": True},
        )
        if not created:
            fav.is_active = not fav.is_active
            fav.save(update_fields=["is_active", "updated_at"])

        return JsonResponse({
            "favorited": fav.is_active,
            "winery_id": str(winery.pk),
            "name": winery.name,
            "city": winery.city,
            "state": winery.state,
        })


class WineryDetailView(LoginRequiredMixin, View):
    def get(self, request, pk):
        winery = get_object_or_404(Winery, pk=pk)
        wines = winery.wines.filter(is_active=True).order_by("name")
        visits = (
            VisitLog.objects.filter(winery=winery, is_active=True)
            .select_related("user")
            .order_by("-visited_at")[:10]
        )
        my_visits = VisitLog.objects.filter(winery=winery, user=request.user, is_active=True).order_by("-visited_at")
        avg_ratings = VisitLog.objects.filter(winery=winery, is_active=True).aggregate(
            staff=Avg("rating_staff"),
            ambience=Avg("rating_ambience"),
            food=Avg("rating_food"),
            overall=Avg("rating_overall"),
        )
        is_favorite = FavoriteWinery.objects.filter(
            user=request.user, winery=winery, is_active=True
        ).exists()
        return render(request, "wineries/detail.html", {
            "winery": winery,
            "wines": wines,
            "visits": visits,
            "my_visits": my_visits,
            "avg_ratings": avg_ratings,
            "is_favorite": is_favorite,
        })


class WineryCreateView(LoginRequiredMixin, View):
    def get(self, request):
        return render(request, "wineries/form.html", {
            "form": WineryForm(),
            "page_title": "Add Winery",
            "icon": "add_business",
        })

    def post(self, request):
        form = WineryForm(request.POST)
        if form.is_valid():
            winery = form.save()
            messages.success(request, f"{winery.name} added!")
            return redirect("winery_detail", pk=winery.pk)
        return render(request, "wineries/form.html", {
            "form": form,
            "page_title": "Add Winery",
            "icon": "add_business",
        })


class WineryEditView(LoginRequiredMixin, View):
    def get(self, request, pk):
        winery = get_object_or_404(Winery, pk=pk)
        return render(request, "wineries/form.html", {
            "form": WineryForm(instance=winery),
            "page_title": f"Edit {winery.name}",
            "icon": "edit",
        })

    def post(self, request, pk):
        winery = get_object_or_404(Winery, pk=pk)
        form = WineryForm(request.POST, instance=winery)
        if form.is_valid():
            form.save()
            messages.success(request, f"{winery.name} updated.")
            return redirect("winery_detail", pk=winery.pk)
        return render(request, "wineries/form.html", {
            "form": form,
            "page_title": f"Edit {winery.name}",
            "icon": "edit",
        })


class WineCreateView(LoginRequiredMixin, View):
    def get(self, request, winery_pk):
        winery = get_object_or_404(Winery, pk=winery_pk)
        return render(request, "wineries/wine_form.html", {
            "form": WineForm(),
            "winery": winery,
        })

    def post(self, request, winery_pk):
        winery = get_object_or_404(Winery, pk=winery_pk)
        form = WineForm(request.POST)
        if form.is_valid():
            wine = form.save(commit=False)
            wine.winery = winery
            wine.save()
            messages.success(request, f"{wine.name} added to {winery.name}!")
            return redirect("winery_detail", pk=winery.pk)
        return render(request, "wineries/wine_form.html", {
            "form": form,
            "winery": winery,
        })


# ── App Admin: Places CRUD ──

class AppAdminRequiredMixin(LoginRequiredMixin, UserPassesTestMixin):
    def test_func(self):
        return self.request.user.is_superuser


class PlaceAdminListView(AppAdminRequiredMixin, ListView):
    model = Winery
    template_name = "admin/list.html"

    def get_queryset(self):
        return Winery.all_objects.all().order_by("name")

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
    model = Winery
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
    model = Winery
    form_class = PlaceAdminForm
    template_name = "admin/place_edit.html"
    success_url = reverse_lazy("admin_places_list")

    def get_queryset(self):
        return Winery.all_objects.all()

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
        ctx["wine_count"] = place.wines.count()
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

        winery = get_object_or_404(Winery.all_objects, pk=pk)
        api_key = django_settings.GOOGLE_MAPS_API_KEY
        if not api_key:
            return JsonResponse({"error": "Google Maps API key not configured"}, status=400)

        # Build search query
        search_query = winery.name
        if winery.city:
            search_query += f" {winery.city}"
        if winery.state:
            search_query += f" {winery.state}"

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

            place = places[0]
            result = {
                "ok": True,
                "name": place.get("displayName", {}).get("text", ""),
                "address": place.get("formattedAddress", ""),
                "phone": place.get("nationalPhoneNumber", ""),
                "website": place.get("websiteUri", ""),
                "description": place.get("editorialSummary", {}).get("text", "") if place.get("editorialSummary") else "",
                "image_url": "",
            }

            # Get photo URL if available
            photos = place.get("photos", [])
            if photos and api_key:
                photo_name = photos[0].get("name", "")
                if photo_name:
                    result["image_url"] = f"https://places.googleapis.com/v1/{photo_name}/media?maxWidthPx=400&key={api_key}"

            # Get lat/lng
            location = place.get("location", {})
            result["latitude"] = location.get("latitude")
            result["longitude"] = location.get("longitude")

            return JsonResponse(result)

        except Exception as e:
            return JsonResponse({"error": str(e)}, status=500)


class PlaceAdminMenuView(AppAdminRequiredMixin, View):
    """AJAX: fetch/scrape wine or beer menu for a place (admin)."""

    def get(self, request, pk):
        from apps.wineries.scraper import scrape_and_cache_wines

        winery = get_object_or_404(Winery.all_objects, pk=pk)

        if request.GET.get("refresh"):
            winery.wine_menu_last_scraped = None
            winery.save(update_fields=["wine_menu_last_scraped", "updated_at"])

        wines = scrape_and_cache_wines(winery)

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
                for w in wines
            ],
        })


class PlaceAdminDeleteView(AppAdminRequiredMixin, View):
    def post(self, request, pk):
        place = get_object_or_404(Winery.all_objects, pk=pk)
        place.is_active = False
        place.save(update_fields=["is_active", "updated_at"])
        messages.success(request, f'Place "{place.name}" deactivated.')
        return redirect("admin_places_list")

    def get(self, request, pk):
        place = get_object_or_404(Winery.all_objects, pk=pk)
        return render(request, "admin/delete.html", {
            "object_name": place.name,
            "cancel_url": reverse("admin_places_list"),
        })
