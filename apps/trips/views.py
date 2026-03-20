import json as _json
import logging
from datetime import datetime, time, timedelta, timezone
from decimal import Decimal

import httpx
from django.conf import settings
from django.contrib import messages
from django.contrib.auth import get_user_model
from django.contrib.auth.mixins import LoginRequiredMixin
from django.db.models import Max, Q
from django.http import JsonResponse
from django.shortcuts import get_object_or_404, redirect, render
from django.views import View
from django.views.generic import ListView

logger = logging.getLogger(__name__)

from apps.trips.forms import TripForm
from apps.trips.models import Trip, TripMember, TripStop
from apps.visits.models import VisitLog
from apps.wineries.models import FavoritePlace, Place

User = get_user_model()


def _user_tz(user):
    """Return the user's ZoneInfo timezone, falling back to UTC."""
    import zoneinfo
    tz_name = getattr(user, "timezone", "") or "UTC"
    try:
        return zoneinfo.ZoneInfo(tz_name)
    except (KeyError, Exception):
        return timezone.utc


class TripListView(LoginRequiredMixin, ListView):
    model = Trip
    template_name = "trips/list.html"
    context_object_name = "trips"
    paginate_by = 10

    def get_queryset(self):
        from django.db.models import Avg, Count, Q

        qs = (
            Trip.objects.filter(members=self.request.user)
            .prefetch_related("trip_members__user", "trip_stops__place")
            .distinct()
        )

        # Search
        q = self.request.GET.get("q", "").strip()
        if q:
            qs = qs.filter(
                Q(name__icontains=q)
                | Q(trip_stops__place__name__icontains=q)
                | Q(trip_stops__place__city__icontains=q)
                | Q(trip_stops__place__state__icontains=q)
            ).distinct()

        # Filter by status
        status = self.request.GET.get("status", "")
        if status:
            qs = qs.filter(status=status)

        # Filter by date range
        date_from = self.request.GET.get("from", "")
        date_to = self.request.GET.get("to", "")
        if date_from:
            qs = qs.filter(scheduled_date__gte=date_from)
        if date_to:
            qs = qs.filter(scheduled_date__lte=date_to)

        # Filter by stop count
        stop_min = self.request.GET.get("stops_min", "")
        if stop_min:
            qs = qs.annotate(_stop_count=Count("trip_stops")).filter(_stop_count__gte=int(stop_min))

        # Sort
        sort = self.request.GET.get("sort", "-scheduled_date")
        valid_sorts = {
            "name": "name",
            "-name": "-name",
            "scheduled_date": "scheduled_date",
            "-scheduled_date": "-scheduled_date",
            "created_at": "created_at",
            "-created_at": "-created_at",
            "status": "status",
            "-status": "-status",
        }
        order = valid_sorts.get(sort, "-scheduled_date")
        qs = qs.order_by(order, "-created_at")

        return qs

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        from datetime import date
        today = date.today()
        for trip in ctx["trips"]:
            trip.show_start_button = (
                trip.status == "in_progress"
                or (trip.status == "confirmed" and trip.scheduled_date and trip.scheduled_date <= today)
            )
        ctx["search_query"] = self.request.GET.get("q", "")
        ctx["filter_status"] = self.request.GET.get("status", "")
        ctx["filter_from"] = self.request.GET.get("from", "")
        ctx["filter_to"] = self.request.GET.get("to", "")
        ctx["current_sort"] = self.request.GET.get("sort", "-scheduled_date")
        ctx["status_choices"] = Trip.Status.choices
        return ctx


class TripCreateView(LoginRequiredMixin, View):
    def _build_context(self, request, form):
        user = request.user
        # Previous trips for "copy" tab
        past_trips = (
            Trip.objects.filter(members=user)
            .prefetch_related("trip_stops__place")
            .distinct()
            .order_by("-created_at")[:20]
        )

        # Recommendations: top-rated unvisited places near places user liked
        from django.db.models import Avg, Count, Q
        fav_place_ids = set(
            FavoritePlace.objects.filter(user=user, is_active=True)
            .values_list("place_id", flat=True)
        )
        visited_place_ids = set(
            VisitLog.objects.filter(user=user, is_active=True)
            .values_list("place_id", flat=True)
            .distinct()
        )
        # Find highly-rated places user hasn't visited, prioritizing
        # ones near their favorites and visited spots
        known_ids = fav_place_ids | visited_place_ids
        recommended = (
            Place.objects.exclude(pk__in=known_ids)
            .annotate(
                visit_count=Count("visits", filter=Q(visits__is_active=True)),
                avg_rating=Avg("visits__rating_overall", filter=Q(visits__is_active=True)),
            )
            .filter(visit_count__gt=0, avg_rating__isnull=False)
            .order_by("-avg_rating", "-visit_count")[:10]
        )
        # If not enough rated places, fill with popular places user hasn't been to
        if recommended.count() < 5:
            popular = (
                Place.objects.exclude(pk__in=known_ids)
                .annotate(
                    visit_count=Count("visits", filter=Q(visits__is_active=True)),
                )
                .order_by("-visit_count", "name")[:10]
            )
            recommended = list(recommended) + [
                p for p in popular if p not in recommended
            ]

        from datetime import date as _date
        today = _date.today()

        return {
            "form": form,
            "page_title": "Plan a Trip",
            "past_trips": past_trips,
            "recommended_places": recommended,
            "default_start_date": today.isoformat(),
            "default_end_date": today.isoformat(),
            "default_start_time": "12:00",
        }

    def get(self, request):
        ctx = self._build_context(request, TripForm())
        return render(request, "trips/form.html", ctx)

    def post(self, request):
        form = TripForm(request.POST)
        if form.is_valid():
            trip = form.save(commit=False)
            trip.created_by = request.user
            trip.save()
            TripMember.objects.create(
                trip=trip,
                user=request.user,
                role=TripMember.Role.ORGANIZER,
                rsvp_status="accepted",
            )
            messages.success(request, f'Trip "{trip.name}" created!')
            return redirect("trip_detail", pk=trip.pk)
        ctx = self._build_context(request, form)
        return render(request, "trips/form.html", ctx)


