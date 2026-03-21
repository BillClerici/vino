from django.conf import settings
from django.contrib import messages
from django.contrib.auth import get_user_model
from django.contrib.auth.mixins import LoginRequiredMixin, UserPassesTestMixin
from django.db.models import Count, Sum
from django.shortcuts import get_object_or_404, redirect, render
from django.urls import reverse, reverse_lazy
from django.utils import timezone
from django.views import View
from django.views.generic import CreateView, ListView, TemplateView, UpdateView

from apps.partners.forms import (
    AdminClaimForm,
    AdminPartnerCreateForm,
    AdminPartnerForm,
    AdminPromotionForm,
    PartnerApplyForm,
    PartnerProfileForm,
    PlaceClaimForm,
    PromotionForm,
)
from apps.partners.models import Partner, PlaceClaim, Promotion, PromotionImpression

from apps.partners.models import PartnerOwner

User = get_user_model()


def _get_user_partner(user):
    """Return the first approved Partner the user owns, or None."""
    po = (
        PartnerOwner.objects.filter(user=user, is_active=True, partner__status=Partner.Status.APPROVED, partner__is_active=True)
        .select_related("partner")
        .first()
    )
    return po.partner if po else None


def _get_any_user_partner(user):
    """Return any Partner the user owns (any status), or None."""
    po = (
        PartnerOwner.objects.filter(user=user, is_active=True, partner__is_active=True)
        .select_related("partner")
        .first()
    )
    return po.partner if po else None


# ── Mixins ──


class ApprovedPartnerRequiredMixin(LoginRequiredMixin):
    """Requires user to be logged in and have an approved partner profile."""

    def dispatch(self, request, *args, **kwargs):
        if not request.user.is_authenticated:
            return self.handle_no_permission()
        partner = _get_user_partner(request.user)
        if not partner:
            messages.warning(request, "You need an approved partner account to access this page.")
            return redirect("partner_apply")
        return super().dispatch(request, *args, **kwargs)

    def get_partner(self):
        return _get_user_partner(self.request.user)


class SuperuserRequiredMixin(LoginRequiredMixin, UserPassesTestMixin):
    """Only allow superusers to access admin views."""

    def test_func(self):
        return self.request.user.is_superuser


# ══════════════════════════════════════════════════
# Partner Portal Views
# ══════════════════════════════════════════════════


class PartnerDashboardView(ApprovedPartnerRequiredMixin, TemplateView):
    template_name = "partners/dashboard.html"

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        partner = self.get_partner()
        ctx["partner"] = partner
        ctx["claimed_places_count"] = partner.claims.filter(status="approved").count()
        ctx["active_promotions_count"] = partner.promotions.filter(status="active").count()
        ctx["total_impressions"] = (
            PromotionImpression.objects.filter(promotion__partner=partner).count()
        )
        ctx["recent_claims"] = partner.claims.select_related("place").order_by("-claimed_at")[:5]
        ctx["recent_promotions"] = partner.promotions.select_related("place").order_by(
            "-created_at"
        )[:5]
        return ctx


class PartnerProfileView(ApprovedPartnerRequiredMixin, View):
    template_name = "partners/profile.html"

    def get(self, request):
        partner = self.get_partner()
        form = PartnerProfileForm(instance=partner)
        return render(request, self.template_name, {"form": form, "partner": partner})

    def post(self, request):
        partner = self.get_partner()
        form = PartnerProfileForm(request.POST, instance=partner)
        if form.is_valid():
            form.save()
            messages.success(request, "Profile updated successfully.")
            return redirect("partner_profile")
        return render(request, self.template_name, {"form": form, "partner": partner})


class PartnerClaimListView(ApprovedPartnerRequiredMixin, ListView):
    template_name = "partners/claims.html"
    context_object_name = "claims"

    def get_queryset(self):
        return self.get_partner().claims.select_related("place").order_by("-claimed_at")

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        ctx["partner"] = self.get_partner()
        return ctx


class PartnerClaimCreateView(ApprovedPartnerRequiredMixin, View):
    template_name = "partners/claim_form.html"

    def get(self, request):
        form = PlaceClaimForm()
        return render(request, self.template_name, {"form": form})

    def post(self, request):
        form = PlaceClaimForm(request.POST)
        if form.is_valid():
            claim = form.save(commit=False)
            claim.partner = self.get_partner()
            claim.save()
            messages.success(request, f"Claim submitted for {claim.place.name}. Pending review.")
            return redirect("partner_claims")
        return render(request, self.template_name, {"form": form})


class PartnerPromotionListView(ApprovedPartnerRequiredMixin, ListView):
    template_name = "partners/promotions.html"
    context_object_name = "promotions"

    def get_queryset(self):
        return self.get_partner().promotions.select_related("place").order_by("-created_at")

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        ctx["partner"] = self.get_partner()
        return ctx


class PartnerPromotionCreateView(ApprovedPartnerRequiredMixin, View):
    template_name = "partners/promotion_form.html"

    def get(self, request):
        partner = self.get_partner()
        form = PromotionForm(partner=partner)
        return render(request, self.template_name, {"form": form, "editing": False})

    def post(self, request):
        partner = self.get_partner()
        form = PromotionForm(request.POST, partner=partner)
        if form.is_valid():
            promo = form.save(commit=False)
            promo.partner = partner
            promo.save()
            messages.success(request, f"Promotion '{promo.name}' created.")
            return redirect("partner_promotions")
        return render(request, self.template_name, {"form": form, "editing": False})


class PartnerPromotionEditView(ApprovedPartnerRequiredMixin, View):
    template_name = "partners/promotion_form.html"

    def get_promotion(self, pk):
        return get_object_or_404(Promotion, pk=pk, partner=self.get_partner())

    def get(self, request, pk):
        promo = self.get_promotion(pk)
        form = PromotionForm(instance=promo, partner=self.get_partner())
        return render(request, self.template_name, {"form": form, "editing": True, "promotion": promo})

    def post(self, request, pk):
        promo = self.get_promotion(pk)
        form = PromotionForm(request.POST, instance=promo, partner=self.get_partner())
        if form.is_valid():
            form.save()
            messages.success(request, f"Promotion '{promo.name}' updated.")
            return redirect("partner_promotions")
        return render(request, self.template_name, {"form": form, "editing": True, "promotion": promo})


class PartnerApplyView(LoginRequiredMixin, View):
    template_name = "partners/apply.html"

    def get(self, request):
        partner = _get_any_user_partner(request.user)
        if partner:
            if partner.status == Partner.Status.APPROVED:
                return redirect("partner_dashboard")
            return render(request, self.template_name, {"form": None, "partner": partner})
        form = PartnerApplyForm()
        return render(request, self.template_name, {"form": form, "partner": None})

    def post(self, request):
        partner = _get_any_user_partner(request.user)
        if partner:
            messages.info(request, "You have already applied for a partner account.")
            return redirect("partner_apply")
        form = PartnerApplyForm(request.POST)
        if form.is_valid():
            partner = form.save(commit=False)
            partner.status = Partner.Status.PENDING
            partner.save()
            PartnerOwner.objects.create(
                partner=partner,
                user=request.user,
                role=PartnerOwner.Role.PRIMARY,
                contact_email=request.user.email,
            )
            messages.success(
                request,
                "Your partner application has been submitted! We will review it shortly.",
            )
            return redirect("partner_apply")
        return render(request, self.template_name, {"form": form, "partner": None})


# ══════════════════════════════════════════════════
# Admin Views
# ══════════════════════════════════════════════════


class AdminPartnerListView(SuperuserRequiredMixin, ListView):
    model = Partner
    template_name = "admin/list.html"

    def get_queryset(self):
        return Partner.all_objects.prefetch_related("partner_owners__user").order_by("-created_at")

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        ctx["page_title"] = "Partners"
        ctx["icon"] = "handshake"
        ctx["create_url"] = reverse("admin_partners_create")
        ctx["columns"] = ["Business Name", "Owners", "Tier", "Status", "Created"]
        rows = []
        for p in ctx["object_list"]:
            owner_names = ", ".join(
                o.user.full_name or o.user.email
                for o in p.partner_owners.filter(is_active=True)[:3]
            ) or "—"
            rows.append({
                "values": [
                    p.business_name,
                    owner_names,
                    p.get_tier_display(),
                    p.get_status_display(),
                    p.created_at.strftime("%Y-%m-%d"),
                ],
                "edit_url": reverse("admin_partners_edit", args=[p.pk]),
                "delete_url": reverse("admin_partners_delete", args=[p.pk]),
            })
        ctx["rows"] = rows
        return ctx


