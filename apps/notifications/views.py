from django.contrib import messages
from django.contrib.auth.mixins import UserPassesTestMixin
from django.shortcuts import redirect
from django.views.generic import TemplateView

from apps.notifications.fcm import send_fcm_message
from apps.notifications.models import DeviceToken, Notification
from apps.users.models import User


class SendNotificationView(UserPassesTestMixin, TemplateView):
    template_name = "notifications/send_notification.html"

    def test_func(self):
        return self.request.user.is_superuser

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        ctx["users"] = User.objects.filter(is_active=True).order_by("email")
        ctx["users_with_devices"] = set(
            DeviceToken.objects.filter(is_active=True)
            .values_list("user_id", flat=True)
            .distinct()
        )
        ctx["recent_notifications"] = Notification.objects.select_related(
            "user"
        ).order_by("-created_at")[:20]
        return ctx

    def post(self, request, *args, **kwargs):
        user_id = request.POST.get("user_id", "")
        title = request.POST.get("title", "").strip()
        body = request.POST.get("body", "").strip()
        send_all = request.POST.get("send_all") == "1"

        if not title or not body:
            messages.error(request, "Title and body are required.")
            return redirect("admin_send_notification")

        if send_all:
            tokens = DeviceToken.objects.filter(is_active=True).select_related("user")
        elif user_id:
            tokens = DeviceToken.objects.filter(
                user_id=user_id, is_active=True
            ).select_related("user")
        else:
            messages.error(request, "Select a user or check 'Send to all'.")
            return redirect("admin_send_notification")

        sent, failed = 0, 0
        notified_users = set()
        for dt in tokens:
            try:
                ok = send_fcm_message(
                    token=dt.token,
                    title=title,
                    body=body,
                    data={"type": "general", "route": "/notifications"},
                )
            except Exception:
                ok = False
            if ok:
                sent += 1
            else:
                failed += 1
            # Always create in-app notification regardless of push result
            if dt.user_id not in notified_users:
                Notification.objects.create(
                    user=dt.user,
                    notification_type="general",
                    title=title,
                    body=body,
                    data={"type": "general", "route": "/notifications"},
                )
                notified_users.add(dt.user_id)
            else:
                failed += 1

        messages.success(
            request, f"Sent to {sent} device(s), {failed} failed, {len(notified_users)} user(s) notified."
        )
        return redirect("admin_send_notification")
