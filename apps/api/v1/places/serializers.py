from rest_framework import serializers

from apps.wineries.models import FavoritePlace, MenuItem, Place


class MenuItemSerializer(serializers.ModelSerializer):
    class Meta:
        model = MenuItem
        fields = [
            "id", "name", "varietal", "vintage", "description",
            "price", "image_url", "created_at",
        ]
        read_only_fields = ["id", "created_at"]


class PlaceListSerializer(serializers.ModelSerializer):
    visit_count = serializers.IntegerField(read_only=True, default=0)
    avg_rating = serializers.FloatField(read_only=True, default=None)
    is_favorited = serializers.BooleanField(read_only=True, default=False)

    class Meta:
        model = Place
        fields = [
            "id", "name", "place_type", "description",
            "address", "city", "state", "zip_code", "country",
            "latitude", "longitude", "website", "phone", "image_url",
            "visit_count", "avg_rating", "is_favorited",
        ]
        read_only_fields = ["id"]


class PlaceDetailSerializer(serializers.ModelSerializer):
    menu_items = MenuItemSerializer(many=True, read_only=True)
    visit_count = serializers.IntegerField(read_only=True, default=0)
    avg_rating = serializers.FloatField(read_only=True, default=None)
    is_favorited = serializers.BooleanField(read_only=True, default=False)

    class Meta:
        model = Place
        fields = [
            "id", "name", "place_type", "description",
            "address", "city", "state", "zip_code", "country",
            "latitude", "longitude", "website", "phone", "image_url",
            "metadata", "visit_count", "avg_rating", "is_favorited",
            "menu_items", "created_at", "updated_at",
        ]
        read_only_fields = ["id", "created_at", "updated_at"]


class PlaceWriteSerializer(serializers.ModelSerializer):
    # Override website to accept any string (Google Places may return non-URL formats)
    website = serializers.CharField(required=False, allow_blank=True, default="")

    class Meta:
        model = Place
        fields = [
            "name", "place_type", "description",
            "address", "city", "state", "zip_code", "country",
            "latitude", "longitude", "website", "phone", "image_url",
            "metadata",
        ]


class PlaceMapSerializer(serializers.ModelSerializer):
    """Lightweight serializer for map markers."""

    class Meta:
        model = Place
        fields = ["id", "name", "place_type", "latitude", "longitude", "image_url"]


class FavoritePlaceSerializer(serializers.ModelSerializer):
    place = PlaceListSerializer(read_only=True)

    class Meta:
        model = FavoritePlace
        fields = ["id", "place", "created_at"]
        read_only_fields = fields


class MenuItemWriteSerializer(serializers.ModelSerializer):
    class Meta:
        model = MenuItem
        fields = ["name", "varietal", "vintage", "description", "price", "image_url"]
