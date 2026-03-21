"""
Partner Stripe subscription views.
Separate from user subscriptions — Partners have their own Products/Prices in Stripe.
"""

import json
import logging

import stripe
from django.conf import settings
from django.contrib.auth.mixins import LoginRequiredMixin, UserPassesTestMixin
from django.http import JsonResponse
from django.shortcuts import get_object_or_404, redirect, render
from django.views import View

from apps.partners.models import Partner, PartnerOwner
from apps.partners.views import ApprovedPartnerRequiredMixin, _get_user_partner


class SuperuserRequiredMixin(LoginRequiredMixin, UserPassesTestMixin):
    def test_func(self):
        return self.request.user.is_superuser

logger = logging.getLogger(__name__)

# Map tier+billing to settings price IDs
PARTNER_PRICE_MAP = {
    "silver_monthly": "STRIPE_PARTNER_SILVER_MONTHLY_PRICE_ID",
    "silver_yearly": "STRIPE_PARTNER_SILVER_YEARLY_PRICE_ID",
    "gold_monthly": "STRIPE_PARTNER_GOLD_MONTHLY_PRICE_ID",
    "gold_yearly": "STRIPE_PARTNER_GOLD_YEARLY_PRICE_ID",
    "platinum_monthly": "STRIPE_PARTNER_PLATINUM_MONTHLY_PRICE_ID",
    "platinum_yearly": "STRIPE_PARTNER_PLATINUM_YEARLY_PRICE_ID",
}

# Reverse map: price_id -> (tier, billing_period)
def _build_reverse_price_map():
    result = {}
    for plan_key, setting_name in PARTNER_PRICE_MAP.items():
        price_id = getattr(settings, setting_name, "")
        if price_id:
            tier, period = plan_key.rsplit("_", 1)
            result[price_id] = (tier, period)
    return result


def _get_stripe():
    stripe.api_key = settings.STRIPE_SECRET_KEY
    return stripe


class PartnerPricingView(ApprovedPartnerRequiredMixin, View):
    """Display partner subscription pricing page."""

    def get(self, request):
        partner = _get_user_partner(request.user)

        # Sync from Stripe if customer exists
        if partner.stripe_customer_id:
            try:
                _get_stripe()
                subs = stripe.Subscription.list(
                    customer=partner.stripe_customer_id, status="active", limit=5
                )
                if subs.data:
                    latest = sorted(subs.data, key=lambda s: s.created, reverse=True)[0]
                    price_id = latest["items"]["data"][0]["price"]["id"]
                    reverse_map = _build_reverse_price_map()
                    tier, period = reverse_map.get(price_id, (partner.tier, ""))
                    plan = f"{tier}_{period}" if period else ""

                    changed = False
                    if partner.stripe_subscription_id != latest.id:
                        partner.stripe_subscription_id = latest.id
                        changed = True
                    if partner.subscription_status != latest.status:
                        partner.subscription_status = latest.status
                        changed = True
                    if partner.tier != tier:
                        partner.tier = tier
                        changed = True
                    if partner.subscription_plan != plan:
                        partner.subscription_plan = plan
                        changed = True
                    if changed:
                        partner.save(update_fields=[
                            "stripe_subscription_id", "subscription_status",
                            "tier", "subscription_plan", "updated_at",
                        ])
                elif partner.subscription_status == "active":
                    partner.subscription_status = "canceled"
                    partner.tier = Partner.Tier.FREE
                    partner.subscription_plan = ""
                    partner.save(update_fields=[
                        "subscription_status", "tier", "subscription_plan", "updated_at",
                    ])
            except Exception as e:
                logger.warning("Failed to sync partner subscription: %s", e)

        return render(request, "partners/pricing.html", {
            "partner": partner,
            "stripe_publishable_key": settings.STRIPE_PUBLISHABLE_KEY,
        })