class AdminPartnerCreateView(SuperuserRequiredMixin, CreateView):
    model = Partner
    form_class = AdminPartnerCreateForm
    template_name = "admin/form.html"
    success_url = reverse_lazy("admin_partners_list")

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        ctx["page_title"] = "Add Partner"
        ctx["icon"] = "handshake"
        ctx["cancel_url"] = reverse("admin_partners_list")
        return ctx

    def form_valid(self, form):
        partner = form.save(commit=False)
        if partner.status == Partner.Status.APPROVED and not partner.approved_at:
            partner.approved_at = timezone.now()
            partner.approved_by = self.request.user
        partner.save()
        messages.success(self.request, f'Partner "{partner.business_name}" created! Add owners on the edit page.')
        return redirect("admin_partners_edit", pk=partner.pk)


class _AdminPartnerBaseMixin(SuperuserRequiredMixin):
    """Base mixin for all partner sub-pages — loads the partner and nav context."""

    def get_partner(self):
        return get_object_or_404(
            Partner.all_objects.select_related("approved_by", "rejected_by"),
            pk=self.kwargs["pk"],
        )

    def get_partner_nav(self, partner, active_tab="dashboard"):
        owners_count = partner.partner_owners.filter(is_active=True).count()
        claims_count = partner.claims.filter(is_active=True).count()
        promos_count = partner.promotions.filter(is_active=True).count()
        return {
            "partner": partner,
            "active_tab": active_tab,
            "owners_count": owners_count,
            "claims_count": claims_count,
            "promos_count": promos_count,
        }


class AdminPartnerEditView(_AdminPartnerBaseMixin, View):
    """Partner dashboard — overview of all sections."""

    def get(self, request, pk):
        partner = self.get_partner()
        owners = partner.partner_owners.filter(is_active=True).select_related("user")[:5]
        claims = partner.claims.filter(is_active=True).select_related("place").order_by("-claimed_at")[:5]
        promotions = partner.promotions.filter(is_active=True).select_related("place", "promotion_type").order_by("-start_date")[:5]
        from django.db.models import Count
        impressions_count = PromotionImpression.objects.filter(promotion__partner=partner).count()

        ctx = self.get_partner_nav(partner, "dashboard")
        ctx.update({
            "owners": owners,
            "claims": claims,
            "promotions": promotions,
            "impressions_count": impressions_count,
        })
        return render(request, "partners/admin_partner_dashboard.html", ctx)


class AdminPartnerDetailsView(_AdminPartnerBaseMixin, UpdateView):
    """Partner details — edit form + application status."""
    model = Partner
    form_class = AdminPartnerForm
    template_name = "partners/admin_partner_details.html"

    def get_queryset(self):
        return Partner.all_objects.select_related("approved_by", "rejected_by").all()

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        ctx.update(self.get_partner_nav(self.object, "details"))
        return ctx

    def form_valid(self, form):
        form.save()
        messages.success(self.request, f"Partner {self.object.business_name} updated.")
        return redirect("admin_partners_edit", pk=self.object.pk)


class AdminPartnerOwnersView(_AdminPartnerBaseMixin, View):
    """Partner owners management page."""

    def get(self, request, pk):
        partner = self.get_partner()
        owners = partner.partner_owners.filter(is_active=True).select_related("user")
        ctx = self.get_partner_nav(partner, "owners")
        ctx["owners"] = owners
        return render(request, "partners/admin_partner_owners.html", ctx)


class AdminPartnerPlacesView(_AdminPartnerBaseMixin, View):
    """Partner places/claims management page."""

    def get(self, request, pk):
        partner = self.get_partner()
        claims = partner.claims.filter(is_active=True).select_related("place").order_by("-claimed_at")
        ctx = self.get_partner_nav(partner, "places")
        ctx["claims"] = claims
        ctx["google_maps_api_key"] = settings.GOOGLE_MAPS_API_KEY
        return render(request, "partners/admin_partner_places.html", ctx)


