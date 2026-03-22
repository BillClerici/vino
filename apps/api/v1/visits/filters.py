from django.db import models
from django_filters import rest_framework as filters

from apps.visits.models import VisitLog


class VisitLogFilter(filters.FilterSet):
    q = filters.CharFilter(method="search")
    place = filters.UUIDFilter(field_name="place_id")
    rating_min = filters.NumberFilter(field_name="rating_overall", lookup_expr="gte")
    rating_max = filters.NumberFilter(field_name="rating_overall", lookup_expr="lte")
    place_type = filters.CharFilter(field_name="place__place_type")
    date_from = filters.DateFilter(field_name="visited_at", lookup_expr="date__gte")
    date_to = filters.DateFilter(field_name="visited_at", lookup_expr="date__lte")

    class Meta:
        model = VisitLog
        fields = ["place", "place_type", "rating_min", "rating_max", "date_from", "date_to"]

    def search(self, queryset, name, value):
        return queryset.filter(
            models.Q(place__name__icontains=value)
            | models.Q(place__city__icontains=value)
            | models.Q(place__state__icontains=value)
            | models.Q(notes__icontains=value)
        )
