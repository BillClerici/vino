"""
Achievement Badges — computed dynamically from user activity.

No model needed — badges are computed on-the-fly from VisitLog, VisitWine,
Trip, and SippyConversation counts. This keeps them always accurate and
avoids migration overhead.
"""

from django.db.models import Avg, Count, Q, Sum
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.trips.models import SippyConversation, Trip
from apps.visits.models import VisitLog, VisitWine
from apps.wineries.models import WineWishlist
from ..permissions import HasActiveSubscription

# Badge definitions: (id, name, icon, description, category, check_function_name)
BADGE_DEFINITIONS = [
    # Visits
    ("first_visit", "First Sip", "local_drink", "Complete your first check-in", "visits", 1),
    ("explorer_5", "Explorer", "explore", "Visit 5 different places", "visits", 5),
    ("explorer_10", "Seasoned Explorer", "travel_explore", "Visit 10 different places", "visits", 10),
    ("explorer_25", "Trailblazer", "public", "Visit 25 different places", "visits", 25),
    ("regular", "Regular", "repeat", "Visit the same place 3 times", "visits", 3),

    # Wines
    ("first_wine", "Wine Curious", "wine_bar", "Log your first wine", "wines", 1),
    ("wine_10", "Taster", "local_bar", "Log 10 wines", "wines", 10),
    ("wine_50", "Connoisseur", "emoji_events", "Log 50 wines", "wines", 50),
    ("wine_100", "Sommelier", "workspace_premium", "Log 100 wines", "wines", 100),
    ("variety_5", "Variety Seeker", "category", "Try 5 different varietals", "wines", 5),
    ("variety_10", "Open Minded", "psychology", "Try 10 different varietals", "wines", 10),
    ("five_star", "Five Star Find", "star", "Rate a wine 5 out of 5", "wines", 1),
    ("favorite_3", "Heart Collector", "favorite", "Mark 3 wines as favorites", "wines", 3),

    # Trips
    ("first_trip", "Road Tripper", "directions_car", "Complete your first trip", "trips", 1),
    ("trip_5", "Journey Master", "map", "Complete 5 trips", "trips", 5),
    ("big_trip", "Marathon Taster", "route", "Complete a trip with 5+ stops", "trips", 5),

    # Social & AI
    ("sippy_planner", "Sippy's Friend", "auto_awesome", "Plan a trip with Sippy", "ai", 1),
    ("sippy_3", "AI Explorer", "smart_toy", "Plan 3 trips with Sippy", "ai", 3),
    ("flight_builder", "Flight Captain", "local_bar", "Build a tasting flight", "ai", 1),
    ("wishlist_5", "Bucket Lister", "bookmark", "Add 5 wines to your wishlist", "ai", 5),

    # Ratings
    ("critic", "The Critic", "rate_review", "Rate 10 visits", "ratings", 10),
    ("generous", "Generous Pour", "thumb_up", "Give 5 ratings of 5/5", "ratings", 5),

    # Purchases
    ("first_purchase", "Take-Home", "shopping_bag", "Buy your first bottle", "purchases", 1),
    ("collector", "Collector", "inventory_2", "Buy 10 bottles", "purchases", 10),
]


