from django.db.models import Avg, Count, F
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.palate.models import PalateProfile
from apps.visits.models import VisitLog, VisitWine
from ..permissions import HasActiveSubscription
from .serializers import PalateProfileSerializer


class PalateProfileView(APIView):
    permission_classes = [HasActiveSubscription]

    def get(self, request):
        """User's palate profile with visit stats and top varietals."""
        profile, _ = PalateProfile.objects.get_or_create(user=request.user)

        visits = VisitLog.objects.filter(user=request.user, is_active=True)
        visit_stats = visits.aggregate(
            total_visits=Count("id"),
            avg_staff=Avg("rating_staff"),
            avg_ambience=Avg("rating_ambience"),
            avg_food=Avg("rating_food"),
            avg_overall=Avg("rating_overall"),
        )

        # Top varietals from wines tasted
        wines = VisitWine.objects.filter(
            visit__user=request.user, is_active=True
        )

        # Count varietals from menu items
        top_from_menu = list(
            wines.filter(menu_item__isnull=False)
            .values(varietal=F("menu_item__varietal"))
            .annotate(count=Count("id"), avg_rating=Avg("rating"))
            .order_by("-count")[:10]
        )

        # Count varietals from ad-hoc entries
        top_from_adhoc = list(
            wines.filter(wine_type__gt="")
            .values(varietal=F("wine_type"))
            .annotate(count=Count("id"), avg_rating=Avg("rating"))
            .order_by("-count")[:10]
        )

        # Merge and sort
        varietal_map = {}
        for v in top_from_menu + top_from_adhoc:
            key = v["varietal"]
            if not key:
                continue
            if key in varietal_map:
                varietal_map[key]["count"] += v["count"]
            else:
                varietal_map[key] = {
                    "varietal": key,
                    "count": v["count"],
                    "avg_rating": v["avg_rating"],
                }

        top_varietals = sorted(varietal_map.values(), key=lambda x: -x["count"])[:10]

        return Response({
            "profile": PalateProfileSerializer(profile).data,
            "visit_stats": visit_stats,
            "top_varietals": top_varietals,
        })
