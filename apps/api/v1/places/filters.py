from django.db import models
from django_filters import rest_framework as filters

from apps.wineries.models import Place


class PlaceFilter(filters.FilterSet):
    q = filters.CharFilter(method="search")
    place_type = filters.ChoiceFilter(choices=Place.PlaceType.choices)
    city = filters.CharFilter(lookup_expr="icontains")
    state = filters.CharFilter(lookup_expr="icontains")
    has_coordinates = filters.BooleanFilter(method="filter_has_coordinates")

    class Meta:
        model = Place
        fields = ["place_type", "city", "state"]

    def search(self, queryset, name, value):
        return queryset.filter(
            models.Q(name__icontains=value)
            | models.Q(city__icontains=value)
            | models.Q(state__icontains=value)
        )

    def filter_has_coordinates(self, queryset, name, value):
        if value:
            return queryset.filter(latitude__isnull=False, longitude__isnull=False)
        return queryset
