from rest_framework import serializers


class SubscriptionStatusSerializer(serializers.Serializer):
    subscription_status = serializers.CharField()
    subscription_plan = serializers.CharField()
    has_active_subscription = serializers.BooleanField()
    is_in_trial = serializers.BooleanField()
    trial_days_remaining = serializers.IntegerField()
    stripe_customer_id = serializers.CharField()


class CheckoutRequestSerializer(serializers.Serializer):
    plan = serializers.ChoiceField(choices=["monthly", "yearly"])
    success_url = serializers.URLField(
        required=False,
        help_text="Mobile deep link URL for success redirect",
    )
    cancel_url = serializers.URLField(
        required=False,
        help_text="Mobile deep link URL for cancel redirect",
    )