class AdminPartnerPromotionsView(_AdminPartnerBaseMixin, View):
    """Partner promotions management page."""

    def get(self, request, pk):
        partner = self.get_partner()
        claims = partner.claims.filter(status="approved", is_active=True).select_related("place")
        promotions = partner.promotions.filter(is_active=True).select_related("place", "promotion_type").order_by("-start_date")
        from apps.lookup.models import LookupValue
        ctx = self.get_partner_nav(partner, "promotions")
        ctx["claims"] = claims
        ctx["promotions"] = promotions
        ctx["promotion_types"] = LookupValue.objects.filter(parent__code="PROMOTION_TYPE").order_by("sort_order")
        return render(request, "partners/admin_partner_promotions.html", ctx)


class AdminUserSearchView(SuperuserRequiredMixin, View):
    """AJAX: search users by email or name for owner assignment."""

    def get(self, request):
        from django.http import JsonResponse
        q = request.GET.get("q", "").strip()
        if len(q) < 2:
            return JsonResponse({"results": []})
        from django.db.models import Q
        users = (
            User.objects.filter(
                Q(email__icontains=q) | Q(first_name__icontains=q) | Q(last_name__icontains=q)
            )
            .order_by("email")[:10]
        )
        return JsonResponse({
            "results": [
                {"id": str(u.pk), "email": u.email, "name": u.full_name}
                for u in users
            ]
        })


class AdminPartnerAddOwnerView(SuperuserRequiredMixin, View):
    """AJAX: add an owner to a partner."""

    def post(self, request, pk):
        import json
        from django.http import JsonResponse
        partner = get_object_or_404(Partner.all_objects, pk=pk)
        try:
            body = json.loads(request.body)
        except (ValueError, TypeError):
            return JsonResponse({"error": "Invalid JSON"}, status=400)

        user_id = body.get("user_id")
        if not user_id:
            return JsonResponse({"error": "user_id required"}, status=400)

        user = get_object_or_404(User, pk=user_id)
        role = body.get("role", PartnerOwner.Role.OWNER)
        if role not in dict(PartnerOwner.Role.choices):
            role = PartnerOwner.Role.OWNER

        po, created = PartnerOwner.all_objects.get_or_create(
            partner=partner,
            user=user,
            defaults={
                "role": role,
                "title": body.get("title", ""),
                "contact_email": body.get("contact_email", user.email),
                "contact_phone": body.get("contact_phone", ""),
                "mobile_phone": body.get("mobile_phone", ""),
                "address": body.get("address", ""),
                "city": body.get("city", ""),
                "state": body.get("state", ""),
                "zip_code": body.get("zip_code", ""),
            },
        )
        if not created and not po.is_active:
            po.is_active = True
            po.role = role
            po.save(update_fields=["is_active", "role", "updated_at"])
            created = True
        elif not created:
            return JsonResponse({"error": "User is already an owner."}, status=400)

        return JsonResponse(_owner_json(po))


class AdminPartnerUpdateOwnerView(SuperuserRequiredMixin, View):
    """AJAX: update an owner's details."""

    def post(self, request, pk, owner_pk):
        import json
        from django.http import JsonResponse
        partner = get_object_or_404(Partner.all_objects, pk=pk)
        po = get_object_or_404(PartnerOwner, pk=owner_pk, partner=partner)
        try:
            body = json.loads(request.body)
        except (ValueError, TypeError):
            return JsonResponse({"error": "Invalid JSON"}, status=400)

        for field in ("role", "title", "contact_email", "contact_phone",
                       "mobile_phone", "address", "city", "state", "zip_code", "notes"):
            if field in body:
                val = body[field]
                if field == "role" and val not in dict(PartnerOwner.Role.choices):
                    continue
                setattr(po, field, val)
        po.save()
        return JsonResponse(_owner_json(po))


