from rest_framework import permissions


class HasActiveSubscription(permissions.BasePermission):
    """Deny access if the user's subscription is not active (trial or paid)."""

    message = "Active subscription required."

    def has_permission(self, request, view):
        user = request.user
        if not user or not user.is_authenticated:
            return False
        return user.has_active_subscription


class IsOwnerOrReadOnly(permissions.BasePermission):
    """Object-level: allow write only if request.user owns the object."""

    def has_object_permission(self, request, view, obj):
        if request.method in permissions.SAFE_METHODS:
            return True
        # Check common ownership fields
        if hasattr(obj, "user_id"):
            return obj.user_id == request.user.pk
        if hasattr(obj, "created_by_id"):
            return obj.created_by_id == request.user.pk
        return False


class IsTripMemberOrReadOnly(permissions.BasePermission):
    """Object-level: allow write only if user is a member of the trip."""

    def has_object_permission(self, request, view, obj):
        if request.method in permissions.SAFE_METHODS:
            return True
        from apps.trips.models import Trip
        trip = obj if isinstance(obj, Trip) else getattr(obj, "trip", None)
        if trip is None:
            return False
        return trip.trip_members.filter(user=request.user, is_active=True).exists()
