from django.conf import settings
from django.db import models

from apps.core.models import BaseModel


class DeviceToken(BaseModel):
    """Stores FCM device tokens for push notifications."""

    class DeviceType(models.TextChoices):
        ANDROID = "android", "Android"
        IOS = "ios", "iOS"
        WEB = "web", "Web"

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="device_tokens",
    )
    token = models.TextField(unique=True)
    device_type = models.CharField(
        max_length=10,
        choices=DeviceType.choices,
        default=DeviceType.ANDROID,
    )

    class Meta:
        db_table = "notifications_devicetoken"

    def __str__(self):
        return f"{self.user} ({self.device_type})"


class Notification(BaseModel):
    """In-app + push notification record."""

    class NotificationType(models.TextChoices):
        TRIP_INVITE = "trip_invite", "Trip Invite"
        TRIP_REMINDER = "trip_reminder", "Trip Reminder"
        FRIEND_CHECKIN = "friend_checkin", "Friend Check-in"
        WISHLIST_MATCH = "wishlist_match", "Wishlist Match"
        BADGE_EARNED = "badge_earned", "Badge Earned"
        TRIP_STARTED = "trip_started", "Trip Started"
        GENERAL = "general", "General"

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="notifications",
    )
    notification_type = models.CharField(
        max_length=30,
        choices=NotificationType.choices,
        default=NotificationType.GENERAL,
    )
    title = models.CharField(max_length=255)
    body = models.TextField()
    data = models.JSONField(default=dict, blank=True)
    is_read = models.BooleanField(default=False)
    read_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = "notifications_notification"
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.notification_type}: {self.title}"


class NotificationPreference(BaseModel):
    """Per-user notification toggles."""

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="notification_preferences",
    )
    trip_invite = models.BooleanField(default=True)
    trip_reminder = models.BooleanField(default=True)
    friend_checkin = models.BooleanField(default=True)
    wishlist_match = models.BooleanField(default=True)
    badge_earned = models.BooleanField(default=True)
    trip_started = models.BooleanField(default=True)
    general = models.BooleanField(default=True)

    class Meta:
        db_table = "notifications_preference"

    def __str__(self):
        return f"Prefs: {self.user}"