class TripCopyView(LoginRequiredMixin, View):
    """Copy a previous trip with new dates."""

    def post(self, request, pk):
        source = get_object_or_404(Trip, pk=pk)
        try:
            body = _json.loads(request.body)
        except (ValueError, TypeError):
            body = {}

        from datetime import date as _date
        from django.utils import timezone as _tz
        today = _tz.localdate()
        default_meeting = time(12, 0)

        start_str = body.get("scheduled_date")
        end_str = body.get("end_date")
        start_date = _date.fromisoformat(start_str) if start_str else today
        end_date = _date.fromisoformat(end_str) if end_str else today

        new_trip = Trip.objects.create(
            name=body.get("name", f"{source.name} (Copy)"),
            created_by=request.user,
            status=Trip.Status.DRAFT,
            description=source.description,
            scheduled_date=start_date,
            end_date=end_date,
            meeting_time=default_meeting,
            meeting_location=source.meeting_location,
            meeting_notes=source.meeting_notes,
            transportation=source.transportation,
        )
        TripMember.objects.create(
            trip=new_trip,
            user=request.user,
            role=TripMember.Role.ORGANIZER,
            rsvp_status="accepted",
        )

        # Copy stops with recalculated arrival times
        source_stops = list(
            source.trip_stops.select_related("place").order_by("order")
        )
        base_arrival = datetime.combine(
            new_trip.scheduled_date or today, default_meeting, tzinfo=_user_tz(request.user),
        )
        prev_stop = None
        for idx, src in enumerate(source_stops):
            travel_minutes = None
            travel_miles = None
            if prev_stop:
                travel_minutes, travel_miles = _get_drive_info(
                    prev_stop.place.latitude, prev_stop.place.longitude,
                    src.place.latitude, src.place.longitude,
                )
            duration = src.duration_minutes or 90
            if idx == 0:
                arrival = base_arrival
            elif prev_stop:
                prev_dur = prev_stop.duration_minutes or 90
                drive = travel_minutes or 0
                arrival = prev_stop.arrival_time + timedelta(
                    minutes=prev_dur + drive
                ) if prev_stop.arrival_time else None
            else:
                arrival = None

            new_stop = TripStop.objects.create(
                trip=new_trip,
                place=src.place,
                order=idx + 1,
                arrival_time=arrival,
                duration_minutes=duration,
                travel_minutes=travel_minutes,
                travel_miles=travel_miles,
                description=src.description,
                notes=src.notes,
            )
            # Update prev_stop reference for next iteration
            new_stop.arrival_time = arrival
            prev_stop = new_stop

        return JsonResponse({
            "ok": True,
            "trip_url": f"/trips/{new_trip.pk}/",
            "trip_id": str(new_trip.pk),
        })


class TripDetailView(LoginRequiredMixin, View):
    def get(self, request, pk):
        trip = get_object_or_404(
            Trip.objects.prefetch_related(
                "trip_members__user", "trip_stops__place"
            ),
            pk=pk,
        )
        user = request.user
        is_member = trip.trip_members.filter(user=user).exists()
        is_organizer = trip.trip_members.filter(user=user, role=TripMember.Role.ORGANIZER).exists()

        # Favorites for "Add from Favorites" picker
        fav_place_ids = FavoritePlace.objects.filter(
            user=user, is_active=True
        ).values_list("place_id", flat=True)
        favorites = Place.objects.filter(pk__in=fav_place_ids).order_by("name")

        # Visited places for "Add from Visited" picker
        visited_place_ids = (
            VisitLog.objects.filter(user=user, is_active=True)
            .values_list("place_id", flat=True)
            .distinct()
        )
        visited = (
            Place.objects.filter(pk__in=visited_place_ids)
            .annotate(last_visited=Max("visits__visited_at", filter=Q(visits__user=user, visits__is_active=True)))
            .order_by("name")
        )

        # Existing stop place IDs (to mark already-added)
        stop_place_ids = set(
            trip.trip_stops.values_list("place_id", flat=True)
        )

        stops = list(trip.trip_stops.select_related("place").order_by("order"))
        # Mark stops that have cached menu items
        for stop in stops:
            stop.has_cached_wines = stop.place.menu_items.exists()

        from datetime import date
        today = date.today()
        show_start_button = (
            trip.status == Trip.Status.IN_PROGRESS
            or (trip.status == Trip.Status.CONFIRMED
                and trip.scheduled_date
                and trip.scheduled_date <= today)
        )

        is_readonly = trip.status in (Trip.Status.COMPLETED, Trip.Status.CANCELLED)

        return render(request, "trips/detail.html", {
            "trip": trip,
            "is_member": is_member,
            "is_organizer": is_organizer,
            "is_readonly": is_readonly,
            "members": trip.trip_members.select_related("user").order_by("role"),
            "stops": stops,
            "favorites": favorites,
            "visited": visited,
            "stop_place_ids": stop_place_ids,
            "show_start_button": show_start_button,
            "google_maps_api_key": settings.GOOGLE_MAPS_API_KEY,
        })


class TripStopsPartialView(LoginRequiredMixin, View):
    """Return the stops list partial HTML for htmx swap."""

    def get(self, request, pk):
        trip = get_object_or_404(Trip, pk=pk)
        stops = list(trip.trip_stops.select_related("place").order_by("order"))
        for stop in stops:
            stop.has_cached_wines = stop.place.menu_items.exists()
        return render(request, "trips/_stops_list.html", {
            "stops": stops,
            "trip": trip,
        })


