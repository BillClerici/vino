from django.db.models import Count
from rest_framework import status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.viewsets import ModelViewSet

from apps.visits.models import VisitLog, VisitWine
from ..permissions import HasActiveSubscription, IsOwnerOrReadOnly
from .filters import VisitLogFilter
from .serializers import (
    CheckInSerializer,
    VisitLogDetailSerializer,
    VisitLogListSerializer,
    VisitWineSerializer,
    VisitWineWriteSerializer,
)


class VisitLogViewSet(ModelViewSet):
    permission_classes = [HasActiveSubscription, IsOwnerOrReadOnly]
    filterset_class = VisitLogFilter
    search_fields = ["place__name", "notes"]
    ordering_fields = ["visited_at", "rating_overall", "place__name", "created_at"]
    ordering = ["-visited_at"]

    def get_queryset(self):
        return (
            VisitLog.objects.filter(user=self.request.user, is_active=True)
            .select_related("place")
            .annotate(wines_count=Count("wines_tasted", distinct=True))
        )

    def get_serializer_class(self):
        if self.action == "retrieve":
            return VisitLogDetailSerializer
        if self.action == "create":
            return CheckInSerializer
        return VisitLogListSerializer

    def perform_destroy(self, instance):
        instance.is_active = False
        instance.save(update_fields=["is_active", "updated_at"])

    @action(detail=True, methods=["get", "post"], url_path="wines")
    def wines(self, request, pk=None):
        """List or add wines for a visit."""
        visit = self.get_object()
        if request.method == "GET":
            wines = visit.wines_tasted.filter(is_active=True)
            return Response(VisitWineSerializer(wines, many=True).data)

        serializer = VisitWineWriteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        wine = serializer.save(visit=visit)
        return Response(
            VisitWineSerializer(wine).data,
            status=status.HTTP_201_CREATED,
        )

    @action(
        detail=True,
        methods=["put", "patch", "delete"],
        url_path="wines/(?P<wine_pk>[^/.]+)",
    )
    def wine_detail(self, request, pk=None, wine_pk=None):
        """Update or delete a specific wine entry."""
        visit = self.get_object()
        try:
            wine = visit.wines_tasted.get(pk=wine_pk, is_active=True)
        except VisitWine.DoesNotExist:
            return Response(status=status.HTTP_404_NOT_FOUND)

        if request.method == "DELETE":
            wine.is_active = False
            wine.save(update_fields=["is_active", "updated_at"])
            return Response(status=status.HTTP_204_NO_CONTENT)

        serializer = VisitWineWriteSerializer(wine, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(VisitWineSerializer(wine).data)
