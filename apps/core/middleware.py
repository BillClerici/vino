import zoneinfo

from django.utils import timezone


class UserTimezoneMiddleware:
    """Activate the authenticated user's timezone for each request."""

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        if request.user.is_authenticated and getattr(request.user, "timezone", ""):
            try:
                tz = zoneinfo.ZoneInfo(request.user.timezone)
                timezone.activate(tz)
            except (KeyError, Exception):
                timezone.deactivate()
        else:
            timezone.deactivate()

        response = self.get_response(request)
        return response
