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

User = get_user_model()


# ── Mixins ──


class ApprovedPartnerRequiredMixin(LoginRequiredMixin):
    """Requires user to be logged in and have an approved partner profile."""

    def dispatch(self, request, *args, **kwargs):
        if not request.user.is_authenticated:
            return self.handle_no_permission()
        partner = getattr(request.user, "partner_profile", None)
        if not partner or partner.status != Partner.Status.APPROVED:
            messages.warning(request, "You need an approved partner account to access this page.")
            return redirect("partner_apply")
        return super().dispatch(request, *args, **kwargs)

    def get_partner(self):
        return self.request.user.partner_profile


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
        # If already a partner, redirect to dashboard
        partner = getattr(request.user, "partner_profile", None)
        if partner:
            if partner.status == Partner.Status.APPROVED:
                return redirect("partner_dashboard")
            return render(request, self.template_name, {"form": None, "partner": partner})
        form = PartnerApplyForm()
        return render(request, self.template_name, {"form": form, "partner": None})

    def post(self, request):
        partner = getattr(request.user, "partner_profile", None)
        if partner:
            messages.info(request, "You have already applied for a partner account.")
            return redirect("partner_apply")
        form = PartnerApplyForm(request.POST)
        if form.is_valid():
            partner = form.save(commit=False)
            partner.user = request.user
            partner.status = Partner.Status.PENDING
            partner.save()
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
        return Partner.all_objects.select_related("user", "tier").order_by("-created_at")

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        ctx["page_title"] = "Partners"
        ctx["icon"] = "handshake"
        ctx["create_url"] = reverse("admin_partners_create")
        ctx["columns"] = ["Business Name", "User", "Tier", "Status", "Created"]
        ctx["rows"] = [
            {
                "values": [
                    p.business_name,
                    p.user.email,
                    p.tier.label if p.tier else "—",
                    p.get_status_display(),
                    p.created_at.strftime("%Y-%m-%d"),
                ],
                "edit_url": reverse("admin_partners_edit", args=[p.pk]),
                "delete_url": reverse("admin_partners_edit", args=[p.pk]),
            }
            for p in ctx["object_list"]
        ]
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
        messages.success(self.request, f'Partner "{partner.business_name}" created!')
        return redirect(self.success_url)


class AdminPartnerEditView(SuperuserRequiredMixin, UpdateView):
    model = Partner
    form_class = AdminPartnerForm
    template_name = "admin/form.html"
    success_url = reverse_lazy("admin_partners_list")

    def get_queryset(self):
        return Partner.all_objects.all()

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        ctx["page_title"] = f"Edit Partner: {self.object.business_name}"
        ctx["icon"] = "edit"
        ctx["cancel_url"] = reverse("admin_partners_list")
        return ctx

    def form_valid(self, form):
        partner = form.save(commit=False)
        # If status changed to approved, record who approved and when
        if partner.status == Partner.Status.APPROVED and not partner.approved_at:
            partner.approved_at = timezone.now()
            partner.approved_by = self.request.user
        partner.save()
        messages.success(self.request, f"Partner {partner.business_name} updated.")
        return redirect(self.success_url)


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
        return Promotion.all_objects.select_related("partner", "place").order_by("-created_at")

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
                    p.get_promotion_type_display(),
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
