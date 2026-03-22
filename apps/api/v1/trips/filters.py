from django.db import models
from django_filters import rest_framework as filters

from apps.trips.models import Trip


class TripFilter(filters.FilterSet):
    q = filters.CharFilter(method="search")
    status = filters.ChoiceFilter(choices=Trip.Status.choices)
    date_from = filters.DateFilter(field_name="scheduled_date", lookup_expr="gte")
    date_to = filters.DateFilter(field_name="scheduled_date", lookup_expr="lte")
    min_stops = filters.NumberFilter(method="filter_min_stops")

    class Meta:
        model = Trip
        fields = ["status", "date_from", "date_to"]

    def search(self, queryset, name, value):
        return queryset.filter(
            models.Q(name__icontains=value)
            | models.Q(trip_stops__place__name__icontains=value)
            | models.Q(trip_stops__place__city__icontains=value)
        ).distinct()

    def filter_min_stops(self, queryset, name, value):
        from django.db.models import Count
        return queryset.annotate(
            _stop_count=Count("trip_stops")
        ).filter(_stop_count__gte=value)