class TripUpdateView(LoginRequiredMixin, View):
    """AJAX: update trip fields."""

    def post(self, request, pk):
        trip = get_object_or_404(Trip, pk=pk)
        try:
            body = _json.loads(request.body)
        except (ValueError, TypeError):
            return JsonResponse({"error": "Invalid JSON"}, status=400)

        if "name" in body:
            trip.name = body["name"].strip() or trip.name
        if "status" in body and body["status"] in dict(Trip.Status.choices):
            trip.status = body["status"]

        # Date fields
        for field in ["scheduled_date", "end_date"]:
            if field in body:
                setattr(trip, field, body[field] or None)

        # Time field
        if "meeting_time" in body:
            trip.meeting_time = body["meeting_time"] or None

        # Text fields
        text_fields = [
            "description", "meeting_location", "meeting_notes",
            "transportation", "budget_notes", "notes",
        ]
        for field in text_fields:
            if field in body:
                setattr(trip, field, body[field] or "")

        trip.save()
        return JsonResponse({"ok": True, "name": trip.name, "status": trip.status})


class TripDeleteView(LoginRequiredMixin, View):
    """AJAX: soft-delete a trip."""

    def post(self, request, pk):
        trip = get_object_or_404(Trip, pk=pk, created_by=request.user)
        trip.is_active = False
        trip.save(update_fields=["is_active", "updated_at"])
        return JsonResponse({"ok": True})


def _get_drive_info(origin_lat, origin_lng, dest_lat, dest_lng):
    """Fetch driving time (minutes) and distance (miles) via Google Routes API.

    Returns (travel_minutes, travel_miles) or (None, None).
    """
    api_key = getattr(settings, "GOOGLE_MAPS_API_KEY", "")
    if not api_key or None in (origin_lat, origin_lng, dest_lat, dest_lng):
        return None, None
    try:
        resp = httpx.post(
            "https://routes.googleapis.com/directions/v2:computeRoutes",
            headers={
                "X-Goog-Api-Key": api_key,
                "X-Goog-FieldMask": "routes.duration,routes.distanceMeters",
            },
            json={
                "origin": {
                    "location": {
                        "latLng": {
                            "latitude": float(origin_lat),
                            "longitude": float(origin_lng),
                        }
                    }
                },
                "destination": {
                    "location": {
                        "latLng": {
                            "latitude": float(dest_lat),
                            "longitude": float(dest_lng),
                        }
                    }
                },
                "travelMode": "DRIVE",
            },
            timeout=10,
        )
        data = resp.json()
        route = data["routes"][0]
        duration_str = route["duration"]  # e.g. "1523s"
        seconds = int(duration_str.rstrip("s"))
        meters = route.get("distanceMeters", 0)
        miles = round(meters / 1609.344, 1)
        return max(1, round(seconds / 60)), miles
    except Exception:
        logger.exception("Google Routes API error")
    return None, None


class TripAddStopView(LoginRequiredMixin, View):
    """AJAX: add a place stop to a trip."""

    def post(self, request, pk):
        trip = get_object_or_404(Trip, pk=pk)
        try:
            body = _json.loads(request.body)
        except (ValueError, TypeError):
            return JsonResponse({"error": "Invalid JSON"}, status=400)

        place_id = body.get("place_id")
        if not place_id:
            # Fall back to winery_id for backward compatibility
            place_id = body.get("winery_id")
        if not place_id:
            return JsonResponse({"error": "place_id required"}, status=400)

        place = get_object_or_404(Place, pk=place_id)

        # Calculate arrival_time based on existing stops and trip schedule
        default_duration = 90
        default_arrival = None
        travel_minutes = None
        existing_stops = list(
            trip.trip_stops.select_related("place").order_by("order")
        )
        last_stop = existing_stops[-1] if existing_stops else None

        # Get drive info from previous stop to this place
        travel_miles = None
        if last_stop:
            travel_minutes, travel_miles = _get_drive_info(
                last_stop.place.latitude, last_stop.place.longitude,
                place.latitude, place.longitude,
            )

        if last_stop and last_stop.arrival_time:
            # Next stop starts after previous stop's duration + drive time
            prev_duration = last_stop.duration_minutes or default_duration
            drive = travel_minutes or 0
            default_arrival = last_stop.arrival_time + timedelta(
                minutes=prev_duration + drive
            )
        elif trip.scheduled_date:
            # Build from trip's scheduled_date + meeting_time, then offset
            # by cumulative durations + travel times of all existing stops
            meeting = trip.meeting_time or time(0, 0)
            base = datetime.combine(
                trip.scheduled_date, meeting, tzinfo=_user_tz(request.user),
            )
            offset = sum(
                (s.duration_minutes or default_duration) + (s.travel_minutes or 0)
                for s in existing_stops
            )
            drive = travel_minutes or 0
            default_arrival = base + timedelta(minutes=offset + drive)

        # Prevent adding the same place if it's already an active stop
        max_order = last_stop.order if last_stop else 0
        if TripStop.objects.filter(trip=trip, place=place).exists():
            return JsonResponse(
                {"error": "This place is already on the itinerary."},
                status=400,
            )

        # Reactivate soft-deleted stop, or create new
        deleted_stop = (
            TripStop.all_objects
            .filter(trip=trip, place=place, is_active=False)
            .first()
        )
        if deleted_stop:
            tw = deleted_stop
            tw.is_active = True
            tw.order = max_order + 1
            tw.arrival_time = default_arrival
            tw.duration_minutes = tw.duration_minutes or default_duration
            tw.travel_minutes = travel_minutes
            tw.travel_miles = travel_miles
            tw.save(update_fields=[
                "is_active", "order", "arrival_time", "duration_minutes",
                "travel_minutes", "travel_miles", "updated_at",
            ])
        else:
            tw = TripStop.objects.create(
                trip=trip, place=place, order=max_order + 1,
                arrival_time=default_arrival,
                duration_minutes=default_duration,
                travel_minutes=travel_minutes,
                travel_miles=travel_miles,
            )

        return JsonResponse({
            "ok": True,
            "stop_id": str(tw.pk),
            "place_id": str(place.pk),
            "name": place.name,
            "city": place.city,
            "state": place.state,
            "order": tw.order,
            "image_url": place.image_url or "",
            "arrival_time": tw.arrival_time.strftime("%Y-%m-%dT%H:%M") if tw.arrival_time else "",
            "duration_minutes": tw.duration_minutes or "",
            "travel_minutes": tw.travel_minutes or "",
        })