class AdminPartnerRemoveOwnerView(SuperuserRequiredMixin, View):
    """AJAX: remove an owner from a partner (soft delete)."""

    def post(self, request, pk, owner_pk):
        from django.http import JsonResponse
        partner = get_object_or_404(Partner.all_objects, pk=pk)
        po = get_object_or_404(PartnerOwner, pk=owner_pk, partner=partner)
        po.is_active = False
        po.save(update_fields=["is_active", "updated_at"])
        return JsonResponse({"ok": True})


def _owner_json(po):
    """Serialize a PartnerOwner for JSON responses."""
    return {
        "ok": True,
        "owner_id": str(po.pk),
        "user_id": str(po.user_id),
        "name": po.user.full_name or po.user.email,
        "email": po.user.email,
        "role": po.role,
        "role_display": po.get_role_display(),
        "title": po.title,
        "contact_email": po.contact_email,
        "contact_phone": po.contact_phone,
        "mobile_phone": po.mobile_phone,
        "address": po.address,
        "city": po.city,
        "state": po.state,
        "zip_code": po.zip_code,
        "notes": po.notes,
    }


class AdminPartnerDecisionView(SuperuserRequiredMixin, View):
    """AJAX: accept or reject a partner and send notification email."""

    def post(self, request, pk):
        import json as _json
        from django.core.mail import send_mail
        from django.http import JsonResponse

        partner = get_object_or_404(Partner.all_objects, pk=pk)
        try:
            body = _json.loads(request.body)
        except (ValueError, TypeError):
            return JsonResponse({"error": "Invalid JSON"}, status=400)

        action = body.get("action")  # "accept", "reject", or "reset"
        if action not in ("accept", "reject", "reset"):
            return JsonResponse({"error": "Invalid action"}, status=400)

        now = timezone.now()

        if action == "reset":
            partner.status = Partner.Status.PENDING
            partner.approved_at = None
            partner.approved_by = None
            partner.rejected_at = None
            partner.rejected_by = None
            partner.decision_email_sent_at = None
            partner.save(update_fields=[
                "status", "approved_at", "approved_by",
                "rejected_at", "rejected_by", "decision_email_sent_at", "updated_at",
            ])
            return JsonResponse({"ok": True, "status": "pending", "status_display": "Pending"})

        email_to = body.get("to", [])
        email_subject = body.get("subject", "")
        email_body = body.get("body", "")

        if action == "accept":
            partner.status = Partner.Status.APPROVED
            partner.approved_at = now
            partner.approved_by = request.user
            partner.save(update_fields=[
                "status", "approved_at", "approved_by", "updated_at",
            ])
        else:
            partner.status = Partner.Status.REJECTED
            partner.rejected_at = now
            partner.rejected_by = request.user
            partner.save(update_fields=[
                "status", "rejected_at", "rejected_by", "updated_at",
            ])

        # Send the email
        if email_to and email_subject and email_body:
            try:
                from django.conf import settings as _settings
                from_email = getattr(_settings, "DEFAULT_FROM_EMAIL", "noreply@tripme.app")
                send_mail(
                    subject=email_subject,
                    message=email_body,
                    from_email=from_email,
                    recipient_list=email_to if isinstance(email_to, list) else [email_to],
                    fail_silently=False,
                )
                partner.decision_email_sent_at = timezone.now()
                partner.save(update_fields=["decision_email_sent_at", "updated_at"])
            except Exception as e:
                return JsonResponse({
                    "ok": True,
                    "status": partner.status,
                    "email_error": str(e),
                })

        return JsonResponse({
            "ok": True,
            "status": partner.status,
            "status_display": partner.get_status_display(),
        })


class AdminPlaceSearchView(SuperuserRequiredMixin, View):
    """AJAX: search places by name, city, or state."""

    def get(self, request):
        from django.http import JsonResponse
        from django.db.models import Q
        from apps.wineries.models import Place

        q = request.GET.get("q", "").strip()
        if len(q) < 2:
            return JsonResponse({"results": []})

        places = (
            Place.objects.filter(
                Q(name__icontains=q) | Q(city__icontains=q) | Q(state__icontains=q) | Q(address__icontains=q)
            )
            .order_by("name")[:15]
        )
        # Mark which are already claimed
        claimed_ids = set(
            PlaceClaim.objects.filter(status__in=["pending", "approved"]).values_list("place_id", flat=True)
        )
        return JsonResponse({
            "results": [
                {
                    "id": str(p.pk),
                    "name": p.name,
                    "city": p.city,
                    "state": p.state,
                    "address": p.address,
                    "place_type": p.get_place_type_display(),
                    "claimed": str(p.pk) in {str(x) for x in claimed_ids},
                }
                for p in places
            ]
        })


