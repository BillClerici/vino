from django.conf import settings
from django.contrib import messages
from django.contrib.auth.mixins import LoginRequiredMixin
from django.shortcuts import get_object_or_404, redirect, render
from django.views import View
from django.views.generic import ListView

from apps.visits.forms import VisitLogForm
from apps.visits.models import VisitLog
from apps.wineries.models import Place


class VisitListView(LoginRequiredMixin, ListView):
    model = VisitLog
    template_name = "visits/list.html"
    context_object_name = "visits"
    paginate_by = 10

    def get_queryset(self):
        from django.db.models import Q

        qs = (
            VisitLog.objects.filter(user=self.request.user)
            .select_related("place")
            .prefetch_related("wines_tasted__menu_item")
        )

        # Search
        q = self.request.GET.get("q", "").strip()
        if q:
            qs = qs.filter(
                Q(place__name__icontains=q)
                | Q(place__city__icontains=q)
                | Q(place__state__icontains=q)
                | Q(notes__icontains=q)
            )

        # Filter by rating
        rating = self.request.GET.get("rating", "")
        if rating:
            qs = qs.filter(rating_overall=int(rating))

        # Filter by place type
        place_type = self.request.GET.get("type", "")
        if place_type:
            qs = qs.filter(place__place_type=place_type)

        # Filter by date range
        date_from = self.request.GET.get("from", "")
        date_to = self.request.GET.get("to", "")
        if date_from:
            qs = qs.filter(visited_at__date__gte=date_from)
        if date_to:
            qs = qs.filter(visited_at__date__lte=date_to)

        # Sort
        sort = self.request.GET.get("sort", "-visited_at")
        valid_sorts = {
            "visited_at": "visited_at",
            "-visited_at": "-visited_at",
            "place__name": "place__name",
            "-place__name": "-place__name",
            "rating_overall": "rating_overall",
            "-rating_overall": "-rating_overall",
        }
        order = valid_sorts.get(sort, "-visited_at")
        qs = qs.order_by(order)

        return qs

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        ctx["search_query"] = self.request.GET.get("q", "")
        ctx["filter_rating"] = self.request.GET.get("rating", "")
        ctx["filter_type"] = self.request.GET.get("type", "")
        ctx["filter_from"] = self.request.GET.get("from", "")
        ctx["filter_to"] = self.request.GET.get("to", "")
        ctx["current_sort"] = self.request.GET.get("sort", "-visited_at")
        ctx["place_type_choices"] = [
            ("winery", "Winery"),
            ("brewery", "Brewery"),
            ("restaurant", "Restaurant"),
            ("other", "Other"),
        ]
        return ctx


class CheckInView(LoginRequiredMixin, View):
    """Log a new place visit — the core user action."""

    def get(self, request):
        place_id = request.GET.get("winery")
        initial = {}
        place = None
        if place_id:
            place = get_object_or_404(Place, pk=place_id)
            initial["winery"] = place.pk
        form = VisitLogForm(initial=initial)
        return render(request, "visits/checkin.html", {
            "form": form,
            "preselected_place": place,
        })

    def post(self, request):
        form = VisitLogForm(request.POST)
        if form.is_valid():
            visit = form.save(commit=False)
            visit.user = request.user
            visit.save()
            messages.success(request, f"Checked in at {visit.place.name}!")
            return redirect("visit_detail", pk=visit.pk)
        return render(request, "visits/checkin.html", {"form": form})


class VisitDetailView(LoginRequiredMixin, View):
    def get(self, request, pk):
        visit = get_object_or_404(
            VisitLog.objects.select_related("place").prefetch_related("wines_tasted__menu_item"),
            pk=pk,
            user=request.user,
        )
        user = request.user
        place = visit.place

        # Visit history at this place
        visit_history = (
            VisitLog.objects.filter(user=user, place=place, is_active=True)
            .exclude(pk=visit.pk)
            .order_by("-visited_at")[:5]
        )

        # Is this place a favorite?
        from apps.wineries.models import FavoritePlace
        is_favorite = FavoritePlace.objects.filter(
            user=user, place=place, is_active=True,
        ).exists()

        # Stats: user's visits to this place
        from django.db.models import Avg, Count
        place_stats = (
            VisitLog.objects.filter(user=user, place=place, is_active=True)
            .aggregate(
                total_visits=Count("id"),
                avg_overall=Avg("rating_overall"),
                avg_staff=Avg("rating_staff"),
                avg_ambience=Avg("rating_ambience"),
                avg_food=Avg("rating_food"),
            )
        )

        # All wines user has tasted at this place (across all visits)
        from apps.visits.models import VisitWine
        all_wines_here = (
            VisitWine.objects.filter(
                visit__user=user, visit__place=place, is_active=True,
            )
            .select_related("menu_item")
            .order_by("-rating", "wine_name")
        )

        # Wine stats
        wine_stats = {
            "total_tasted": all_wines_here.count(),
            "favorites": all_wines_here.filter(is_favorite=True).count(),
            "purchased": all_wines_here.filter(purchased=True).count(),
            "top_rated": all_wines_here.filter(rating__gte=4).count(),
        }

        # Serving type breakdown for this visit
        serving_counts = {}
        for vw in visit.wines_tasted.all():
            label = vw.get_serving_type_display()
            serving_counts[label] = serving_counts.get(label, 0) + vw.quantity

        # Rating comparison: this visit vs user's average here
        rating_comparison = {}
        if visit.rating_overall and place_stats["avg_overall"]:
            diff = visit.rating_overall - place_stats["avg_overall"]
            if abs(diff) < 0.3:
                rating_comparison["label"] = "On par"
                rating_comparison["icon"] = "remove"
                rating_comparison["color"] = "#9e9e9e"
            elif diff > 0:
                rating_comparison["label"] = "Above your average"
                rating_comparison["icon"] = "trending_up"
                rating_comparison["color"] = "#43a047"
            else:
                rating_comparison["label"] = "Below your average"
                rating_comparison["icon"] = "trending_down"
                rating_comparison["color"] = "#e53935"

        # Place menu items (for the drinks grid when user hasn't logged wines)
        from apps.wineries.models import MenuItem
        menu_items = place.menu_items.filter(is_active=True).order_by("name")

        return render(request, "visits/detail.html", {
            "visit": visit,
            "visit_history": visit_history,
            "is_favorite": is_favorite,
            "place_stats": place_stats,
            "wine_stats": wine_stats,
            "all_wines_here": all_wines_here,
            "menu_items": menu_items,
            "serving_counts": serving_counts,
            "rating_comparison": rating_comparison,
            "google_maps_api_key": getattr(settings, "GOOGLE_MAPS_API_KEY", ""),
        })