class TripUpdateStopView(LoginRequiredMixin, View):
    """AJAX: update a stop's details."""

    def post(self, request, pk, stop_pk):
        trip = get_object_or_404(Trip, pk=pk)
        stop = get_object_or_404(TripStop, pk=stop_pk, trip=trip)
        try:
            body = _json.loads(request.body)
        except (ValueError, TypeError):
            return JsonResponse({"error": "Invalid JSON"}, status=400)

        editable_fields = [
            "arrival_time", "duration_minutes", "travel_minutes", "travel_miles",
            "description", "notes", "meeting_details", "travel_details", "order",
        ]
        for field in editable_fields:
            if field in body:
                val = body[field]
                if field in ("duration_minutes", "travel_minutes"):
                    val = int(val) if val else None
                if field == "travel_miles":
                    val = Decimal(val) if val else None
                if field == "order":
                    val = int(val) if val else stop.order
                if field == "arrival_time":
                    if val:
                        naive = datetime.fromisoformat(val)
                        val = naive.replace(tzinfo=_user_tz(request.user))
                    else:
                        val = None
                setattr(stop, field, val)

        stop.save()
        return JsonResponse({"ok": True})


class TripReorderStopsView(LoginRequiredMixin, View):
    """AJAX: reorder all stops in a trip."""

    def post(self, request, pk):
        trip = get_object_or_404(Trip, pk=pk)
        try:
            body = _json.loads(request.body)
        except (ValueError, TypeError):
            return JsonResponse({"error": "Invalid JSON"}, status=400)

        stops = body.get("stops", [])
        for item in stops:
            TripStop.objects.filter(
                pk=item["stop_id"], trip=trip
            ).update(order=item["order"])

        return JsonResponse({"ok": True})


class TripRemoveStopView(LoginRequiredMixin, View):
    """AJAX: remove a stop from a trip (soft delete) and recalculate itinerary."""

    def post(self, request, pk, stop_pk):
        trip = get_object_or_404(Trip, pk=pk)
        stop = get_object_or_404(TripStop, pk=stop_pk, trip=trip)
        stop.is_active = False
        stop.save(update_fields=["is_active", "updated_at"])

        # Re-sequence remaining stops and recalculate travel/arrival times
        default_duration = 90
        remaining = list(
            trip.trip_stops.select_related("place").order_by("order")
        )
        meeting = trip.meeting_time or time(0, 0)
        base_arrival = (
            datetime.combine(trip.scheduled_date, meeting, tzinfo=_user_tz(request.user))
            if trip.scheduled_date
            else None
        )

        for idx, tw in enumerate(remaining):
            tw.order = idx + 1

            if idx == 0:
                tw.travel_minutes = None
                tw.travel_miles = None
                tw.arrival_time = base_arrival
            else:
                prev = remaining[idx - 1]
                tw.travel_minutes, tw.travel_miles = _get_drive_info(
                    prev.place.latitude, prev.place.longitude,
                    tw.place.latitude, tw.place.longitude,
                )
                if prev.arrival_time:
                    prev_dur = prev.duration_minutes or default_duration
                    drive = tw.travel_minutes or 0
                    tw.arrival_time = prev.arrival_time + timedelta(
                        minutes=prev_dur + drive
                    )

            tw.duration_minutes = tw.duration_minutes or default_duration
            tw.save(update_fields=[
                "order", "arrival_time", "duration_minutes",
                "travel_minutes", "travel_miles", "updated_at",
            ])

        # Fix current_stop_index if it's now out of bounds
        meta = trip.metadata or {}
        current = meta.get("current_stop_index", 0)
        if current >= len(remaining) and len(remaining) > 0:
            meta["current_stop_index"] = len(remaining) - 1
            trip.metadata = meta
            trip.save(update_fields=["metadata", "updated_at"])

        return JsonResponse({"ok": True})