class PartnerCheckoutView(ApprovedPartnerRequiredMixin, View):
    """Create a Stripe Checkout Session for a partner subscription."""

    def post(self, request):
        _get_stripe()
        partner = _get_user_partner(request.user)

        try:
            body = json.loads(request.body)
        except (ValueError, TypeError):
            return JsonResponse({"error": "Invalid request"}, status=400)

        plan = body.get("plan")  # e.g. "gold_monthly"
        setting_name = PARTNER_PRICE_MAP.get(plan)
        if not setting_name:
            return JsonResponse({"error": "Invalid plan"}, status=400)

        price_id = getattr(settings, setting_name, "")
        if not price_id:
            return JsonResponse({"error": "Price not configured for this plan"}, status=400)

        # Create or retrieve Stripe customer for the partner
        if not partner.stripe_customer_id:
            customer = stripe.Customer.create(
                email=partner.business_email or request.user.email,
                name=partner.business_name,
                metadata={"partner_id": str(partner.pk), "type": "partner"},
            )
            partner.stripe_customer_id = customer.id
            partner.save(update_fields=["stripe_customer_id", "updated_at"])

        session = stripe.checkout.Session.create(
            customer=partner.stripe_customer_id,
            payment_method_types=["card"],
            line_items=[{"price": price_id, "quantity": 1}],
            mode="subscription",
            success_url=request.build_absolute_uri(
                f"/partners/subscription/success/?session_id={{CHECKOUT_SESSION_ID}}"
            ),
            cancel_url=request.build_absolute_uri("/partners/subscription/"),
            metadata={"partner_id": str(partner.pk), "plan": plan, "type": "partner"},
        )
        return JsonResponse({"url": session.url})


class PartnerCheckoutSuccessView(ApprovedPartnerRequiredMixin, View):
    """Handle successful partner checkout redirect."""

    def get(self, request):
        _get_stripe()
        partner = _get_user_partner(request.user)
        session_id = request.GET.get("session_id")

        if session_id:
            try:
                session = stripe.checkout.Session.retrieve(session_id, expand=["subscription"])
                subscription = session.subscription

                partner.stripe_subscription_id = subscription.id
                partner.subscription_status = subscription.status

                plan = session.metadata.get("plan", "")
                if plan:
                    tier = plan.rsplit("_", 1)[0]
                    partner.tier = tier
                    partner.subscription_plan = plan

                partner.save(update_fields=[
                    "stripe_subscription_id", "subscription_status",
                    "tier", "subscription_plan", "updated_at",
                ])
                logger.info("Partner checkout success: %s plan=%s", partner.business_name, plan)
            except Exception as e:
                logger.error("Error retrieving partner checkout session: %s", e)

        return render(request, "partners/subscription_success.html", {"partner": partner})


class PartnerPortalView(ApprovedPartnerRequiredMixin, View):
    """Redirect to Stripe Customer Portal for managing partner subscription."""

    def post(self, request):
        _get_stripe()
        partner = _get_user_partner(request.user)

        if not partner.stripe_customer_id:
            return redirect("partner_pricing")

        portal_session = stripe.billing_portal.Session.create(
            customer=partner.stripe_customer_id,
            return_url=request.build_absolute_uri("/partners/subscription/"),
        )
        return redirect(portal_session.url)


