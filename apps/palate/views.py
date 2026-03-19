from django.contrib.auth.mixins import LoginRequiredMixin
from django.db.models import Avg, Count
from django.shortcuts import render
from django.views import View

from apps.palate.models import PalateProfile
from apps.visits.models import VisitLog


class PalateView(LoginRequiredMixin, View):
    """The user's personal palate profile page."""

    def get(self, request):
        profile, _ = PalateProfile.objects.get_or_create(user=request.user)

        # Aggregate stats from visits
        visit_stats = VisitLog.objects.filter(user=request.user, is_active=True).aggregate(
            total_visits=Count("id"),
            avg_staff=Avg("rating_staff"),
            avg_ambience=Avg("rating_ambience"),
            avg_food=Avg("rating_food"),
            avg_overall=Avg("rating_overall"),
        )

        # Top varietals from wines tasted
        from apps.visits.models import VisitWine
        top_varietals = (
            VisitWine.objects.filter(visit__user=request.user, is_active=True)
            .values("wine__varietal")
            .annotate(count=Count("id"), avg_rating=Avg("rating"))
            .order_by("-count")[:5]
        )

        # Recent visits
        recent_visits = (
            VisitLog.objects.filter(user=request.user, is_active=True)
            .select_related("winery")
            .order_by("-visited_at")[:5]
        )

        return render(request, "palate/profile.html", {
            "profile": profile,
            "visit_stats": visit_stats,
            "top_varietals": top_varietals,
            "recent_visits": recent_visits,
        })
