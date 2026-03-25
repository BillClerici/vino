from django.contrib import admin, messages

from .fcm import send_fcm_message
from .models import DeviceToken, Notification, NotificationPreference


@admin.register(DeviceToken)
class DeviceTokenAdmin(admin.ModelAdmin):
    list_display = ("user", "device_type", "is_active", "created_at")
    list_filter = ("device_type", "is_active")
    search_fields = ("user__email",)
    actions = ["send_test_push"]

    @admin.action(description="Send test push notification")
    def send_test_push(self, request, queryset):
        sent, failed = 0, 0
        for dt in queryset.filter(is_active=True):
            ok = send_fcm_message(
                token=dt.token,
                title="Vino Test",
                body="Push notifications are working!",
                data={"type": "general", "route": "/notifications"},
            )
            if ok:
                Notification.objects.create(
                    user=dt.user,
                    notification_type="general",
                    title="Vino Test",
                    body="Push notifications are working!",
                    data={"type": "general", "route": "/notifications"},
                )
                sent += 1
            else:
                failed += 1

        messages.success(request, f"Sent {sent} push(es), {failed} failed.")


@admin.register(Notification)
class NotificationAdmin(admin.ModelAdmin):
    list_display = ("user", "notification_type", "title", "is_read", "created_at")
    list_filter = ("notification_type", "is_read")
    search_fields = ("user__email", "title")


@admin.register(NotificationPreference)
class NotificationPreferenceAdmin(admin.ModelAdmin):
    list_display = ("user",)
    search_fields = ("user__email",)
