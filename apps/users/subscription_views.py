"""
Stripe subscription management views.
Uses Stripe Checkout (hosted) for the payment flow.
"""

import json
import logging

import stripe
from django.conf import settings
from django.contrib.auth.mixins import LoginRequiredMixin
from django.http import HttpResponse, JsonResponse
from django.shortcuts import redirect, render
from django.utils.decorators import method_decorator
from django.views import View
from django.views.decorators.csrf import csrf_exempt

logger = logging.getLogger(__name__)


def _get_stripe():
    stripe.api_key = settings.STRIPE_SECRET_KEY
    return stripe


class PricingView(LoginRequiredMixin, View):
    """Display pricing page with plan options. Syncs from Stripe on each load."""

    def get(self, request):
        user = request.user

        # Sync subscription state from Stripe if user has a customer ID
        if user.stripe_customer_id:
            try:
                s = _get_stripe()
                subs = stripe.Subscription.list(
                    customer=user.stripe_customer_id, status="active", limit=5
                )
                if subs.data:
                    latest = sorted(subs.data, key=lambda s: s.created, reverse=True)[0]
                    price_id = latest["items"]["data"][0]["price"]["id"]
                    plan = ""
                    if price_id == settings.STRIPE_MONTHLY_PRICE_ID:
                        plan = "monthly"
                    elif price_id == settings.STRIPE_YEARLY_PRICE_ID:
                        plan = "yearly"

                    changed = False
                    if user.stripe_subscription_id != latest.id:
                        user.stripe_subscription_id = latest.id
                        changed = True
                    if user.subscription_status != latest.status:
                        user.subscription_status = latest.status
                        changed = True
                    if user.subscription_plan != plan:
                        user.subscription_plan = plan
                        changed = True
                    if changed:
                        user.save(update_fields=[
                            "stripe_subscription_id", "subscription_status",
                            "subscription_plan", "updated_at",
                        ])
                elif user.subscription_status == "active":
                    # No active subs in Stripe but DB says active — mark as canceled
                    user.subscription_status = "canceled"
                    user.subscription_plan = ""
                    user.save(update_fields=["subscription_status", "subscription_plan", "updated_at"])
            except Exception as e:
                logger.warning("Failed to sync subscription from Stripe: %s", e)

        return render(request, "subscription/pricing.html", {
            "stripe_publishable_key": settings.STRIPE_PUBLISHABLE_KEY,
            "user": user,
        })


class CreateCheckoutSessionView(LoginRequiredMixin, View):
    """Create a Stripe Checkout Session and redirect."""

    def post(self, request):
        s = _get_stripe()
        user = request.user

        try:
            body = json.loads(request.body)
        except (ValueError, TypeError):
            return JsonResponse({"error": "Invalid request"}, status=400)

        plan = body.get("plan")
        if plan == "monthly":
            price_id = settings.STRIPE_MONTHLY_PRICE_ID
        elif plan == "yearly":
            price_id = settings.STRIPE_YEARLY_PRICE_ID
        else:
            return JsonResponse({"error": "Invalid plan"}, status=400)

        if not price_id:
            return JsonResponse({"error": "Price not configured"}, status=400)

        # Create or retrieve Stripe customer
        if not user.stripe_customer_id:
            customer = stripe.Customer.create(
                email=user.email,
                name=user.full_name,
                metadata={"user_id": str(user.pk)},
            )
            user.stripe_customer_id = customer.id
            user.save(update_fields=["stripe_customer_id", "updated_at"])
        else:
            customer = stripe.Customer.retrieve(user.stripe_customer_id)

        # Build checkout session
        checkout_params = {
            "customer": user.stripe_customer_id,
            "payment_method_types": ["card"],
            "line_items": [{"price": price_id, "quantity": 1}],
            "mode": "subscription",
            "success_url": request.build_absolute_uri("/subscription/success/?session_id={CHECKOUT_SESSION_ID}"),
            "cancel_url": request.build_absolute_uri("/subscription/pricing/"),
            "metadata": {"user_id": str(user.pk), "plan": plan},
        }

        # Add trial if user is still in trial period
        if user.subscription_status == "trialing" and user.trial_days_remaining > 0:
            checkout_params["subscription_data"] = {
                "trial_period_days": user.trial_days_remaining,
            }

        session = stripe.checkout.Session.create(**checkout_params)
        return JsonResponse({"url": session.url})


