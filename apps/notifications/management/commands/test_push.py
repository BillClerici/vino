"""Send a test push notification to a user's registered devices."""

from django.core.management.base import BaseCommand

from apps.notifications.fcm import send_fcm_message
from apps.notifications.models import DeviceToken, Notification


class Command(BaseCommand):
    help = "Send a test push notification to a user"

    def add_arguments(self, parser):
        parser.add_argument("--email", type=str, help="User email to notify")

    def handle(self, *args, **options):
        email = options.get("email")

        tokens = DeviceToken.objects.filter(is_active=True)
        if email:
            tokens = tokens.filter(user__email=email)

        if not tokens.exists():
            self.stderr.write("No active device tokens found.")
            return

        for dt in tokens:
            self.stdout.write(
                f"Sending to {dt.user.email} ({dt.device_type}): {dt.token[:20]}..."
            )
            result = send_fcm_message(
                token=dt.token,
                title="Vino Test",
                body="Push notifications are working!",
                data={"type": "general", "route": "/notifications"},
            )
            status = "OK" if result else "FAILED (token invalid)"
            self.stdout.write(f"  -> {status}")

            # Also create an in-app notification
            Notification.objects.create(
                user=dt.user,
                notification_type="general",
                title="Vino Test",
                body="Push notifications are working!",
                data={"type": "general", "route": "/notifications"},
            )

        self.stdout.write(self.style.SUCCESS("Done."))