class AdminPartnerCreatePlaceAndClaimView(SuperuserRequiredMixin, View):
    """AJAX: create a place from Google Maps data and claim it for a partner."""

    def post(self, request, pk):
        import json as _json
        from django.http import JsonResponse
        from decimal import Decimal
        from apps.wineries.models import Place

        partner = get_object_or_404(Partner.all_objects, pk=pk)
        try:
            body = _json.loads(request.body)
        except (ValueError, TypeError):
            return JsonResponse({"error": "Invalid JSON"}, status=400)

        name = body.get("name", "").strip()
        if not name:
            return JsonResponse({"error": "Name is required"}, status=400)

        lat = body.get("lat")
        lng = body.get("lng")
        addr = body.get("address", "")

        # Try to find existing place by name + coordinates
        place = None
        if lat and lng:
            lat_d, lng_d = Decimal(str(lat)), Decimal(str(lng))
            place = Place.objects.filter(
                name__iexact=name,
                latitude__range=(lat_d - Decimal("0.001"), lat_d + Decimal("0.001")),
                longitude__range=(lng_d - Decimal("0.001"), lng_d + Decimal("0.001")),
            ).first()

        if not place:
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
            if place_type not in dict(Place.PlaceType.choices):
                place_type = "winery"

            place = Place.objects.create(
                name=name,
                address=addr,
                city=city,
                state=state,
                latitude=lat,
                longitude=lng,
                website=body.get("website", ""),
                image_url=body.get("photo_url", ""),
                place_type=place_type,
                phone=body.get("phone", ""),
            )

        # Check if actively claimed
        active_claim = PlaceClaim.all_objects.filter(place=place, status__in=["pending", "approved"], is_active=True).first()
        if active_claim:
            return JsonResponse({"error": "This place is already claimed."}, status=400)

        auto_approve = body.get("auto_approve", True)

        existing = PlaceClaim.all_objects.filter(place=place).first()
        if existing:
            existing.partner = partner
            existing.status = "approved" if auto_approve else "pending"
            existing.is_active = True
            existing.approved_at = timezone.now() if auto_approve else None
            existing.approved_by = request.user if auto_approve else None
            existing.save()
            claim = existing
        else:
            claim = PlaceClaim.objects.create(
                partner=partner,
                place=place,
                status="approved" if auto_approve else "pending",
                approved_at=timezone.now() if auto_approve else None,
                approved_by=request.user if auto_approve else None,
            )

        return JsonResponse({
            "ok": True,
            "claim_id": str(claim.pk),
            "place_id": str(place.pk),
            "place_name": place.name,
            "place_city": place.city,
            "place_state": place.state,
            "status": claim.status,
            "status_display": claim.get_status_display(),
        })


class AdminPartnerAddPromotionView(SuperuserRequiredMixin, View):
    """AJAX: create a promotion for a partner."""

    def post(self, request, pk):
        import json as _json
        from django.http import JsonResponse
        from apps.wineries.models import Place
        from apps.lookup.models import LookupValue

        partner = get_object_or_404(Partner.all_objects, pk=pk)
        try:
            body = _json.loads(request.body)
        except (ValueError, TypeError):
            return JsonResponse({"error": "Invalid JSON"}, status=400)

        place_id = body.get("place_id")
        name = body.get("name", "").strip()
        promo_type_id = body.get("promotion_type_id")
        start_date = body.get("start_date")
        end_date = body.get("end_date")

        if not all([place_id, name, start_date, end_date]):
            return JsonResponse({"error": "Name, place, start date, and end date are required."}, status=400)

        place = get_object_or_404(Place, pk=place_id)
        promo_type = get_object_or_404(LookupValue, pk=promo_type_id) if promo_type_id else None

        from datetime import date as _date
        promo = Promotion.objects.create(
            partner=partner,
            place=place,
            name=name,
            promotion_type=promo_type,
            start_date=_date.fromisoformat(start_date),
            end_date=_date.fromisoformat(end_date),
            headline=body.get("headline", ""),
            description=body.get("description", ""),
            status="active",
        )

        return JsonResponse({
            "ok": True,
            "promo_id": str(promo.pk),
            "name": promo.name,
            "place_name": place.name,
            "type_label": promo_type.label if promo_type else "—",
            "status_display": promo.get_status_display(),
            "start_date": promo.start_date.strftime("%b %d"),
            "end_date": promo.end_date.strftime("%b %d, %Y"),
        })