class TripInviteView(LoginRequiredMixin, View):
    """AJAX: invite a member by email with optional personalised message."""

    def post(self, request, pk):
        from django.core.mail import send_mail
        from django.conf import settings as django_settings
        from django.utils import timezone

        trip = get_object_or_404(Trip, pk=pk)
        try:
            body = _json.loads(request.body)
        except (ValueError, TypeError):
            return JsonResponse({"error": "Invalid JSON"}, status=400)

        email = body.get("email", "").strip().lower()
        first_name = body.get("first_name", "").strip()
        last_name = body.get("last_name", "").strip()
        message = body.get("message", "").strip()

        if not email:
            return JsonResponse({"error": "Email is required"}, status=400)

        # Check for existing active member with same email
        existing = TripMember.objects.filter(trip=trip, invite_email__iexact=email)
        if existing.exists():
            return JsonResponse({"error": "This email has already been invited"}, status=400)

        # Link to existing user if possible
        user = User.objects.filter(email__iexact=email).first()

        if user and TripMember.all_objects.filter(trip=trip, user=user).exists():
            tm = TripMember.all_objects.get(trip=trip, user=user)
            if tm.is_active:
                return JsonResponse({"error": "Already a member"}, status=400)
            tm.is_active = True
            tm.rsvp_status = "pending"
            tm.role = TripMember.Role.INVITED
            tm.invite_email = email
            tm.invite_first_name = first_name
            tm.invite_last_name = last_name
            tm.invite_message = message
            tm.invited_at = timezone.now()
            tm.responded_at = None
            tm.save()
        else:
            tm = TripMember.objects.create(
                trip=trip,
                user=user,
                role=TripMember.Role.INVITED,
                rsvp_status="pending",
                invite_email=email,
                invite_first_name=first_name,
                invite_last_name=last_name,
                invite_message=message,
                invited_at=timezone.now(),
            )

        # Send invitation email
        inviter = request.user.full_name or request.user.email
        greeting = first_name or "there"
        subject = f"You're invited to {trip.name} — Vino Trip"
        body_text = (
            f"Hi {greeting},\n\n"
            f"{inviter} has invited you to join a trip!\n\n"
            f"Trip: {trip.name}\n"
        )
        if trip.scheduled_date:
            body_text += f"Date: {trip.scheduled_date.strftime('%B %d, %Y')}\n"
        if trip.description:
            body_text += f"Description: {trip.description}\n"
        if message:
            body_text += f"\nPersonal message:\n{message}\n"
        body_text += (
            "\nLog in to Vino Trip to view the trip and RSVP.\n\n"
            "Cheers!\nThe Vino Trip Team"
        )

        try:
            send_mail(
                subject=subject,
                message=body_text,
                from_email=django_settings.DEFAULT_FROM_EMAIL,
                recipient_list=[email],
                fail_silently=False,
            )
        except Exception:
            pass  # Don't fail the invite if email delivery fails

        return JsonResponse({
            "ok": True,
            "member_id": str(tm.pk),
            "email": email,
            "name": tm.display_name,
            "initial": tm.display_initial,
            "role": tm.get_role_display(),
            "rsvp": tm.rsvp_status,
            "invited_at": tm.invited_at.strftime("%b %d, %Y %I:%M %p") if tm.invited_at else "",
        })


class TripUpdateMemberView(LoginRequiredMixin, View):
    """AJAX: organizer updates a member's details (RSVP, notes, name, etc.)."""

    def post(self, request, pk, member_pk):
        from django.utils import timezone

        trip = get_object_or_404(Trip, pk=pk)
        tm = get_object_or_404(TripMember, pk=member_pk, trip=trip)
        try:
            body = _json.loads(request.body)
        except (ValueError, TypeError):
            return JsonResponse({"error": "Invalid JSON"}, status=400)

        update_fields = ["updated_at"]

        # RSVP status
        new_status = body.get("rsvp_status", "").strip()
        if new_status and new_status in ("pending", "accepted", "declined"):
            old_status = tm.rsvp_status
            tm.rsvp_status = new_status
            update_fields.append("rsvp_status")
            if new_status != "pending" and old_status == "pending":
                tm.responded_at = timezone.now()
            elif new_status == "pending":
                tm.responded_at = None
            update_fields.append("responded_at")

        # Notes
        if "notes" in body:
            tm.notes = body["notes"]
            update_fields.append("notes")

        # Invite details (name, email, message)
        if "invite_first_name" in body:
            tm.invite_first_name = body["invite_first_name"]
            update_fields.append("invite_first_name")
        if "invite_last_name" in body:
            tm.invite_last_name = body["invite_last_name"]
            update_fields.append("invite_last_name")
        if "invite_email" in body:
            tm.invite_email = body["invite_email"]
            update_fields.append("invite_email")
        if "invite_message" in body:
            tm.invite_message = body["invite_message"]
            update_fields.append("invite_message")

        # Role — allow promoting to organizer, prevent demoting the last organizer
        if "role" in body:
            new_role = body["role"]
            if new_role in dict(TripMember.Role.choices):
                if tm.role == TripMember.Role.ORGANIZER and new_role != TripMember.Role.ORGANIZER:
                    # Demoting an organizer — only allow if there's another organizer
                    other_organizers = trip.trip_members.filter(
                        role=TripMember.Role.ORGANIZER
                    ).exclude(pk=tm.pk).count()
                    if other_organizers == 0:
                        return JsonResponse({"error": "Cannot demote the last organizer"}, status=400)
                tm.role = new_role
                update_fields.append("role")

        tm.save(update_fields=update_fields)

        return JsonResponse({
            "ok": True,
            "name": tm.display_name,
            "initial": tm.display_initial,
            "rsvp": tm.rsvp_status,
            "role": tm.get_role_display(),
            "responded_at": tm.responded_at.strftime("%b %d, %Y %I:%M %p") if tm.responded_at else "",
        })


class TripRemoveMemberView(LoginRequiredMixin, View):
    """AJAX: remove a member from a trip."""

    def post(self, request, pk, member_pk):
        trip = get_object_or_404(Trip, pk=pk)
        tm = get_object_or_404(TripMember, pk=member_pk, trip=trip)
        if tm.role == TripMember.Role.ORGANIZER:
            other_organizers = trip.trip_members.filter(
                role=TripMember.Role.ORGANIZER
            ).exclude(pk=tm.pk).count()
            if other_organizers == 0:
                return JsonResponse({"error": "Cannot remove the last organizer"}, status=400)
        tm.is_active = False
        tm.save(update_fields=["is_active", "updated_at"])
        return JsonResponse({"ok": True})


