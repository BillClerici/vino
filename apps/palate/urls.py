from django.urls import path

from apps.palate.views import PalateView

urlpatterns = [
    path("", PalateView.as_view(), name="palate_profile"),
]
