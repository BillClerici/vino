"""Django signals that trigger push notifications."""

import logging

from django.db.models.signals import post_save
from django.dispatch import receiver

logger = logging.getLogger(__name__)


@receiver(post_save, sender="trips.TripMember")
def notify_trip_invite(sender, instance, created, **kwargs):
    """Notify a user when they're added to a trip."""
    if not created:
        return
    # Don't notify the organizer about their own trip
    if hasattr(instance, "role") and instance.role == "organizer":
        return
    if not instance.user_id:
        return

    from .tasks import send_push_notification

    trip_name = instance.trip.name if instance.trip else "a trip"
    send_push_notification.delay(
        user_id=str(instance.user_id),
        title="Trip Invitation",
        body=f'You\'ve been invited to "{trip_name}"!',
        data={"type": "trip_invite", "route": f"/trips/{instance.trip_id}"},
        notification_type="trip_invite",
    )


@receiver(post_save, sender="visits.VisitLog")
def notify_friends_of_checkin(sender, instance, created, **kwargs):
    """Notify trip companions when someone checks in."""
    if not created:
        return
    if not instance.user_id or not instance.place_id:
        return

    from apps.trips.models import TripMember

    from .tasks import send_push_notification

    # Find users who share any trip with this user
    friend_ids = (
        TripMember.objects.filter(
            trip__trip_members__user_id=instance.user_id,
            is_active=True,
        )
        .exclude(user_id=instance.user_id)
        .values_list("user_id", flat=True)
        .distinct()
    )

    user_name = instance.user.first_name or "A friend"
    place_name = instance.place.name if instance.place else "a spot"

    for friend_id in friend_ids:
        if friend_id:
            send_push_notification.delay(
                user_id=str(friend_id),
                title="Friend Checked In!",
                body=f"{user_name} just checked in at {place_name}",
                data={"type": "friend_checkin", "route": f"/visits/{instance.id}"},
                notification_type="friend_checkin",
            )