class QuickTripView(LoginRequiredMixin, View):
    """AJAX endpoint: create a new trip with a place as the first stop."""

    def post(self, request):
        try:
            body = _json.loads(request.body)
        except (ValueError, TypeError):
            return JsonResponse({"error": "Invalid JSON"}, status=400)

        place = None
        place_id = body.get("place_id")
        if not place_id:
            place_id = body.get("winery_id")  # backward compatibility

        if place_id:
            place = get_object_or_404(Place, pk=place_id)
        else:
            name = body.get("name", "").strip()
            if not name:
                return JsonResponse({"error": "Name is required"}, status=400)

            lat = body.get("lat")
            lng = body.get("lng")

            if lat and lng:
                lat_d, lng_d = Decimal(str(lat)), Decimal(str(lng))
                place = Place.objects.filter(
                    name__iexact=name,
                    latitude__range=(lat_d - Decimal("0.001"), lat_d + Decimal("0.001")),
                    longitude__range=(lng_d - Decimal("0.001"), lng_d + Decimal("0.001")),
                ).first()

            if not place:
                addr = body.get("address", "")
                city, state = "", ""
                if addr:
                    parts = [p.strip() for p in addr.split(",")]
                    if len(parts) >= 3:
                        city = parts[-3]
                        state_zip = parts[-2].strip().split(" ")
                        state = state_zip[0] if state_zip else ""
                    elif len(parts) == 2:
                        city = parts[0]

                place_type = body.get("place_type", "winery")
                place = Place.objects.create(
                    name=name, address=addr, city=city, state=state,
                    latitude=lat, longitude=lng,
                    website=body.get("website", ""),
                    image_url=body.get("photo_url", ""),
                    place_type=place_type if place_type in dict(Place.PlaceType.choices) else "winery",
                    phone=body.get("phone", ""),
                    description=body.get("description", ""),
                )
            else:
                changed = []
                if body.get("photo_url") and not place.image_url:
                    place.image_url = body["photo_url"]
                    changed.append("image_url")
                if body.get("phone") and not place.phone:
                    place.phone = body["phone"]
                    changed.append("phone")
                if body.get("description") and not place.description:
                    place.description = body["description"]
                    changed.append("description")
                if changed:
                    place.save(update_fields=changed + ["updated_at"])

        from django.utils import timezone as _tz

        today = _tz.localdate()
        default_meeting = time(12, 0)

        trip = Trip.objects.create(
            name=f"Trip to {place.name}",
            created_by=request.user,
            status=Trip.Status.DRAFT,
            scheduled_date=today,
            end_date=today,
            meeting_time=default_meeting,
        )
        TripMember.objects.create(
            trip=trip, user=request.user,
            role=TripMember.Role.ORGANIZER, rsvp_status="accepted",
        )
        default_arrival = datetime.combine(today, default_meeting, tzinfo=_user_tz(request.user))
        TripStop.objects.create(
            trip=trip, place=place, order=1,
            arrival_time=default_arrival,
            duration_minutes=90,
        )

        return JsonResponse({
            "trip_id": str(trip.pk),
            "trip_url": f"/trips/{trip.pk}/",
            "trip_name": trip.name,
        })


# ── Live Trip ──────────────────────────────────────────────

def _find_trip_visit(trip, place, user):
    """Find a user's visit at a place during the trip's date range."""
    from datetime import timedelta
    from django.utils import timezone

    qs = VisitLog.objects.filter(user=user, place=place)
    if trip.scheduled_date:
        end = trip.end_date or trip.scheduled_date
        qs = qs.filter(
            visited_at__date__gte=trip.scheduled_date,
            visited_at__date__lte=end + timedelta(days=1),
        )
    else:
        # No trip dates — find any visit in the last 30 days
        qs = qs.filter(visited_at__date__gte=timezone.now().date() - timedelta(days=30))
    return qs.order_by("-visited_at").first()


class QuickCheckinView(LoginRequiredMixin, View):
    """Create a confirmed trip with one stop, check in, and redirect to live trip."""

    def get(self, request):
        from django.utils import timezone as _tz

        place_id = request.GET.get("place")
        if not place_id:
            messages.error(request, "No place specified.")
            return redirect("place_list")

        place = get_object_or_404(Place, pk=place_id)
        today = _tz.localdate()
        now = _tz.now()
        default_meeting = time(12, 0)

        # Create confirmed trip
        trip = Trip.objects.create(
            name=f"Visit to {place.name}",
            created_by=request.user,
            status=Trip.Status.CONFIRMED,
            scheduled_date=today,
            end_date=today,
            meeting_time=default_meeting,
        )
        TripMember.objects.create(
            trip=trip,
            user=request.user,
            role=TripMember.Role.ORGANIZER,
            rsvp_status="accepted",
        )

        # Add the place as the first stop
        arrival = datetime.combine(today, default_meeting, tzinfo=_user_tz(request.user))
        TripStop.objects.create(
            trip=trip,
            place=place,
            order=1,
            arrival_time=arrival,
            duration_minutes=90,
        )

        # Auto check-in: create the VisitLog
        VisitLog.objects.create(
            user=request.user,
            place=place,
            visited_at=now,
        )

        return redirect("trip_live", pk=trip.pk)


