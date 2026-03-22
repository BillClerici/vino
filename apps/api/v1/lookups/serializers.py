from rest_framework import serializers

from apps.lookup.models import LookupValue


class LookupValueSerializer(serializers.ModelSerializer):
    class Meta:
        model = LookupValue
        fields = ["id", "parent", "code", "label", "description", "sort_order", "metadata"]
        read_only_fields = fields
