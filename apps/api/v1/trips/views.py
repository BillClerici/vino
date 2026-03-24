
from django.db.models import Avg, Count, Q
from django.utils import timezone
from rest_framework import status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.viewsets import ModelViewSet

from apps.palate.models import PalateProfile
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
        # Auto-activate trips whose scheduled date/time has arrived
        Trip.auto_activate_user_trips(self.request.user)

        qs = Trip.objects.filter(
            members=self.request.user, is_active=True
        ).select_related("created_by").annotate(
            member_count=Count("trip_members", distinct=True),
            stop_count=Count("trip_stops", filter=Q(trip_stops__is_active=True), distinct=True),
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
        # Auto-activate if scheduled date/time has arrived
        obj.auto_activate_if_ready()
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

        # Create a visit for this stop and link it
        visit = VisitLog.objects.create(
            user=request.user,
            place=stop.place,
            visited_at=timezone.now(),
        )
        stop.visit = visit
        stop.save(update_fields=["visit"])

        # Check for wishlist matches at this place
        from apps.wineries.models import MenuItem, WineWishlist
        wishlist_matches = []
        # Direct menu_item matches
        direct = WineWishlist.objects.filter(
            user=request.user, is_active=True,
            menu_item__place=stop.place, menu_item__is_active=True,
        ).values_list("wine_name", flat=True)
        wishlist_matches.extend(direct)
        # Name matches against menu
        wishlist_names = list(
            WineWishlist.objects.filter(user=request.user, is_active=True)
            .exclude(wine_name="")
            .values_list("wine_name", flat=True)
        )
        if wishlist_names:
            from django.db.models import Q as WQ
            q = WQ()
            for wn in wishlist_names:
                q |= WQ(name__icontains=wn)
            found = MenuItem.objects.filter(
                q, place=stop.place, is_active=True
            ).values_list("name", flat=True)
            wishlist_matches.extend(found)

        return Response({
            "visit_id": str(visit.id),
            "place_name": stop.place.name,
            "stop_order": stop.order,
            "wishlist_matches": list(set(wishlist_matches)),
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

    @action(detail=True, methods=["post"], url_path="live/metadata/(?P<visit_pk>[^/.]+)")
    def live_metadata(self, request, pk=None, visit_pk=None):
        """Save AI results (flight, recommendations, pairings) to visit metadata."""
        try:
            visit = VisitLog.objects.get(pk=visit_pk, user=request.user, is_active=True)
        except VisitLog.DoesNotExist:
            return Response(status=status.HTTP_404_NOT_FOUND)

        meta = visit.metadata or {}
        # Merge provided keys into metadata
        for key in ("flight", "recommendations", "pairings"):
            if key in request.data:
                value = request.data[key]
                if value:
                    meta[key] = value
                else:
                    meta.pop(key, None)
        visit.metadata = meta
        visit.save(update_fields=["metadata", "updated_at"])
        return Response({"detail": "Saved."})

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

        from ..visits.serializers import VisitWineSerializer, VisitWineWriteSerializer
        serializer = VisitWineWriteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        wine = serializer.save(visit=visit)
        return Response(VisitWineSerializer(wine).data, status=status.HTTP_201_CREATED)

    # ── Trip Recap ────────────────────────────────────────────────

    @action(detail=True, methods=["get"])
    def recap(self, request, pk=None):
        """Generate a recap summary for a completed trip."""
        trip = self.get_object()

        stops = trip.trip_stops.filter(is_active=True).select_related("place").order_by("order")

        # Gather all visits by trip members during trip date range
        member_user_ids = trip.trip_members.filter(
            is_active=True, user__isnull=False
        ).values_list("user_id", flat=True)

        visit_filter = Q(user_id__in=member_user_ids, is_active=True)
        place_ids = stops.values_list("place_id", flat=True)
        visit_filter &= Q(place_id__in=place_ids)

        visits = VisitLog.objects.filter(visit_filter).select_related("place", "user")

        # Build per-stop recap
        stop_recaps = []
        total_wines = 0
        all_photos = []
        for stop in stops:
            place = stop.place
            stop_visits = [v for v in visits if v.place_id == place.id]

            # Wines tasted at this stop
            visit_ids = [v.id for v in stop_visits]
            wines = VisitWine.objects.filter(
                visit_id__in=visit_ids, is_active=True
            ).select_related("menu_item")
            wines_list = []
            for w in wines:
                total_wines += 1
                name = w.display_name or w.wine_name or "Unknown"
                wine_data = {
                    "name": name,
                    "type": w.wine_type or "",
                    "rating": w.rating,
                    "is_favorite": w.is_favorite,
                    "tasting_notes": w.tasting_notes or "",
                }
                if w.photo:
                    wine_data["photo"] = w.photo
                    all_photos.append(w.photo)
                wines_list.append(wine_data)

            # Aggregate ratings for this stop
            avg_ratings = {}
            if stop_visits:
                ratings_qs = VisitLog.objects.filter(id__in=visit_ids).aggregate(
                    avg_overall=Avg("rating_overall"),
                    avg_staff=Avg("rating_staff"),
                    avg_ambience=Avg("rating_ambience"),
                    avg_food=Avg("rating_food"),
                )
                avg_ratings = {k: round(v, 1) if v else None for k, v in ratings_qs.items()}

            stop_recaps.append({
                "order": stop.order,
                "place": {
                    "id": str(place.id),
                    "name": place.name,
                    "place_type": place.place_type,
                    "city": place.city or "",
                    "state": place.state or "",
                    "latitude": place.latitude,
                    "longitude": place.longitude,
                    "image_url": place.image_url or "",
                },
                "checked_in": len(stop_visits) > 0,
                "visit_count": len(stop_visits),
                "wines_tasted": wines_list,
                "avg_ratings": avg_ratings,
                "duration_minutes": stop.duration_minutes,
                "travel_minutes": stop.travel_minutes,
                "travel_miles": stop.travel_miles,
            })

        # Total travel stats
        total_travel_minutes = sum(s.travel_minutes or 0 for s in stops)
        total_travel_miles = sum(float(s.travel_miles or 0) for s in stops)

        # Members
        members = trip.trip_members.filter(is_active=True).select_related("user")
        member_list = []
        for m in members:
            member_list.append({
                "display_name": m.display_name,
                "role": m.role,
                "rsvp_status": m.rsvp_status,
            })

        return Response({
            "trip": {
                "id": str(trip.id),
                "name": trip.name,
                "description": trip.description or "",
                "status": trip.status,
                "scheduled_date": trip.scheduled_date.isoformat() if trip.scheduled_date else None,
                "end_date": trip.end_date.isoformat() if trip.end_date else None,
            },
            "stats": {
                "total_stops": len(stop_recaps),
                "stops_visited": sum(1 for s in stop_recaps if s["checked_in"]),
                "total_wines": total_wines,
                "total_travel_minutes": total_travel_minutes,
                "total_travel_miles": round(total_travel_miles, 1),
                "total_members": len(member_list),
                "total_photos": len(all_photos),
            },
            "stops": stop_recaps,
            "members": member_list,
            "photos": all_photos[:20],  # First 20 photos
        })

    # ── Group Palate Matchmaker ───────────────────────────────────

    @action(detail=True, methods=["post"], url_path="palate-match")
    def palate_match(self, request, pk=None):
        """Aggregate member palates and recommend places for the group."""
        import json
        import logging

        logger = logging.getLogger(__name__)
        trip = self.get_object()

        # Get members with user accounts
        member_users = trip.trip_members.filter(
            is_active=True, user__isnull=False
        ).select_related("user")

        if member_users.count() < 1:
            return Response(
                {"detail": "No members with accounts found."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Build per-member palate summary
        member_profiles = []
        for m in member_users:
            user = m.user
            profile = PalateProfile.objects.filter(user=user).first()

            # Get top varietals for this user
            wines = VisitWine.objects.filter(
                visit__user=user, is_active=True
            )
            from django.db.models import F
            top_varietals = list(
                wines.filter(wine_type__gt="")
                .values(varietal=F("wine_type"))
                .annotate(count=Count("id"), avg_rating=Avg("rating"))
                .order_by("-count")[:5]
            )
            menu_varietals = list(
                wines.filter(menu_item__isnull=False)
                .values(varietal=F("menu_item__varietal"))
                .annotate(count=Count("id"), avg_rating=Avg("rating"))
                .order_by("-count")[:5]
            )

            # Merge
            varietal_map = {}
            for v in top_varietals + menu_varietals:
                key = v.get("varietal", "")
                if not key:
                    continue
                if key in varietal_map:
                    varietal_map[key]["count"] += v["count"]
                else:
                    varietal_map[key] = v

            visit_stats = VisitLog.objects.filter(
                user=user, is_active=True
            ).aggregate(
                total=Count("id"),
                avg_overall=Avg("rating_overall"),
            )

            member_profiles.append({
                "name": m.display_name,
                "preferences": profile.preferences if profile else {},
                "top_varietals": sorted(
                    varietal_map.values(), key=lambda x: -x["count"]
                )[:5],
                "visit_count": visit_stats["total"],
                "avg_rating": round(visit_stats["avg_overall"], 1)
                if visit_stats["avg_overall"]
                else None,
            })

        # Build prompt for Claude
        prompt = """You are an expert sommelier helping plan a group wine trip.
Analyze each member's palate profile below and provide:

1. **group_summary** — 2-3 sentences describing the group's collective taste
2. **common_ground** — List of 3-5 wines/styles everyone would enjoy
3. **adventurous_picks** — 2-3 wines/styles that would challenge the group in a fun way
4. **place_types** — Which place types (winery, brewery, restaurant) best suit this group
5. **suggested_varietals** — Top 5 varietals to seek out, ordered by group fit
6. **tips** — 2-3 specific tips for making this trip great for everyone

Return ONLY valid JSON with these keys. Write in a warm, conversational tone.

GROUP MEMBERS:
"""
        for mp in member_profiles:
            prompt += f"\n### {mp['name']}\n"
            if mp["preferences"]:
                prompt += f"Profile: {json.dumps(mp['preferences'])}\n"
            if mp["top_varietals"]:
                tops = ", ".join(
                    f"{v['varietal']} ({v['count']}x)"
                    for v in mp["top_varietals"]
                )
                prompt += f"Top varietals: {tops}\n"
            prompt += f"Visits: {mp['visit_count']}, Avg rating: {mp['avg_rating']}\n"

        try:
            from langchain_core.messages import HumanMessage

            from apps.api.ai_utils import get_claude

            llm = get_claude()
            response = llm.invoke([HumanMessage(content=prompt)])
            raw = response.content.strip()

            # Strip markdown fences
            if raw.startswith("```"):
                raw = raw.split("\n", 1)[1] if "\n" in raw else raw[3:]
                if raw.endswith("```"):
                    raw = raw[:-3]
                raw = raw.strip()

            recommendations = json.loads(raw)

            return Response({
                "member_profiles": member_profiles,
                "recommendations": recommendations,
            })

        except json.JSONDecodeError:
            logger.exception("Claude returned invalid JSON for palate match")
            return Response(
                {"detail": "Could not generate recommendations. Try again."},
                status=status.HTTP_422_UNPROCESSABLE_ENTITY,
            )
        except Exception:
            logger.exception("Palate match failed")
            return Response(
                {"detail": "Analysis failed. Please try again."},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )

    # ── Live Trip Activity Feed ───────────────────────────────────

    @action(detail=True, methods=["get"])
    def activity(self, request, pk=None):
        """Return recent activity events for a live trip."""
        trip = self.get_object()

        # Get all members
        member_users = trip.trip_members.filter(
            is_active=True, user__isnull=False
        ).select_related("user")
        member_ids = list(member_users.values_list("user_id", flat=True))
        user_map = {m.user_id: m.display_name for m in member_users}

        # Get stop places
        stops = trip.trip_stops.filter(is_active=True).select_related("place")
        place_ids = [s.place_id for s in stops]

        # Get visits at trip places by trip members
        visits = (
            VisitLog.objects.filter(
                user_id__in=member_ids,
                place_id__in=place_ids,
                is_active=True,
            )
            .select_related("place")
            .order_by("-visited_at")[:50]
        )

        # Get wines for those visits
        visit_ids = [v.id for v in visits]
        wines = (
            VisitWine.objects.filter(visit_id__in=visit_ids, is_active=True)
            .select_related("visit")
            .order_by("-created_at")[:50]
        )

        # Build activity events
        events = []

        for v in visits:
            events.append({
                "type": "checkin",
                "user_name": user_map.get(v.user_id, "Someone"),
                "place_name": v.place.name if v.place else "Unknown",
                "timestamp": v.visited_at.isoformat(),
                "rating": v.rating_overall,
                "notes": v.notes or "",
            })

        for w in wines:
            events.append({
                "type": "wine",
                "user_name": user_map.get(w.visit.user_id, "Someone"),
                "wine_name": w.display_name or w.wine_name or "a wine",
                "wine_type": w.wine_type or "",
                "timestamp": w.created_at.isoformat(),
                "rating": w.rating,
                "is_favorite": w.is_favorite,
                "photo": w.photo or "",
            })

            if w.rating:
                events.append({
                    "type": "rating",
                    "user_name": user_map.get(w.visit.user_id, "Someone"),
                    "wine_name": w.display_name or w.wine_name or "a wine",
                    "rating": w.rating,
                    "timestamp": w.created_at.isoformat(),
                })

        # Sort by timestamp descending
        events.sort(key=lambda e: e["timestamp"], reverse=True)

        return Response({
            "events": events[:30],
            "total_events": len(events),
        })

    # ── Ask Sippy (Trip-aware AI Chat) ────────────────────────────

    @action(detail=True, methods=["post"])
    def chat(self, request, pk=None):
        """Chat with Sippy, the trip-aware AI assistant."""
        import json
        import logging

        logger = logging.getLogger(__name__)
        trip = self.get_object()

        user_message = request.data.get("message", "").strip()
        if not user_message:
            return Response(
                {"detail": "Message is required."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Build rich trip context
        stops = trip.trip_stops.filter(is_active=True).select_related("place").order_by("order")
        members = trip.trip_members.filter(is_active=True).select_related("user")

        context_lines = [f"## Trip: {trip.name}"]
        context_lines.append(f"Status: {trip.status}")
        if trip.scheduled_date:
            context_lines.append(f"Date: {trip.scheduled_date}")
        if trip.meeting_time:
            context_lines.append(f"Meeting time: {trip.meeting_time}")
        if trip.meeting_location:
            context_lines.append(f"Meeting location: {trip.meeting_location}")
        if trip.description:
            context_lines.append(f"Description: {trip.description}")
        if trip.notes:
            context_lines.append(f"Notes: {trip.notes}")

        context_lines.append(f"\n## Members ({members.count()})")
        for m in members:
            context_lines.append(f"- {m.display_name} ({m.role}, RSVP: {m.rsvp_status})")

        context_lines.append(f"\n## Stops ({stops.count()})")
        for stop in stops:
            place = stop.place
            context_lines.append(f"\n### Stop {stop.order + 1}: {place.name}")
            context_lines.append(f"Type: {place.place_type}")
            if place.city:
                context_lines.append(f"Location: {place.city}, {place.state or ''}")
            if place.address:
                context_lines.append(f"Address: {place.address}")
            if place.website:
                context_lines.append(f"Website: {place.website}")
            if place.phone:
                context_lines.append(f"Phone: {place.phone}")
            if place.description:
                context_lines.append(f"About: {place.description}")
            if stop.arrival_time:
                context_lines.append(f"Arrival: {stop.arrival_time}")
            if stop.duration_minutes:
                context_lines.append(f"Duration: {stop.duration_minutes} min")
            if stop.travel_minutes:
                context_lines.append(f"Drive from previous: {stop.travel_minutes} min, {stop.travel_miles} mi")
            if stop.notes:
                context_lines.append(f"Stop notes: {stop.notes}")

            # Menu items for this place
            menu_items = place.menu_items.filter(is_active=True)[:20]
            if menu_items:
                context_lines.append("Menu:")
                for item in menu_items:
                    price = f" ${item.price}" if item.price else ""
                    vintage = f" ({item.vintage})" if item.vintage else ""
                    context_lines.append(f"  - {item.name} — {item.varietal}{vintage}{price}")

        # User's palate profile
        profile = PalateProfile.objects.filter(user=request.user).first()
        if profile and profile.preferences:
            context_lines.append("\n## Your Palate Profile")
            context_lines.append(json.dumps(profile.preferences, indent=2))

        # Recent visits at these places
        place_ids = [s.place_id for s in stops]
        recent_visits = VisitLog.objects.filter(
            user=request.user, place_id__in=place_ids, is_active=True
        ).select_related("place").order_by("-visited_at")[:10]
        if recent_visits:
            context_lines.append("\n## Your Past Visits at These Places")
            for v in recent_visits:
                context_lines.append(
                    f"- {v.place.name} ({v.visited_at:%Y-%m-%d}): "
                    f"overall={v.rating_overall}/5"
                    f"{f' — {v.notes}' if v.notes else ''}"
                )

        trip_context = "\n".join(context_lines)

        system_prompt = """You are Sippy, a friendly and knowledgeable AI trip assistant for a wine, beer, and food tasting app called Vino. You have full knowledge of the user's trip, including all stops, places, menus, members, and their palate profile.

You can help with:
- Recommending what to order at each stop based on their palate
- Suggesting an order to visit stops for the best experience
- Answering questions about the places, their menus, and varietals
- Tips for making the most of each stop
- Food and wine pairing suggestions
- General wine/beer knowledge and tasting advice
- Trip logistics (drive times, timing, etc.)

Keep responses conversational, warm, and concise (2-4 sentences unless more detail is asked for). Use the trip data to personalize every answer. If they ask about something unrelated to the trip or wine/beer/food, gently redirect.

""" + trip_context

        try:
            from langchain_core.messages import AIMessage, HumanMessage, SystemMessage

            from apps.api.ai_utils import get_claude

            llm = get_claude()
            messages = [SystemMessage(content=system_prompt)]

            # Include conversation history if provided
            chat_history = request.data.get("history", [])
            if chat_history:
                for msg in chat_history[-10:]:
                    role = msg.get("role", "")
                    content = msg.get("content", "")
                    if role == "user":
                        messages.append(HumanMessage(content=content))
                    elif role == "assistant":
                        messages.append(AIMessage(content=content))

            messages.append(HumanMessage(content=user_message))

            response = llm.invoke(messages)
            reply = response.content

            # Auto-persist conversation
            from apps.trips.models import SippyConversation
            conversation_id = request.data.get("conversation_id", "")
            conversation = None
            if conversation_id:
                conversation = SippyConversation.objects.filter(
                    pk=conversation_id, user=request.user, is_active=True
                ).first()

            if not conversation:
                conversation = SippyConversation.objects.create(
                    user=request.user,
                    trip=trip,
                    chat_type=SippyConversation.ChatType.ASK,
                    title=user_message[:60],
                    messages=[],
                )

            msgs = conversation.messages or []
            msgs.append({"role": "user", "content": user_message})
            msgs.append({"role": "assistant", "content": reply})
            conversation.messages = msgs
            conversation.save(update_fields=["messages", "updated_at"])

            return Response({
                "reply": reply,
                "conversation_id": str(conversation.id),
            })

        except Exception:
            logger.exception("Sippy chat failed")
            return Response(
                {"detail": "Sippy is taking a sip break. Try again!"},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )

    # ── Sippy Trip Planner (LangGraph) ────────────────────────────

    @action(detail=False, methods=["post"])
    def plan(self, request):
        """Conversational trip planner powered by LangGraph."""
        import logging
        import time

        logger = logging.getLogger(__name__)

        from apps.trips.models import SippyConversation

        user_message = request.data.get("message", "").strip()
        action_type = request.data.get("action")  # approve | reject | None
        session_id = request.data.get("session_id", "")
        conversation_id = request.data.get("conversation_id", "")

        if not user_message and not action_type:
            return Response(
                {"detail": "Message or action is required."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Generate or reuse session ID
        if not session_id:
            session_id = f"plan:{request.user.id}:{int(time.time())}"

        # Load or create conversation record
        conversation = None
        if conversation_id:
            conversation = SippyConversation.objects.filter(
                pk=conversation_id, user=request.user, is_active=True
            ).first()

        try:
            from langchain_core.messages import AIMessage as AI
            from langchain_core.messages import HumanMessage as HM

            from apps.api.agents.graph import get_compiled_graph

            graph = get_compiled_graph("trip_planner")
            config = {"configurable": {"thread_id": session_id}}

            # Replay conversation history for context (if provided)
            history_msgs = []
            for h in request.data.get("history", [])[-10:]:
                role = h.get("role", "")
                content = h.get("content", "")
                if role == "user":
                    history_msgs.append(HM(content=content))
                elif role == "assistant":
                    history_msgs.append(AI(content=content))

            # Handle approve directly — skip LangGraph, go straight to commit
            if action_type == "approve":
                display_user_msg = "Looks good! Create it."

                # Get proposed trip from conversation record
                proposed = conversation.proposed_trip if conversation else None
                if not proposed:
                    return Response(
                        {"detail": "No trip preview to approve. Please plan a trip first."},
                        status=status.HTTP_400_BAD_REQUEST,
                    )

                from apps.api.agents.nodes import planner_commit
                commit_state = {
                    "proposed_trip": proposed,
                    "user_id": str(request.user.id),
                }
                commit_result = planner_commit(commit_state)

                reply = ""
                for msg in commit_result.get("messages", []):
                    if isinstance(msg, AI):
                        reply = msg.content
                        break

                phase = commit_result.get("phase", "approved")
                trip_id = commit_result.get("created_trip_id")

                # Update conversation
                if conversation:
                    msgs = conversation.messages or []
                    msgs.append({"role": "user", "content": display_user_msg})
                    if reply:
                        msgs.append({"role": "assistant", "content": reply})
                    conversation.messages = msgs
                    conversation.phase = phase
                    if trip_id:
                        conversation.trip_id = trip_id
                    conversation.save(update_fields=[
                        "messages", "phase", "trip_id", "updated_at",
                    ])

                return Response({
                    "reply": reply,
                    "phase": phase,
                    "session_id": session_id,
                    "proposed_trip": proposed,
                    "trip_id": trip_id,
                    "conversation_id": str(conversation.id) if conversation else None,
                })

            # Handle reject
            if action_type == "reject":
                display_user_msg = "Let's start over with a different plan."
                if conversation:
                    msgs = conversation.messages or []
                    msgs.append({"role": "user", "content": display_user_msg})
                    msgs.append({"role": "assistant", "content": "No problem! Let's start fresh — tell me what you're in the mood for."})
                    conversation.messages = msgs
                    conversation.phase = "gathering"
                    conversation.proposed_trip = {}
                    # Fresh session so we don't hit old LangGraph checkpoint
                    conversation.session_id = f"plan:{request.user.id}:{int(time.time())}"
                    conversation.save(update_fields=["messages", "phase", "proposed_trip", "session_id", "updated_at"])

                new_session = conversation.session_id if conversation else session_id
                return Response({
                    "reply": "No problem! Let's start fresh — tell me what you're in the mood for.",
                    "phase": "gathering",
                    "session_id": new_session,
                    "proposed_trip": None,
                    "conversation_id": str(conversation.id) if conversation else None,
                })

            # Normal conversation — invoke LangGraph
            display_user_msg = user_message
            input_state = {
                "messages": history_msgs + [HM(content=user_message)],
                "user_id": str(request.user.id),
            }

            result = graph.invoke(input_state, config)

            # Extract last AI message
            reply = ""
            for msg in reversed(result.get("messages", [])):
                if isinstance(msg, AI):
                    reply = msg.content
                    break

            phase = result.get("phase", "gathering")
            proposed = result.get("proposed_trip")
            trip_id = result.get("created_trip_id")

            # Auto-persist conversation
            if not conversation:
                title = user_message[:60] if user_message else "Trip Plan"
                conversation = SippyConversation.objects.create(
                    user=request.user,
                    chat_type=SippyConversation.ChatType.PLAN,
                    title=title,
                    session_id=session_id,
                    messages=[],
                )

            msgs = conversation.messages or []
            if display_user_msg:
                msgs.append({"role": "user", "content": display_user_msg})
            if reply:
                msgs.append({"role": "assistant", "content": reply})
            conversation.messages = msgs
            conversation.phase = phase
            if proposed:
                conversation.proposed_trip = proposed
            if trip_id:
                conversation.trip_id = trip_id
            conversation.save(update_fields=[
                "messages", "phase", "proposed_trip", "trip_id",
                "session_id", "updated_at",
            ])

            return Response({
                "reply": reply,
                "phase": phase,
                "session_id": session_id,
                "proposed_trip": proposed,
                "trip_id": trip_id,
                "conversation_id": str(conversation.id),
            })

        except Exception:
            logger.exception("Sippy trip planner failed")

            # Generate a fresh session_id so retry doesn't hit the corrupt checkpoint
            new_session = f"plan:{request.user.id}:{int(time.time())}"
            if conversation:
                conversation.session_id = new_session
                conversation.save(update_fields=["session_id", "updated_at"])

            return Response(
                {
                    "detail": "Sippy had trouble planning. Try again!",
                    "session_id": new_session,
                    "conversation_id": str(conversation.id) if conversation else None,
                },
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )
