import json as _json
from decimal import Decimal

from django.conf import settings
from django.contrib import messages
from django.contrib.auth import get_user_model
from django.contrib.auth.mixins import LoginRequiredMixin
from django.db.models import Max, Q
from django.http import JsonResponse
from django.shortcuts import get_object_or_404, redirect, render
from django.views import View
from django.views.generic import ListView

from apps.trips.forms import TripForm
from apps.trips.models import Trip, TripMember, TripStop
from apps.visits.models import VisitLog
from apps.wineries.models import FavoritePlace, Place

User = get_user_model()


class TripListView(LoginRequiredMixin, ListView):
    model = Trip
    template_name = "trips/list.html"
    context_object_name = "trips"
    paginate_by = 10

    def get_queryset(self):
        return (
            Trip.objects.filter(members=self.request.user)
            .prefetch_related("trip_members__user", "trip_stops__place")
            .distinct()
            .order_by("-created_at")
        )

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        from datetime import date
        today = date.today()
        for trip in ctx["trips"]:
            trip.show_start_button = (
                trip.status == "in_progress"
                or (trip.status == "confirmed" and trip.scheduled_date and trip.scheduled_date <= today)
            )
        return ctx


class TripCreateView(LoginRequiredMixin, View):
    def get(self, request):
        return render(request, "trips/form.html", {
            "form": TripForm(),
            "page_title": "Plan a Trip",
        })

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
        return render(request, "trips/form.html", {
            "form": form,
            "page_title": "Plan a Trip",
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

        return render(request, "trips/detail.html", {
            "trip": trip,
            "is_member": is_member,
            "is_organizer": is_organizer,
            "members": trip.trip_members.select_related("user").order_by("role"),
            "stops": stops,
            "favorites": favorites,
            "visited": visited,
            "stop_place_ids": stop_place_ids,
            "show_start_button": show_start_button,
            "google_maps_api_key": settings.GOOGLE_MAPS_API_KEY,
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

        # Check if already added
        if TripStop.all_objects.filter(trip=trip, place=place).exists():
            tw = TripStop.all_objects.get(trip=trip, place=place)
            tw.is_active = True
            tw.save(update_fields=["is_active", "updated_at"])
        else:
            max_order = trip.trip_stops.order_by("-order").values_list("order", flat=True).first() or 0
            tw = TripStop.objects.create(
                trip=trip, place=place, order=max_order + 1
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
            "arrival_time", "duration_minutes", "description",
            "notes", "meeting_details", "travel_details", "order",
        ]
        for field in editable_fields:
            if field in body:
                val = body[field]
                if field == "duration_minutes":
                    val = int(val) if val else None
                if field == "order":
                    val = int(val) if val else stop.order
                if field == "arrival_time":
                    val = val or None
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
    """AJAX: remove a stop from a trip (soft delete)."""

    def post(self, request, pk, stop_pk):
        trip = get_object_or_404(Trip, pk=pk)
        stop = get_object_or_404(TripStop, pk=stop_pk, trip=trip)
        stop.is_active = False
        stop.save(update_fields=["is_active", "updated_at"])

        # Re-sequence remaining stops
        remaining = list(trip.trip_stops.order_by("order"))
        for idx, tw in enumerate(remaining, start=1):
            if tw.order != idx:
                tw.order = idx
                tw.save(update_fields=["order", "updated_at"])

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

        trip = Trip.objects.create(
            name=f"Trip to {place.name}",
            created_by=request.user,
            status=Trip.Status.DRAFT,
        )
        TripMember.objects.create(
            trip=trip, user=request.user,
            role=TripMember.Role.ORGANIZER, rsvp_status="accepted",
        )
        TripStop.objects.create(trip=trip, place=place, order=1)

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
                            "purchased_price", "purchased_notes")
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
