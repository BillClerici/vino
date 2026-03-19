import json

from django.conf import settings
from django.contrib import messages
from django.contrib.auth.mixins import LoginRequiredMixin
from django.db.models import Avg, Count, Max, Q
from django.http import JsonResponse
from django.shortcuts import get_object_or_404, redirect, render
from django.views import View
from django.views.generic import ListView

from apps.visits.models import VisitLog
from apps.wineries.forms import WineForm, WineryForm
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

            winery = Winery.objects.create(
                name=name,
                address=addr,
                city=city,
                state=state,
                latitude=lat,
                longitude=lng,
                website=website,
                image_url=photo_url,
            )
        elif photo_url and not winery.image_url:
            winery.image_url = photo_url
            winery.save(update_fields=["image_url", "updated_at"])

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