class AdminPartnerRemovePromotionView(SuperuserRequiredMixin, View):
    """AJAX: remove a promotion (soft delete)."""

    def post(self, request, pk, promo_pk):
        from django.http import JsonResponse
        partner = get_object_or_404(Partner.all_objects, pk=pk)
        promo = get_object_or_404(Promotion, pk=promo_pk, partner=partner)
        promo.is_active = False
        promo.save(update_fields=["is_active", "updated_at"])
        return JsonResponse({"ok": True})


class AdminPartnerAddClaimView(SuperuserRequiredMixin, View):
    """AJAX: create a place claim for a partner."""

    def post(self, request, pk):
        import json as _json
        from django.http import JsonResponse
        from apps.wineries.models import Place

        partner = get_object_or_404(Partner.all_objects, pk=pk)
        try:
            body = _json.loads(request.body)
        except (ValueError, TypeError):
            return JsonResponse({"error": "Invalid JSON"}, status=400)

        place_id = body.get("place_id")
        if not place_id:
            return JsonResponse({"error": "place_id required"}, status=400)

        place = get_object_or_404(Place, pk=place_id)

        # Check if actively claimed by someone else
        active_claim = PlaceClaim.all_objects.filter(place=place, status__in=["pending", "approved"], is_active=True).first()
        if active_claim:
            return JsonResponse({"error": "This place is already claimed."}, status=400)

        auto_approve = body.get("auto_approve", False)

        # Reactivate soft-deleted claim or create new (OneToOne constraint)
        existing = PlaceClaim.all_objects.filter(place=place).first()
        if existing:
            existing.partner = partner
            existing.status = "approved" if auto_approve else "pending"
            existing.is_active = True
            existing.approved_at = timezone.now() if auto_approve else None
            existing.approved_by = request.user if auto_approve else None
            existing.save()
            claim = existing
        else:
            claim = PlaceClaim.objects.create(
                partner=partner,
                place=place,
                status="approved" if auto_approve else "pending",
                approved_at=timezone.now() if auto_approve else None,
                approved_by=request.user if auto_approve else None,
            )

        return JsonResponse({
            "ok": True,
            "claim_id": str(claim.pk),
            "place_name": place.name,
            "place_city": place.city,
            "place_state": place.state,
            "status": claim.status,
            "status_display": claim.get_status_display(),
        })


class AdminPartnerRemoveClaimView(SuperuserRequiredMixin, View):
    """AJAX: remove a claim (soft delete)."""

    def post(self, request, pk, claim_pk):
        from django.http import JsonResponse
        partner = get_object_or_404(Partner.all_objects, pk=pk)
        claim = get_object_or_404(PlaceClaim, pk=claim_pk, partner=partner)
        claim.status = "revoked"
        claim.is_active = False
        claim.save(update_fields=["status", "is_active", "updated_at"])
        return JsonResponse({"ok": True})