class LiveTripView(LoginRequiredMixin, View):
    """Full-page live trip wizard."""

    def get(self, request, pk):
        from django.utils import timezone

        trip = get_object_or_404(
            Trip.objects.prefetch_related(
                "trip_stops__place__menu_items", "trip_members__user"
            ),
            pk=pk,
        )

        # Must be confirmed or in_progress
        if trip.status not in (Trip.Status.CONFIRMED, Trip.Status.IN_PROGRESS):
            messages.info(request, "This trip is not ready to start yet.")
            return redirect("trip_detail", pk=trip.pk)

        # Auto-transition confirmed → in_progress
        if trip.status == Trip.Status.CONFIRMED:
            trip.status = Trip.Status.IN_PROGRESS
            trip.save(update_fields=["status", "updated_at"])

        stops = list(trip.trip_stops.select_related("place").order_by("order"))
        if not stops:
            messages.info(request, "Add stops to your itinerary before starting.")
            return redirect("trip_detail", pk=trip.pk)

        # Current stop index from metadata
        meta = trip.metadata or {}
        current_index = meta.get("current_stop_index", 0)
        if current_index >= len(stops):
            current_index = len(stops) - 1

        # Find existing visits for this user at each stop's place during the trip
        from apps.visits.models import VisitWine
        user = request.user

        # Determine the trip date range
        trip_start = trip.scheduled_date
        trip_end = trip.end_date or trip.scheduled_date
        if trip_start:
            from datetime import timedelta
            # Include visits from trip start through end (+ 1 day buffer for timezone)
            visit_filter = {"user": user, "visited_at__date__gte": trip_start, "visited_at__date__lte": (trip_end or trip_start) + timedelta(days=1)}
        else:
            # No dates set — fall back to any recent visit (last 7 days)
            from datetime import timedelta
            visit_filter = {"user": user, "visited_at__date__gte": timezone.now().date() - timedelta(days=7)}

        stop_visits_json = {}
        for idx, stop in enumerate(stops):
            visit = VisitLog.objects.filter(
                place=stop.place, **visit_filter
            ).order_by("-visited_at").first()
            if visit:
                wines_logged = list(
                    VisitWine.objects.filter(visit=visit)
                    .select_related("menu_item")
                    .values("id", "menu_item_id", "wine_name", "wine_type",
                            "wine_vintage", "serving_type", "quantity",
                            "tasting_notes", "rating", "is_favorite",
                            "purchased", "purchased_quantity",
                            "purchased_price", "purchased_notes", "photo")
                )
                # Convert UUIDs and Decimals for JSON
                for w in wines_logged:
                    w["id"] = str(w["id"])
                    w["menu_item_id"] = str(w["menu_item_id"]) if w["menu_item_id"] else None
                    if w.get("purchased_price") is not None:
                        w["purchased_price"] = float(w["purchased_price"])

                stop_visits_json[idx] = {
                    "visit_id": str(visit.pk),
                    "place_name": stop.place.name,
                    "ratings": {
                        "rating_overall": visit.rating_overall,
                        "rating_staff": visit.rating_staff,
                        "rating_ambience": visit.rating_ambience,
                        "rating_food": visit.rating_food,
                    },
                    "notes": visit.notes,
                    "wines": wines_logged,
                }

        # Compute per-place stats: past visit count and favorite/top wine count
        from apps.visits.models import VisitWine
        from django.db.models import Count, Q
        place_stats = {}
        for stop in stops:
            place_id = stop.place_id
            if place_id not in place_stats:
                # Count visits before this trip started
                past_qs = VisitLog.objects.filter(user=user, place_id=place_id)
                if trip.scheduled_date:
                    past_qs = past_qs.filter(visited_at__date__lt=trip.scheduled_date)
                past_visits = past_qs.count()
                fav_wines = VisitWine.objects.filter(
                    visit__user=user, visit__place_id=place_id
                ).filter(Q(is_favorite=True) | Q(rating__gte=4)).count()
                place_stats[place_id] = {
                    "past_visits": past_visits,
                    "fav_wines": fav_wines,
                }
            stop.past_visits = place_stats[place_id]["past_visits"]
            stop.fav_wines = place_stats[place_id]["fav_wines"]

        import json
        return render(request, "trips/live.html", {
            "trip": trip,
            "stops": stops,
            "current_index": current_index,
            "stop_visits_json": json.dumps(stop_visits_json),
            "google_maps_api_key": settings.GOOGLE_MAPS_API_KEY,
        })


class LiveTripCheckinView(LoginRequiredMixin, View):
    """AJAX: check in at a stop — creates a VisitLog."""

    def post(self, request, pk, stop_pk):
        from django.utils import timezone
        from datetime import timedelta

        trip = get_object_or_404(Trip, pk=pk)
        stop = get_object_or_404(TripStop, pk=stop_pk, trip=trip)
        user = request.user

        # Find existing visit during trip date range
        visit = _find_trip_visit(trip, stop.place, user)

        if not visit:
            visit = VisitLog.objects.create(
                user=user,
                place=stop.place,
                visited_at=timezone.now(),
            )

        return JsonResponse({
            "ok": True,
            "visit_id": str(visit.pk),
            "place_name": stop.place.name,
            "checked_in_at": visit.visited_at.strftime("%I:%M %p"),
        })


class LiveTripUndoCheckinView(LoginRequiredMixin, View):
    """AJAX: undo a check-in — soft-deletes the VisitLog and its wines."""

    def post(self, request, pk, stop_pk):
        from django.utils import timezone
        from apps.visits.models import VisitWine

        trip = get_object_or_404(Trip, pk=pk)
        stop = get_object_or_404(TripStop, pk=stop_pk, trip=trip)
        user = request.user

        visit = _find_trip_visit(trip, stop.place, user)

        if visit:
            # Soft-delete wines logged on this visit
            VisitWine.objects.filter(visit=visit).update(is_active=False)
            # Soft-delete the visit
            visit.is_active = False
            visit.save(update_fields=["is_active", "updated_at"])

        return JsonResponse({"ok": True})


class LiveTripRateView(LoginRequiredMixin, View):
    """AJAX: save ratings and notes for a visit."""

    def post(self, request, pk, visit_pk):
        trip = get_object_or_404(Trip, pk=pk)  # noqa: F841
        visit = get_object_or_404(VisitLog, pk=visit_pk, user=request.user)
        try:
            body = _json.loads(request.body)
        except (ValueError, TypeError):
            return JsonResponse({"error": "Invalid JSON"}, status=400)

        update_fields = ["updated_at"]
        for field in ("rating_staff", "rating_ambience", "rating_food", "rating_overall"):
            if field in body:
                val = body[field]
                setattr(visit, field, int(val) if val else None)
                update_fields.append(field)
        if "notes" in body:
            visit.notes = body["notes"]
            update_fields.append("notes")

        visit.save(update_fields=update_fields)
        return JsonResponse({"ok": True})


