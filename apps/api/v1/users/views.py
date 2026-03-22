from django.db.models import Avg, Count
from rest_framework import status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.viewsets import GenericViewSet

from apps.trips.models import Trip
from apps.visits.models import VisitLog
from apps.wineries.models import FavoritePlace
from ..permissions import HasActiveSubscription
from .serializers import UserProfileUpdateSerializer, UserSerializer


class UserProfileViewSet(GenericViewSet):
    """Endpoints for the current authenticated user's profile."""

    permission_classes = [HasActiveSubscription]

    def get_object(self):
        return self.request.user

    def retrieve(self, request, *args, **kwargs):
        """GET /api/v1/me/ — Current user profile."""
        serializer = UserSerializer(request.user)
        return Response(serializer.data)

    def partial_update(self, request, *args, **kwargs):
        """PATCH /api/v1/me/ — Update profile fields."""
        serializer = UserProfileUpdateSerializer(request.user, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(UserSerializer(request.user).data)

    @action(detail=False, methods=["get"])
    def stats(self, request):
        """GET /api/v1/me/stats/ — User activity statistics."""
        user = request.user
        visits = VisitLog.objects.filter(user=user, is_active=True)
        data = {
            "visit_count": visits.count(),
            "places_visited": visits.values("place").distinct().count(),
            "avg_rating": visits.aggregate(avg=Avg("rating_overall"))["avg"],
            "trips_completed": Trip.objects.filter(
                members=user, is_active=True, status="completed"
            ).count(),
            "trips_total": Trip.objects.filter(members=user, is_active=True).count(),
            "wines_logged": sum(
                v.wines_tasted.filter(is_active=True).count() for v in visits
            ),
            "favorites_count": FavoritePlace.objects.filter(user=user, is_active=True).count(),
        }
        return Response(data)
