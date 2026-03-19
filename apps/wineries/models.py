from django.conf import settings
from django.db import models

from apps.core.models import BaseModel


class Winery(BaseModel):
    name = models.CharField(max_length=255, db_index=True)
    description = models.TextField(blank=True)

    # Location
    address = models.CharField(max_length=500, blank=True)
    city = models.CharField(max_length=100, blank=True)
    state = models.CharField(max_length=100, blank=True)
    country = models.CharField(max_length=100, default="US")
    latitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    longitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)

    # Contact & metadata
    website = models.URLField(blank=True)
    phone = models.CharField(max_length=30, blank=True)
    image_url = models.URLField(max_length=1000, blank=True)
    metadata = models.JSONField(default=dict, blank=True)

    class Meta:
        db_table = "wineries_winery"
        verbose_name_plural = "wineries"
        ordering = ["name"]

    def __str__(self):
        return self.name


class Wine(BaseModel):
    winery = models.ForeignKey(Winery, on_delete=models.CASCADE, related_name="wines")
    name = models.CharField(max_length=255)
    varietal = models.CharField(max_length=100, db_index=True)
    vintage = models.PositiveIntegerField(null=True, blank=True)
    description = models.TextField(blank=True)
    pinecone_vector_id = models.CharField(max_length=255, blank=True, db_index=True)
    metadata = models.JSONField(default=dict, blank=True)

    class Meta:
        db_table = "wineries_wine"
        ordering = ["name", "-vintage"]

    def __str__(self):
        vintage = f" ({self.vintage})" if self.vintage else ""
        return f"{self.name}{vintage} — {self.winery.name}"


class FavoriteWinery(BaseModel):
    """Tracks which wineries a user has favorited."""
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="favorite_wineries"
    )
    winery = models.ForeignKey(Winery, on_delete=models.CASCADE, related_name="favorited_by")

    class Meta:
        db_table = "wineries_favoritewinery"
        unique_together = [("user", "winery")]

    def __str__(self):
        return f"{self.user} ♥ {self.winery}"
