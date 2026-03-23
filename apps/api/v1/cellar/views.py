"""
My Cellar / Purchase Dashboard — aggregates wine purchase data
from VisitWine records where purchased=True.
"""

from decimal import Decimal

from django.db.models import Avg, F, Sum
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.visits.models import VisitWine

from ..permissions import HasActiveSubscription


class CellarView(APIView):
    """GET /api/v1/cellar/ — purchase dashboard for the current user."""

    permission_classes = [HasActiveSubscription]

    def get(self, request):
        purchases = VisitWine.objects.filter(
            visit__user=request.user,
            is_active=True,
            purchased=True,
        ).select_related("visit__place", "menu_item")

        # Summary stats
        total_bottles = purchases.aggregate(
            total=Sum("purchased_quantity"),
        )["total"] or 0

        total_spend = purchases.aggregate(
            total=Sum(F("purchased_price") * F("purchased_quantity")),
        )["total"] or Decimal("0.00")

        unique_wines = purchases.values("wine_name").distinct().count()
        unique_places = purchases.values("visit__place").distinct().count()
        avg_price = purchases.filter(
            purchased_price__isnull=False
        ).aggregate(avg=Avg("purchased_price"))["avg"]

        # Recent purchases (latest 20)
        recent = []
        for w in purchases.order_by("-visit__visited_at")[:20]:
            recent.append({
                "id": str(w.id),
                "wine_name": w.display_name or w.wine_name or "Unknown",
                "wine_type": w.wine_type or "",
                "wine_vintage": w.wine_vintage,
                "quantity": w.purchased_quantity or 1,
                "price": float(w.purchased_price) if w.purchased_price else None,
                "total": float(w.purchased_price * (w.purchased_quantity or 1)) if w.purchased_price else None,
                "place_name": w.visit.place.name if w.visit and w.visit.place else "",
                "date": w.visit.visited_at.isoformat() if w.visit else "",
                "rating": w.rating,
                "is_favorite": w.is_favorite,
                "photo": w.photo or "",
            })

        # Top places by spend
        top_places = list(
            purchases.filter(purchased_price__isnull=False)
            .values(
                place_name=F("visit__place__name"),
                place_id=F("visit__place__id"),
            )
            .annotate(
                total_spend=Sum(F("purchased_price") * F("purchased_quantity")),
                bottle_count=Sum("purchased_quantity"),
            )
            .order_by("-total_spend")[:5]
        )
        for tp in top_places:
            tp["total_spend"] = float(tp["total_spend"]) if tp["total_spend"] else 0
            tp["place_id"] = str(tp["place_id"])

        # Top varietals purchased
        top_varietals = list(
            purchases.exclude(wine_type="")
            .values(varietal=F("wine_type"))
            .annotate(
                count=Sum("purchased_quantity"),
                avg_price=Avg("purchased_price"),
            )
            .order_by("-count")[:8]
        )
        for tv in top_varietals:
            tv["avg_price"] = float(tv["avg_price"]) if tv["avg_price"] else None

        return Response({
            "stats": {
                "total_bottles": total_bottles,
                "total_spend": float(total_spend),
                "unique_wines": unique_wines,
                "unique_places": unique_places,
                "avg_price": float(avg_price) if avg_price else None,
            },
            "recent_purchases": recent,
            "top_places": top_places,
            "top_varietals": top_varietals,
        })
