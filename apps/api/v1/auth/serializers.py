from rest_framework import serializers


class MobileGoogleAuthSerializer(serializers.Serializer):
    auth_code = serializers.CharField(help_text="Google OAuth2 authorization code from google_sign_in")


class MobileMicrosoftAuthSerializer(serializers.Serializer):
    auth_code = serializers.CharField(help_text="Microsoft OAuth2 authorization code")


class TokenResponseSerializer(serializers.Serializer):
    access_token = serializers.CharField()
    refresh_token = serializers.CharField()
