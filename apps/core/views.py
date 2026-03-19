from django.contrib.auth.mixins import LoginRequiredMixin, UserPassesTestMixin
from django.db.models import Avg, Count
from django.views.generic import TemplateView

from apps.trips.models import Trip
from apps.visits.models import VisitLog
from apps.wineries.models import Place


class LandingPageView(TemplateView):
    template_name = "landing.html"

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        user = self.request.user

        if not user.is_authenticated:
            return ctx

        # Personal stats
        my_visits = VisitLog.objects.filter(user=user, is_active=True)
        ctx["visit_count"] = my_visits.count()
        ctx["unique_places"] = my_visits.values("place").distinct().count()
        ctx["avg_rating"] = my_visits.aggregate(avg=Avg("rating_overall"))["avg"]
        ctx["trips_completed"] = Trip.objects.filter(
            members=user, is_active=True, status="completed"
        ).count()

        # Recent visits
        ctx["recent_visits"] = (
            my_visits.select_related("place").order_by("-visited_at")[:5]
        )

        # Active trips
        from datetime import date
        active_trips = list(
            Trip.objects.filter(members=user, is_active=True)
            .exclude(status__in=["completed", "cancelled"])
            .prefetch_related("trip_members__user", "trip_stops__place")
            .order_by("-created_at")[:3]
        )
        today = date.today()
        for trip in active_trips:
            trip.show_start_button = (
                trip.status == "in_progress"
                or (trip.status == "confirmed" and trip.scheduled_date and trip.scheduled_date <= today)
            )
            trip.is_today = (trip.scheduled_date == today) if trip.scheduled_date else False
        ctx["active_trips"] = active_trips

        # Top-rated places (from user's visits, only those with ratings)
        ctx["top_places"] = (
            my_visits.filter(rating_overall__isnull=False)
            .values("place__id", "place__name", "place__city", "place__state")
            .annotate(avg_overall=Avg("rating_overall"), times_visited=Count("id"))
            .order_by("-avg_overall")[:5]
        )

        # Discover — places the user hasn't visited yet
        visited_ids = my_visits.values_list("place_id", flat=True)
        ctx["discover"] = (
            Place.objects.exclude(pk__in=visited_ids)
            .annotate(
                avg_rating=Avg("visits__rating_overall", default=0),
                visit_count=Count("visits"),
            )
            .order_by("-avg_rating")[:4]
        )

        return ctx


class AppSettingsView(LoginRequiredMixin, UserPassesTestMixin, TemplateView):
    template_name = "settings/app_settings.html"

    def test_func(self):
        return self.request.user.is_superuser