class AdminPartnerDeleteView(SuperuserRequiredMixin, View):
    """Delete a partner — soft or hard."""

    def get(self, request, pk):
        partner = get_object_or_404(Partner.all_objects, pk=pk)
        return render(request, "admin/delete.html", {
            "object_name": partner.business_name,
            "cancel_url": reverse("admin_partners_edit", args=[pk]),
            "can_hard_delete": True,
        })

    def post(self, request, pk):
        partner = get_object_or_404(Partner.all_objects, pk=pk)
        delete_type = request.POST.get("delete_type", "soft")

        if delete_type == "hard":
            name = partner.business_name
            # Delete related records first
            PromotionImpression.objects.filter(promotion__partner=partner).delete()
            Promotion.all_objects.filter(partner=partner).delete()
            PlaceClaim.all_objects.filter(partner=partner).delete()
            PartnerOwner.all_objects.filter(partner=partner).delete()
            partner.delete()
            messages.success(request, f'Partner "{name}" permanently deleted.')
        else:
            partner.is_active = False
            partner.save(update_fields=["is_active", "updated_at"])
            messages.success(request, f'Partner "{partner.business_name}" deactivated.')

        return redirect("admin_partners_list")


class AdminClaimListView(SuperuserRequiredMixin, ListView):
    model = PlaceClaim
    template_name = "admin/list.html"

    def get_queryset(self):
        return PlaceClaim.all_objects.select_related("partner", "place").order_by("-claimed_at")

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        ctx["page_title"] = "Place Claims"
        ctx["icon"] = "store"
        ctx["create_url"] = ""
        ctx["columns"] = ["Partner", "Place", "Status", "Claimed At"]
        ctx["rows"] = [
            {
                "values": [
                    c.partner.business_name,
                    c.place.name,
                    c.get_status_display(),
                    c.claimed_at.strftime("%Y-%m-%d"),
                ],
                "edit_url": reverse("admin_claims_edit", args=[c.pk]),
                "delete_url": reverse("admin_claims_edit", args=[c.pk]),
            }
            for c in ctx["object_list"]
        ]
        return ctx


class AdminClaimEditView(SuperuserRequiredMixin, UpdateView):
    model = PlaceClaim
    form_class = AdminClaimForm
    template_name = "admin/form.html"
    success_url = reverse_lazy("admin_claims_list")

    def get_queryset(self):
        return PlaceClaim.all_objects.all()

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        claim = self.object
        ctx["page_title"] = f"Edit Claim: {claim.partner.business_name} → {claim.place.name}"
        ctx["icon"] = "edit"
        ctx["cancel_url"] = reverse("admin_claims_list")
        return ctx

    def form_valid(self, form):
        claim = form.save(commit=False)
        if claim.status == PlaceClaim.Status.APPROVED and not claim.approved_at:
            claim.approved_at = timezone.now()
            claim.approved_by = self.request.user
        claim.save()
        messages.success(self.request, f"Claim for {claim.place.name} updated.")
        return redirect(self.success_url)


class AdminPromotionListView(SuperuserRequiredMixin, ListView):
    model = Promotion
    template_name = "admin/list.html"

    def get_queryset(self):
        return Promotion.all_objects.select_related("partner", "place", "promotion_type").order_by("-created_at")

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        ctx["page_title"] = "Promotions"
        ctx["icon"] = "campaign"
        ctx["create_url"] = ""
        ctx["columns"] = ["Name", "Partner", "Place", "Type", "Status", "Dates"]
        ctx["rows"] = [
            {
                "values": [
                    p.name,
                    p.partner.business_name,
                    p.place.name,
                    p.promotion_type.label if p.promotion_type else "—",
                    p.get_status_display(),
                    f"{p.start_date} — {p.end_date}",
                ],
                "edit_url": reverse("admin_promotions_edit", args=[p.pk]),
                "delete_url": reverse("admin_promotions_edit", args=[p.pk]),
            }
            for p in ctx["object_list"]
        ]
        return ctx


class AdminPromotionEditView(SuperuserRequiredMixin, UpdateView):
    model = Promotion
    form_class = AdminPromotionForm
    template_name = "admin/form.html"
    success_url = reverse_lazy("admin_promotions_list")

    def get_queryset(self):
        return Promotion.all_objects.all()

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        ctx["page_title"] = f"Edit Promotion: {self.object.name}"
        ctx["icon"] = "edit"
        ctx["cancel_url"] = reverse("admin_promotions_list")
        return ctx

    def form_valid(self, form):
        form.save()
        messages.success(self.request, f"Promotion {self.object.name} updated.")
        return redirect(self.success_url)
