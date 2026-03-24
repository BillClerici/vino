"""Celery tasks for sending push notifications."""

import logging
from datetime import timedelta

from celery import shared_task
from django.utils import timezone

logger = logging.getLogger(__name__)


@shared_task(bind=True, max_retries=3, default_retry_delay=60)
def send_push_notification(self, user_id, title, body, data=None, notification_type="general"):
    """Send a push notification to a single user (all their devices)."""
    from .fcm import send_fcm_message
    from .models import DeviceToken, Notification, NotificationPreference

    # Check user preferences
    try:
        prefs = NotificationPreference.objects.get(user_id=user_id, is_active=True)
        if not getattr(prefs, notification_type, True):
            logger.info("User %s has %s notifications disabled, skipping", user_id, notification_type)
            return
    except NotificationPreference.DoesNotExist:
        pass  # No preferences = all enabled (defaults)

    # Create in-app notification record
    Notification.objects.create(
        user_id=user_id,
        notification_type=notification_type,
        title=title,
        body=body,
        data=data or {},
    )

    # Send to all active device tokens
    tokens = DeviceToken.objects.filter(user_id=user_id, is_active=True)
    stale_ids = []

    for device in tokens:
        success = send_fcm_message(
            token=device.token,
            title=title,
            body=body,
            data=data,
        )
        if not success:
            stale_ids.append(device.id)

    # Deactivate stale tokens
    if stale_ids:
        DeviceToken.objects.filter(id__in=stale_ids).update(is_active=False)
        logger.info("Deactivated %d stale FCM tokens for user %s", len(stale_ids), user_id)


@shared_task
def send_trip_reminders():
    """Send push notifications for trips happening tomorrow. Run daily via celery-beat."""
    from apps.trips.models import Trip

    tomorrow = timezone.now().date() + timedelta(days=1)
    trips = Trip.objects.filter(
        scheduled_date=tomorrow,
        status__in=[Trip.Status.PLANNING, Trip.Status.CONFIRMED],
        is_active=True,
    )

    count = 0
    for trip in trips:
        member_ids = trip.trip_members.filter(is_active=True).values_list("user_id", flat=True)
        for user_id in member_ids:
            if user_id:
                send_push_notification.delay(
                    user_id=str(user_id),
                    title="Trip Tomorrow!",
                    body=f'Your trip "{trip.name}" is tomorrow. Get excited!',
                    data={"type": "trip_reminder", "route": f"/trips/{trip.id}"},
                    notification_type="trip_reminder",
                )
                count += 1

    logger.info("Queued %d trip reminder notifications for %s", count, tomorrow)
