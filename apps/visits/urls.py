from django.urls import path

from apps.visits.views import CheckInView, VisitDetailView, VisitListView

urlpatterns = [
    path("", VisitListView.as_view(), name="visit_list"),
    path("checkin/", CheckInView.as_view(), name="checkin"),
    path("<uuid:pk>/", VisitDetailView.as_view(), name="visit_detail"),
]