class LiveTripWineView(LoginRequiredMixin, View):
    """AJAX: log a wine tasting (known menu item or ad-hoc)."""

    def post(self, request, pk):
        from apps.visits.models import VisitWine
        from apps.wineries.models import MenuItem

        trip = get_object_or_404(Trip, pk=pk)  # noqa: F841
        try:
            body = _json.loads(request.body)
        except (ValueError, TypeError):
            return JsonResponse({"error": "Invalid JSON"}, status=400)

        visit = get_object_or_404(VisitLog, pk=body.get("visit_id"), user=request.user)

        wine_id = body.get("wine_id")
        menu_item = None
        if wine_id:
            menu_item = get_object_or_404(MenuItem, pk=wine_id)

        # Update existing or create new
        vw_id = body.get("visit_wine_id")
        if vw_id:
            vw = get_object_or_404(VisitWine, pk=vw_id, visit=visit)
        else:
            vw = VisitWine(visit=visit)

        if menu_item:
            vw.menu_item = menu_item
            vw.wine_name = menu_item.name
            vw.wine_type = menu_item.varietal
            vw.wine_vintage = menu_item.vintage
        else:
            vw.menu_item = None
            vw.wine_name = body.get("wine_name", "")
            vw.wine_type = body.get("wine_type", "")
            vw.wine_vintage = int(body["wine_vintage"]) if body.get("wine_vintage") else None

        vw.serving_type = body.get("serving_type", "tasting")
        vw.quantity = int(body["quantity"]) if body.get("quantity") else 1
        vw.tasting_notes = body.get("tasting_notes", "")
        vw.rating = int(body["rating"]) if body.get("rating") else None
        if "is_favorite" in body:
            vw.is_favorite = bool(body["is_favorite"])
        if "purchased" in body:
            vw.purchased = bool(body["purchased"])
        if "purchased_quantity" in body:
            vw.purchased_quantity = int(body["purchased_quantity"]) if body["purchased_quantity"] else None
        if "purchased_price" in body:
            vw.purchased_price = body["purchased_price"] if body["purchased_price"] else None
        if "purchased_notes" in body:
            vw.purchased_notes = body["purchased_notes"]
        if "photo" in body:
            vw.photo = body["photo"] or ""
        vw.is_active = True
        vw.save()

        return JsonResponse({
            "ok": True,
            "visit_wine_id": str(vw.pk),
            "wine_name": vw.display_name,
            "wine_type": vw.wine_type,
            "wine_vintage": vw.wine_vintage,
            "serving_type": vw.serving_type,
            "quantity": vw.quantity,
            "rating": vw.rating,
            "tasting_notes": vw.tasting_notes,
            "is_favorite": vw.is_favorite,
            "purchased": vw.purchased,
            "purchased_quantity": vw.purchased_quantity,
            "purchased_price": float(vw.purchased_price) if vw.purchased_price else None,
            "purchased_notes": vw.purchased_notes,
            "photo": vw.photo or "",
        })

    def delete(self, request, pk):
        from apps.visits.models import VisitWine

        trip = get_object_or_404(Trip, pk=pk)  # noqa: F841
        try:
            body = _json.loads(request.body)
        except (ValueError, TypeError):
            return JsonResponse({"error": "Invalid JSON"}, status=400)

        vw = get_object_or_404(VisitWine, pk=body.get("visit_wine_id"))
        if vw.visit.user != request.user:
            return JsonResponse({"error": "Not yours"}, status=403)
        vw.is_active = False
        vw.save(update_fields=["is_active", "updated_at"])
        return JsonResponse({"ok": True})


class LiveTripAdvanceView(LoginRequiredMixin, View):
    """AJAX: advance or go back in the itinerary."""

    def post(self, request, pk):
        trip = get_object_or_404(Trip, pk=pk)
        try:
            body = _json.loads(request.body)
        except (ValueError, TypeError):
            return JsonResponse({"error": "Invalid JSON"}, status=400)

        stop_count = trip.trip_stops.count()
        meta = trip.metadata or {}
        current = meta.get("current_stop_index", 0)

        if "set_index" in body:
            current = max(0, min(int(body["set_index"]), stop_count - 1))
        else:
            direction = body.get("direction", "next")
            if direction == "next":
                current = min(current + 1, stop_count - 1)
            elif direction == "prev":
                current = max(current - 1, 0)

        meta["current_stop_index"] = current
        trip.metadata = meta
        trip.save(update_fields=["metadata", "updated_at"])

        return JsonResponse({"ok": True, "current_stop_index": current})


class LiveTripCompleteView(LoginRequiredMixin, View):
    """AJAX: mark trip as completed."""

    def post(self, request, pk):
        trip = get_object_or_404(Trip, pk=pk)
        trip.status = Trip.Status.COMPLETED
        meta = trip.metadata or {}
        meta.pop("current_stop_index", None)
        trip.metadata = meta
        trip.save(update_fields=["status", "metadata", "updated_at"])
        return JsonResponse({"ok": True})


class LiveTripWineMenuView(LoginRequiredMixin, View):
    """AJAX: fetch known menu items for a place (scrapes website if needed)."""

    def get(self, request, pk, place_pk):
        from apps.wineries.models import Place as PlaceModel
        from apps.wineries.scraper import scrape_and_cache_menu_items

        trip = get_object_or_404(Trip, pk=pk)  # noqa: F841
        place = get_object_or_404(PlaceModel, pk=place_pk)

        if request.GET.get("refresh"):
            place.wine_menu_last_scraped = None
            place.save(update_fields=["wine_menu_last_scraped", "updated_at"])

        menu_items = scrape_and_cache_menu_items(place)

        return JsonResponse({
            "ok": True,
            "wines": [
                {
                    "wine_id": str(w.pk),
                    "name": w.name,
                    "varietal": w.varietal,
                    "vintage": w.vintage,
                    "description": w.description or "",
                    "wine_type": (w.metadata or {}).get("wine_type", ""),
                    "price": float(w.price) if w.price else None,
                    "image_url": w.image_url or "",
                }
                for w in menu_items
            ],
            "has_website": bool(place.website),
            "place_name": place.name,
        })