class CheckoutSuccessView(LoginRequiredMixin, View):
    """Handle successful checkout redirect."""

    def get(self, request):
        s = _get_stripe()
        session_id = request.GET.get("session_id")
        if session_id:
            try:
                session = stripe.checkout.Session.retrieve(session_id, expand=["subscription"])
                subscription = session.subscription

                user = request.user
                user.stripe_subscription_id = subscription.id
                user.subscription_status = subscription.status

                # Get plan from metadata or detect from price
                plan = session.metadata.get("plan", "")
                if not plan and subscription.get("items"):
                    price_id = subscription["items"]["data"][0]["price"]["id"]
                    if price_id == settings.STRIPE_MONTHLY_PRICE_ID:
                        plan = "monthly"
                    elif price_id == settings.STRIPE_YEARLY_PRICE_ID:
                        plan = "yearly"
                user.subscription_plan = plan

                if subscription.get("trial_end"):
                    from datetime import datetime, timezone as tz
                    user.trial_end = datetime.fromtimestamp(subscription["trial_end"], tz=tz.utc)

                user.save(update_fields=[
                    "stripe_subscription_id", "subscription_status",
                    "subscription_plan", "trial_end", "updated_at",
                ])
                logger.info("Checkout success for %s: plan=%s status=%s", user.email, plan, subscription.status)
            except Exception as e:
                logger.error("Error retrieving checkout session: %s", e)

        return render(request, "subscription/success.html")


class CustomerPortalView(LoginRequiredMixin, View):
    """Redirect to Stripe Customer Portal for managing subscription."""

    def post(self, request):
        s = _get_stripe()
        user = request.user

        if not user.stripe_customer_id:
            return redirect("pricing")

        portal_session = stripe.billing_portal.Session.create(
            customer=user.stripe_customer_id,
            return_url=request.build_absolute_uri("/subscription/pricing/"),
        )
        return redirect(portal_session.url)


@method_decorator(csrf_exempt, name="dispatch")
class StripeWebhookView(View):
    """Handle Stripe webhook events for subscription lifecycle."""

    def post(self, request):
        s = _get_stripe()
        payload = request.body
        sig_header = request.META.get("HTTP_STRIPE_SIGNATURE", "")
        webhook_secret = settings.STRIPE_WEBHOOK_SECRET

        try:
            if webhook_secret:
                event = stripe.Webhook.construct_event(payload, sig_header, webhook_secret)
            else:
                event = json.loads(payload)
        except (ValueError, stripe.error.SignatureVerificationError) as e:
            logger.warning("Webhook signature verification failed: %s", e)
            return HttpResponse(status=400)

        event_type = event.get("type", "")
        data = event.get("data", {}).get("object", {})

        logger.info("Stripe webhook: %s", event_type)

        from apps.users.models import User

        if event_type in (
            "customer.subscription.created",
            "customer.subscription.updated",
        ):
            self._handle_subscription_update(data)
        elif event_type == "customer.subscription.deleted":
            self._handle_subscription_deleted(data)
        elif event_type == "invoice.payment_failed":
            self._handle_payment_failed(data)

        return HttpResponse(status=200)

    def _handle_subscription_update(self, subscription):
        from apps.users.models import User

        customer_id = subscription.get("customer")

        # Check if this is a partner subscription
        from apps.partners.models import Partner
        if Partner.objects.filter(stripe_customer_id=customer_id).exists():
            from apps.partners.subscription_views import handle_partner_subscription_webhook
            handle_partner_subscription_webhook("customer.subscription.updated", subscription)
            return

        try:
            user = User.objects.get(stripe_customer_id=customer_id)
        except User.DoesNotExist:
            logger.warning("No user found for customer %s", customer_id)
            return

        user.stripe_subscription_id = subscription.get("id", "")
        user.subscription_status = subscription.get("status", "")

        # Update plan from price
        items = subscription.get("items", {}).get("data", [])
        if items:
            price_id = items[0].get("price", {}).get("id", "")
            if price_id == settings.STRIPE_MONTHLY_PRICE_ID:
                user.subscription_plan = "monthly"
            elif price_id == settings.STRIPE_YEARLY_PRICE_ID:
                user.subscription_plan = "yearly"

        trial_end = subscription.get("trial_end")
        if trial_end:
            from datetime import datetime, timezone
            user.trial_end = datetime.fromtimestamp(trial_end, tz=timezone.utc)

        user.save(update_fields=[
            "stripe_subscription_id", "subscription_status",
            "subscription_plan", "trial_end", "updated_at",
        ])
        logger.info("Updated subscription for %s: %s", user.email, user.subscription_status)

    def _handle_subscription_deleted(self, subscription):
        from apps.users.models import User

        customer_id = subscription.get("customer")

        # Check if this is a partner subscription
        from apps.partners.models import Partner
        if Partner.objects.filter(stripe_customer_id=customer_id).exists():
            from apps.partners.subscription_views import handle_partner_subscription_webhook
            handle_partner_subscription_webhook("customer.subscription.deleted", subscription)
            return

        try:
            user = User.objects.get(stripe_customer_id=customer_id)
            user.subscription_status = "canceled"
            user.save(update_fields=["subscription_status", "updated_at"])
            logger.info("Subscription canceled for %s", user.email)
        except User.DoesNotExist:
            pass

    def _handle_payment_failed(self, invoice):
        from apps.users.models import User

        customer_id = invoice.get("customer")
        try:
            user = User.objects.get(stripe_customer_id=customer_id)
            user.subscription_status = "past_due"
            user.save(update_fields=["subscription_status", "updated_at"])
            logger.info("Payment failed for %s", user.email)
        except User.DoesNotExist:
            pass
