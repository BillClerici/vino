from rest_framework import serializers

from apps.users.models import SocialAccount, User


class SocialAccountSerializer(serializers.ModelSerializer):
    class Meta:
        model = SocialAccount
        fields = ["id", "provider", "provider_uid", "created_at"]
        read_only_fields = fields


class UserSerializer(serializers.ModelSerializer):
    full_name = serializers.CharField(read_only=True)
    has_active_subscription = serializers.BooleanField(read_only=True)
    is_in_trial = serializers.BooleanField(read_only=True)
    trial_days_remaining = serializers.IntegerField(read_only=True)
    social_accounts = SocialAccountSerializer(many=True, read_only=True)

    class Meta:
        model = User
        fields = [
            "id", "email", "first_name", "last_name", "avatar_url",
            "full_name", "timezone", "subscription_status", "subscription_plan",
            "has_active_subscription", "is_in_trial", "trial_days_remaining",
            "onboarding_status", "social_accounts", "created_at",
        ]
        read_only_fields = [
            "id", "email", "subscription_status", "subscription_plan", "created_at",
        ]


class UserProfileUpdateSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ["first_name", "last_name", "avatar_url", "timezone", "onboarding_status"]


class UserSummarySerializer(serializers.ModelSerializer):
    """Minimal user info for embedding in other serializers."""
    full_name = serializers.CharField(read_only=True)

    class Meta:
        model = User
        fields = ["id", "email", "first_name", "last_name", "full_name", "avatar_url"]
        read_only_fields = fields
