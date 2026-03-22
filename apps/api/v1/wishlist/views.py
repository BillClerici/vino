from rest_framework import status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.viewsets import ModelViewSet

from apps.wineries.models import MenuItem, WineWishlist
from ..permissions import HasActiveSubscription
from .serializers import WishlistSerializer, WishlistWriteSerializer


class WishlistViewSet(ModelViewSet):
    permission_classes = [HasActiveSubscription]
    ordering = ["-created_at"]

    def get_queryset(self):
        return WineWishlist.objects.filter(
            user=self.request.user, is_active=True
        ).select_related("menu_item", "source_place")

    def get_serializer_class(self):
        if self.action in ("create", "update", "partial_update"):
            return WishlistWriteSerializer
        return WishlistSerializer

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)

    def perform_destroy(self, instance):
        instance.is_active = False
        instance.save(update_fields=["is_active", "updated_at"])

    @action(detail=False, methods=["get"], url_path="check/(?P<place_pk>[^/.]+)")
    def check(self, request, place_pk=None):
        """Check if any wishlisted wines are available at a given place.

        Matches by menu_item.place_id or by wine_name against MenuItem.name.
        """
        # Direct menu_item matches
        direct = list(
            self.get_queryset()
            .filter(menu_item__place_id=place_pk, menu_item__is_active=True)
            .values("id", "wine_name", "wine_type", menu_item_name=None)
        )

        # Name-based matches
        wishlist_names = list(
            self.get_queryset()
            .exclude(wine_name="")
            .values_list("wine_name", flat=True)
        )
        name_matches = []
        if wishlist_names:
            from django.db.models import Q
            q = Q()
            for name in wishlist_names:
                q |= Q(name__icontains=name)
            matching_items = MenuItem.objects.filter(
                q, place_id=place_pk, is_active=True
            ).values("id", "name", "varietal")
            for item in matching_items:
                name_matches.append({
                    "menu_item_id": str(item["id"]),
                    "menu_item_name": item["name"],
                    "varietal": item["varietal"],
                })

        has_matches = len(direct) > 0 or len(name_matches) > 0
        return Response({
            "has_matches": has_matches,
            "direct_matches": direct,
            "name_matches": name_matches,
        })

    @action(detail=False, methods=["post"], url_path="toggle")
    def toggle(self, request):
        """Add or remove a wine from the wishlist."""
        wine_name = request.data.get("wine_name", "").strip()
        menu_item_id = request.data.get("menu_item")
        source_place_id = request.data.get("source_place")

        if not wine_name and not menu_item_id:
            return Response(
                {"detail": "wine_name or menu_item is required."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Check if already wishlisted
        filters = {"user": request.user, "is_active": True}
        if menu_item_id:
            filters["menu_item_id"] = menu_item_id
        else:
            filters["wine_name__iexact"] = wine_name

        existing = WineWishlist.objects.filter(**filters).first()
        if existing:
            existing.is_active = False
            existing.save(update_fields=["is_active", "updated_at"])
            return Response({"wishlisted": False, "detail": "Removed from wishlist."})

        # Add to wishlist
        wl = WineWishlist.objects.create(
            user=request.user,
            wine_name=wine_name,
            wine_type=request.data.get("wine_type", ""),
            wine_vintage=request.data.get("wine_vintage"),
            notes=request.data.get("notes", ""),
            menu_item_id=menu_item_id,
            source_place_id=source_place_id,
        )
        return Response(
            {"wishlisted": True, "id": str(wl.id), "detail": "Added to wishlist!"},
            status=status.HTTP_201_CREATED,
        )
