from rest_framework import serializers

from apps.wineries.models import WineWishlist


class WishlistSerializer(serializers.ModelSerializer):
    display_name = serializers.CharField(read_only=True)
    place_name = serializers.SerializerMethodField()

    class Meta:
        model = WineWishlist
        fields = [
            "id", "wine_name", "wine_type", "wine_vintage", "notes",
            "menu_item", "source_place", "display_name", "place_name",
            "created_at",
        ]

    def get_place_name(self, obj):
        if obj.source_place:
            return obj.source_place.name
        if obj.menu_item and obj.menu_item.place:
            return obj.menu_item.place.name
        return None


class WishlistWriteSerializer(serializers.ModelSerializer):
    class Meta:
        model = WineWishlist
        fields = [
            "wine_name", "wine_type", "wine_vintage", "notes",
            "menu_item", "source_place",
        ]
