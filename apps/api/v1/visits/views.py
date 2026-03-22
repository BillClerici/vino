import io
import uuid
from pathlib import Path

from django.conf import settings
from django.db.models import Count, Max
from PIL import Image
from rest_framework import status
from rest_framework.decorators import action
from rest_framework.parsers import MultiPartParser
from rest_framework.response import Response
from rest_framework.viewsets import ModelViewSet

from apps.visits.models import VisitLog, VisitWine
from ..permissions import HasActiveSubscription, IsOwnerOrReadOnly
from .filters import VisitLogFilter
from .serializers import (
    CheckInSerializer,
    VisitLogDetailSerializer,
    VisitLogListSerializer,
    VisitWineSerializer,
    VisitWineWriteSerializer,
)

MAX_PHOTO_SIZE = 5 * 1024 * 1024  # 5 MB
MAX_DIMENSION = 1200


def _process_image(uploaded_file) -> bytes:
    """Validate, resize, strip EXIF, and compress an uploaded image."""
    img = Image.open(uploaded_file)

    # Convert to RGB (handles RGBA PNGs, CMYK, etc.)
    if img.mode not in ("RGB", "L"):
        img = img.convert("RGB")

    # Resize if larger than max dimension
    if max(img.size) > MAX_DIMENSION:
        img.thumbnail((MAX_DIMENSION, MAX_DIMENSION), Image.LANCZOS)

    # Save as JPEG, stripping EXIF by not copying info
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=85, optimize=True)
    return buf.getvalue()


def _save_photo(user_id: str, wine_id: str, image_bytes: bytes, request=None) -> str:
    """Save processed image to S3 or local media. Returns the public URL."""
    filename = f"{wine_id}.jpg"
    key = f"drink-photos/{user_id}/{filename}"

    if getattr(settings, "AWS_S3_BUCKET", ""):
        import boto3

        s3 = boto3.client("s3", region_name=settings.AWS_S3_REGION)
        s3.put_object(
            Bucket=settings.AWS_S3_BUCKET,
            Key=key,
            Body=image_bytes,
            ContentType="image/jpeg",
        )
        return f"https://{settings.AWS_S3_BUCKET}.s3.{settings.AWS_S3_REGION}.amazonaws.com/{key}"

    # Local storage fallback
    media_dir = Path(settings.MEDIA_ROOT) / "drink-photos" / str(user_id)
    media_dir.mkdir(parents=True, exist_ok=True)
    filepath = media_dir / filename
    filepath.write_bytes(image_bytes)
    relative_url = f"{settings.MEDIA_URL}drink-photos/{user_id}/{filename}"
    if request:
        return request.build_absolute_uri(relative_url)
    return relative_url


class VisitLogViewSet(ModelViewSet):
    permission_classes = [HasActiveSubscription, IsOwnerOrReadOnly]
    filterset_class = VisitLogFilter
    search_fields = ["place__name", "notes"]
    ordering_fields = ["visited_at", "rating_overall", "place__name", "created_at"]
    ordering = ["-visited_at"]

    def get_queryset(self):
        return (
            VisitLog.objects.filter(user=self.request.user, is_active=True)
            .select_related("place")
            .annotate(wines_count=Count("wines_tasted", distinct=True))
        )

    def get_serializer_class(self):
        if self.action == "retrieve":
            return VisitLogDetailSerializer
        if self.action == "create":
            return CheckInSerializer
        return VisitLogListSerializer

    def perform_destroy(self, instance):
        instance.is_active = False
        instance.save(update_fields=["is_active", "updated_at"])

    @action(detail=False, methods=["get"], url_path="history-map")
    def history_map(self, request):
        """All visited places with visit count, last visit date, and last visit ID."""
        places = (
            VisitLog.objects.filter(user=request.user, is_active=True)
            .values(
                "place__id", "place__name", "place__place_type",
                "place__city", "place__state",
                "place__latitude", "place__longitude",
                "place__image_url",
                "place__address", "place__website", "place__phone",
            )
            .annotate(
                visit_count=Count("id"),
                last_visited=Max("visited_at"),
            )
            .filter(
                place__latitude__isnull=False,
                place__longitude__isnull=False,
            )
            .order_by("-last_visited")
        )

        results = []
        for p in places:
            # Get the last visit ID separately (can't MAX a UUID)
            last_visit = (
                VisitLog.objects.filter(
                    user=request.user,
                    place_id=p["place__id"],
                    is_active=True,
                )
                .order_by("-visited_at")
                .values_list("id", flat=True)
                .first()
            )

            results.append({
                "place_id": str(p["place__id"]),
                "name": p["place__name"],
                "place_type": p["place__place_type"],
                "city": p["place__city"] or "",
                "state": p["place__state"] or "",
                "latitude": float(p["place__latitude"]),
                "longitude": float(p["place__longitude"]),
                "image_url": p["place__image_url"] or "",
                "address": p["place__address"] or "",
                "website": p["place__website"] or "",
                "phone": p["place__phone"] or "",
                "visit_count": p["visit_count"],
                "last_visited": p["last_visited"].isoformat() if p["last_visited"] else None,
                "last_visit_id": str(last_visit) if last_visit else None,
            })

        return Response({
            "places": results,
            "total_places": len(results),
        })

    @action(detail=True, methods=["get", "post"], url_path="wines")
    def wines(self, request, pk=None):
        """List or add wines for a visit."""
        visit = self.get_object()
        if request.method == "GET":
            wines = visit.wines_tasted.filter(is_active=True)
            return Response(VisitWineSerializer(wines, many=True).data)

        serializer = VisitWineWriteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        wine = serializer.save(visit=visit)
        return Response(
            VisitWineSerializer(wine).data,
            status=status.HTTP_201_CREATED,
        )

    @action(
        detail=True,
        methods=["put", "patch", "delete"],
        url_path="wines/(?P<wine_pk>[^/.]+)",
    )
    def wine_detail(self, request, pk=None, wine_pk=None):
        """Update or delete a specific wine entry."""
        visit = self.get_object()
        try:
            wine = visit.wines_tasted.get(pk=wine_pk, is_active=True)
        except VisitWine.DoesNotExist:
            return Response(status=status.HTTP_404_NOT_FOUND)

        if request.method == "DELETE":
            wine.is_active = False
            wine.save(update_fields=["is_active", "updated_at"])
            return Response(status=status.HTTP_204_NO_CONTENT)

        serializer = VisitWineWriteSerializer(wine, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(VisitWineSerializer(wine).data)

    @action(
        detail=True,
        methods=["post"],
        url_path="wines/(?P<wine_pk>[^/.]+)/photo",
        parser_classes=[MultiPartParser],
    )
    def wine_photo(self, request, pk=None, wine_pk=None):
        """Upload a photo for a specific wine entry."""
        visit = self.get_object()
        try:
            wine = visit.wines_tasted.get(pk=wine_pk, is_active=True)
        except VisitWine.DoesNotExist:
            return Response(status=status.HTTP_404_NOT_FOUND)

        uploaded = request.FILES.get("file")
        if not uploaded:
            return Response(
                {"detail": "No file provided."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if uploaded.size > MAX_PHOTO_SIZE:
            return Response(
                {"detail": "File too large. Maximum size is 5 MB."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            image_bytes = _process_image(uploaded)
        except Exception:
            return Response(
                {"detail": "Invalid image file."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        photo_url = _save_photo(
            str(request.user.id), str(wine.id), image_bytes, request=request
        )
        wine.photo = photo_url
        wine.save(update_fields=["photo", "updated_at"])

        return Response({"photo_url": photo_url})