def handle_partner_subscription_webhook(event_type, data):
    """Called from the main Stripe webhook when customer is a partner."""
    customer_id = data.get("customer")
    if not customer_id:
        return

    try:
        partner = Partner.objects.get(stripe_customer_id=customer_id)
    except Partner.DoesNotExist:
        return

    if event_type in ("customer.subscription.created", "customer.subscription.updated"):
        partner.stripe_subscription_id = data.get("id", "")
        partner.subscription_status = data.get("status", "")

        items = data.get("items", {}).get("data", [])
        if items:
            price_id = items[0].get("price", {}).get("id", "")
            reverse_map = _build_reverse_price_map()
            tier, period = reverse_map.get(price_id, (partner.tier, ""))
            partner.tier = tier
            partner.subscription_plan = f"{tier}_{period}" if period else ""

        partner.save(update_fields=[
            "stripe_subscription_id", "subscription_status",
            "tier", "subscription_plan", "updated_at",
        ])
        logger.info("Partner sub updated: %s -> %s (%s)", partner.business_name, partner.tier, partner.subscription_status)

    elif event_type == "customer.subscription.deleted":
        partner.subscription_status = "canceled"
        partner.tier = Partner.Tier.FREE
        partner.subscription_plan = ""
        partner.save(update_fields=[
            "subscription_status", "tier", "subscription_plan", "updated_at",
        ])
        logger.info("Partner sub canceled: %s", partner.business_name)


# ── Admin Subscription Views ──


class AdminPartnerSubscriptionView(SuperuserRequiredMixin, View):
    """Admin page to manage a partner's subscription."""

    def get(self, request, pk):
        partner = get_object_or_404(Partner.all_objects, pk=pk)
        owners_count = partner.partner_owners.filter(is_active=True).count()
        claims_count = partner.claims.filter(is_active=True).count()
        promos_count = partner.promotions.filter(is_active=True).count()
        return render(request, "partners/admin_partner_subscription.html", {
            "partner": partner,
            "stripe_publishable_key": settings.STRIPE_PUBLISHABLE_KEY,
            "active_tab": "subscription",
            "owners_count": owners_count,
            "claims_count": claims_count,
            "promos_count": promos_count,
        })


class AdminPartnerCheckoutView(SuperuserRequiredMixin, View):
    """Admin: create Stripe Checkout for a partner subscription."""

    def post(self, request, pk):
        _get_stripe()
        partner = get_object_or_404(Partner.all_objects, pk=pk)

        try:
            body = json.loads(request.body)
        except (ValueError, TypeError):
            return JsonResponse({"error": "Invalid request"}, status=400)

        plan = body.get("plan")
        setting_name = PARTNER_PRICE_MAP.get(plan)
        if not setting_name:
            return JsonResponse({"error": "Invalid plan"}, status=400)

        price_id = getattr(settings, setting_name, "")
        if not price_id:
            return JsonResponse({"error": "Price not configured. Run: manage.py setup_partner_stripe"}, status=400)

        if not partner.stripe_customer_id:
            customer = stripe.Customer.create(
                email=partner.business_email or request.user.email,
                name=partner.business_name,
                metadata={"partner_id": str(partner.pk), "type": "partner"},
            )
            partner.stripe_customer_id = customer.id
            partner.save(update_fields=["stripe_customer_id", "updated_at"])

        session = stripe.checkout.Session.create(
            customer=partner.stripe_customer_id,
            payment_method_types=["card"],
            line_items=[{"price": price_id, "quantity": 1}],
            mode="subscription",
            success_url=request.build_absolute_uri(
                f"/manage/partners/{partner.pk}/edit/"
            ),
            cancel_url=request.build_absolute_uri(
                f"/manage/partners/{partner.pk}/subscription/"
            ),
            metadata={"partner_id": str(partner.pk), "plan": plan, "type": "partner"},
        )
        return JsonResponse({"url": session.url})


class AdminPartnerStripePortalView(SuperuserRequiredMixin, View):
    """Admin: redirect to Stripe Customer Portal for a partner."""

    def post(self, request, pk):
        _get_stripe()
        partner = get_object_or_404(Partner.all_objects, pk=pk)

        if not partner.stripe_customer_id:
            return redirect("admin_partner_subscription", pk=pk)

        portal_session = stripe.billing_portal.Session.create(
            customer=partner.stripe_customer_id,
            return_url=request.build_absolute_uri(
                f"/manage/partners/{partner.pk}/subscription/"
            ),
        )
        return redirect(portal_session.url)
