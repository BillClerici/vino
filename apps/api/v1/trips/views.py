from datetime import date

from django.db.models import Count
from django.utils import timezone
from rest_framework import status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.viewsets import ModelViewSet

from apps.trips.models import Trip, TripMember, TripStop
from apps.visits.models import VisitLog, VisitWine
from ..permissions import HasActiveSubscription, IsTripMemberOrReadOnly
from .filters import TripFilter
from .serializers import (
    TripDetailSerializer,
    TripInviteSerializer,
    TripListSerializer,
    TripMemberSerializer,
    TripMemberUpdateSerializer,
    TripStopReorderSerializer,
    TripStopSerializer,
    TripStopWriteSerializer,
    TripWriteSerializer,
)


class TripViewSet(ModelViewSet):
    permission_classes = [HasActiveSubscription, IsTripMemberOrReadOnly]
    filterset_class = TripFilter
    search_fields = ["name"]
    ordering_fields = ["name", "scheduled_date", "created_at", "status"]
    ordering = ["-scheduled_date"]

    def get_queryset(self):
        qs = Trip.objects.filter(
            members=self.request.user, is_active=True
        ).select_related("created_by").annotate(
            member_count=Count("trip_members", distinct=True),
            stop_count=Count("trip_stops", distinct=True),
        ).distinct()

        # Add active_stops and active_members for detail view
        return qs.prefetch_related(
            "trip_stops__place",
            "trip_members__user",
        )

    def get_serializer_class(self):
        if self.action == "retrieve":
            return TripDetailSerializer
        if self.action in ("create", "update", "partial_update"):
            return TripWriteSerializer
        return TripListSerializer

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        trip = serializer.save()
        # Return detail representation (includes id, stops, members)
        trip.active_stops = trip.trip_stops.filter(is_active=True).order_by("order")
        trip.active_members = trip.trip_members.filter(is_active=True)
        detail = TripDetailSerializer(trip, context=self.get_serializer_context())
        return Response(detail.data, status=status.HTTP_201_CREATED)

    def get_serializer_context(self):
        ctx = super().get_serializer_context()
        ctx["request"] = self.request
        return ctx

    def get_object(self):
        obj = super().get_object()
        # Attach filtered related sets for detail serializer
        obj.active_stops = obj.trip_stops.filter(is_active=True).order_by("order")
        obj.active_members = obj.trip_members.filter(is_active=True)
        return obj

    def perform_destroy(self, instance):
        instance.is_active = False
        instance.save(update_fields=["is_active", "updated_at"])

    # ── Stop management ──────────────────────────────────────────────

    @action(detail=True, methods=["post"], url_path="stops")
    def add_stop(self, request, pk=None):
        """Add a stop to the trip."""
        from datetime import datetime as dt

        trip = self.get_object()
        serializer = TripStopWriteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        # Auto-set order if not provided
        if not serializer.validated_data.get("order"):
            max_order = trip.trip_stops.filter(is_active=True).count()
            serializer.validated_data["order"] = max_order

        # Default arrival_time to trip's scheduled_date + meeting_time
        if not serializer.validated_data.get("arrival_time"):
            if trip.scheduled_date:
                meeting_time = trip.meeting_time or dt.strptime("12:00", "%H:%M").time()
                if max_order == 0:
                    # First stop: use meeting time
                    arrival = dt.combine(trip.scheduled_date, meeting_time)
                else:
                    # Subsequent stops: use scheduled_date at noon as default
                    arrival = dt.combine(trip.scheduled_date, dt.strptime("12:00", "%H:%M").time())
                serializer.validated_data["arrival_time"] = timezone.make_aware(arrival)

        stop = serializer.save(trip=trip)
        return Response(
            TripStopSerializer(stop).data,
            status=status.HTTP_201_CREATED,
        )

    @action(detail=True, methods=["put", "patch", "delete"], url_path="stops/(?P<stop_pk>[^/.]+)")
    def update_stop(self, request, pk=None, stop_pk=None):
        """Update or remove a trip stop."""
        trip = self.get_object()
        try:
            stop = trip.trip_stops.get(pk=stop_pk, is_active=True)
        except TripStop.DoesNotExist:
            return Response(status=status.HTTP_404_NOT_FOUND)

        if request.method == "DELETE":
            stop.is_active = False
            stop.save(update_fields=["is_active", "updated_at"])
            return Response(status=status.HTTP_204_NO_CONTENT)

        serializer = TripStopWriteSerializer(stop, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(TripStopSerializer(stop).data)

    @action(detail=True, methods=["post"], url_path="stops/reorder")
    def reorder_stops(self, request, pk=None):
        """Reorder trip stops."""
        trip = self.get_object()
        serializer = TripStopReorderSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        for item in serializer.validated_data["stops"]:
            trip.trip_stops.filter(
                pk=item["id"], is_active=True
            ).update(order=int(item["order"]))

        stops = trip.trip_stops.filter(is_active=True).order_by("order")
        return Response(TripStopSerializer(stops, many=True).data)

    # ── Member management ────────────────────────────────────────────

    @action(detail=True, methods=["post"], url_path="members/invite")
    def invite_member(self, request, pk=None):
        """Invite a member to the trip."""
        trip = self.get_object()
        serializer = TripInviteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        # Check if already a member
        from apps.users.models import User
        existing_user = User.objects.filter(email=data["email"]).first()

        if existing_user:
            member, created = TripMember.all_objects.get_or_create(
                trip=trip, user=existing_user,
                defaults={
                    "role": TripMember.Role.INVITED,
                    "rsvp_status": "pending",
                    "invite_email": data["email"],
                    "invite_message": data.get("message", ""),
                    "invited_at": timezone.now(),
                },
            )
        else:
            member, created = TripMember.all_objects.get_or_create(
                trip=trip, invite_email=data["email"],
                defaults={
                    "role": TripMember.Role.INVITED,
                    "rsvp_status": "pending",
                    "invite_first_name": data.get("first_name", ""),
                    "invite_last_name": data.get("last_name", ""),
                    "invite_message": data.get("message", ""),
                    "invited_at": timezone.now(),
                },
            )

        if not created and not member.is_active:
            member.is_active = True
            member.save(update_fields=["is_active", "updated_at"])

        return Response(
            TripMemberSerializer(member).data,
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
        )

    @action(detail=True, methods=["put", "patch", "delete"], url_path="members/(?P<member_pk>[^/.]+)")
    def update_member(self, request, pk=None, member_pk=None):
        """Update or remove a trip member."""
        trip = self.get_object()
        try:
            member = trip.trip_members.get(pk=member_pk, is_active=True)
        except TripMember.DoesNotExist:
            return Response(status=status.HTTP_404_NOT_FOUND)

        if request.method == "DELETE":
            member.is_active = False
            member.save(update_fields=["is_active", "updated_at"])
            return Response(status=status.HTTP_204_NO_CONTENT)

        serializer = TripMemberUpdateSerializer(data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        for field, value in serializer.validated_data.items():
            setattr(member, field, value)
        if "rsvp_status" in serializer.validated_data:
            member.responded_at = timezone.now()
        member.save()
        return Response(TripMemberSerializer(member).data)

    # ── Status transitions ───────────────────────────────────────────

    @action(detail=True, methods=["post"])
    def start(self, request, pk=None):
        """Transition trip to IN_PROGRESS."""
        trip = self.get_object()
        if trip.status not in (Trip.Status.CONFIRMED, Trip.Status.DRAFT, Trip.Status.PLANNING):
            return Response(
                {"detail": f"Cannot start a trip with status '{trip.status}'."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        trip.status = Trip.Status.IN_PROGRESS
        trip.save(update_fields=["status", "updated_at"])
        return Response(TripDetailSerializer(trip).data)

    @action(detail=True, methods=["post"])
    def complete(self, request, pk=None):
        """Mark trip as COMPLETED."""
        trip = self.get_object()
        if trip.status != Trip.Status.IN_PROGRESS:
            return Response(
                {"detail": "Only in-progress trips can be completed."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        trip.status = Trip.Status.COMPLETED
        trip.save(update_fields=["status", "updated_at"])
        return Response(TripDetailSerializer(trip).data)

    # ── Live trip actions ────────────────────────────────────────────

    @action(detail=True, methods=["post"], url_path="live/checkin/(?P<stop_pk>[^/.]+)")
    def live_checkin(self, request, pk=None, stop_pk=None):
        """Check in at a stop during a live trip."""
        trip = self.get_object()
        try:
            stop = trip.trip_stops.get(pk=stop_pk, is_active=True)
        except TripStop.DoesNotExist:
            return Response(status=status.HTTP_404_NOT_FOUND)

        # Create a visit for this stop
        visit = VisitLog.objects.create(
            user=request.user,
            place=stop.place,
            visited_at=timezone.now(),
        )
        return Response({
            "visit_id": str(visit.id),
            "place_name": stop.place.name,
            "stop_order": stop.order,
        }, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=["post"], url_path="live/rate/(?P<visit_pk>[^/.]+)")
    def live_rate(self, request, pk=None, visit_pk=None):
        """Rate a visit during a live trip."""
        try:
            visit = VisitLog.objects.get(pk=visit_pk, user=request.user, is_active=True)
        except VisitLog.DoesNotExist:
            return Response(status=status.HTTP_404_NOT_FOUND)

        for field in ("rating_staff", "rating_ambience", "rating_food", "rating_overall", "notes"):
            if field in request.data:
                setattr(visit, field, request.data[field])
        visit.save()
        return Response({"detail": "Rating saved."})

    @action(detail=True, methods=["post"], url_path="live/wine")
    def live_wine(self, request, pk=None):
        """Log a wine during a live trip."""
        visit_id = request.data.get("visit_id")
        if not visit_id:
            return Response(
                {"detail": "visit_id is required."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        try:
            visit = VisitLog.objects.get(pk=visit_id, user=request.user, is_active=True)
        except VisitLog.DoesNotExist:
            return Response(status=status.HTTP_404_NOT_FOUND)

        from ..visits.serializers import VisitWineWriteSerializer, VisitWineSerializer
        serializer = VisitWineWriteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        wine = serializer.save(visit=visit)
        return Response(VisitWineSerializer(wine).data, status=status.HTTP_201_CREATED)
