from rest_framework import serializers

from apps.visits.models import VisitLog, VisitWine
from apps.wineries.models import MenuItem
from ..places.serializers import PlaceListSerializer


class VisitWineSerializer(serializers.ModelSerializer):
    display_name = serializers.CharField(read_only=True)
    menu_item_name = serializers.SerializerMethodField()

    class Meta:
        model = VisitWine
        fields = [
            "id", "menu_item", "menu_item_name", "wine_name", "wine_type",
            "wine_vintage", "serving_type", "quantity", "is_favorite",
            "tasting_notes", "rating", "photo", "purchased",
            "purchased_quantity", "purchased_price", "purchased_notes",
            "display_name", "created_at",
        ]
        read_only_fields = ["id", "display_name", "created_at"]

    def get_menu_item_name(self, obj):
        if obj.menu_item:
            return obj.menu_item.name
        return None


class VisitWineWriteSerializer(serializers.ModelSerializer):
    class Meta:
        model = VisitWine
        fields = [
            "menu_item", "wine_name", "wine_type", "wine_vintage",
            "serving_type", "quantity", "is_favorite", "tasting_notes",
            "rating", "photo", "purchased", "purchased_quantity",
            "purchased_price", "purchased_notes",
        ]


class VisitLogListSerializer(serializers.ModelSerializer):
    place = PlaceListSerializer(read_only=True)
    wines_count = serializers.IntegerField(read_only=True, default=0)

    class Meta:
        model = VisitLog
        fields = [
            "id", "place", "visited_at", "notes",
            "rating_staff", "rating_ambience", "rating_food", "rating_overall",
            "wines_count", "created_at",
        ]
        read_only_fields = ["id", "created_at"]


class VisitLogDetailSerializer(serializers.ModelSerializer):
    place = PlaceListSerializer(read_only=True)
    wines_tasted = VisitWineSerializer(many=True, read_only=True)

    class Meta:
        model = VisitLog
        fields = [
            "id", "place", "visited_at", "notes",
            "rating_staff", "rating_ambience", "rating_food", "rating_overall",
            "metadata", "wines_tasted", "created_at", "updated_at",
        ]
        read_only_fields = ["id", "created_at", "updated_at"]


class CheckInSerializer(serializers.ModelSerializer):
    """Create a visit with optional wines in a single request."""
    wines = VisitWineWriteSerializer(many=True, required=False)

    class Meta:
        model = VisitLog
        fields = [
            "place", "visited_at", "notes",
            "rating_staff", "rating_ambience", "rating_food", "rating_overall",
            "wines",
        ]

    def create(self, validated_data):
        wines_data = validated_data.pop("wines", [])
        validated_data["user"] = self.context["request"].user
        visit = VisitLog.objects.create(**validated_data)
        for wine_data in wines_data:
            VisitWine.objects.create(visit=visit, **wine_data)
        return visit
