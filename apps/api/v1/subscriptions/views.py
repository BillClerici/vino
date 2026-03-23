import logging

import stripe
from django.conf import settings
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from ..permissions import HasActiveSubscription
from .serializers import CheckoutRequestSerializer

logger = logging.getLogger(__name__)


def _get_stripe():
    stripe.api_key = settings.STRIPE_SECRET_KEY
    return stripe


class SubscriptionStatusView(APIView):
    """GET /api/v1/subscription/status/ — Current subscription info."""

    def get(self, request):
        user = request.user
        data = {
            "subscription_status": user.subscription_status,
            "subscription_plan": user.subscription_plan,
            "has_active_subscription": user.has_active_subscription,
            "is_in_trial": user.is_in_trial,
            "trial_days_remaining": user.trial_days_remaining,
            "stripe_customer_id": user.stripe_customer_id or "",
        }
        return Response(data)


class CreateMobileCheckoutView(APIView):
    """POST /api/v1/subscription/checkout/ — Create Stripe Checkout session."""

    permission_classes = [HasActiveSubscription]

    def post(self, request):
        serializer = CheckoutRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        s = _get_stripe()
        user = request.user

        plan = data["plan"]
        if plan == "monthly":
            price_id = settings.STRIPE_MONTHLY_PRICE_ID
        else:
            price_id = settings.STRIPE_YEARLY_PRICE_ID

        if not price_id:
            return Response(
                {"detail": "Price not configured."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Create or retrieve Stripe customer
        if not user.stripe_customer_id:
            customer = stripe.Customer.create(
                email=user.email,
                name=user.full_name,
                metadata={"user_id": str(user.pk)},
            )
            user.stripe_customer_id = customer.id
            user.save(update_fields=["stripe_customer_id", "updated_at"])

        success_url = data.get("success_url") or request.build_absolute_uri(
            "/subscription/success/?session_id={CHECKOUT_SESSION_ID}"
        )
        cancel_url = data.get("cancel_url") or request.build_absolute_uri(
            "/subscription/pricing/"
        )

        checkout_params = {
            "customer": user.stripe_customer_id,
            "payment_method_types": ["card"],
            "line_items": [{"price": price_id, "quantity": 1}],
            "mode": "subscription",
            "success_url": success_url,
            "cancel_url": cancel_url,
            "metadata": {"user_id": str(user.pk), "plan": plan},
        }

        if user.subscription_status == "trialing" and user.trial_days_remaining > 0:
            checkout_params["subscription_data"] = {
                "trial_period_days": user.trial_days_remaining,
            }

        try:
            session = stripe.checkout.Session.create(**checkout_params)
            return Response({"checkout_url": session.url})
        except Exception:
            logger.exception("Stripe checkout creation failed")
            return Response(
                {"detail": "Failed to create checkout session."},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )


class CustomerPortalURLView(APIView):
    """POST /api/v1/subscription/portal/ — Get Stripe Customer Portal URL."""

    def post(self, request):
        s = _get_stripe()
        user = request.user

        if not user.stripe_customer_id:
            return Response(
                {"detail": "No Stripe customer found."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        return_url = request.data.get("return_url") or request.build_absolute_uri(
            "/subscription/pricing/"
        )

        try:
            portal = stripe.billing_portal.Session.create(
                customer=user.stripe_customer_id,
                return_url=return_url,
            )
            return Response({"portal_url": portal.url})
        except Exception:
            logger.exception("Stripe portal creation failed")
            return Response(
                {"detail": "Failed to create portal session."},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )
