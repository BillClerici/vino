from django.urls import path
from rest_framework.routers import DefaultRouter

from .views import (
    DeviceTokenRegisterView,
    DeviceTokenUnregisterView,
    NotificationPreferenceView,
    NotificationViewSet,
    TestPushView,
)

router = DefaultRouter()
router.register(r"", NotificationViewSet, basename="notification")

urlpatterns = [
    path("device/register/", DeviceTokenRegisterView.as_view(), name="device_register"),
    path("device/unregister/", DeviceTokenUnregisterView.as_view(), name="device_unregister"),
    path("preferences/", NotificationPreferenceView.as_view(), name="notification_preferences"),
    path("test-push/", TestPushView.as_view(), name="test_push"),
] + router.urls