class BadgesView(APIView):
    """GET /api/v1/badges/ — compute and return all badges for the current user."""

    permission_classes = [HasActiveSubscription]

    def get(self, request):
        user = request.user

        # Gather stats
        visits = VisitLog.objects.filter(user=user, is_active=True)
        total_visits = visits.count()
        unique_places = visits.values("place").distinct().count()
        max_visits_one_place = 0
        if total_visits > 0:
            from django.db.models.functions import Coalesce
            place_counts = visits.values("place").annotate(c=Count("id")).order_by("-c")
            if place_counts:
                max_visits_one_place = place_counts[0]["c"]

        rated_visits = visits.filter(rating_overall__isnull=False).count()
        five_star_visits = visits.filter(rating_overall=5).count()

        wines = VisitWine.objects.filter(visit__user=user, is_active=True)
        total_wines = wines.count()
        unique_varietals = wines.exclude(wine_type="").values("wine_type").distinct().count()
        favorite_wines = wines.filter(is_favorite=True).count()
        five_star_wines = wines.filter(rating=5).count()

        purchased_count = wines.filter(purchased=True).count()

        trips = Trip.objects.filter(members=user, is_active=True)
        completed_trips = trips.filter(status=Trip.Status.COMPLETED).count()
        big_trips = trips.filter(status=Trip.Status.COMPLETED).annotate(
            stop_count=Count("trip_stops", filter=Q(trip_stops__is_active=True))
        ).filter(stop_count__gte=5).count()

        sippy_plans = SippyConversation.objects.filter(
            user=user, chat_type="plan", phase="approved", is_active=True
        ).count()

        wishlist_count = WineWishlist.objects.filter(user=user, is_active=True).count()

        # Check each badge
        stats = {
            "total_visits": total_visits,
            "unique_places": unique_places,
            "max_visits_one_place": max_visits_one_place,
            "rated_visits": rated_visits,
            "five_star_visits": five_star_visits,
            "total_wines": total_wines,
            "unique_varietals": unique_varietals,
            "favorite_wines": favorite_wines,
            "five_star_wines": five_star_wines,
            "purchased_count": purchased_count,
            "completed_trips": completed_trips,
            "big_trips": big_trips,
            "sippy_plans": sippy_plans,
            "wishlist_count": wishlist_count,
        }

        badges = []
        for badge_id, name, icon, description, category, threshold in BADGE_DEFINITIONS:
            earned = _check_badge(badge_id, stats, threshold)
            badges.append({
                "id": badge_id,
                "name": name,
                "icon": icon,
                "description": description,
                "category": category,
                "earned": earned,
                "progress": _get_progress(badge_id, stats, threshold),
            })

        earned_count = sum(1 for b in badges if b["earned"])

        return Response({
            "badges": badges,
            "earned_count": earned_count,
            "total_count": len(badges),
            "stats": stats,
        })


def _check_badge(badge_id, stats, threshold):
    """Check if a badge has been earned."""
    mapping = {
        "first_visit": stats["total_visits"],
        "explorer_5": stats["unique_places"],
        "explorer_10": stats["unique_places"],
        "explorer_25": stats["unique_places"],
        "regular": stats["max_visits_one_place"],
        "first_wine": stats["total_wines"],
        "wine_10": stats["total_wines"],
        "wine_50": stats["total_wines"],
        "wine_100": stats["total_wines"],
        "variety_5": stats["unique_varietals"],
        "variety_10": stats["unique_varietals"],
        "five_star": stats["five_star_wines"],
        "favorite_3": stats["favorite_wines"],
        "first_trip": stats["completed_trips"],
        "trip_5": stats["completed_trips"],
        "big_trip": stats["big_trips"],
        "sippy_planner": stats["sippy_plans"],
        "sippy_3": stats["sippy_plans"],
        "flight_builder": 0,  # TODO: track flight builds
        "wishlist_5": stats["wishlist_count"],
        "critic": stats["rated_visits"],
        "generous": stats["five_star_visits"],
        "first_purchase": stats["purchased_count"],
        "collector": stats["purchased_count"],
    }
    current = mapping.get(badge_id, 0)
    return current >= threshold


def _get_progress(badge_id, stats, threshold):
    """Get progress fraction (0.0 to 1.0) toward earning a badge."""
    mapping = {
        "first_visit": stats["total_visits"],
        "explorer_5": stats["unique_places"],
        "explorer_10": stats["unique_places"],
        "explorer_25": stats["unique_places"],
        "regular": stats["max_visits_one_place"],
        "first_wine": stats["total_wines"],
        "wine_10": stats["total_wines"],
        "wine_50": stats["total_wines"],
        "wine_100": stats["total_wines"],
        "variety_5": stats["unique_varietals"],
        "variety_10": stats["unique_varietals"],
        "five_star": stats["five_star_wines"],
        "favorite_3": stats["favorite_wines"],
        "first_trip": stats["completed_trips"],
        "trip_5": stats["completed_trips"],
        "big_trip": stats["big_trips"],
        "sippy_planner": stats["sippy_plans"],
        "sippy_3": stats["sippy_plans"],
        "flight_builder": 0,
        "wishlist_5": stats["wishlist_count"],
        "critic": stats["rated_visits"],
        "generous": stats["five_star_visits"],
        "first_purchase": stats["purchased_count"],
        "collector": stats["purchased_count"],
    }
    current = mapping.get(badge_id, 0)
    return min(current / threshold, 1.0) if threshold > 0 else 0.0
