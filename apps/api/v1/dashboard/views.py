from django.db.models import Avg, Count, Q
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.trips.models import Trip
from apps.visits.models import VisitLog
from apps.wineries.models import Place
from ..permissions import HasActiveSubscription
from ..visits.serializers import VisitLogListSerializer
from ..places.serializers import PlaceListSerializer


class DashboardView(APIView):
    """GET /api/v1/dashboard/ — Aggregated dashboard data for the home screen."""

    permission_classes = [HasActiveSubscription]

    def get(self, request):
        user = request.user
        my_visits = VisitLog.objects.filter(user=user, is_active=True)

        # Stats
        stats = {
            "visit_count": my_visits.count(),
            "unique_places": my_visits.values("place").distinct().count(),
            "avg_rating": my_visits.aggregate(avg=Avg("rating_overall"))["avg"],
            "trip_count": Trip.objects.filter(
                members=user, is_active=True,
            ).count(),
        }

        # Recent visits (5)
        recent_visits = (
            my_visits.select_related("place")
            .annotate(wines_count=Count("wines_tasted", distinct=True))
            .order_by("-visited_at")[:5]
        )

        # Active trips (3) — include cover image from first stop
        active_trips_qs = (
            Trip.objects.filter(members=user, is_active=True)
            .exclude(status__in=["completed", "cancelled"])
            .select_related("created_by")
            .prefetch_related("trip_stops__place")
            .annotate(
                member_count=Count("trip_members", distinct=True),
                stop_count=Count("trip_stops", filter=Q(trip_stops__is_active=True), distinct=True),
            )
            .order_by("-created_at")[:10]
        )
        active_trips = []
        for trip in active_trips_qs:
            # Find cover image: first stop's place image, or any stop with an image
            cover_image = ""
            stop_place_names = []
            for stop in trip.trip_stops.filter(is_active=True).order_by("order"):
                if stop.place.image_url and not cover_image:
                    cover_image = stop.place.image_url
                stop_place_names.append(stop.place.name)

            active_trips.append({
                "id": str(trip.id),
                "name": trip.name,
                "status": trip.status,
                "scheduled_date": trip.scheduled_date.isoformat() if trip.scheduled_date else None,
                "end_date": trip.end_date.isoformat() if trip.end_date else None,
                "member_count": trip.member_count,
                "stop_count": trip.stop_count,
                "created_by_name": trip.created_by.full_name,
                "cover_image": cover_image,
                "stop_names": stop_place_names[:3],  # First 3 stop names for preview
            })

        # Top-rated places
        top_places = (
            my_visits.filter(rating_overall__isnull=False)
            .values("place__id", "place__name", "place__city", "place__state", "place__image_url")
            .annotate(avg_overall=Avg("rating_overall"), times_visited=Count("id"))
            .order_by("-avg_overall")[:5]
        )

        # Discover — places user hasn't visited
        visited_ids = my_visits.values_list("place_id", flat=True)
        discover_qs = (
            Place.objects.exclude(pk__in=visited_ids)
            .filter(is_active=True)
            .annotate(
                avg_rating=Avg("visits__rating_overall", default=0),
                visit_count=Count("visits"),
            )
            .order_by("-avg_rating")[:4]
        )

        return Response({
            "stats": stats,
            "recent_visits": VisitLogListSerializer(recent_visits, many=True).data,
            "active_trips": active_trips,
            "top_places": list(top_places),
            "discover": PlaceListSerializer(discover_qs, many=True).data,
        })
