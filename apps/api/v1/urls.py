from django.urls import path
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.routers import DefaultRouter

from .auth.views import dev_login, mobile_google_auth, mobile_microsoft_auth
from .dashboard.views import DashboardView
from .lookups.views import LookupValueViewSet
from .palate.views import PalateProfileView
from .places.views import MenuItemViewSet, PlaceViewSet
from .subscriptions.views import (
    CreateMobileCheckoutView,
    CustomerPortalURLView,
    SubscriptionStatusView,
)
from .trips.views import TripViewSet
from .users.views import UserProfileViewSet
from .visits.views import VisitLogViewSet

router = DefaultRouter()
router.register(r"places", PlaceViewSet, basename="place")
router.register(r"visits", VisitLogViewSet, basename="visit")
router.register(r"trips", TripViewSet, basename="trip")
router.register(r"lookups", LookupValueViewSet, basename="lookup")


@api_view(["GET"])
@permission_classes([AllowAny])
def image_proxy(request):
    """Proxy external images to avoid CORS issues on web."""
    import httpx
    from django.http import HttpResponse

    url = request.query_params.get("url", "")
    if not url or not url.startswith("http"):
        return Response({"detail": "url parameter required"}, status=400)

    try:
        with httpx.Client(timeout=10, follow_redirects=True) as client:
            resp = client.get(url)
            resp.raise_for_status()
            content_type = resp.headers.get("content-type", "image/jpeg")
            return HttpResponse(
                resp.content,
                content_type=content_type,
                headers={"Cache-Control": "public, max-age=86400"},
            )
    except Exception:
        return Response({"detail": "Failed to fetch image"}, status=502)


@api_view(["GET"])
def distance_matrix(request):
    """Calculate driving distance and duration using Google Routes API."""
    import httpx
    from django.conf import settings

    origins = request.query_params.get("origins", "")
    destinations = request.query_params.get("destinations", "")
    if not origins or not destinations:
        return Response({"detail": "origins and destinations required"}, status=400)

    api_key = settings.GOOGLE_MAPS_API_KEY
    if not api_key:
        return Response({"detail": "No Google Maps API key configured"}, status=500)

    try:
        origin_parts = origins.split(",")
        dest_parts = destinations.split(",")

        # Try Routes API (New) first
        with httpx.Client(timeout=15) as client:
            resp = client.post(
                "https://routes.googleapis.com/directions/v2:computeRoutes",
                headers={
                    "Content-Type": "application/json",
                    "X-Goog-Api-Key": api_key,
                    "X-Goog-FieldMask": "routes.duration,routes.distanceMeters",
                },
                json={
                    "origin": {
                        "location": {
                            "latLng": {
                                "latitude": float(origin_parts[0]),
                                "longitude": float(origin_parts[1]),
                            }
                        }
                    },
                    "destination": {
                        "location": {
                            "latLng": {
                                "latitude": float(dest_parts[0]),
                                "longitude": float(dest_parts[1]),
                            }
                        }
                    },
                    "travelMode": "DRIVE",
                    "units": "IMPERIAL",
                },
            )
            resp.raise_for_status()
            data = resp.json()

            routes = data.get("routes", [])
            if routes:
                route = routes[0]
                duration_str = route.get("duration", "0s")
                # Duration comes as "1234s" string
                duration_sec = int(duration_str.replace("s", ""))
                distance_meters = route.get("distanceMeters", 0)
                drive_min = round(duration_sec / 60)
                miles = round(distance_meters / 1609.34, 1)

                return Response({
                    "drive_minutes": drive_min,
                    "miles": miles,
                    "duration_seconds": duration_sec,
                    "distance_meters": distance_meters,
                })

        return Response({"detail": "No route found"}, status=404)
    except Exception as e:
        import logging
        logging.getLogger(__name__).exception("Distance calculation failed")
        return Response({"detail": f"Failed to calculate distance: {e}"}, status=502)


@api_view(["GET"])
@permission_classes([AllowAny])
def config_view(request):
    """App config and feature flags for mobile client."""
    from django.conf import settings
    return Response({
        "minimum_app_version": "1.0.0",
        "features": {
            "live_trip": True,
            "ai_palate": True,
            "push_notifications": False,
        },
        "maintenance_mode": False,
        "google_maps_api_key": settings.GOOGLE_MAPS_API_KEY,
    })


urlpatterns = [
    # Auth
    path("auth/dev-login/", dev_login, name="dev_login"),
    path("auth/mobile/google/", mobile_google_auth, name="mobile_google_auth"),
    path("auth/mobile/microsoft/", mobile_microsoft_auth, name="mobile_microsoft_auth"),

    # User profile (singleton)
    path("me/", UserProfileViewSet.as_view({"get": "retrieve", "patch": "partial_update"}), name="user_profile"),
    path("me/stats/", UserProfileViewSet.as_view({"get": "stats"}), name="user_stats"),

    # Dashboard
    path("dashboard/", DashboardView.as_view(), name="dashboard"),

    # Palate
    path("palate/", PalateProfileView.as_view(), name="palate_profile"),

    # Subscriptions
    path("subscription/status/", SubscriptionStatusView.as_view(), name="subscription_status"),
    path("subscription/checkout/", CreateMobileCheckoutView.as_view(), name="subscription_checkout"),
    path("subscription/portal/", CustomerPortalURLView.as_view(), name="subscription_portal"),

    # Proxies (for CORS on web)
    path("image-proxy/", image_proxy, name="image_proxy"),
    path("distance-matrix/", distance_matrix, name="distance_matrix"),

    # Menu items (nested under places)
    path(
        "places/<uuid:place_pk>/menu/",
        MenuItemViewSet.as_view({"get": "list", "post": "create"}),
        name="place_menu_list",
    ),
    path(
        "places/<uuid:place_pk>/menu/<uuid:pk>/",
        MenuItemViewSet.as_view({"get": "retrieve", "put": "update", "delete": "destroy"}),
        name="place_menu_detail",
    ),

    # Config / feature flags
    path("config/", config_view, name="app_config"),
]

urlpatterns += router.urls
