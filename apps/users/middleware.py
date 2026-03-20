"""
Subscription middleware — redirects users without an active subscription
to the pricing page. Allows access to subscription, auth, and admin pages.
"""

from django.shortcuts import redirect
from django.urls import reverse


ALLOWED_PATHS = [
    "/subscription/",
    "/login/",
    "/logout/",
    "/register/",
    "/auth/",
    "/admin/",
    "/health/",
    "/profile/",
    "/api/",
    "/manage/",
    "/static/",
    "/partners/",
]


class SubscriptionRequiredMiddleware:
    """Redirect users without active subscription to pricing page."""

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        if request.user.is_authenticated and not request.user.is_superuser:
            # Check if the path is allowed without subscription
            path = request.path
            is_allowed = any(path.startswith(p) for p in ALLOWED_PATHS)

            if not is_allowed and not request.user.has_active_subscription:
                return redirect(reverse("pricing"))

        return self.get_response(request)
