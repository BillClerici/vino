from django.utils import timezone
from rest_framework import serializers, status
from rest_framework.decorators import action
from rest_framework.permissions import IsAdminUser, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.viewsets import ReadOnlyModelViewSet

from apps.notifications.fcm import send_fcm_message
from apps.notifications.models import DeviceToken, Notification, NotificationPreference


# ── Serializers ──────────────────────────────────────────────────

class DeviceTokenSerializer(serializers.Serializer):
    token = serializers.CharField()
    device_type = serializers.ChoiceField(
        choices=DeviceToken.DeviceType.choices,
        default=DeviceToken.DeviceType.ANDROID,
    )


class NotificationSerializer(serializers.ModelSerializer):
    class Meta:
        model = Notification
        fields = [
            "id", "notification_type", "title", "body",
            "data", "is_read", "read_at", "created_at",
        ]


class NotificationPreferenceSerializer(serializers.ModelSerializer):
    class Meta:
        model = NotificationPreference
        fields = [
            "trip_invite", "trip_reminder", "friend_checkin",
            "wishlist_match", "badge_earned", "trip_started", "general",
        ]


# ── Device Token Registration ───────────────────────────────────

class DeviceTokenRegisterView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        """Register or update an FCM device token."""
        ser = DeviceTokenSerializer(data=request.data)
        ser.is_valid(raise_exception=True)

        token_value = ser.validated_data["token"]
        device_type = ser.validated_data["device_type"]

        # If this token belongs to another user, reassign it
        DeviceToken.objects.filter(token=token_value).exclude(
            user=request.user
        ).update(is_active=False)

        # Create or reactivate for this user
        obj, created = DeviceToken.all_objects.update_or_create(
            token=token_value,
            defaults={
                "user": request.user,
                "device_type": device_type,
                "is_active": True,
            },
        )

        return Response(
            {"registered": True, "device_type": device_type},
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
        )


class DeviceTokenUnregisterView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        """Unregister an FCM device token (soft delete)."""
        token_value = request.data.get("token", "")
        if not token_value:
            return Response(
                {"detail": "token is required"},
                status=status.HTTP_400_BAD_REQUEST,
            )
        DeviceToken.objects.filter(
            token=token_value, user=request.user
        ).update(is_active=False)
        return Response(status=status.HTTP_204_NO_CONTENT)


# ── Notifications ────────────────────────────────────────────────

class NotificationViewSet(ReadOnlyModelViewSet):
    serializer_class = NotificationSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return Notification.objects.filter(user=self.request.user, is_active=True)

    def list(self, request, *args, **kwargs):
        qs = self.get_queryset()
        page = self.paginate_queryset(qs)
        if page is not None:
            serializer = self.get_serializer(page, many=True)
            return self.get_paginated_response(serializer.data)
        serializer = self.get_serializer(qs[:50], many=True)
        unread = qs.filter(is_read=False).count()
        return Response({
            "data": serializer.data,
            "unread_count": unread,
        })

    @action(detail=True, methods=["post"], url_path="mark-read")
    def mark_read(self, request, pk=None):
        notif = self.get_object()
        notif.is_read = True
        notif.read_at = timezone.now()
        notif.save(update_fields=["is_read", "read_at", "updated_at"])
        return Response({"success": True})

    @action(detail=False, methods=["post"], url_path="mark-all-read")
    def mark_all_read(self, request):
        count = self.get_queryset().filter(is_read=False).update(
            is_read=True, read_at=timezone.now()
        )
        return Response({"success": True, "count": count})


# ── Notification Preferences ─────────────────────────────────────

class NotificationPreferenceView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        prefs, _ = NotificationPreference.objects.get_or_create(user=request.user)
        ser = NotificationPreferenceSerializer(prefs)
        return Response(ser.data)

    def patch(self, request):
        prefs, _ = NotificationPreference.objects.get_or_create(user=request.user)
        ser = NotificationPreferenceSerializer(prefs, data=request.data, partial=True)
        ser.is_valid(raise_exception=True)
        ser.save()
        return Response(ser.data)


# ── Test Push (superuser only) ──────────────────────────────────

class TestPushView(APIView):
    permission_classes = []
    authentication_classes = []

    def get(self, request):
        """Send a test push to all registered devices. Requires secret key."""
        from django.conf import settings as django_settings

        key = request.query_params.get("key", "")
        if key != django_settings.SECRET_KEY[:12]:
            return Response(status=status.HTTP_403_FORBIDDEN)

        email = request.query_params.get("email", "")
        tokens = DeviceToken.objects.filter(is_active=True)
        if email:
            tokens = tokens.filter(user__email=email)

        if not tokens.exists():
            return Response(
                {"detail": "No registered device tokens"},
                status=status.HTTP_404_NOT_FOUND,
            )

        results = []
        for dt in tokens:
            ok = send_fcm_message(
                token=dt.token,
                title="Vino Test",
                body="Push notifications are working!",
                data={"type": "general", "route": "/notifications"},
            )
            results.append({
                "email": dt.user.email,
                "device_type": dt.device_type,
                "success": ok,
            })

            Notification.objects.create(
                user=dt.user,
                notification_type="general",
                title="Vino Test",
                body="Push notifications are working!",
                data={"type": "general", "route": "/notifications"},
            )

        return Response({"results": results})
